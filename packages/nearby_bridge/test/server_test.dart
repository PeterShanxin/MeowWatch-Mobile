import 'dart:async';
import 'dart:io';
import 'package:nearby_bridge/nearby_bridge.dart';
import 'package:test/test.dart';

final class _Store implements NearbySecretStore {
  final records = <String, DeviceCredential>{};
  Completer<void>? revokeGate;
  Completer<void>? revokeEntered;
  bool failRevoke = false;
  int reads = 0;
  @override
  Future<DeviceCredential?> read(String id) async {
    reads++;
    return records[id];
  }

  @override
  Future<void> write(DeviceCredential credential) async {
    records[credential.tokenId] = credential;
  }

  @override
  Future<void> revoke(String id) async {
    if (revokeEntered != null && !revokeEntered!.isCompleted) {
      revokeEntered!.complete();
    }
    await revokeGate?.future;
    if (failRevoke) throw StateError('protected storage unavailable');
    records.remove(id);
  }
}

final class _Handler implements NearbyCommandHandler {
  final controller = StreamController<NearbyServerEvent>.broadcast(sync: true);
  final calls = <String>[];
  final effects = <String>[];
  Completer<void>? gate;
  Completer<void>? entered;
  Object? error;
  @override
  int stateRevision = 0;
  @override
  Map<String, Object?> get snapshot => {
    'desktop': {
      'id': 'desktop',
      'name': 'Test desktop',
      'protocolVersion': 1,
      'capabilities': [],
    },
    'session': {
      'epoch': 'adapter-epoch',
      'mode': 'local',
      'connection': 'connected',
    },
    'playback': {
      'revision': stateRevision,
      'sampledAtUnixMs': 1,
      'positionMs': 0,
      'playing': false,
      'status': 'ready',
    },
    'participants': [],
    'chat': [],
  };
  @override
  Stream<NearbyServerEvent> get events => controller.stream;
  @override
  Future<Map<String, Object?>> handle(NearbyCommand command) async {
    command.checkActive();
    calls.add(command.method);
    if (entered != null && !entered!.isCompleted) entered!.complete();
    await gate?.future;
    command.checkActive();
    if (error != null) throw error!;
    effects.add(command.method);
    stateRevision++;
    return {};
  }
}

final class _Peer {
  _Peer(this.socket)
    : frames = StreamIterator(
        socket.cast<List<int>>().transform(const JsonLineDecoder()),
      );
  final SecureSocket socket;
  final StreamIterator<NearbyFrame> frames;
  int sequence = 0;
  String epoch = '';
  void send(Map<String, Object?> fields) => socket.add(
    const NearbyFrameCodec().encode(NearbyFrame({'v': 1, ...fields})),
  );
  Future<NearbyFrame> next() async {
    if (!await frames.moveNext().timeout(const Duration(seconds: 5))) {
      throw StateError('connection closed');
    }
    return frames.current;
  }

  void command(
    String id,
    String method, [
    Map<String, Object?> args = const {},
  ]) => send({
    'type': 'command',
    'seq': ++sequence,
    'sessionEpoch': epoch,
    'id': id,
    'method': method,
    'args': args,
  });
  Future<NearbyFrame> result(String id) async {
    while (true) {
      final frame = await next();
      if (frame.type == 'error' ||
          (frame.type == 'result' && frame.fields['id'] == id)) {
        return frame;
      }
    }
  }

  Future<void> dispose() async {
    socket.destroy();
    await frames.cancel();
  }
}

