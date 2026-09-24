import 'dart:async';
import 'dart:io';

import 'package:nearby_bridge/src/client.dart';
import 'package:nearby_bridge/src/authority.dart';
import 'package:nearby_bridge/src/server.dart';
import 'package:nearby_bridge/src/invitation.dart';
import 'package:nearby_bridge/src/lan.dart';
import 'package:nearby_bridge/src/primitives.dart';
import 'package:nearby_bridge/src/tls.dart';
import 'package:nearby_bridge/src/transcript.dart';
import 'package:nearby_bridge/src/wire.dart';
import 'package:test/test.dart';

final _desktopId = encodeBytes(List.filled(16, 1));
final _pairId = encodeBytes(List.filled(16, 2));
final _tokenId = encodeBytes(List.filled(16, 3));
final _connectionId = encodeBytes(List.filled(16, 4));
final _epoch = encodeBytes(List.filled(16, 5));
final _secret = List.filled(32, 6);
final _pairSecret = List.filled(16, 7);
final _nonce = List.filled(32, 8);

final class _Clock implements MonotonicClock {
  @override
  Duration now = Duration.zero;
}

final class _DesktopStore implements NearbySecretStore {
  final records = <String, DeviceCredential>{};
  int reads = 0;
  @override
  Future<DeviceCredential?> read(String tokenId) async {
    reads++;
    return records[tokenId];
  }

  @override
  Future<void> write(DeviceCredential credential) async {
    records[credential.tokenId] = credential;
  }

  @override
  Future<void> revoke(String tokenId) async {
    records.remove(tokenId);
  }
}

final class _Handler implements NearbyCommandHandler {
  @override
  int stateRevision = 0;
  bool playing = false;
  @override
  Map<String, Object?> get snapshot => {
    'stateRevision': stateRevision,
    'playing': playing,
  };
  @override
  Stream<NearbyServerEvent> get events => const Stream.empty();
  @override
  Future<Map<String, Object?>> handle(NearbyCommand command) async {
    command.checkActive();
    if (command.method == 'playback.play') playing = true;
    if (command.method == 'playback.pause') playing = false;
    stateRevision++;
    return {};
  }
}

final class _Store implements NearbyClientStore {
  NearbyClientCredential? saved;
  Completer<void>? gate;
  bool fail = false;
  @override
  Future<NearbyClientCredential?> read(String desktopId) async => saved;
  @override
  Future<void> remove(String desktopId) async => saved = null;
  @override
  Future<void> write(NearbyClientCredential credential) async {
    if (gate != null) await gate!.future;
    if (fail) throw StateError('secret diagnostic must not escape');
    saved = credential;
  }
}

final class _Peer {
  _Peer(this.socket)
    : reader = StreamIterator(const JsonLineDecoder().bind(socket));
  final SecureSocket socket;
  final StreamIterator<NearbyFrame> reader;
  Future<NearbyFrame> next() async {
    if (!await reader.moveNext()) throw StateError('Peer closed');
    return reader.current;
  }

  Future<void> send(String type, Map<String, Object?> fields) async {
    socket.add(
      const NearbyFrameCodec().encode(
        NearbyFrame({'v': 1, 'type': type, ...fields}),
      ),
    );
    await socket.flush();
  }
}

final class _SilentTlsServer {
  _SilentTlsServer(this.listener) {
    subscription = listener.listen((socket) {
      peer = socket;
      accepted.complete();
      socket.listen(
        (_) {},
        onError: (Object _) {
          if (!disconnected.isCompleted) disconnected.complete();
        },
        onDone: () {
          if (!disconnected.isCompleted) disconnected.complete();
        },
      );
    });
  }

  final ServerSocket listener;
  late final StreamSubscription<Socket> subscription;
  final accepted = Completer<void>();
  final disconnected = Completer<void>();
  Socket? peer;

  Future<void> close() async {
    peer?.destroy();
    await subscription.cancel();
    await listener.close();
  }
}

