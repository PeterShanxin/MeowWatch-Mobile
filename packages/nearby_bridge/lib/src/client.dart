import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'client_transport.dart';
import 'invitation.dart';
import 'lan.dart';
import 'primitives.dart';
import 'tls.dart';
import 'transcript.dart';
import 'wire.dart';

/// Implement with platform-protected storage, without a plaintext fallback.
abstract interface class NearbyClientStore {
  Future<NearbyClientCredential?> read(String desktopId);
  Future<void> write(NearbyClientCredential credential);
  Future<void> remove(String desktopId);
}

final class NearbyClientCredential {
  NearbyClientCredential({
    required this.desktopId,
    required this.tokenId,
    required this.clientId,
    required this.clientName,
    required this.endpoint,
    required List<int> certificateSha256,
    required List<int> secret,
  }) : certificateSha256 = immutableBytes(certificateSha256, 32),
       secret = immutableBytes(secret, 32) {
    decodeBytes(desktopId, 16);
    decodeBytes(tokenId, 16);
    decodeBytes(clientId, 16);
    validateName(clientName);
  }
  final String desktopId;
  final String tokenId;
  final String clientId;
  final String clientName;
  final LanEndpoint endpoint;
  final Uint8List certificateSha256;
  final Uint8List secret;
  @override
  String toString() => 'NearbyClientCredential([REDACTED])';
}

enum NearbyClientPhase {
  disconnected,
  connecting,
  pairing,
  awaitingApproval,
  saving,
  authenticating,
  connected,
  disposed,
}

final class NearbyClientState {
  const NearbyClientState(this.phase, {this.errorCode});
  final NearbyClientPhase phase;
  final String? errorCode;
}

final class _PendingCommand {
  final result = Completer<Map<String, Object?>>();
  Timer? timer;
}

/// QR-pinned LAN client. Reconnection is always an explicit caller action.
/// A fresh instance is needed after [dispose]. No command is ever retransmitted.
final class NearbyClient {
  NearbyClient({
    required NearbyClientStore store,
    SecureRandom? random,
    MonotonicClock? clock,
  }) : // Keep the protected-storage implementation private behind a public argument.
       // ignore: prefer_initializing_formals
       _store = store,
       _random = random ?? SystemSecureRandom(),
       _clock = clock ?? StopwatchClock();

  final NearbyClientStore _store;
  final SecureRandom _random;
  final MonotonicClock _clock;
  final _states = StreamController<NearbyClientState>.broadcast();
  final _events = StreamController<NearbyFrame>.broadcast();
  final _pending = <String, _PendingCommand>{};
  NearbyClientState _state = const NearbyClientState(
    NearbyClientPhase.disconnected,
  );
  ClientTransport? _transport;
  Timer? _heartbeat;
  FrameSequence _incoming = FrameSequence();
  Duration _lastInbound = Duration.zero;
  String? _epoch;
  int _seq = 0;
  int _generation = 0;
  bool _disposed = false;
  Future<void> _storeTail = Future.value();

  NearbyClientState get state => _state;
  Stream<NearbyClientState> get states => _states.stream;

  /// Authenticated state snapshots and social events only; no credential frames.
  Stream<NearbyFrame> get events => _events.stream;

  void _set(NearbyClientPhase phase, {String? errorCode}) {
    if (_disposed) return;
    _state = NearbyClientState(phase, errorCode: errorCode);
    _states.add(_state);
  }

  int _begin() {
    if (_disposed) throw const NearbyException('disposed');
    _drop();
    _set(NearbyClientPhase.connecting);
    return _generation;
  }

  void _current(int generation) {
    if (_disposed || generation != _generation) {
      throw const NearbyException('cancelled');
    }
  }

  Future<ClientTransport> _open(
    int generation,
    LanEndpoint endpoint,
    LanSubnet subnet,
    List<int> pin,
  ) async {
    subnet.requirePeer(endpoint.address.toString());
    final socket = await connectPinnedTls(
      address: InternetAddress(endpoint.address.toString()),
      port: endpoint.port,
      certificateSha256: pin,
    );
    if (_disposed || generation != _generation) {
      socket.destroy();
      throw const NearbyException('cancelled');
    }
    return _transport = ClientTransport(socket);
  }

