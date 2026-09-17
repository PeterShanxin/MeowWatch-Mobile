import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'primitives.dart';
import 'wire.dart';

/// Internal, bounded connection. Never exposes socket diagnostics or payloads.
final class ClientTransport {
  ClientTransport(this.socket) {
    socket.listen(
      _bytes,
      onError: (Object _) => close('not_connected'),
      onDone: () => close('not_connected'),
    );
  }

  final SecureSocket socket;
  final _queued = Queue<NearbyFrame>();
  final _partial = BytesBuilder(copy: false);
  Completer<NearbyFrame>? _reader;
  Timer? _assembly;
  Future<void> _writeTail = Future.value();
  int _pendingBytes = 0;
  String? _closed;
  void Function(NearbyFrame)? onFrame;
  void Function(String)? onClosed;

  void _bytes(List<int> bytes) {
    if (_closed != null) return;
    try {
      var start = 0;
      for (var i = 0; i < bytes.length; i++) {
        if (bytes[i] != 10) continue;
        if (_partial.length + i - start > maxFrameBytes) {
          throw const NearbyException('invalid_argument');
        }
        _partial.add(bytes.sublist(start, i));
        _assembly?.cancel();
        _assembly = null;
        final frame = const NearbyFrameCodec().decode(_partial.takeBytes());
        final reader = _reader;
        if (onFrame != null) {
          onFrame!(frame);
        } else if (reader != null) {
          _reader = null;
          reader.complete(frame);
        } else {
          if (_queued.length >= 16) {
            throw const NearbyException('rate_limited');
          }
          _queued.add(frame);
        }
        if (_closed != null) return;
        start = i + 1;
      }
      if (_partial.length + bytes.length - start > maxFrameBytes) {
        throw const NearbyException('invalid_argument');
      }
      _partial.add(bytes.sublist(start));
      if (_partial.isNotEmpty) {
        _assembly ??= Timer(
          const Duration(seconds: 5),
          () => close('frame_timeout'),
        );
      }
    } on NearbyException catch (error) {
      close(error.code);
    } catch (_) {
      close('invalid_argument');
    }
  }

  Future<NearbyFrame> next(Duration timeout) async {
    // EOF may follow a flushed pair.accept. Protocol failures must not leave
    // previously queued handshake frames eligible for acceptance.
    if (_closed != null && _closed != 'not_connected') {
      throw NearbyException(_closed!);
    }
    if (_queued.isNotEmpty) return _queued.removeFirst();
    if (_closed != null) throw NearbyException(_closed!);
    if (_reader != null) throw StateError('Only one ceremony reader allowed');
    final reader = _reader = Completer<NearbyFrame>();
    try {
      return await reader.future.timeout(timeout);
    } on TimeoutException {
      close('timeout');
      throw const NearbyException('timeout');
    } finally {
      if (identical(_reader, reader)) _reader = null;
    }
  }

  void dispatchQueued() {
    while (_queued.isNotEmpty && _closed == null) {
      onFrame!(_queued.removeFirst());
    }
    if (_closed != null) onClosed?.call(_closed!);
  }

  Future<void> send(NearbyFrame frame) {
    final bytes = const NearbyFrameCodec().encode(frame);
    if (_closed != null) return Future.error(NearbyException(_closed!));
    if (_pendingBytes + bytes.length > 256 * 1024) {
      close('slow_peer');
      return Future.error(const NearbyException('slow_peer'));
    }
    _pendingBytes += bytes.length;
    final write = _writeTail
        .then((_) async {
          if (_closed != null) throw NearbyException(_closed!);
          try {
            socket.add(bytes);
            await socket.flush().timeout(const Duration(seconds: 5));
          } catch (_) {
            close('slow_peer');
            throw const NearbyException('slow_peer');
          }
        })
        .whenComplete(() => _pendingBytes -= bytes.length);
    _writeTail = write.catchError((Object _) {});
    return write;
  }

  void close(String code) {
    if (_closed != null) return;
    _closed = code;
    _assembly?.cancel();
    socket.destroy();
    final reader = _reader;
    _reader = null;
    reader?.completeError(NearbyException(code));
    onClosed?.call(code);
  }
}
