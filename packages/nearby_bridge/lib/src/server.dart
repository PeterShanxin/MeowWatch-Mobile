import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'authority.dart';
import 'lan.dart';
import 'primitives.dart';
import 'tls.dart';
import 'wire.dart';

abstract interface class NearbyCommandHandler {
  int get stateRevision;
  Map<String, Object?> get snapshot;
  Stream<NearbyServerEvent> get events;
  Future<Map<String, Object?>> handle(NearbyCommand command);
}

final class NearbyCommand {
  NearbyCommand._(
    this.id,
    this.sessionEpoch,
    this.method,
    this.args,
    this._check,
  );

  /// Handler unit-test seam; production commands are created by NearbyServer.
  factory NearbyCommand.forTesting({
    required String id,
    required String sessionEpoch,
    required String method,
    required Map<String, Object?> args,
    required void Function() checkActive,
  }) => NearbyCommand._(
    id,
    sessionEpoch,
    method,
    Map.unmodifiable(args),
    checkActive,
  );
  final String id;
  final String sessionEpoch;
  final String method;
  final Map<String, Object?> args;
  final void Function() _check;
  void checkActive() => _check();
}

final class NearbyServerEvent {
  const NearbyServerEvent(this.type, this.body);
  final String type;
  final Map<String, Object?> body;
}

/// One listener wrapping an existing desktop session. Owns its authority once
/// bound. It never creates playback, chat or Syncplay instances itself.
final class NearbyServer {
  NearbyServer._(
    this._listener,
    this.identity,
    this.authority,
    this.handler,
    this.approvePairing,
    this._peerAddress,
    this._peerAllowed,
    this.commandTimeout,
  ) {
    if (!constantTimeEqual(
      identity.certificateSha256,
      authority.certificateSha256,
    )) {
      throw const NearbyException('invalid_argument');
    }
    _closureSubscription = authority.connectionsToClose.listen((id) {
      _pending.remove(id)?.destroy();
      _connections[id]?.close();
    });
    _eventSubscription = handler.events.listen(
      (event) {
        for (final connection in _connections.values.toList()) {
          connection.publish(event);
        }
      },
      onError: (Object _) {
        for (final connection in _connections.values.toList()) {
          connection.fail(const NearbyException('native_failure'));
        }
      },
    );
    _listenerSubscription = _listener.listen(
      (socket) {
        unawaited(_accept(socket));
      },
      onError: (Object _) {
        unawaited(close());
      },
    );
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      authority.expire();
      for (final connection in _connections.values.toList()) {
        connection.heartbeat();
      }
    });
  }

  static Future<NearbyServer> bind({
    required LanSubnet subnet,
    required TlsIdentity identity,
    required NearbyAuthority authority,
    required NearbyCommandHandler handler,
    required Future<bool> Function(PendingApproval approval) approvePairing,
    int port = 0,
    Duration commandTimeout = const Duration(seconds: 10),
  }) async {
    final listener = await ServerSocket.bind(
      subnet.localAddress.toString(),
      port,
      shared: false,
    );
    try {
      return NearbyServer._(
        listener,
        identity,
        authority,
        handler,
        approvePairing,
        (socket) => socket.remoteAddress.address,
        subnet.requirePeer,
        commandTimeout,
      );
    } catch (_) {
      await listener.close();
      rethrow;
    }
  }

  /// Explicitly nonshipping injection for portable loopback socket tests.
  /// Production callers must use [bind], which fixes both address and LAN policy.
  factory NearbyServer.forTesting({
    required ServerSocket listener,
    required TlsIdentity identity,
    required NearbyAuthority authority,
    required NearbyCommandHandler handler,
    required Future<bool> Function(PendingApproval approval) approvePairing,
    required String Function(Socket socket) peerAddressForTesting,
    Duration commandTimeout = const Duration(seconds: 10),
  }) => NearbyServer._(
    listener,
    identity,
    authority,
    handler,
    approvePairing,
    peerAddressForTesting,
    (_) {},
    commandTimeout,
  );

  final ServerSocket _listener;
  final TlsIdentity identity;
  final NearbyAuthority authority;
  final NearbyCommandHandler handler;
  final Future<bool> Function(PendingApproval approval) approvePairing;
  final String Function(Socket) _peerAddress;
  final void Function(String) _peerAllowed;
  final Duration commandTimeout;
  final _pending = <String, Socket>{};
  final _connections = <String, _ServerConnection>{};
  late final StreamSubscription<Socket> _listenerSubscription;
  late final StreamSubscription<String> _closureSubscription;
  late final StreamSubscription<NearbyServerEvent> _eventSubscription;
  late final Timer _timer;
  Future<void>? _closing;
  int get port => _listener.port;
  InternetAddress get address => _listener.address;

  Future<void> _accept(Socket raw) async {
    String? id;
    try {
      if (_closing != null) {
        raw.destroy();
        return;
      }
      final peer = _peerAddress(raw);
      _peerAllowed(peer);
      id = authority.openConnection(peerAddress: peer);
      _pending[id] = raw;
      final socket = await SecureSocket.secureServer(
        raw,
        identity.createServerContext(),
        supportedProtocols: [nearbyAlpn],
      ).timeout(const Duration(seconds: 5));
      if (!_pending.containsKey(id) ||
          _closing != null ||
          socket.selectedProtocol != nearbyAlpn) {
        socket.destroy();
        authority.closeConnection(id);
        return;
      }
      _pending.remove(id);
      final connection = _ServerConnection(this, id, socket);
      _connections[id] = connection;
      connection.listen();
    } catch (_) {
      raw.destroy();
      if (id != null) {
        _pending.remove(id);
        authority.closeConnection(id);
      }
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _timer.cancel();
    authority.stop();
    for (final socket in _pending.values) {
      socket.destroy();
    }
    _pending.clear();
    for (final connection in _connections.values.toList()) {
      connection.close();
    }
    await _listenerSubscription.cancel();
    await _listener.close();
    await _closureSubscription.cancel();
    await _eventSubscription.cancel();
    await authority.dispose();
  }
}