  Future<NearbyClientCredential> pair({
    required PairingInvitation invitation,
    required LanSubnet subnet,
    required String clientName,
  }) async {
    validateName(clientName);
    final generation = _begin();
    try {
      final transport = await _open(
        generation,
        invitation.endpoint,
        subnet,
        invitation.certificateSha256,
      );
      _set(NearbyClientPhase.pairing);
      final clientId = encodeBytes(_random.bytes(16));
      final nonce = _random.bytes(32);
      await transport.send(
        _frame('pair.hello', {
          'clientId': clientId,
          'clientName': clientName,
          'clientNonce': encodeBytes(nonce),
          'pairId': invitation.pairId,
        }),
      );
      _current(generation);
      final challenge = await _expect(transport, 'pair.challenge', [
        'desktopId',
        'pairId',
        'serverNonce',
      ]);
      _current(generation);
      if (challenge['desktopId'] != invitation.desktopId ||
          challenge['pairId'] != invitation.pairId) {
        throw const NearbyException('auth_failed');
      }
      final transcript = PairingTranscript(
        desktopId: invitation.desktopId,
        pairId: invitation.pairId,
        clientId: clientId,
        clientName: clientName,
        clientNonce: nonce,
        serverNonce: _bytes(challenge, 'serverNonce', 32),
        certificateSha256: sha256
            .convert(transport.socket.peerCertificate!.der)
            .bytes,
      );
      await transport.send(
        _frame('pair.proof', {
          'proof': encodeBytes(transcript.clientProof(invitation.pairSecret)),
        }),
      );
      _current(generation);
      final pending = await _expect(transport, 'pair.pending', ['expiresInMs']);
      _current(generation);
      final expiry = pending['expiresInMs'];
      if (expiry is! int || expiry < 1 || expiry > 30000) {
        throw const NearbyException('invalid_argument');
      }
      _set(NearbyClientPhase.awaitingApproval);
      final accepted = await _expect(transport, 'pair.accept', [
        'desktopId',
        'tokenId',
        'deviceSecret',
        'serverProof',
      ], timeout: Duration(milliseconds: expiry));
      _current(generation);
      if (accepted['desktopId'] != invitation.desktopId) {
        throw const NearbyException('auth_failed');
      }
      final tokenId = _text(accepted, 'tokenId');
      final secret = _bytes(accepted, 'deviceSecret', 32);
      if (!constantTimeEqual(
        _bytes(accepted, 'serverProof', 32),
        transcript.serverProof(invitation.pairSecret, tokenId, secret),
      )) {
        throw const NearbyException('auth_failed');
      }
      final credential = NearbyClientCredential(
        desktopId: invitation.desktopId,
        tokenId: tokenId,
        clientId: clientId,
        clientName: clientName,
        endpoint: invitation.endpoint,
        certificateSha256: invitation.certificateSha256,
        secret: secret,
      );
      transport.close('not_connected');
      _transport = null;
      _set(NearbyClientPhase.saving);
      try {
        final write = _storeTail.then((_) async {
          _current(generation);
          await _store.write(credential);
        });
        _storeTail = write.catchError((Object _) {});
        await write.timeout(const Duration(seconds: 10));
      } catch (_) {
        _current(generation);
        throw const NearbyException('storage_unavailable');
      }
      _current(generation);
      _set(NearbyClientPhase.disconnected);
      return credential;
    } catch (error) {
      _failed(generation, error);
    }
  }

