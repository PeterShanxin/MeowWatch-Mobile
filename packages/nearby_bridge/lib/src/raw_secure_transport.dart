import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

/// A byte-stream surface for an owned raw TLS connection.
/// The original RawSocket remains owned here, including during shutdown.
final class RawSecureTransport extends Stream<Uint8List> {
  RawSecureTransport(this._underlying, this._secure) {
    _input = StreamController<Uint8List>(
      sync: true,
      onListen: () => _secure.readEventsEnabled = true,
      onPause: () => _secure.readEventsEnabled = false,
      onResume: () => _secure.readEventsEnabled = true,
      onCancel: () => _secure.readEventsEnabled = false,
    );
    _secure.readEventsEnabled = false;
    _subscription = _secure.listen(
      _event,
      onError: (Object error, StackTrace stack) => _fail(error, stack),
      onDone: () => _fail(const SocketException('connection closed')),
    );
  }

  final RawSocket _underlying;
  final RawSecureSocket _secure;
  late final StreamController<Uint8List> _input;
  final _writes = Queue<Uint8List>();
  final _flushes = <(int, Completer<void>)>[];
  late final StreamSubscription<RawSocketEvent> _subscription;
  int _offset = 0;
  int _enqueued = 0;
  int _written = 0;
  bool _closed = false;
  bool _outputClosing = false;
  bool _outputClosed = false;
  bool _draining = false;
  Object? _failure;
  Future<void>? _outputShutdown;
  Future<void>? _drainedClose;

  String? get selectedProtocol => _secure.selectedProtocol;
  X509Certificate? get peerCertificate => _secure.peerCertificate;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _input.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  void add(List<int> bytes) {
    if (_closed || _outputClosing || _failure != null) {
      throw _failure ?? const SocketException('connection closed');
    }
    if (bytes.isEmpty) return;
    _writes.add(Uint8List.fromList(bytes));
    _enqueued += bytes.length;
    _drain();
  }

  Future<void> flush() {
    if (_failure case final failure?) return Future.error(failure);
    if (_closed) {
      return Future.error(const SocketException('connection closed'));
    }
    if (_written >= _enqueued) return Future.value();
    final waiter = Completer<void>();
    _flushes.add((_enqueued, waiter));
    return waiter.future;
  }

  /// Half-closes TLS output while leaving reads active for a final receipt.
  Future<void> shutdownOutput() =>
      _drainedClose ?? (_outputShutdown ??= _shutdownOutput());

  Future<void> _shutdownOutput() async {
    if (_closed || _outputClosed) return;
    _outputClosing = true;
    await flush();
    if (_closed || _outputClosed) return;
    _outputClosed = true;
    _secure.shutdown(SocketDirection.send);
  }

  /// Waits for TLS output to drain and the underlying secure socket to close.
  /// Callers that need a hard deadline must bound this future and destroy then.
  Future<void> close() => _drainedClose ??= _close();

  Future<void> _close() async {
    if (_closed) return;
    _outputClosing = true;
    if (_outputShutdown case final shutdown?) {
      await shutdown;
    } else {
      await flush();
    }
    if (_closed) return;
    _outputClosed = true;
    await _secure.close();
  }

  void destroy() {
    if (_closed) return;
    _closed = true;
    _fail(const SocketException('connection closed'));
    unawaited(_underlying.close());
    unawaited(_secure.close());
    unawaited(_subscription.cancel());
  }

  void _event(RawSocketEvent event) {
    try {
      if (event == RawSocketEvent.read) {
        Uint8List? bytes;
        while ((bytes = _secure.read()) != null) {
          if (bytes!.isNotEmpty) _input.add(bytes);
        }
      } else if (event == RawSocketEvent.write) {
        _drain();
      } else if (event == RawSocketEvent.readClosed ||
          event == RawSocketEvent.closed) {
        _fail(const SocketException('connection closed'));
      }
    } catch (error, stack) {
      _fail(error, stack);
    }
  }

  void _drain() {
    if (_draining || _closed || _failure != null) return;
    _draining = true;
    try {
      while (_writes.isNotEmpty) {
        final bytes = _writes.first;
        final count = _secure.write(bytes, _offset);
        if (count == 0) {
          _secure.writeEventsEnabled = true;
          return;
        }
        _offset += count;
        _written += count;
        if (_offset == bytes.length) {
          _writes.removeFirst();
          _offset = 0;
        }
        _completeFlushes();
      }
    } catch (error, stack) {
      _fail(error, stack);
    } finally {
      _draining = false;
    }
  }

  void _completeFlushes() {
    while (_flushes.isNotEmpty && _flushes.first.$1 <= _written) {
      _flushes.removeAt(0).$2.complete();
    }
  }

  void _fail(Object error, [StackTrace? stack]) {
    if (_failure != null) return;
    _failure = error;
    for (final (_, waiter) in _flushes) {
      waiter.completeError(error, stack);
    }
    _flushes.clear();
    _writes.clear();
    if (!_input.isClosed) {
      _input.addError(error, stack);
      unawaited(_input.close());
    }
  }
}