enum _Phase {
  hello,
  pairProof,
  approval,
  authProof,
  authenticating,
  active,
  revoking,
  closing,
}

final class _CachedCommand {
  _CachedCommand(this.fingerprint, this.at, this.result);
  final String fingerprint;
  final Duration at;
  final Future<Map<String, Object?>> result;
}

final class _ServerConnection {
  _ServerConnection(this.server, this.id, this.socket);
  final NearbyServer server;
  final String id;
  final SecureSocket socket;
  final _clock = Stopwatch()..start();
  final _input = StreamController<List<int>>();
  final _inboundSequence = FrameSequence();
  final _cache = <String, _CachedCommand>{};
  final _commandTimes = <Duration>[];
  final _closedSignal = Completer<bool>();
  StreamSubscription<Uint8List>? _socketSubscription;
  StreamSubscription<NearbyFrame>? _frameSubscription;
  Timer? _frameTimer;
  Timer? _receiptCloseTimer;
  var _partialBytes = 0;
  var _queuedBytes = 0;
  var _queuedCommands = 0;
  var _pendingFrames = 0;
  var _transportClosed = false;
  var _sequence = 0;
  var _lastPing = Duration.zero;
  var _phase = _Phase.hello;
  ControllerLease? _lease;
  Future<void> _writeTail = Future.value();
  Future<void> _inboundTail = Future.value();
  Future<void> _commandTail = Future.value();
  bool get closed => _phase == _Phase.closing;