  Future<void> connect({
    required NearbyClientCredential credential,
    required LanSubnet subnet,
    LanEndpoint? endpoint,
  }) async {
    final generation = _begin();
    try {
      final transport = await _open(
        generation,
        endpoint ?? credential.endpoint,
        subnet,
        credential.certificateSha256,
      );
      _set(NearbyClientPhase.authenticating);
      await transport.send(_frame('auth.hello', {}));
      _current(generation);
      final challenge = await _expect(transport, 'auth.challenge', [
        'desktopId',
        'serverNonce',
      ]);
      _current(generation);
      if (challenge['desktopId'] != credential.desktopId) {
        throw const NearbyException('auth_failed');
      }
      final nonce = _random.bytes(32);
      final transcript = AuthTranscript(
        desktopId: credential.desktopId,
        tokenId: credential.tokenId,
        clientNonce: nonce,
        serverNonce: _bytes(challenge, 'serverNonce', 32),
        certificateSha256: sha256
            .convert(transport.socket.peerCertificate!.der)
            .bytes,
      );
      await transport.send(
        _frame('auth.proof', {
          'tokenId': credential.tokenId,
          'clientNonce': encodeBytes(nonce),
          'proof': encodeBytes(transcript.clientProof(credential.secret)),
        }),
      );
      _current(generation);
      final accepted = await _expect(transport, 'auth.ok', [
        'connectionId',
        'sessionEpoch',
        'serverProof',
      ]);
      _current(generation);
      final connectionId = _text(accepted, 'connectionId');
      final epoch = _text(accepted, 'sessionEpoch');
      decodeBytes(epoch, 16);
      if (!constantTimeEqual(
        _bytes(accepted, 'serverProof', 32),
        transcript.serverProof(credential.secret, connectionId),
      )) {
        throw const NearbyException('auth_failed');
      }
      _epoch = epoch;
      _seq = 0;
      _incoming = FrameSequence();
      _lastInbound = _clock.now;
      transport.onFrame = (frame) => _receive(generation, frame);
      transport.onClosed = (code) {
        if (generation == _generation) {
          _drop();
          _set(NearbyClientPhase.disconnected, errorCode: code);
        }
      };
      _set(NearbyClientPhase.connected);
      transport.dispatchQueued();
      _current(generation);
      _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
        if (_clock.now - _lastInbound >= const Duration(seconds: 15)) {
          transport.close('heartbeat_timeout');
        } else {
          unawaited(_sendAuthenticated('ping', {}).catchError((Object _) {}));
        }
      });
    } catch (error) {
      _failed(generation, error);
    }
  }

  Future<void> reconnect({
    required NearbyClientCredential credential,
    required LanSubnet subnet,
    LanEndpoint? endpoint,
  }) => connect(credential: credential, subnet: subnet, endpoint: endpoint);

  Future<Map<String, Object?>> command(
    String method, [
    Map<String, Object?> args = const {},
  ]) {
    if (_state.phase != NearbyClientPhase.connected) {
      return Future.error(const NearbyException('not_connected'));
    }
    if (_pending.length >= 32) {
      return Future.error(const NearbyException('rate_limited'));
    }
    final id = encodeBytes(_random.bytes(16));
    if (_pending.containsKey(id)) {
      return Future.error(const NearbyException('rate_limited'));
    }
    final frame = _authenticated('command', {
      'id': id,
      'method': method,
      'args': args,
    });
    // Validate all nested caller data before allocating pending state.
    const NearbyFrameCodec().encode(frame);
    final pending = _PendingCommand();
    _pending[id] = pending;
    pending.timer = Timer(const Duration(seconds: 10), () {
      _pending.remove(id);
      pending.result.completeError(const NearbyException('command_uncertain'));
      _transport?.close('command_uncertain');
    });
    final transport = _transport!;
    unawaited(
      transport.send(frame).catchError((Object _) {
        transport.close('command_uncertain');
      }),
    );
    return pending.result.future;
  }

  void _receive(int generation, NearbyFrame frame) {
    if (generation != _generation || _disposed) return;
    try {
      _incoming.accept(frame);
      final fields = frame.fields;
      if (fields['sessionEpoch'] != _epoch) {
        throw const NearbyException('session_changed');
      }
      switch (frame.type) {
        case 'ping':
        case 'pong':
          _keys(fields, ['seq', 'sessionEpoch']);
          if (frame.type == 'ping') {
            unawaited(_sendAuthenticated('pong', {}).catchError((Object _) {}));
          }
        case 'result':
          final ok = fields['ok'];
          if (ok is! bool ||
              fields['stateRevision'] is! int ||
              (fields['stateRevision']! as int) < 0) {
            throw const NearbyException('invalid_argument');
          }
          _keys(fields, [
            'seq',
            'sessionEpoch',
            'id',
            'ok',
            'stateRevision',
            if (ok) 'result' else 'error',
          ]);
          final result = fields['result'];
          if (ok && result is! Map<String, Object?>) {
            throw const NearbyException('invalid_argument');
          }
          final errorCode = ok ? null : _serverError(fields['error']);
          final pending = _pending.remove(_text(fields, 'id'));
          if (pending == null) throw const NearbyException('invalid_argument');
          pending.timer?.cancel();
          if (ok) {
            pending.result.complete(result! as Map<String, Object?>);
          } else {
            pending.result.completeError(
              NearbyException(
                errorCode == 'command_timeout'
                    ? 'command_uncertain'
                    : errorCode!,
              ),
            );
            if (errorCode == 'command_timeout') {
              _transport?.close('command_uncertain');
            }
          }
        case 'state.snapshot':
          _keys(fields, ['seq', 'sessionEpoch', 'state']);
          if (fields['state'] is! Map<String, Object?>) {
            throw const NearbyException('invalid_argument');
          }
          _events.add(frame);
        case 'error':
          _keys(fields, ['seq', 'sessionEpoch', 'error']);
          throw NearbyException(_serverError(fields['error']));
        case 'chat.message':
        case 'chat.reaction':
        case 'chat.typing':
        case 'presence':
          _keys(fields, ['seq', 'sessionEpoch', 'event']);
          if (fields['event'] is! Map<String, Object?>) {
            throw const NearbyException('invalid_argument');
          }
          _events.add(frame);
        default:
          throw const NearbyException('invalid_argument');
      }
      _lastInbound = _clock.now;
    } on NearbyException catch (error) {
      _transport?.close(error.code);
    } catch (_) {
      _transport?.close('invalid_argument');
    }
  }

  NearbyFrame _authenticated(String type, Map<String, Object?> fields) =>
      _frame(type, {'seq': ++_seq, 'sessionEpoch': _epoch, ...fields});
  Future<void> _sendAuthenticated(String type, Map<String, Object?> fields) =>
      _transport!.send(_authenticated(type, fields));

  void disconnect() {
    if (_disposed) return;
    _drop();
    _set(NearbyClientPhase.disconnected);
  }

  void _drop() {
    _generation++;
    _heartbeat?.cancel();
    _heartbeat = null;
    final transport = _transport;
    _transport = null;
    transport?.close('not_connected');
    _epoch = null;
    for (final pending in _pending.values) {
      pending.timer?.cancel();
      pending.result.completeError(const NearbyException('command_uncertain'));
    }
    _pending.clear();
  }

  Never _failed(int generation, Object error) {
    final code = error is NearbyException ? error.code : 'not_connected';
    if (generation == _generation && !_disposed) {
      _drop();
      _set(NearbyClientPhase.disconnected, errorCode: code);
    }
    throw NearbyException(code);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _drop();
    _state = const NearbyClientState(NearbyClientPhase.disposed);
    _states.add(_state);
    _disposed = true;
    await Future.wait([_states.close(), _events.close()]);
  }
}

