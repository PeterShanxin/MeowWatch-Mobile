import 'dart:async';
import 'dart:typed_data';
import 'invitation.dart';
import 'lan.dart';
import 'primitives.dart';
import 'transcript.dart';

/// The implementation must use platform-protected storage. [revoke] must
/// durably tombstone/delete a credential, even if no record currently exists.
/// No file/preferences fallback is supplied by this package.
abstract interface class NearbySecretStore {
  Future<DeviceCredential?> read(String tokenId);
  Future<void> write(DeviceCredential credential);
  Future<void> revoke(String tokenId);
}

final class DeviceCredential {
  DeviceCredential({
    required this.tokenId,
    required this.clientId,
    required this.clientName,
    required List<int> secret,
    required this.lastUsedAt,
  }) : secret = immutableBytes(secret, 32) {
    decodeBytes(tokenId, 16);
    decodeBytes(clientId, 16);
    validateName(clientName);
  }
  final String tokenId;
  final String clientId;
  final String clientName;
  final Uint8List secret;
  final DateTime lastUsedAt;
  @override
  String toString() => 'DeviceCredential([REDACTED])';
}

final class PairChallenge {
  PairChallenge._(this.pairId, this.serverNonce, this.expiresAt);
  final String pairId;
  final Uint8List serverNonce;
  final Duration expiresAt;
}

final class PendingApproval {
  PendingApproval._(this.id, this.clientName, this.expiresAt);
  final String id;
  final String clientName;
  final Duration expiresAt;
}

final class PairAcceptance {
  PairAcceptance._(this.credential, this.serverProof);
  final DeviceCredential credential;
  final Uint8List serverProof;
  @override
  String toString() => 'PairAcceptance([REDACTED])';
}

final class AuthChallenge {
  AuthChallenge._(this.serverNonce, this.expiresAt);
  final Uint8List serverNonce;
  final Duration expiresAt;
}

final class ControllerLease {
  ControllerLease._(this.connectionId, this.tokenId, this.sessionEpoch);
  final String connectionId;
  final String tokenId;
  final String sessionEpoch;
}

final class AuthAcceptance {
  AuthAcceptance._(this.lease, this.serverProof);
  final ControllerLease lease;
  final Uint8List serverProof;
}

final class _Connection {
  _Connection(this.id, this.expiresAt);
  final String id;
  Duration expiresAt;
  Duration lastPersistedActivity = Duration.zero;
  DeviceCredential? credential;
  bool started = false;
  _PairAttempt? pair;
  AuthChallenge? auth;
}

final class _PairAttempt {
  _PairAttempt(
    this.invitation,
    this.invitationDeadline,
    this.clientId,
    this.clientName,
    this.transcript,
    this.challenge,
  );
  final PairingInvitation invitation;
  final Duration invitationDeadline;
  final String clientId;
  final String clientName;
  final PairingTranscript transcript;
  final PairChallenge challenge;
  bool proofUsed = false;
  PendingApproval? approval;
}

/// Single-isolate authority, independent of sockets/UI. The transport assigns
/// each socket one connection ID and must forward [connectionsToClose]. Every
/// command checks [requireLease] before execution and again after every await.
final class NearbyAuthority {
  NearbyAuthority({
    required this.desktopId,
    required List<int> certificateSha256,
    required NearbySecretStore store,
    MonotonicClock? clock,
    SecureRandom? random,
    DateTime Function()? utcNow,
  }) : certificateSha256 = immutableBytes(certificateSha256, 32),
       // Public named parameter intentionally hides the private backing field.
       // ignore: prefer_initializing_formals
       _store = store,
       _clock = clock ?? StopwatchClock(),
       _random = random ?? SystemSecureRandom(),
       _utcNow = utcNow ?? (() => DateTime.now().toUtc()) {
    decodeBytes(desktopId, 16);
    _sessionEpoch = _id();
  }
  final String desktopId;
  final Uint8List certificateSha256;
  final NearbySecretStore _store;
  final MonotonicClock _clock;
  final SecureRandom _random;
  final DateTime Function() _utcNow;
  final Map<String, _Connection> _connections = {};
  final Set<String> _revoked = {};
  final List<({Duration at, String address})> _arrivals = [];
  final _closeEvents = StreamController<String>.broadcast(sync: true);
  Future<void> _storeTail = Future.value();
  PairingInvitation? _invitation;
  Duration _invitationDeadline = Duration.zero;
  int _pairGeneration = 0;
  int _failedProofs = 0;
  bool _stopped = false;
  bool _storageFailed = false;
  ControllerLease? _lease;
  String? _controllerReservation;
  late String _sessionEpoch;
  Stream<String> get connectionsToClose => _closeEvents.stream;
  String get sessionEpoch => _sessionEpoch;
  String _id() => encodeBytes(_random.bytes(16));