  void listen() {
    _frameSubscription = _input.stream
        .transform(const JsonLineDecoder())
        .listen(
          (frame) {
            if (++_pendingFrames > 32) {
              fail(const NearbyException('rate_limited'));
              return;
            }
            _inboundTail = _inboundTail
                .then((_) => _receive(frame))
                .catchError((Object error) {
                  fail(error);
                })
                .whenComplete(() {
                  _pendingFrames--;
                });
          },
          onError: (Object error) {
            fail(error);
          },
        );
    _socketSubscription = socket.listen(
      (bytes) {
        if (closed) return;
        final lastLf = bytes.lastIndexOf(10);
        if (lastLf >= 0) {
          _frameTimer?.cancel();
          _partialBytes = bytes.length - lastLf - 1;
          if (_partialBytes > 0) _startFrameDeadline();
        } else {
          if (_partialBytes == 0 && bytes.isNotEmpty) _startFrameDeadline();
          _partialBytes += bytes.length;
        }
        if (_partialBytes > maxFrameBytes) {
          fail(const NearbyException('invalid_argument'));
          return;
        }
        _input.add(bytes);
      },
      onError: (Object _) {
        close();
      },
      onDone: close,
    );
  }

  void _startFrameDeadline() {
    _frameTimer = Timer(const Duration(seconds: 3), () {
      fail(const NearbyException('command_timeout'));
    });
  }

  void _keys(
    NearbyFrame frame,
    Set<String> required, [
    Set<String> optional = const {},
  ]) {
    final keys = frame.fields.keys.toSet();
    if (!keys.containsAll({'v', 'type', ...required}) ||
        keys.difference({'v', 'type', ...required, ...optional}).isNotEmpty) {
      throw const NearbyException('invalid_argument');
    }
  }

  String _string(NearbyFrame frame, String key) {
    final value = frame.fields[key];
    if (value is! String) throw const NearbyException('invalid_argument');
    return value;
  }

  Future<void> _receive(NearbyFrame frame) async {
    if (closed) return;
    // Only the pending durability receipt can leave this terminal phase.
    if (_phase == _Phase.revoking) return;
    if (_phase == _Phase.active) {
      await _receiveActive(frame);
      return;
    }
    switch ((_phase, frame.type)) {
      case (_Phase.hello, 'pair.hello'):
        _keys(frame, {'clientId', 'clientName', 'clientNonce'}, {'pairId'});
        final challenge = server.authority.beginPairing(
          connectionId: id,
          clientId: _string(frame, 'clientId'),
          clientName: _string(frame, 'clientName'),
          clientNonce: decodeBytes(_string(frame, 'clientNonce'), 32),
          pairId: frame.fields.containsKey('pairId')
              ? _string(frame, 'pairId')
              : null,
        );
        _phase = _Phase.pairProof;
        await _send({
          'type': 'pair.challenge',
          'desktopId': server.authority.desktopId,
          'pairId': challenge.pairId,
          'serverNonce': encodeBytes(challenge.serverNonce),
        });
      case (_Phase.pairProof, 'pair.proof'):
        _keys(frame, {'proof'});
        final pending = server.authority.verifyPairingProof(
          id,
          decodeBytes(_string(frame, 'proof'), 32),
        );
        _phase = _Phase.approval;
        // Authority's deadline remains authoritative if the invitation expires earlier.
        await _send({'type': 'pair.pending', 'expiresInMs': 30000});
        unawaited(
          _approve(pending).catchError((Object error) {
            fail(error);
          }),
        );
      case (_Phase.hello, 'auth.hello'):
        _keys(frame, {});
        final challenge = server.authority.beginAuthentication(id);
        _phase = _Phase.authProof;
        await _send({
          'type': 'auth.challenge',
          'desktopId': server.authority.desktopId,
          'serverNonce': encodeBytes(challenge.serverNonce),
        });
      case (_Phase.authProof, 'auth.proof'):
        _keys(frame, {'tokenId', 'clientNonce', 'proof'});
        _phase = _Phase.authenticating;
        final accepted = await server.authority.authenticate(
          connectionId: id,
          tokenId: _string(frame, 'tokenId'),
          clientNonce: decodeBytes(_string(frame, 'clientNonce'), 32),
          proof: decodeBytes(_string(frame, 'proof'), 32),
        );
        if (closed) return;
        _lease = accepted.lease;
        _check();
        await _send({
          'type': 'auth.ok',
          'connectionId': accepted.lease.connectionId,
          'sessionEpoch': accepted.lease.sessionEpoch,
          'serverProof': encodeBytes(accepted.serverProof),
        });
        _check();
        _phase = _Phase.active;
        await _snapshot();
      default:
        throw const NearbyException('auth_failed');
    }
  }