void main() {
  test('credentials validate byte sizes and redact secrets', () {
    final credential = NearbyClientCredential(
      desktopId: _desktopId,
      tokenId: _tokenId,
      clientId: _pairId,
      clientName: 'Phone',
      endpoint: LanEndpoint(
        address: LanIpv4Address.parse('192.168.1.2'),
        port: 1234,
      ),
      certificateSha256: List.filled(32, 0),
      secret: _secret,
    );
    expect(credential.toString(), 'NearbyClientCredential([REDACTED])');
    expect(() => credential.secret[0] = 3, throwsUnsupportedError);
    expect(
      () => NearbyClientCredential(
        desktopId: 'bad',
        tokenId: _tokenId,
        clientId: _pairId,
        clientName: 'Phone',
        endpoint: credential.endpoint,
        certificateSha256: List.filled(32, 0),
        secret: _secret,
      ),
      throwsA(isA<NearbyException>()),
    );
  });

  test('off-subnet pairing is rejected before opening a socket', () async {
    final client = NearbyClient(store: _Store());
    addTearDown(client.dispose);
    final invitation = PairingInvitation(
      desktopId: _desktopId,
      pairId: _pairId,
      endpoint: LanEndpoint(
        address: LanIpv4Address.parse('192.168.2.2'),
        port: 1234,
      ),
      certificateSha256: List.filled(32, 0),
      pairSecret: _pairSecret,
    );
    await expectLater(
      client.pair(
        invitation: invitation,
        subnet: LanSubnet(
          localAddress: LanIpv4Address.parse('192.168.1.2'),
          prefixLength: 24,
        ),
        clientName: 'Phone',
      ),
      throwsA(_code('lan_unavailable')),
    );
    expect(client.state.phase, NearbyClientPhase.disconnected);
  });

  final address = Platform.environment['NEARBY_TEST_ADDRESS'];
  final prefix = int.tryParse(Platform.environment['NEARBY_TEST_PREFIX'] ?? '');
  group(
    'real pinned TLS client on explicit local adapter',
    () {
      late TlsIdentity identity;
      late SecureServerSocket listener;
      late LanSubnet subnet;
      late PairingInvitation invitation;
      late NearbyClientCredential credential;
      late _Store store;
      late NearbyClient client;
      late Future<void> Function(_Peer) script;
      late List<SecureSocket> sockets;

      setUpAll(() async {
        identity = await TlsIdentity.generate();
      });
      setUp(() async {
        sockets = [];
        subnet = LanSubnet(
          localAddress: LanIpv4Address.parse(address!),
          prefixLength: prefix!,
        );
        listener = await SecureServerSocket.bind(
          address,
          0,
          identity.createServerContext(),
        );
        listener.listen((socket) {
          sockets.add(socket);
          unawaited(
            script(_Peer(socket)).catchError((Object _) {
              socket.destroy();
            }),
          );
        }, onError: (Object _) {});
        final endpoint = LanEndpoint(
          address: subnet.localAddress,
          port: listener.port,
        );
        invitation = PairingInvitation(
          desktopId: _desktopId,
          pairId: _pairId,
          endpoint: endpoint,
          certificateSha256: identity.certificateSha256,
          pairSecret: _pairSecret,
        );
        credential = NearbyClientCredential(
          desktopId: _desktopId,
          tokenId: _tokenId,
          clientId: _pairId,
          clientName: 'Phone',
          endpoint: endpoint,
          certificateSha256: identity.certificateSha256,
          secret: _secret,
        );
        store = _Store();
        client = NearbyClient(store: store);
      });
      tearDown(() async {
        await client.dispose();
        for (final socket in sockets) {
          socket.destroy();
        }
        await listener.close();
      });

      Future<void> pairReply(
        _Peer peer, {
        bool wrongProof = false,
        bool timeout = false,
      }) async {
        final hello = await peer.next();
        expect(hello.type, 'pair.hello');
        await peer.send('pair.challenge', {
          'desktopId': _desktopId,
          'pairId': _pairId,
          'serverNonce': encodeBytes(_nonce),
        });
        final transcript = PairingTranscript(
          desktopId: _desktopId,
          pairId: _pairId,
          clientId: hello.fields['clientId']! as String,
          clientName: hello.fields['clientName']! as String,
          clientNonce: decodeBytes(hello.fields['clientNonce']! as String, 32),
          serverNonce: _nonce,
          certificateSha256: identity.certificateSha256,
        );
        final proof = await peer.next();
        expect(
          constantTimeEqual(
            decodeBytes(proof.fields['proof']! as String, 32),
            transcript.clientProof(_pairSecret),
          ),
          isTrue,
        );
        await peer.send('pair.pending', {'expiresInMs': timeout ? 30 : 5000});
        if (timeout) return;
        await peer.send('pair.accept', {
          'desktopId': _desktopId,
          'tokenId': _tokenId,
          'deviceSecret': encodeBytes(_secret),
          'serverProof': encodeBytes(
            wrongProof
                ? List.filled(32, 0)
                : transcript.serverProof(_pairSecret, _tokenId, _secret),
          ),
        });
      }

      Future<void> authReply(_Peer peer, {bool wrongProof = false}) async {
        expect((await peer.next()).type, 'auth.hello');
        await peer.send('auth.challenge', {
          'desktopId': _desktopId,
          'serverNonce': encodeBytes(_nonce),
        });
        final proof = await peer.next();
        final transcript = AuthTranscript(
          desktopId: _desktopId,
          tokenId: _tokenId,
          clientNonce: decodeBytes(proof.fields['clientNonce']! as String, 32),
          serverNonce: _nonce,
          certificateSha256: identity.certificateSha256,
        );
        expect(
          constantTimeEqual(
            decodeBytes(proof.fields['proof']! as String, 32),
            transcript.clientProof(_secret),
          ),
          isTrue,
        );
        await peer.send('auth.ok', {
          'connectionId': _connectionId,
          'sessionEpoch': _epoch,
          'serverProof': encodeBytes(
            transcript.serverProof(
              _secret,
              wrongProof ? _pairId : _connectionId,
            ),
          ),
        });
      }

      Future<(_SilentTlsServer, PairingInvitation)> silentInvitation() async {
        final silent = _SilentTlsServer(await ServerSocket.bind(address!, 0));
        addTearDown(silent.close);
        return (
          silent,
          PairingInvitation(
            desktopId: _desktopId,
            pairId: _pairId,
            endpoint: LanEndpoint(
              address: subnet.localAddress,
              port: silent.listener.port,
            ),
            certificateSha256: identity.certificateSha256,
            pairSecret: _pairSecret,
          ),
        );
      }

      test('dispose closes a pending TLS handshake promptly', () async {
        final (silent, stalledInvitation) = await silentInvitation();
        final pending = client.pair(
          invitation: stalledInvitation,
          subnet: subnet,
          clientName: 'Phone',
        );
        final rejected = expectLater(pending, throwsA(_code('cancelled')));
        await silent.accepted.future.timeout(const Duration(seconds: 3));
        await client.dispose();
        await rejected;
        await silent.disconnected.future.timeout(const Duration(seconds: 2));
        expect(store.saved, isNull);
      });

      test('manual disconnect closes a pending TLS handshake', () async {
        final (silent, stalledInvitation) = await silentInvitation();
        final pending = client.pair(
          invitation: stalledInvitation,
          subnet: subnet,
          clientName: 'Phone',
        );
        final rejected = expectLater(pending, throwsA(_code('cancelled')));
        await silent.accepted.future.timeout(const Duration(seconds: 3));
        client.disconnect();
        await rejected;
        await silent.disconnected.future.timeout(const Duration(seconds: 2));
        expect(client.state.phase, NearbyClientPhase.disconnected);
        expect(store.saved, isNull);
      });

      test(
        'superseding a stalled handshake closes it before valid pairing',
        () async {
          final (silent, stalledInvitation) = await silentInvitation();
          final stale = client.pair(
            invitation: stalledInvitation,
            subnet: subnet,
            clientName: 'Phone',
          );
          final rejected = expectLater(stale, throwsA(_code('cancelled')));
          await silent.accepted.future.timeout(const Duration(seconds: 3));
          script = pairReply;
          final current = client.pair(
            invitation: invitation,
            subnet: subnet,
            clientName: 'Phone',
          );
          await rejected;
          await silent.disconnected.future.timeout(const Duration(seconds: 2));
          final result = await current;
          expect(store.saved, same(result));
        },
      );

      test(
        'valid QR pairing persists only after mutual proof and gets no lease',
        () async {
          script = pairReply;
          final result = await client.pair(
            invitation: invitation,
            subnet: subnet,
            clientName: 'Phone',
          );
          expect(identical(store.saved, result), isTrue);
          expect(client.state.phase, NearbyClientPhase.disconnected);
          await expectLater(
            client.command('playback.play'),
            throwsA(_code('not_connected')),
          );
        },
      );

      test('wrong pair server proof never persists a credential', () async {
        script = (peer) => pairReply(peer, wrongProof: true);
        await expectLater(
          client.pair(
            invitation: invitation,
            subnet: subnet,
            clientName: 'Phone',
          ),
          throwsA(_code('auth_failed')),
        );
        expect(store.saved, isNull);
      });

      test('pending desktop approval has a deadline', () async {
        script = (peer) => pairReply(peer, timeout: true);
        await expectLater(
          client.pair(
            invitation: invitation,
            subnet: subnet,
            clientName: 'Phone',
          ),
          throwsA(_code('timeout')),
        );
        expect(store.saved, isNull);
      });

      test(
        'protected storage error is redacted and cannot activate control',
        () async {
          script = pairReply;
          store.fail = true;
          await expectLater(
            client.pair(
              invitation: invitation,
              subnet: subnet,
              clientName: 'Phone',
            ),
            throwsA(_code('storage_unavailable')),
          );
          expect(client.state.phase, NearbyClientPhase.disconnected);
        },
      );

      test(
        'dispose during delayed storage cannot attach a late pairing',
        () async {
          script = pairReply;
          store.gate = Completer<void>();
          final saving = client.states.firstWhere(
            (state) => state.phase == NearbyClientPhase.saving,
          );
          final pair = client.pair(
            invitation: invitation,
            subnet: subnet,
            clientName: 'Phone',
          );
          final outcome = expectLater(pair, throwsA(_code('cancelled')));
          await saving;
          await client.dispose();
          store.gate!.complete();
          await outcome;
          expect(client.state.phase, NearbyClientPhase.disposed);
        },
      );

      test(
        'connection-bound authentication rejects proof for another connection',
        () async {
          script = (peer) => authReply(peer, wrongProof: true);
          await expectLater(
            client.connect(credential: credential, subnet: subnet),
            throwsA(_code('auth_failed')),
          );
          expect(client.state.phase, NearbyClientPhase.disconnected);
        },
      );

      test(
        'authenticated result resolves command and event carries verified epoch',
        () async {
          script = (peer) async {
            await authReply(peer);
            await peer.send('state.snapshot', {
              'seq': 1,
              'sessionEpoch': _epoch,
              'state': {'playing': false},
            });
            final command = await peer.next();
            expect(command.fields['method'], 'playback.play');
            await peer.send('result', {
              'seq': 2,
              'sessionEpoch': _epoch,
              'id': command.fields['id'],
              'ok': true,
              'stateRevision': 1,
              'result': <String, Object?>{},
            });
          };
          final snapshot = client.events.first;
          await client.connect(credential: credential, subnet: subnet);
          expect((await snapshot).type, 'state.snapshot');
          expect(await client.command('playback.play'), isEmpty);
        },
      );

      test(
        'repeated sequence closes connection before delivering second event',
        () async {
          final release = Completer<void>();
          script = (peer) async {
            await authReply(peer);
            await release.future;
            await peer.send('state.snapshot', {
              'seq': 1,
              'sessionEpoch': _epoch,
              'state': <String, Object?>{},
            });
            await peer.send('state.snapshot', {
              'seq': 1,
              'sessionEpoch': _epoch,
              'state': <String, Object?>{},
            });
          };
          final events = <NearbyFrame>[];
          final subscription = client.events.listen(events.add);
          addTearDown(subscription.cancel);
          await client.connect(credential: credential, subnet: subnet);
          final disconnected = client.states.firstWhere(
            (state) => state.phase == NearbyClientPhase.disconnected,
          );
          release.complete();
          expect((await disconnected).errorCode, 'invalid_argument');
          expect(events.length, 1);
        },
      );

      test('heartbeat responds to server ping with sequenced pong', () async {
        final response = Completer<NearbyFrame>();
        script = (peer) async {
          await authReply(peer);
          await peer.send('ping', {'seq': 1, 'sessionEpoch': _epoch});
          response.complete(await peer.next());
        };
        await client.connect(credential: credential, subnet: subnet);
        final pong = await response.future;
        expect(pong.type, 'pong');
        expect(pong.fields['seq'], 1);
        expect(pong.fields['sessionEpoch'], _epoch);
      });

      test(
        '15 seconds without valid incoming activity expires control',
        () async {
          final clock = _Clock();
          await client.dispose();
          client = NearbyClient(store: store, clock: clock);
          script = authReply;
          await client.connect(credential: credential, subnet: subnet);
          final disconnected = client.states.firstWhere(
            (state) => state.phase == NearbyClientPhase.disconnected,
          );
          clock.now = const Duration(seconds: 15);
          expect((await disconnected).errorCode, 'heartbeat_timeout');
        },
      );

      test('server command timeout is reported as uncertain', () async {
        script = (peer) async {
          await authReply(peer);
          final command = await peer.next();
          await peer.send('result', {
            'seq': 1,
            'sessionEpoch': _epoch,
            'id': command.fields['id'],
            'ok': false,
            'stateRevision': 0,
            'error': {'code': 'command_timeout'},
          });
        };
        await client.connect(credential: credential, subnet: subnet);
        await expectLater(
          client.command('playback.play'),
          throwsA(_code('command_uncertain')),
        );
        expect(client.state.phase, NearbyClientPhase.disconnected);
      });

      test(
        'pending commands are bounded and all fail uncertain on disconnect',
        () async {
          script = authReply;
          await client.connect(credential: credential, subnet: subnet);
          final outcomes = [
            for (var i = 0; i < 32; i++)
              expectLater(
                client.command('playback.play'),
                throwsA(_code('command_uncertain')),
              ),
          ];
          await expectLater(
            client.command('playback.play'),
            throwsA(_code('rate_limited')),
          );
          client.disconnect();
          await Future.wait(outcomes);
        },
      );

      test(
        'command timeout is uncertain and invalidates the connection',
        () async {
          script = authReply;
          await client.connect(credential: credential, subnet: subnet);
          await expectLater(
            client.command('playback.play'),
            throwsA(_code('command_uncertain')),
          );
          expect(client.state.phase, NearbyClientPhase.disconnected);
        },
      );

      test('trickled incomplete frame has an assembly deadline', () async {
        final release = Completer<void>();
        script = (peer) async {
          await authReply(peer);
          await release.future;
          peer.socket.add([123]);
          await peer.socket.flush();
        };
        await client.connect(credential: credential, subnet: subnet);
        final disconnected = client.states.firstWhere(
          (state) => state.phase == NearbyClientPhase.disconnected,
        );
        release.complete();
        expect((await disconnected).errorCode, 'frame_timeout');
      });

      test(
        'old epoch fails pending command as uncertain without replay',
        () async {
          script = (peer) async {
            await authReply(peer);
            final command = await peer.next();
            await peer.send('result', {
              'seq': 1,
              'sessionEpoch': _pairId,
              'id': command.fields['id'],
              'ok': true,
              'stateRevision': 1,
              'result': <String, Object?>{},
            });
          };
          await client.connect(credential: credential, subnet: subnet);
          await expectLater(
            client.command('playback.play'),
            throwsA(_code('command_uncertain')),
          );
          expect(client.state.phase, NearbyClientPhase.disconnected);
        },
      );

      test(
        'production server/client pair, reconnect, control and revoke over TLS',
        () async {
          final desktopStore = _DesktopStore();
          final desktopClock = _Clock();
          final authority = NearbyAuthority(
            desktopId: _desktopId,
            certificateSha256: identity.certificateSha256,
            store: desktopStore,
            clock: desktopClock,
          );
          final handler = _Handler();
          final server = await NearbyServer.bind(
            subnet: subnet,
            identity: identity,
            authority: authority,
            handler: handler,
            approvePairing: (_) async => true,
          );
          addTearDown(server.close);
          final qr = authority.openInvitation(
            LanEndpoint(address: subnet.localAddress, port: server.port),
          );
          final paired = await client.pair(
            invitation: qr,
            subnet: subnet,
            clientName: 'Phone',
          );
          expect(desktopStore.records.length, 1);
          expect(store.saved?.tokenId, paired.tokenId);
          final snapshot = client.events.first;
          await client.connect(credential: paired, subnet: subnet);
          expect((await snapshot).type, 'state.snapshot');
          await client.command('playback.play');
          expect(handler.playing, isTrue);
          final detached = client.states.firstWhere(
            (s) => s.phase == NearbyClientPhase.disconnected,
          );
          await client.command('controller.detach');
          await detached;
          await client.reconnect(credential: paired, subnet: subnet);
          await client.command('playback.pause');
          expect(handler.playing, isFalse);
          final revoked = client.states.firstWhere(
            (s) => s.phase == NearbyClientPhase.disconnected,
          );
          await client.command('device.revokeSelf');
          await revoked;
          expect(desktopStore.records, isEmpty);
          await server.close();
          // A fresh authority has neither admission history nor an in-memory
          // revocation set: rejection must follow the durable store lookup.
          final restarted = await NearbyServer.bind(
            subnet: subnet,
            identity: identity,
            authority: NearbyAuthority(
              desktopId: _desktopId,
              certificateSha256: identity.certificateSha256,
              store: desktopStore,
            ),
            handler: handler,
            approvePairing: (_) async => true,
          );
          addTearDown(restarted.close);
          final readsBeforeRevokedAuth = desktopStore.reads;
          await expectLater(
            client.reconnect(
              credential: paired,
              subnet: subnet,
              endpoint: LanEndpoint(
                address: subnet.localAddress,
                port: restarted.port,
              ),
            ),
            throwsA(anyOf(_code('auth_failed'), _code('not_connected'))),
          );
          expect(desktopStore.reads, greaterThan(readsBeforeRevokedAuth));
        },
      );

      test(
        'dispose cancels a pending authentication and ignores late proof',
        () async {
          final ready = Completer<void>();
          final release = Completer<void>();
          script = (peer) async {
            ready.complete();
            await release.future;
            await authReply(peer);
          };
          final connecting = client.connect(
            credential: credential,
            subnet: subnet,
          );
          final outcome = expectLater(
            connecting,
            throwsA(isA<NearbyException>()),
          );
          await ready.future;
          await client.dispose();
          release.complete();
          await outcome;
          expect(client.state.phase, NearbyClientPhase.disposed);
        },
      );
    },
    skip: address == null || prefix == null
        ? 'Set NEARBY_TEST_ADDRESS and NEARBY_TEST_PREFIX from actual adapter enumeration.'
        : false,
  );
}

Matcher _code(String code) =>
    isA<NearbyException>().having((e) => e.code, 'code', code);