  void _available() {
    if (_stopped || _storageFailed) {
      throw const NearbyException('not_connected');
    }
  }

  _Connection _connection(String id) {
    _available();
    final connection = _connections[id];
    if (connection == null) throw const NearbyException('auth_failed');
    if (_clock.now >= connection.expiresAt) {
      closeConnection(id);
      throw const NearbyException('auth_failed');
    }
    return connection;
  }

  bool _live(_Connection connection) =>
      !_stopped &&
      !_storageFailed &&
      identical(_connections[connection.id], connection);

  /// Apply after the server verifies its selected LAN prefix. IDs never come
  /// from a peer-controlled frame. Rate limits do not reset on invitation refresh.
  String openConnection({required String peerAddress}) {
    _available();
    LanIpv4Address.parse(peerAddress);
    final now = _clock.now;
    _arrivals.removeWhere((a) => now - a.at >= const Duration(minutes: 1));
    if (_connections.length >= 16 ||
        _arrivals.length >= 10 ||
        _arrivals.where((a) => a.address == peerAddress).length >= 5) {
      throw const NearbyException('rate_limited');
    }
    _arrivals.add((at: now, address: peerAddress));
    final id = _id();
    _connections[id] = _Connection(id, now + const Duration(seconds: 5));
    return id;
  }

  PairingInvitation openInvitation(LanEndpoint endpoint) {
    _available();
    cancelInvitation();
    _failedProofs = 0;
    _invitationDeadline = _clock.now + const Duration(seconds: 120);
    return _invitation = PairingInvitation(
      desktopId: desktopId,
      pairId: _id(),
      endpoint: endpoint,
      certificateSha256: certificateSha256,
      pairSecret: _random.bytes(16),
    );
  }

  void cancelInvitation() {
    _pairGeneration++;
    _invitation = null;
    final pending = _connections.values
        .where((c) => c.pair != null)
        .map((c) => c.id)
        .toList();
    for (final id in pending) {
      closeConnection(id);
    }
  }

  PairChallenge beginPairing({
    required String connectionId,
    required String clientId,
    required String clientName,
    required List<int> clientNonce,
    String? pairId,
  }) {
    final connection = _connection(connectionId);
    final invitation = _invitation;
    if (invitation == null) throw const NearbyException('pairing_closed');
    if (_clock.now >= _invitationDeadline) {
      cancelInvitation();
      throw const NearbyException('pairing_expired');
    }
    if (connection.started || (pairId != null && pairId != invitation.pairId)) {
      throw const NearbyException('auth_failed');
    }
    // Expired attempts are retired before applying the global pending limit.
    for (final c in _connections.values.toList()) {
      final attempt = c.pair;
      if (attempt != null &&
          _clock.now >=
              (attempt.approval?.expiresAt ?? attempt.challenge.expiresAt)) {
        closeConnection(c.id);
      }
    }
    if (_connections.values.where((c) => c.pair != null).length >= 4) {
      throw const NearbyException('rate_limited');
    }
    final challenge = PairChallenge._(
      invitation.pairId,
      immutableBytes(_random.bytes(32), 32),
      _clock.now + const Duration(seconds: 10),
    );
    final transcript = PairingTranscript(
      desktopId: desktopId,
      pairId: invitation.pairId,
      clientId: clientId,
      clientName: clientName,
      clientNonce: clientNonce,
      serverNonce: challenge.serverNonce,
      certificateSha256: certificateSha256,
    );
    connection.started = true;
    connection.expiresAt = challenge.expiresAt;
    connection.pair = _PairAttempt(
      invitation,
      _invitationDeadline,
      clientId,
      clientName,
      transcript,
      challenge,
    );
    return challenge;
  }

  PendingApproval verifyPairingProof(String connectionId, List<int> proof) {
    final connection = _connection(connectionId);
    final attempt = connection.pair;
    if (attempt == null ||
        attempt.proofUsed ||
        !identical(attempt.invitation, _invitation) ||
        _clock.now >= attempt.challenge.expiresAt ||
        _clock.now >= attempt.invitationDeadline) {
      closeConnection(connectionId);
      throw const NearbyException('auth_failed');
    }
    attempt.proofUsed = true;
    if (!constantTimeEqual(
      attempt.transcript.clientProof(attempt.invitation.pairSecret),
      proof,
    )) {
      _failedProofs++;
      closeConnection(connectionId);
      if (_failedProofs >= 5) cancelInvitation();
      throw const NearbyException('auth_failed');
    }
    var deadline = _clock.now + const Duration(seconds: 30);
    if (deadline > attempt.invitationDeadline) {
      deadline = attempt.invitationDeadline;
    }
    connection.expiresAt = deadline;
    return attempt.approval = PendingApproval._(
      _id(),
      attempt.clientName,
      deadline,
    );
  }