  Future<void> _approve(PendingApproval pending) async {
    final allowed = await Future.any<bool>([
      server.approvePairing(pending),
      _closedSignal.future,
    ]).timeout(const Duration(seconds: 30));
    if (closed) return;
    if (!allowed) {
      fail(const NearbyException('pairing_denied'));
      return;
    }
    final accepted = await server.authority.approvePairing(pending.id);
    if (closed) return;
    await _send({
      'type': 'pair.accept',
      'desktopId': server.authority.desktopId,
      'tokenId': accepted.credential.tokenId,
      'deviceSecret': encodeBytes(accepted.credential.secret),
      'serverProof': encodeBytes(accepted.serverProof),
    });
    close();
  }

  Future<void> _receiveActive(NearbyFrame frame) async {
    _check();
    _inboundSequence.accept(frame);
    if (_string(frame, 'sessionEpoch') != _lease!.sessionEpoch) {
      throw const NearbyException('session_changed');
    }
    switch (frame.type) {
      case 'ping':
      case 'pong':
        _keys(frame, {'seq', 'sessionEpoch'});
      case 'command':
        _keys(frame, {'seq', 'sessionEpoch', 'id', 'method', 'args'});
      default:
        throw const NearbyException('invalid_argument');
    }
    await server.authority.recordActivity(
      _lease!,
      sessionEpoch: _lease!.sessionEpoch,
    );
    _check();
    if (frame.type == 'ping') {
      await _sendActive({'type': 'pong'});
      return;
    }
    if (frame.type == 'pong') return;
    _enqueueCommand(frame);
  }

  void _check() {
    if (closed || _lease == null) throw const NearbyException('auth_failed');
    server.authority.requireLease(_lease!, sessionEpoch: _lease!.sessionEpoch);
  }

  void _enqueueCommand(NearbyFrame frame) {
    final now = _clock.elapsed;
    _commandTimes.removeWhere(
      (time) => now - time >= const Duration(seconds: 1),
    );
    if (_commandTimes.length >= 20 || _queuedCommands >= 16) {
      throw const NearbyException('rate_limited');
    }
    _commandTimes.add(now);
    _cache.removeWhere(
      (_, entry) => now - entry.at >= const Duration(minutes: 2),
    );
    final commandId = _string(frame, 'id');
    final fingerprint = jsonEncode(
      _canonical({
        'method': frame.fields['method'],
        'args': frame.fields['args'],
        'sessionEpoch': frame.fields['sessionEpoch'],
      }),
    );
    final cached = _cache[commandId];
    if (cached != null && cached.fingerprint != fingerprint) {
      throw const NearbyException('invalid_argument');
    }
    final command = NearbyCommand._(
      commandId,
      _lease!.sessionEpoch,
      _string(frame, 'method'),
      frame.fields['args']! as Map<String, Object?>,
      _check,
    );
    final Completer<Map<String, Object?>>? completion = cached == null
        ? Completer()
        : null;
    if (completion != null) {
      if (_cache.length >= 128) _cache.remove(_cache.keys.first);
      _cache[commandId] = _CachedCommand(fingerprint, now, completion.future);
    }
    _queuedCommands++;
    _commandTail = _commandTail.then((_) async {
      try {
        _check();
        if (command.method == 'device.revokeSelf') {
          final result = await _revokeSelf(commandId);
          if (completion != null && !completion.isCompleted) {
            completion.complete(result);
          }
          return;
        }
        final result = cached != null
            ? await cached.result
            : await _execute(command);
        if (completion != null && !completion.isCompleted) {
          completion.complete(result);
        }
        _check();
        await _sendActive({'type': 'result', 'id': commandId, ...result});
        if (command.method == 'controller.detach') {
          close();
          return;
        }
        if (result['ok'] == true && command.method != 'state.get') {
          await _snapshot();
        }
        final error = result['error'];
        if (error is Map && error['code'] == 'command_timeout') close();
      } catch (error) {
        // Complete pending duplicate waiters without retaining uncaught errors.
        if (completion != null && !completion.isCompleted) {
          completion.complete({
            'ok': false,
            'stateRevision': 0,
            'error': {'code': 'auth_failed'},
          });
        }
        fail(error);
      } finally {
        _queuedCommands--;
      }
    });
  }