NearbyFrame _frame(String type, Map<String, Object?> fields) =>
    NearbyFrame({'v': 1, 'type': type, ...fields});

String _text(Map<String, Object?> fields, String key) {
  final value = fields[key];
  if (value is! String) throw const NearbyException('invalid_argument');
  return value;
}

Uint8List _bytes(Map<String, Object?> fields, String key, int size) =>
    decodeBytes(_text(fields, key), size);

void _keys(Map<String, Object?> fields, List<String> names) {
  if (fields.length != names.length + 2 || !names.every(fields.containsKey)) {
    throw const NearbyException('invalid_argument');
  }
}

Future<Map<String, Object?>> _expect(
  ClientTransport transport,
  String type,
  List<String> keys, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final frame = await transport.next(timeout);
  if (frame.type == 'error') {
    _keys(frame.fields, ['error']);
    throw NearbyException(_serverError(frame.fields['error']));
  }
  if (frame.type != type) throw const NearbyException('invalid_argument');
  _keys(frame.fields, keys);
  return frame.fields;
}

String _serverError(Object? value) {
  if (value is! Map<String, Object?> ||
      value.length != 1 ||
      value['code'] is! String) {
    throw const NearbyException('invalid_argument');
  }
  final code = value['code']! as String;
  return const {
        'auth_failed',
        'version_unsupported',
        'pairing_closed',
        'pairing_expired',
        'pairing_denied',
        'approval_denied',
        'device_revoked',
        'controller_busy',
        'not_connected',
        'session_changed',
        'invalid_argument',
        'unsupported_command',
        'rate_limited',
        'storage_unavailable',
        'command_failed',
        'command_timeout',
        'native_failure',
        'room_mismatch',
        'no_media',
        'permission_denied',
        'lan_unavailable',
      }.contains(code)
      ? code
      : 'request_failed';
}