  Future<PairAcceptance> approvePairing(String approvalId) async {
    _available();
    final matches = _connections.values.where(
      (c) => c.pair?.approval?.id == approvalId,
    );
    if (matches.isEmpty) throw const NearbyException('pairing_expired');
    final connection = matches.first;
    final attempt = connection.pair!;
    final approval = attempt.approval!;
    if (_clock.now >= approval.expiresAt ||
        !identical(attempt.invitation, _invitation)) {
      closeConnection(connection.id);
      throw const NearbyException('pairing_expired');
    }
    // Reserve before the first await. Concurrent approvals cannot both consume.
    _invitation = null;
    attempt.approval = null;
    final generation = ++_pairGeneration;
    for (final c in _connections.values.toList()) {
      if (c != connection && c.pair != null) closeConnection(c.id);
    }
    final credential = DeviceCredential(
      tokenId: _id(),
      clientId: attempt.clientId,
      clientName: attempt.clientName,
      secret: _random.bytes(32),
      lastUsedAt: _utcNow(),
    );
    await _storage(() => _store.write(credential));
    if (!_live(connection) ||
        generation != _pairGeneration ||
        _clock.now >= approval.expiresAt) {
      await revoke(credential.tokenId);
      throw const NearbyException('pairing_expired');
    }
    final result = PairAcceptance._(
      credential,
      attempt.transcript.serverProof(
        attempt.invitation.pairSecret,
        credential.tokenId,
        credential.secret,
      ),
    );
    // Pairing has no controller lease. Reconnect with the stored credential.
    connection.pair = null;
    return result;
  }

  void denyPairing(String approvalId) {
    for (final c in _connections.values.toList()) {
      if (c.pair?.approval?.id == approvalId) closeConnection(c.id);
    }
  }

  AuthChallenge beginAuthentication(String connectionId) {
    final connection = _connection(connectionId);
    if (connection.started) throw const NearbyException('auth_failed');
    connection.started = true;
    connection.expiresAt = _clock.now + const Duration(seconds: 5);
    return connection.auth = AuthChallenge._(
      immutableBytes(_random.bytes(32), 32),
      connection.expiresAt,
    );
  }

  Future<AuthAcceptance> authenticate({
    required String connectionId,
    required String tokenId,
    required List<int> clientNonce,
    required List<int> proof,
  }) async {
    final connection = _connection(connectionId);
    final challenge = connection.auth;
    connection.auth =
        null; // Consume before storage awaits or proof verification.
    if (challenge == null ||
        _clock.now >= challenge.expiresAt ||
        _revoked.contains(tokenId)) {
      closeConnection(connectionId);
      throw const NearbyException('auth_failed');
    }
    final transcript = AuthTranscript(
      desktopId: desktopId,
      tokenId: tokenId,
      clientNonce: clientNonce,
      serverNonce: challenge.serverNonce,
      certificateSha256: certificateSha256,
    );
    final credential = await _storage(() => _store.read(tokenId));
    final now = _utcNow();
    if (!_live(connection) ||
        _clock.now >= challenge.expiresAt ||
        credential == null ||
        credential.tokenId != tokenId ||
        _revoked.contains(tokenId) ||
        now.isBefore(credential.lastUsedAt) ||
        now.difference(credential.lastUsedAt) >= const Duration(days: 30) ||
        !constantTimeEqual(transcript.clientProof(credential.secret), proof)) {
      closeConnection(connectionId);
      throw const NearbyException('auth_failed');
    }
    if (_lease != null || _controllerReservation != null) {
      closeConnection(connectionId);
      throw const NearbyException('controller_busy');
    }
    _controllerReservation = connectionId;
    final epoch = _sessionEpoch;
    try {
      await _storage(
        () => _store.write(
          DeviceCredential(
            tokenId: tokenId,
            clientId: credential.clientId,
            clientName: credential.clientName,
            secret: credential.secret,
            lastUsedAt: now,
          ),
        ),
      );
      if (!_live(connection) ||
          _revoked.contains(tokenId) ||
          epoch != _sessionEpoch ||
          _clock.now >= challenge.expiresAt) {
        throw const NearbyException('auth_failed');
      }
      final lease = ControllerLease._(connectionId, tokenId, epoch);
      _lease = lease;
      connection.expiresAt = _clock.now + const Duration(seconds: 15);
      connection.lastPersistedActivity = _clock.now;
      connection.credential = credential;
      return AuthAcceptance._(
        lease,
        transcript.serverProof(credential.secret, connectionId),
      );
    } finally {
      if (_controllerReservation == connectionId) _controllerReservation = null;
    }
  }