  Future<Map<String, Object?>> _execute(NearbyCommand command) async {
    try {
      command.checkActive();
      final Map<String, Object?> result;
      switch (command.method) {
        case 'state.get':
          result = {'state': server.handler.snapshot};
        case 'controller.detach':
          result = {};
        default:
          result = await server.handler
              .handle(command)
              .timeout(server.commandTimeout);
      }
      command.checkActive();
      return {
        'ok': true,
        'stateRevision': server.handler.stateRevision,
        'result': result,
      };
    } catch (error) {
      command.checkActive();
      return {
        'ok': false,
        'stateRevision': server.handler.stateRevision,
        'error': {'code': _errorCode(error)},
      };
    }
  }

  Future<Map<String, Object?>> _revokeSelf(String commandId) async {
    final lease = _lease!;
    final revision = server.handler.stateRevision;
    _phase = _Phase.revoking;
    Map<String, Object?> result;
    try {
      await server.authority
          .revokeForAcknowledgement(lease)
          .timeout(server.commandTimeout);
      result = {
        'ok': true,
        'stateRevision': revision,
        'result': <String, Object?>{},
      };
    } catch (error) {
      result = {
        'ok': false,
        'stateRevision': revision,
        'error': {'code': _errorCode(error)},
      };
    }
    try {
      // This single receipt is deliberately not _sendActive: revocation already
      // destroyed that authority. No command, snapshot or lease is restored.
      await _send({
        'type': 'result',
        'id': commandId,
        ...result,
        'seq': ++_sequence,
        'sessionEpoch': lease.sessionEpoch,
      });
      return result;
    } finally {
      await _closeAfterReceipt();
    }
  }

  Future<void> _closeAfterReceipt() async {
    if (_transportClosed) return;
    _phase = _Phase.closing;
    _frameTimer?.cancel();
    // flush() only drains Dart's consumer, not the peer's TCP/TLS buffers.
    // Immediate destroy with an in-flight incoming frame can reset Linux TCP
    // and discard the durability receipt. Close TLS output, continue draining
    // the unauthorised read side, and bound final destruction independently.
    _receiptCloseTimer = Timer(const Duration(seconds: 3), close);
    try {
      await socket.close();
    } catch (_) {
      close();
    }
  }

  Future<void> _snapshot() =>
      _sendActive({'type': 'state.snapshot', 'state': server.handler.snapshot});

  void publish(NearbyServerEvent event) {
    if (_phase != _Phase.active) return;
    if (!const {
      'state.snapshot',
      'chat.message',
      'chat.reaction',
      'chat.typing',
      'presence',
    }.contains(event.type)) {
      fail(const NearbyException('invalid_argument'));
      return;
    }
    try {
      unawaited(
        _sendActive({
          'type': event.type,
          event.type == 'state.snapshot' ? 'state' : 'event': event.body,
        }).catchError((Object error) {
          fail(error);
        }),
      );
    } catch (error) {
      fail(error);
    }
  }

