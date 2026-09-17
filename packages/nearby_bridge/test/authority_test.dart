import 'dart:async';
import 'package:nearby_bridge/nearby_bridge.dart';
import 'package:test/test.dart';

final class TestClock implements MonotonicClock {
  @override
  Duration now = Duration.zero;
}

final class TestStore implements NearbySecretStore {
  final records = <String, DeviceCredential>{};
  Completer<void>? writeGate;
  Completer<void>? revokeGate;
  bool fail = false;
  @override
  Future<DeviceCredential?> read(String tokenId) async => records[tokenId];
  @override
  Future<void> write(DeviceCredential credential) async {
    await writeGate?.future;
    if (fail) throw StateError('protected store unavailable');
    records[credential.tokenId] = credential;
  }

  @override
  Future<void> revoke(String tokenId) async {
    await revokeGate?.future;
    records.remove(tokenId);
  }
}

void main() {
  final desktop = encodeBytes(List.filled(16, 1));
  final client = encodeBytes(List.filled(16, 2));
  final pin = List.filled(32, 3);
  final nonce = List.filled(32, 4);
  final endpoint = LanEndpoint(
    address: LanIpv4Address.parse('192.168.1.10'),
    port: 1234,
  );
  late TestClock clock;
  late TestStore store;
  late NearbyAuthority authority;
  late DateTime utc;
  var addressSuffix = 20;
  String connection() =>
      authority.openConnection(peerAddress: '192.168.1.${addressSuffix++}');
  ({String socket, PendingApproval approval, PairingTranscript transcript})
  request(PairingInvitation invitation, {String? socket}) {
    final id = socket ?? connection();
    final challenge = authority.beginPairing(
      connectionId: id,
      clientId: client,
      clientName: 'Phone',
      clientNonce: nonce,
      pairId: invitation.pairId,
    );
    final transcript = PairingTranscript(
      desktopId: desktop,
      pairId: invitation.pairId,
      clientId: client,
      clientName: 'Phone',
      clientNonce: nonce,
      serverNonce: challenge.serverNonce,
      certificateSha256: pin,
    );
    final approval = authority.verifyPairingProof(
      id,
      transcript.clientProof(invitation.pairSecret),
    );
    return (socket: id, approval: approval, transcript: transcript);
  }

  Future<PairAcceptance> pair() async {
    final invitation = authority.openInvitation(endpoint);
    final pending = request(invitation);
    return authority.approvePairing(pending.approval.id);
  }

  ({
    String socket,
    AuthTranscript transcript,
    Future<AuthAcceptance> Function() send,
  })
  authenticate(DeviceCredential credential) {
    final socket = connection();
    final challenge = authority.beginAuthentication(socket);
    final transcript = AuthTranscript(
      desktopId: desktop,
      tokenId: credential.tokenId,
      clientNonce: nonce,
      serverNonce: challenge.serverNonce,
      certificateSha256: pin,
    );
    return (
      socket: socket,
      transcript: transcript,
      send: () => authority.authenticate(
        connectionId: socket,
        tokenId: credential.tokenId,
        clientNonce: nonce,
        proof: transcript.clientProof(credential.secret),
      ),
    );
  }

  setUp(() {
    addressSuffix = 20;
    clock = TestClock();
    store = TestStore();
    utc = DateTime.utc(2026, 9, 16);
    authority = NearbyAuthority(
      desktopId: desktop,
      certificateSha256: pin,
      store: store,
      clock: clock,
      utcNow: () => utc,
    );
  });
  tearDown(() => authority.dispose());

  test(
    'approval persists before accept; fresh auth grants one revocable lease',
    () async {
      final invitation = authority.openInvitation(endpoint);
      final pending = request(invitation);
      expect(store.records, isEmpty);
      final paired = await authority.approvePairing(pending.approval.id);
      expect(store.records.length, 1);
      expect(
        paired.serverProof,
        pending.transcript.serverProof(
          invitation.pairSecret,
          paired.credential.tokenId,
          paired.credential.secret,
        ),
      );
      final auth = authenticate(paired.credential);
      final accepted = await auth.send();
      expect(
        accepted.serverProof,
        auth.transcript.serverProof(paired.credential.secret, auth.socket),
      );
      authority.requireLease(
        accepted.lease,
        sessionEpoch: authority.sessionEpoch,
      );
      final closeEvents = <String>[];
      final sub = authority.connectionsToClose.listen(closeEvents.add);
      await authority.revoke(paired.credential.tokenId);
      expect(closeEvents, contains(auth.socket));
      expect(
        () => authority.requireLease(
          accepted.lease,
          sessionEpoch: authority.sessionEpoch,
        ),
        throwsA(isA<NearbyException>()),
      );
      expect(store.records, isEmpty);
      await expectLater(
        authenticate(paired.credential).send(),
        throwsA(isA<NearbyException>()),
      );
      await sub.cancel();
    },
  );

  test(
    'receipt-only revocation retires lease before durable store completes',
    () async {
      final paired = await pair();
      final accepted = await authenticate(paired.credential).send();
      final closures = <String>[];
      final subscription = authority.connectionsToClose.listen(closures.add);
      store.revokeGate = Completer<void>();
      final pending = authority.revokeForAcknowledgement(accepted.lease);
      try {
        expect(
          () => authority.requireLease(
            accepted.lease,
            sessionEpoch: authority.sessionEpoch,
          ),
          throwsA(isA<NearbyException>()),
        );
        expect(closures, isNot(contains(accepted.lease.connectionId)));
        expect(store.records.containsKey(paired.credential.tokenId), true);
        await expectLater(
          authenticate(paired.credential).send(),
          throwsA(isA<NearbyException>()),
        );
      } finally {
        store.revokeGate!.complete();
      }
      await pending;
      expect(store.records, isEmpty);
      expect(
        () => authority.requireLease(
          accepted.lease,
          sessionEpoch: authority.sessionEpoch,
        ),
        throwsA(isA<NearbyException>()),
      );
      await subscription.cancel();
    },
  );

  test('proof is bound to socket nonce; cannot replay on a second socket', () {
    final invitation = authority.openInvitation(endpoint);
    final first = request(invitation);
    final second = connection();
    authority.beginPairing(
      connectionId: second,
      clientId: client,
      clientName: 'Phone',
      clientNonce: nonce,
    );
    expect(
      () => authority.verifyPairingProof(
        second,
        first.transcript.clientProof(invitation.pairSecret),
      ),
      throwsA(isA<NearbyException>()),
    );
    expect(
      () => authority.verifyPairingProof(
        first.socket,
        first.transcript.clientProof(invitation.pairSecret),
      ),
      throwsA(isA<NearbyException>()),
    );
  });

  test('different actual TLS certificate fails before owner approval', () {
    final invitation = authority.openInvitation(endpoint);
    final socket = connection();
    final challenge = authority.beginPairing(
      connectionId: socket,
      clientId: client,
      clientName: 'Phone',
      clientNonce: nonce,
    );
    final relayed = PairingTranscript(
      desktopId: desktop,
      pairId: invitation.pairId,
      clientId: client,
      clientName: 'Phone',
      clientNonce: nonce,
      serverNonce: challenge.serverNonce,
      certificateSha256: List.filled(32, 8),
    );
    expect(
      () => authority.verifyPairingProof(
        socket,
        relayed.clientProof(invitation.pairSecret),
      ),
      throwsA(isA<NearbyException>()),
    );
    expect(store.records, isEmpty);
  });

  test(
    'expired challenge and invitation are fail closed with monotonic time',
    () {
      final invitation = authority.openInvitation(endpoint);
      final socket = connection();
      final challenge = authority.beginPairing(
        connectionId: socket,
        clientId: client,
        clientName: 'Phone',
        clientNonce: nonce,
      );
      clock.now = const Duration(seconds: 10);
      final transcript = PairingTranscript(
        desktopId: desktop,
        pairId: invitation.pairId,
        clientId: client,
        clientName: 'Phone',
        clientNonce: nonce,
        serverNonce: challenge.serverNonce,
        certificateSha256: pin,
      );
      expect(
        () => authority.verifyPairingProof(
          socket,
          transcript.clientProof(invitation.pairSecret),
        ),
        throwsA(isA<NearbyException>()),
      );
      clock.now = const Duration(seconds: 120);
      expect(() => request(invitation), throwsA(isA<NearbyException>()));
    },
  );

  test(
    'denial, refresh and approval expiry never create a credential',
    () async {
      var invitation = authority.openInvitation(endpoint);
      var pending = request(invitation);
      authority.denyPairing(pending.approval.id);
      await expectLater(
        authority.approvePairing(pending.approval.id),
        throwsA(isA<NearbyException>()),
      );
      pending = request(invitation);
      invitation = authority.openInvitation(endpoint);
      await expectLater(
        authority.approvePairing(pending.approval.id),
        throwsA(isA<NearbyException>()),
      );
      pending = request(invitation);
      clock.now += const Duration(seconds: 30);
      await expectLater(
        authority.approvePairing(pending.approval.id),
        throwsA(isA<NearbyException>()),
      );
      expect(store.records, isEmpty);
    },
  );

  test(
    'invitation can be consumed once while persistence is delayed',
    () async {
      final invitation = authority.openInvitation(endpoint);
      final first = request(invitation);
      final second = request(invitation);
      store.writeGate = Completer<void>();
      final accepted = authority.approvePairing(first.approval.id);
      await expectLater(
        authority.approvePairing(second.approval.id),
        throwsA(isA<NearbyException>()),
      );
      store.writeGate!.complete();
      await accepted;
      expect(store.records.length, 1);
    },
  );

  for (final action in ['cancel', 'close', 'expire', 'stop']) {
    test(
      '$action during secure-store write rolls back pending approval',
      () async {
        final pending = request(authority.openInvitation(endpoint));
        store.writeGate = Completer<void>();
        final future = authority.approvePairing(pending.approval.id);
        final rejected = expectLater(future, throwsA(isA<NearbyException>()));
        switch (action) {
          case 'cancel':
            authority.cancelInvitation();
          case 'close':
            authority.closeConnection(pending.socket);
          case 'expire':
            clock.now += const Duration(seconds: 30);
          case 'stop':
            authority.stop();
        }
        store.writeGate!.complete();
        await rejected;
        expect(store.records, isEmpty);
      },
    );
  }

  test('secure-store failure grants nothing and stops authority', () async {
    store.fail = true;
    await expectLater(pair(), throwsA(isA<NearbyException>()));
    expect(store.records, isEmpty);
    expect(() => connection(), throwsA(isA<NearbyException>()));
  });

  test('two auth calls cannot reuse a consumed challenge', () async {
    final paired = await pair();
    final auth = authenticate(paired.credential);
    final first = auth.send();
    final firstCheck = expectLater(first, throwsA(isA<NearbyException>()));
    await expectLater(auth.send(), throwsA(isA<NearbyException>()));
    await firstCheck; // Replay closes the socket, invalidating even pending auth.
  });

  test(
    'controller reservation excludes concurrent auth while storage awaits',
    () async {
      final paired = await pair();
      store.writeGate = Completer<void>();
      final first = authenticate(paired.credential).send();
      // Let first read complete and reserve the lease before starting a second.
      await Future<void>.delayed(Duration.zero);
      final second = authenticate(paired.credential).send();
      final rejection = expectLater(second, throwsA(isA<NearbyException>()));
      store.writeGate!.complete();
      final accepted = await first;
      await rejection;
      authority.requireLease(
        accepted.lease,
        sessionEpoch: authority.sessionEpoch,
      );
    },
  );

  test(
    'revocation during auth storage await prevents late lease and resurrection',
    () async {
      final paired = await pair();
      store.writeGate = Completer<void>();
      final future = authenticate(paired.credential).send();
      final rejected = expectLater(future, throwsA(isA<NearbyException>()));
      await Future<void>.delayed(Duration.zero);
      final revoked = authority.revoke(paired.credential.tokenId);
      store.writeGate!.complete();
      await rejected;
      await revoked;
      expect(store.records, isEmpty);
    },
  );

  test(
    '15-second heartbeat expiry and room replacement invalidate handles',
    () async {
      final paired = await pair();
      var accepted = await authenticate(paired.credential).send();
      final oldEpoch = authority.sessionEpoch;
      clock.now += const Duration(seconds: 14);
      await authority.recordActivity(accepted.lease, sessionEpoch: oldEpoch);
      clock.now += const Duration(seconds: 15);
      expect(
        () => authority.requireLease(accepted.lease, sessionEpoch: oldEpoch),
        throwsA(isA<NearbyException>()),
      );
      accepted = await authenticate(paired.credential).send();
      authority.replaceSession();
      expect(authority.sessionEpoch, isNot(oldEpoch));
      expect(
        () => authority.requireLease(accepted.lease, sessionEpoch: oldEpoch),
        throwsA(isA<NearbyException>()),
      );
    },
  );

  test(
    'auth expires at five seconds; inactive and clock-rollback records fail',
    () async {
      final paired = await pair();
      final auth = authenticate(paired.credential);
      clock.now += const Duration(seconds: 5);
      await expectLater(auth.send(), throwsA(isA<NearbyException>()));
      utc = utc.add(const Duration(days: 30));
      await expectLater(
        authenticate(paired.credential).send(),
        throwsA(isA<NearbyException>()),
      );
      utc = utc.subtract(const Duration(days: 31));
      await expectLater(
        authenticate(paired.credential).send(),
        throwsA(isA<NearbyException>()),
      );
    },
  );

  test('active controller updates protected last-use at most hourly', () async {
    final paired = await pair();
    final accepted = await authenticate(paired.credential).send();
    final initial = utc;
    for (var i = 0; i < 360; i++) {
      clock.now += const Duration(seconds: 10);
      utc = utc.add(const Duration(seconds: 10));
      await authority.recordActivity(
        accepted.lease,
        sessionEpoch: authority.sessionEpoch,
      );
      if (i == 358) {
        expect(store.records[paired.credential.tokenId]!.lastUsedAt, initial);
      }
    }
    expect(
      store.records[paired.credential.tokenId]!.lastUsedAt,
      initial.add(const Duration(hours: 1)),
    );
  });

  test(
    'global arrival cap survives invitation refresh and different addresses',
    () {
      for (var i = 0; i < 10; i++) {
        authority.closeConnection(connection());
      }
      authority.openInvitation(endpoint);
      expect(() => connection(), throwsA(isA<NearbyException>()));
      clock.now += const Duration(minutes: 1);
      expect(connection(), isNotEmpty);
    },
  );

  test('pending challenges and bad proofs are globally bounded', () {
    final invitation = authority.openInvitation(endpoint);
    final ids = <String>[];
    for (var i = 0; i < 4; i++) {
      final socket = connection();
      ids.add(socket);
      authority.beginPairing(
        connectionId: socket,
        clientId: client,
        clientName: 'Phone',
        clientNonce: nonce,
      );
    }
    expect(() => request(invitation), throwsA(isA<NearbyException>()));
    for (final socket in ids) {
      expect(
        () => authority.verifyPairingProof(socket, List.filled(32, 0)),
        throwsA(isA<NearbyException>()),
      );
    }
    final socket = connection();
    authority.beginPairing(
      connectionId: socket,
      clientId: client,
      clientName: 'Phone',
      clientNonce: nonce,
    );
    expect(
      () => authority.verifyPairingProof(socket, List.filled(32, 0)),
      throwsA(isA<NearbyException>()),
    );
    expect(() => request(invitation), throwsA(isA<NearbyException>()));
  });

  test(
    'per-address arrival limit allows normal pairing/reconnect but stays bounded',
    () {
      for (var i = 0; i < 5; i++) {
        authority.closeConnection(
          authority.openConnection(peerAddress: '192.168.1.50'),
        );
      }
      expect(
        () => authority.openConnection(peerAddress: '192.168.1.50'),
        throwsA(isA<NearbyException>()),
      );
      expect(authority.openConnection(peerAddress: '192.168.1.51'), isNotEmpty);
    },
  );
}