  void requireLease(ControllerLease lease, {required String sessionEpoch}) {
    _available();
    if (!identical(_lease, lease) ||
        !_connections.containsKey(lease.connectionId) ||
        _revoked.contains(lease.tokenId)) {
      throw const NearbyException('auth_failed');
    }
    if (_clock.now >= _connections[lease.connectionId]!.expiresAt) {
      closeConnection(lease.connectionId);
      throw const NearbyException('not_connected');
    }
    if (sessionEpoch != _sessionEpoch || lease.sessionEpoch != _sessionEpoch) {
      throw const NearbyException('session_changed');
    }
  }

  /// Call only for an authenticated, sequence-checked inbound frame.
  Future<void> recordActivity(
    ControllerLease lease, {
    required String sessionEpoch,
  }) async {
    requireLease(lease, sessionEpoch: sessionEpoch);
    final connection = _connections[lease.connectionId]!;
    connection.expiresAt = _clock.now + const Duration(seconds: 15);
    // Bound secure-storage writes while keeping long-lived controllers active.
    if (_clock.now - connection.lastPersistedActivity <
        const Duration(hours: 1)) {
      return;
    }
    final credential = connection.credential!;
    final now = _utcNow();
    if (now.isBefore(credential.lastUsedAt)) {
      closeConnection(lease.connectionId);
      throw const NearbyException('auth_failed');
    }
    connection.lastPersistedActivity = _clock.now;
    final updated = DeviceCredential(
      tokenId: credential.tokenId,
      clientId: credential.clientId,
      clientName: credential.clientName,
      secret: credential.secret,
      lastUsedAt: now,
    );
    connection.credential = updated;
    await _storage(() => _store.write(updated));
    requireLease(lease, sessionEpoch: sessionEpoch);
  }

  /// The transport calls this from its heartbeat timer; it performs no I/O.
  void expire() {
    if (_invitation != null && _clock.now >= _invitationDeadline) {
      cancelInvitation();
    }
    for (final connection in _connections.values.toList()) {
      if (_clock.now >= connection.expiresAt) closeConnection(connection.id);
    }
  }

  /// Room replacement invalidates all old command handles and reconnects the
  /// controller. This avoids silently extending an old lease into a new room.
  void replaceSession() {
    _sessionEpoch = _id();
    if (_lease case final lease?) {
      closeConnection(lease.connectionId);
    }
  }

  void closeConnection(String connectionId) {
    if (_connections.remove(connectionId) == null) return;
    if (_lease?.connectionId == connectionId) _lease = null;
    if (_controllerReservation == connectionId) _controllerReservation = null;
    _closeEvents.add(connectionId);
  }

  Future<void> revoke(String tokenId) async {
    decodeBytes(tokenId, 16);
    _revoked.add(tokenId); // Immediate, including while persistence is pending.
    if (_lease?.tokenId == tokenId) closeConnection(_lease!.connectionId);
    await _storage(() => _store.revoke(tokenId));
  }

  /// Retire the authenticated requester immediately, retaining no command
  /// authority while durable revocation is pending. The transport owns the
  /// now unauthorised socket solely to send the final durability receipt, then
  /// close it; unlike [revoke], no immediate socket-close event is emitted.
  /// A failed store still stops this authority and must never be acknowledged
  /// as successful revocation.
  Future<void> revokeForAcknowledgement(ControllerLease lease) async {
    requireLease(lease, sessionEpoch: lease.sessionEpoch);
    _revoked.add(lease.tokenId);
    _lease = null;
    _connections.remove(lease.connectionId);
    if (_controllerReservation == lease.connectionId) {
      _controllerReservation = null;
    }
    await _storage(() => _store.revoke(lease.tokenId));
  }

  /// Stop is terminal for this authority. Stored pairings remain unless revoked.
  void stop() {
    if (_stopped) return;
    _stopped = true;
    cancelInvitation();
    for (final id in _connections.keys.toList()) {
      closeConnection(id);
    }
  }

  Future<void> dispose() async {
    stop();
    await _storeTail;
    await _closeEvents.close();
  }

  Future<T> _storage<T>(Future<T> Function() operation) {
    final done = Completer<T>();
    _storeTail = _storeTail.then((_) async {
      try {
        done.complete(await operation());
      } catch (_) {
        _storageFailed = true;
        stop();
        done.completeError(const NearbyException('storage_unavailable'));
      }
    });
    return done.future;
  }
}