  void heartbeat() {
    if (_phase != _Phase.active ||
        _clock.elapsed - _lastPing < const Duration(seconds: 5)) {
      return;
    }
    _lastPing = _clock.elapsed;
    try {
      unawaited(
        _sendActive({'type': 'ping'}).catchError((Object error) {
          fail(error);
        }),
      );
    } catch (error) {
      fail(error);
    }
  }

  Future<void> _sendActive(Map<String, Object?> body) {
    _check();
    return _send({
      ...body,
      'seq': ++_sequence,
      'sessionEpoch': _lease!.sessionEpoch,
    });
  }

  Future<void> _send(Map<String, Object?> body) {
    if (closed) return Future.error(const NearbyException('not_connected'));
    final bytes = const NearbyFrameCodec().encode(
      NearbyFrame({'v': 1, ...body}),
    );
    if (_queuedBytes + bytes.length > 256 * 1024) {
      close();
      return Future.error(const NearbyException('rate_limited'));
    }
    _queuedBytes += bytes.length;
    final completion = Completer<void>();
    _writeTail = _writeTail.then((_) async {
      try {
        if (closed) throw const NearbyException('not_connected');
        socket.add(bytes);
        await socket.flush().timeout(const Duration(seconds: 3));
        completion.complete();
      } catch (error) {
        close();
        completion.completeError(error);
      } finally {
        _queuedBytes -= bytes.length;
      }
    });
    return completion.future;
  }

  void fail(Object error) {
    if (closed) return;
    final body = <String, Object?>{
      'type': 'error',
      'error': {'code': _errorCode(error)},
    };
    // Freeze authority before a bounded final error flush. Removing the dispatch
    // entry first prevents the authority notification destroying this flush.
    _phase = _Phase.closing;
    _frameTimer?.cancel();
    server._connections.remove(id);
    server.authority.closeConnection(id);
    try {
      final encoded = const NearbyFrameCodec().encode(
        NearbyFrame({
          'v': 1,
          ...body,
          if (_lease != null) 'seq': ++_sequence,
          if (_lease != null) 'sessionEpoch': _lease!.sessionEpoch,
        }),
      );
      socket.add(encoded);
      unawaited(
        socket
            .flush()
            .timeout(const Duration(seconds: 1))
            .then(
              (_) {
                close();
              },
              onError: (Object _) {
                close();
              },
            ),
      );
    } catch (_) {
      close();
    }
  }

  void close() {
    if (_transportClosed) return;
    _transportClosed = true;
    _phase = _Phase.closing;
    if (!_closedSignal.isCompleted) _closedSignal.complete(false);
    _frameTimer?.cancel();
    _receiptCloseTimer?.cancel();
    server._connections.remove(id);
    server.authority.closeConnection(id);
    socket.destroy();
    // Canceling async* framing with a partial buffered frame can complete the
    // cancellation future with its expected EOF parse error. The lease/socket
    // are already closed; consume cleanup errors without reopening dispatch.
    unawaited(_socketSubscription?.cancel().catchError((Object _) {}));
    unawaited(_frameSubscription?.cancel().catchError((Object _) {}));
    unawaited(_input.close().catchError((Object _) {}));
  }
}

Object? _canonical(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

String _errorCode(Object error) {
  if (error is TimeoutException) return 'command_timeout';
  if (error is NearbyException &&
      const {
        'version_unsupported',
        'pairing_closed',
        'pairing_expired',
        'pairing_denied',
        'auth_failed',
        'device_revoked',
        'controller_busy',
        'session_changed',
        'room_mismatch',
        'no_media',
        'not_connected',
        'invalid_argument',
        'unsupported_command',
        'rate_limited',
        'native_failure',
        'command_timeout',
        'permission_denied',
        'lan_unavailable',
        'storage_unavailable',
      }.contains(error.code)) {
    return error.code;
  }
  return 'native_failure';
}