void main() {
  late TlsIdentity identity;
  late NearbyServer server;
  late NearbyAuthority authority;
  late _Store store;
  late _Handler handler;
  final peers = <_Peer>[];
  late DeviceCredential credential;
  Future<bool> Function(PendingApproval) approval = (_) async => true;
  final desktopId = encodeBytes(List.filled(16, 1));
  final clientId = encodeBytes(List.filled(16, 2));
  final clientNonce = List.filled(32, 3);

  Future<_Peer> peer({bool login = false}) async {
    final peer = _Peer(
      await connectPinnedTls(
        address: InternetAddress.loopbackIPv4,
        port: server.port,
        certificateSha256: identity.certificateSha256,
      ),
    );
    peers.add(peer);
    if (login) {
      peer.send({'type': 'auth.hello'});
      final challenge = await peer.next();
      expect(challenge.type, 'auth.challenge');
      final transcript = AuthTranscript(
        desktopId: desktopId,
        tokenId: credential.tokenId,
        clientNonce: clientNonce,
        serverNonce: decodeBytes(
          challenge.fields['serverNonce']! as String,
          32,
        ),
        certificateSha256: identity.certificateSha256,
      );
      peer.send({
        'type': 'auth.proof',
        'tokenId': credential.tokenId,
        'clientNonce': encodeBytes(clientNonce),
        'proof': encodeBytes(transcript.clientProof(credential.secret)),
      });
      final accepted = await peer.next();
      expect(accepted.type, 'auth.ok');
      expect(
        decodeBytes(accepted.fields['serverProof']! as String, 32),
        transcript.serverProof(
          credential.secret,
          accepted.fields['connectionId']! as String,
        ),
      );
      peer.epoch = accepted.fields['sessionEpoch']! as String;
      final snapshot = await peer.next();
      expect(snapshot.type, 'state.snapshot');
      expect(snapshot.fields['seq'], 1);
    }
    return peer;
  }

  setUpAll(() async {
    identity = await TlsIdentity.generate();
  });
  setUp(() async {
    store = _Store();
    handler = _Handler();
    approval = (_) async => true;
    credential = DeviceCredential(
      tokenId: encodeBytes(List.filled(16, 4)),
      clientId: clientId,
      clientName: 'Phone',
      secret: List.filled(32, 5),
      lastUsedAt: DateTime.now().toUtc(),
    );
    store.records[credential.tokenId] = credential;
    authority = NearbyAuthority(
      desktopId: desktopId,
      certificateSha256: identity.certificateSha256,
      store: store,
    );
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    var address = 20;
    server = NearbyServer.forTesting(
      listener: listener,
      identity: identity,
      authority: authority,
      handler: handler,
      approvePairing: (request) => approval(request),
      peerAddressForTesting: (_) => '192.168.1.${address++}',
      commandTimeout: const Duration(milliseconds: 300),
    );
  });
  tearDown(() async {
    if (store.revokeGate != null && !store.revokeGate!.isCompleted) {
      store.revokeGate!.complete();
    }
    if (handler.gate != null && !handler.gate!.isCompleted) {
      handler.gate!.complete();
    }
    for (final peer in peers) {
      await peer.dispose();
    }
    peers.clear();
    await server.close();
    await handler.controller.close();
  });

  test(
    'real TLS approved pairing produces verifiable credential, then fresh authentication',
    () async {
      final invitation = authority.openInvitation(
        LanEndpoint(
          address: LanIpv4Address.parse('192.168.1.10'),
          port: server.port,
        ),
      );
      final gate = Completer<bool>();
      approval = (_) => gate.future;
      final phone = await peer();
      phone.send({
        'type': 'pair.hello',
        'clientId': clientId,
        'clientName': 'Phone',
        'clientNonce': encodeBytes(clientNonce),
        'pairId': invitation.pairId,
      });
      final challenge = await phone.next();
      final transcript = PairingTranscript(
        desktopId: desktopId,
        pairId: invitation.pairId,
        clientId: clientId,
        clientName: 'Phone',
        clientNonce: clientNonce,
        serverNonce: decodeBytes(
          challenge.fields['serverNonce']! as String,
          32,
        ),
        certificateSha256: identity.certificateSha256,
      );
      phone.send({
        'type': 'pair.proof',
        'proof': encodeBytes(transcript.clientProof(invitation.pairSecret)),
      });
      expect((await phone.next()).type, 'pair.pending');
      expect(store.records.length, 1);
      expect(handler.calls, isEmpty);
      gate.complete(true);
      final accepted = await phone.next();
      expect(accepted.type, 'pair.accept');
      final token = accepted.fields['tokenId']! as String;
      final secret = decodeBytes(
        accepted.fields['deviceSecret']! as String,
        32,
      );
      expect(
        decodeBytes(accepted.fields['serverProof']! as String, 32),
        transcript.serverProof(invitation.pairSecret, token, secret),
      );
      credential = store.records[token]!;
      final active = await peer(login: true);
      active.command('play', 'playback.play');
      expect((await active.result('play')).fields['ok'], true);
      expect(handler.effects, ['playback.play']);
    },
  );

  test(
    'no application command or snapshot is available before authentication',
    () async {
      final phone = await peer();
      phone.epoch = authority.sessionEpoch;
      phone.command('early', 'playback.play');
      final failure = await phone.next();
      expect(failure.type, 'error');
      expect(failure.fields['error'], {'code': 'auth_failed'});
      expect(handler.calls, isEmpty);
    },
  );

  test('pending owner approval cannot be bypassed by a command', () async {
    final invitation = authority.openInvitation(
      LanEndpoint(
        address: LanIpv4Address.parse('192.168.1.10'),
        port: server.port,
      ),
    );
    final gate = Completer<bool>();
    approval = (_) => gate.future;
    final phone = await peer();
    phone.send({
      'type': 'pair.hello',
      'clientId': clientId,
      'clientName': 'Phone',
      'clientNonce': encodeBytes(clientNonce),
    });
    final challenge = await phone.next();
    final transcript = PairingTranscript(
      desktopId: desktopId,
      pairId: invitation.pairId,
      clientId: clientId,
      clientName: 'Phone',
      clientNonce: clientNonce,
      serverNonce: decodeBytes(challenge.fields['serverNonce']! as String, 32),
      certificateSha256: identity.certificateSha256,
    );
    phone.send({
      'type': 'pair.proof',
      'proof': encodeBytes(transcript.clientProof(invitation.pairSecret)),
    });
    expect((await phone.next()).type, 'pair.pending');
    phone.epoch = authority.sessionEpoch;
    phone.command('early', 'playback.play');
    expect((await phone.next()).type, 'error');
    gate.complete(true);
    expect(store.records.length, 1);
    expect(handler.calls, isEmpty);
  });

  test(
    'duplicate command IDs run once; conflicting reuse terminates lease',
    () async {
      final phone = await peer(login: true);
      phone.command('same', 'playback.play');
      expect((await phone.result('same')).fields['ok'], true);
      phone.command('same', 'playback.play');
      expect((await phone.result('same')).fields['ok'], true);
      expect(handler.calls, ['playback.play']);
      phone.command('same', 'playback.pause');
      final failure = await phone.result('same');
      expect(failure.type, 'error');
      expect(handler.calls, ['playback.play']);
    },
  );

  test('commands serialize while heartbeat remains responsive', () async {
    final phone = await peer(login: true);
    handler.gate = Completer<void>();
    handler.entered = Completer<void>();
    phone.command('first', 'playback.play');
    await handler.entered!.future;
    phone.command('second', 'playback.pause');
    phone.send({
      'type': 'ping',
      'seq': ++phone.sequence,
      'sessionEpoch': phone.epoch,
    });
    expect((await phone.next()).type, 'pong');
    expect(handler.calls, ['playback.play']);
    handler.gate!.complete();
    expect((await phone.result('first')).fields['ok'], true);
    expect((await phone.result('second')).fields['ok'], true);
    expect(handler.effects, ['playback.play', 'playback.pause']);
  });

  test(
    'revocation closes real socket and denies in-flight native continuation',
    () async {
      final phone = await peer(login: true);
      handler.gate = Completer<void>();
      handler.entered = Completer<void>();
      phone.command('delayed', 'playback.play');
      await handler.entered!.future;
      await authority.revoke(credential.tokenId);
      handler.gate!.complete();
      expect(
        await phone.frames.moveNext().timeout(const Duration(seconds: 3)),
        false,
      );
      expect(handler.effects, isEmpty);
      expect(store.records, isEmpty);
    },
  );

  test(
    'native timeout is uncertain error and invalidates queued work',
    () async {
      final phone = await peer(login: true);
      handler.gate = Completer<void>();
      phone.command('slow', 'playback.play');
      phone.command('queued', 'playback.pause');
      final result = await phone.result('slow');
      expect(result.fields['ok'], false);
      expect(result.fields['error'], {'code': 'command_timeout'});
      handler.gate!.complete();
      expect(
        await phone.frames.moveNext().timeout(const Duration(seconds: 3)),
        false,
      );
      expect(handler.effects, isEmpty);
      expect(handler.calls, ['playback.play']);
    },
  );

  test('malformed handshake fields and stale epoch do not dispatch', () async {
    final malformed = await peer();
    malformed.send({'type': 'auth.hello', 'extra': 'not allowed'});
    expect((await malformed.next()).fields['error'], {
      'code': 'invalid_argument',
    });
    final active = await peer(login: true);
    active.epoch = 'old-room';
    active.command('old', 'playback.play');
    expect((await active.next()).fields['error'], {'code': 'session_changed'});
    expect(handler.calls, isEmpty);
  });

  test(
    'unexpected native exceptions are sanitized and typed failure remains usable',
    () async {
      final phone = await peer(login: true);
      handler.error = StateError('SECRET native local file path');
      phone.command('bad', 'playback.play');
      final result = await phone.result('bad');
      expect(result.fields['error'], {'code': 'native_failure'});
      expect(result.fields.toString(), isNot(contains('SECRET')));
      handler.error = null;
      phone.command('good', 'playback.pause');
      expect((await phone.result('good')).fields['ok'], true);
    },
  );

  test('bounded writer closes on synchronous 256KiB event backlog', () async {
    final phone = await peer(login: true);
    final body = {'data': List.filled(8, 'x' * 4000)};
    for (var i = 0; i < 10; i++) {
      handler.controller.add(NearbyServerEvent('presence', body));
    }
    // The test client need not be artificially slow: ten synchronous events
    // exceed the bounded queue before any asynchronous socket flush completes.
    while (await phone.frames.moveNext().timeout(const Duration(seconds: 3))) {}
    expect(handler.calls, isEmpty);
  });

  test('arrival cap applies before expensive TLS handshakes', () async {
    final rawSockets = <Socket>[];
    addTearDown(() {
      for (final socket in rawSockets) {
        socket.destroy();
      }
    });
    for (var i = 0; i < 10; i++) {
      final raw = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      raw.listen((_) {}, onError: (Object _) {});
      rawSockets.add(raw);
    }
    await expectLater(
      connectPinnedTls(
        address: InternetAddress.loopbackIPv4,
        port: server.port,
        certificateSha256: identity.certificateSha256,
      ),
      throwsA(anyOf(isA<HandshakeException>(), isA<SocketException>())),
    );
    expect(handler.calls, isEmpty);
  });

  test(
    'self revocation waits for durable store before acknowledging success',
    () async {
      final phone = await peer(login: true);
      store.revokeGate = Completer<void>();
      store.revokeEntered = Completer<void>();
      phone.command('revoke', 'device.revokeSelf');
      var received = false;
      final response = phone.result('revoke').then((frame) {
        received = true;
        return frame;
      });
      await store.revokeEntered!.future.timeout(const Duration(seconds: 3));
      phone.command('forbidden', 'playback.play');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        received,
        false,
        reason: 'A durable revocation has not completed.',
      );
      expect(store.records.containsKey(credential.tokenId), true);
      expect(handler.calls, isEmpty);
      store.revokeGate!.complete();
      expect((await response).fields['ok'], true);
      expect(store.records, isEmpty);
      expect(
        await phone.frames.moveNext().timeout(const Duration(seconds: 3)),
        false,
      );
      expect(handler.effects, isEmpty);
    },
  );

  test('self revocation storage failure never returns success', () async {
    final phone = await peer(login: true);
    store.failRevoke = true;
    phone.command('revoke', 'device.revokeSelf');
    final response = await phone.result('revoke');
    expect(response.fields['ok'], isNot(true));
    expect(response.fields['error'], {'code': 'storage_unavailable'});
    expect(store.records.containsKey(credential.tokenId), true);
    expect(
      () => authority.openConnection(peerAddress: '192.168.1.99'),
      throwsA(isA<NearbyException>()),
    );
    expect(handler.effects, isEmpty);
  });

  test(
    'self revocation timeout reports uncertainty without restoring authority',
    () async {
      final phone = await peer(login: true);
      store.revokeGate = Completer<void>();
      phone.command('revoke', 'device.revokeSelf');
      final response = await phone.result('revoke');
      expect(response.fields['ok'], false);
      expect(response.fields['error'], {'code': 'command_timeout'});
      expect(store.records.containsKey(credential.tokenId), true);
      expect(
        await phone.frames.moveNext().timeout(const Duration(seconds: 3)),
        false,
      );
      store.revokeGate!.complete();
      // Drain the real protected-store operation; its later completion cannot
      // cause a successful response on the already-closed socket.
      await server.close();
      expect(store.records, isEmpty);
      expect(handler.effects, isEmpty);
    },
  );

  test(
    'acknowledged self revocation rejects stored credential after authority restart',
    () async {
      final phone = await peer(login: true);
      phone.command('revoke', 'device.revokeSelf');
      expect((await phone.result('revoke')).fields['ok'], true);
      expect(store.records, isEmpty);
      await server.close();
      authority = NearbyAuthority(
        desktopId: desktopId,
        certificateSha256: identity.certificateSha256,
        store: store,
      );
      server = NearbyServer.forTesting(
        listener: await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
        identity: identity,
        authority: authority,
        handler: handler,
        approvePairing: (_) async => true,
        peerAddressForTesting: (_) => '192.168.1.90',
      );
      final retry = await peer();
      retry.send({'type': 'auth.hello'});
      final challenge = await retry.next();
      final transcript = AuthTranscript(
        desktopId: desktopId,
        tokenId: credential.tokenId,
        clientNonce: clientNonce,
        serverNonce: decodeBytes(
          challenge.fields['serverNonce']! as String,
          32,
        ),
        certificateSha256: identity.certificateSha256,
      );
      final readsBefore = store.reads;
      retry.send({
        'type': 'auth.proof',
        'tokenId': credential.tokenId,
        'clientNonce': encodeBytes(clientNonce),
        'proof': encodeBytes(transcript.clientProof(credential.secret)),
      });
      final hasFrame = await retry.frames.moveNext().timeout(
        const Duration(seconds: 3),
      );
      if (hasFrame) expect(retry.frames.current.type, 'error');
      expect(
        store.reads,
        readsBefore + 1,
        reason: 'The restarted authority must reach storage.',
      );
      expect(handler.effects, isEmpty);
    },
  );

  test(
    'incomplete TLS application frame has a fixed assembly deadline',
    () async {
      final phone = await peer();
      phone.socket.add([
        123,
      ]); // A single opening brace cannot hold a slot forever.
      final error = await phone.next();
      expect(error.fields['error'], {'code': 'command_timeout'});
      expect(handler.calls, isEmpty);
    },
  );

  test(
    'replayed authenticated sequence closes without executing twice',
    () async {
      final phone = await peer(login: true);
      phone.command('first', 'playback.play');
      expect((await phone.result('first')).fields['ok'], true);
      phone.sequence = 0;
      phone.command('second', 'playback.pause');
      expect((await phone.result('second')).type, 'error');
      expect(handler.calls, ['playback.play']);
    },
  );

  test(
    'room replacement cancels native continuation and queued commands',
    () async {
      final phone = await peer(login: true);
      handler.gate = Completer<void>();
      handler.entered = Completer<void>();
      phone.command('first', 'playback.play');
      await handler.entered!.future;
      phone.command('second', 'playback.pause');
      authority.replaceSession();
      handler.gate!.complete();
      expect(
        await phone.frames.moveNext().timeout(const Duration(seconds: 3)),
        false,
      );
      expect(handler.effects, isEmpty);
      expect(handler.calls, ['playback.play']);
    },
  );

  test(
    'server shutdown cancels pending owner approval without a late credential',
    () async {
      final invitation = authority.openInvitation(
        LanEndpoint(
          address: LanIpv4Address.parse('192.168.1.10'),
          port: server.port,
        ),
      );
      final gate = Completer<bool>();
      approval = (_) => gate.future;
      final phone = await peer();
      phone.send({
        'type': 'pair.hello',
        'clientId': clientId,
        'clientName': 'Phone',
        'clientNonce': encodeBytes(clientNonce),
      });
      final challenge = await phone.next();
      final transcript = PairingTranscript(
        desktopId: desktopId,
        pairId: invitation.pairId,
        clientId: clientId,
        clientName: 'Phone',
        clientNonce: clientNonce,
        serverNonce: decodeBytes(
          challenge.fields['serverNonce']! as String,
          32,
        ),
        certificateSha256: identity.certificateSha256,
      );
      phone.send({
        'type': 'pair.proof',
        'proof': encodeBytes(transcript.clientProof(invitation.pairSecret)),
      });
      expect((await phone.next()).type, 'pair.pending');
      await server.close();
      gate.complete(true);
      expect(
        await phone.frames.moveNext().timeout(const Duration(seconds: 3)),
        false,
      );
      expect(store.records.length, 1);
    },
  );
}
