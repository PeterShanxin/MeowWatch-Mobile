import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/nearby/nearby_desktop_target.dart';
import 'package:meowwatch_mobile/core/playback/playback_target.dart';
import 'package:nearby_bridge/nearby_bridge.dart';

import 'nearby_snapshot_test.dart' show nearbySnapshotFixture;

final _desktopId = encodeBytes(List.filled(16, 1));
final _epoch = encodeBytes(List.filled(16, 2));
final _tokenId = encodeBytes(List.filled(16, 3));
final _connectionId = encodeBytes(List.filled(16, 4));
final _secret = List.filled(32, 5);

class _Store implements NearbyClientStore {
  @override
  Future<NearbyClientCredential?> read(String desktopId) async => null;
  @override
  Future<void> write(NearbyClientCredential credential) async {}
  @override
  Future<void> remove(String desktopId) async {}
}

class _Peer {
  _Peer(this.socket)
    : input = StreamIterator(const JsonLineDecoder().bind(socket));
  final SecureSocket socket;
  final StreamIterator<NearbyFrame> input;
  int sequence = 0;
  Future<NearbyFrame> next() async {
    if (!await input.moveNext()) throw StateError('Peer disconnected');
    return input.current;
  }

  Future<void> send(String type, Map<String, Object?> fields) async {
    socket.add(
      const NearbyFrameCodec().encode(
        NearbyFrame({'v': 1, 'type': type, ...fields}),
      ),
    );
    await socket.flush();
  }

  Future<void> snapshot([Map<String, Object?>? state]) =>
      send('state.snapshot', {
        'seq': ++sequence,
        'sessionEpoch': _epoch,
        'state': state ?? nearbySnapshotFixture(),
      });
  Future<void> result(NearbyFrame command) => send('result', {
    'seq': ++sequence,
    'sessionEpoch': _epoch,
    'id': command.fields['id'],
    'ok': true,
    'stateRevision': 1,
    'result': <String, Object?>{},
  });
}

void main() {
  test('public error messages never echo untrusted diagnostics', () {
    expect(nearbyErrorMessage('password=secret'), isNot(contains('secret')));
    expect(nearbyErrorMessage('command_uncertain'), contains('check playback'));
  });

  final address = Platform.environment['NEARBY_TEST_ADDRESS'];
  final prefix = int.tryParse(Platform.environment['NEARBY_TEST_PREFIX'] ?? '');
  group(
    'desktop target over actual adapter pinned TLS',
    () {
      late TlsIdentity identity;
      late SecureServerSocket server;
      late LanSubnet subnet;
      late NearbyDesktopTarget target;
      late List<SecureSocket> sockets;
      late Future<void> Function(_Peer peer, int connection) script;

      setUpAll(() async {
        identity = await TlsIdentity.generate();
      });
      setUp(() async {
        sockets = [];
        subnet = LanSubnet(
          localAddress: LanIpv4Address.parse(address!),
          prefixLength: prefix!,
        );
        server = await SecureServerSocket.bind(
          address,
          0,
          identity.createServerContext(),
        );
        var connectionCount = 0;
        server.listen((socket) {
          final connection = ++connectionCount;
          sockets.add(socket);
          final peer = _Peer(socket);
          unawaited(
            () async {
              expect((await peer.next()).type, 'auth.hello');
              final nonce = List.filled(32, 8);
              await peer.send('auth.challenge', {
                'desktopId': _desktopId,
                'serverNonce': encodeBytes(nonce),
              });
              final proof = await peer.next();
              final transcript = AuthTranscript(
                desktopId: _desktopId,
                tokenId: _tokenId,
                clientNonce: decodeBytes(
                  proof.fields['clientNonce']! as String,
                  32,
                ),
                serverNonce: nonce,
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
                  transcript.serverProof(_secret, _connectionId),
                ),
              });
              await script(peer, connection);
            }().catchError((Object _) {
              socket.destroy();
            }),
          );
        }, onError: (Object _) {});
        final credential = NearbyClientCredential(
          desktopId: _desktopId,
          tokenId: _tokenId,
          clientId: _connectionId,
          clientName: 'Phone',
          secret: _secret,
          certificateSha256: identity.certificateSha256,
          endpoint: LanEndpoint(
            address: subnet.localAddress,
            port: server.port,
          ),
        );
        target = NearbyDesktopTarget(
          client: NearbyClient(store: _Store()),
          credential: credential,
        );
      });
      tearDown(() async {
        await target.close();
        for (final socket in sockets) {
          socket.destroy();
        }
        await server.close();
      });

      test('connect waits for an initial authoritative snapshot', () async {
        final authed = Completer<_Peer>();
        script = (peer, _) async {
          authed.complete(peer);
        };
        var completed = false;
        final connecting = target.connect(subnet).then((_) {
          completed = true;
        });
        final peer = await authed.future;
        expect(completed, isFalse);
        expect(target.connected, isFalse);
        await peer.snapshot();
        await connecting;
        expect(target.connected, isTrue);
        expect(target.label, 'Living room');
        expect(target.remote?.room?.room, 'Movie night');
      });

      test(
        'commands are remote only and acknowledgments never change playback',
        () async {
          final authed = Completer<_Peer>();
          final commands = <NearbyFrame>[];
          script = (peer, _) async {
            authed.complete(peer);
            await peer.snapshot();
            for (var i = 0; i < 4; i++) {
              final command = await peer.next();
              commands.add(command);
              await peer.result(command);
            }
          };
          await expectLater(target.play(), throwsA(_code('not_connected')));
          await target.connect(subnet);
          final peer = await authed.future;
          await target.play();
          expect(target.snapshot.playing, isFalse);
          final updated = nearbySnapshotFixture();
          (updated['playback']! as Map)['playing'] = true;
          final playing = target.states.firstWhere((state) => state.playing);
          await peer.snapshot(updated);
          await playing;
          await target.seek(const Duration(minutes: 5));
          expect(commands[1].fields['args'], {'positionMs': 90000});
          expect(target.snapshot.position, const Duration(seconds: 1));
          await target.sendChat('Hello');
          await target.sendReaction('❤️');
          expect(commands.map((command) => command.fields['method']), [
            'playback.play',
            'playback.seek',
            'chat.send',
            'chat.reaction',
          ]);
          await expectLater(
            target.load(
              MediaItem(uri: Uri.file('C:/private.mp4'), title: 'Private'),
            ),
            throwsA(_code('desktop_media_required')),
          );
          expect(commands.length, 4);
        },
      );

      test(
        'unknown desktop duration does not turn every seek into zero',
        () async {
          final received = Completer<NearbyFrame>();
          script = (peer, _) async {
            final state = nearbySnapshotFixture();
            (state['playback']! as Map)['durationMs'] = null;
            await peer.snapshot(state);
            final command = await peer.next();
            received.complete(command);
            await peer.result(command);
          };
          await target.connect(subnet);
          await target.seek(const Duration(seconds: 6));
          expect((await received.future).fields['args'], {'positionMs': 6000});
        },
      );

      test(
        'EOF before initial snapshot fails promptly instead of waiting 15 seconds',
        () async {
          script = (peer, _) async {
            peer.socket.destroy();
          };
          await expectLater(
            target.connect(subnet).timeout(const Duration(seconds: 2)),
            throwsA(isA<NearbyException>()),
          );
          expect(target.connected, isFalse);
        },
      );

      test('close cancels pending readiness and is idempotent', () async {
        final authed = Completer<void>();
        script = (_, _) async {
          authed.complete();
        };
        final outcome = expectLater(
          target.connect(subnet),
          throwsA(isA<NearbyException>()),
        );
        await authed.future;
        await target.close();
        await target.close();
        await outcome;
        expect(target.connected, isFalse);
        await expectLater(target.play(), throwsA(_code('not_connected')));
      });

      test(
        'superseded connection failure cannot disconnect a newer attempt',
        () async {
          final firstAuthed = Completer<void>();
          script = (peer, connection) async {
            if (connection == 1) {
              firstAuthed.complete();
              return;
            }
            await peer.snapshot();
          };
          final first = expectLater(
            target.connect(subnet),
            throwsA(isA<NearbyException>()),
          );
          await firstAuthed.future;
          await target.connect(subnet);
          await first;
          expect(target.connected, isTrue);
          expect(target.snapshot.ready, isTrue);
        },
      );

      test(
        'malformed initial snapshot fails closed with a safe diagnostic',
        () async {
          script = (peer, _) async {
            final state = nearbySnapshotFixture();
            (state['playback']! as Map)['buffering'] = 'secret';
            await peer.snapshot(state);
          };
          await expectLater(
            target.connect(subnet),
            throwsA(_code('invalid_argument')),
          );
          expect(target.connected, isFalse);
          expect(target.snapshot.error, nearbyErrorMessage('invalid_argument'));
          expect(target.snapshot.error, isNot(contains('secret')));
        },
      );

      for (final mismatch in ['desktop', 'epoch']) {
        test('rejects a snapshot with mismatched $mismatch identity', () async {
          script = (peer, _) async {
            final state = nearbySnapshotFixture(
              desktopId: mismatch == 'desktop' ? _tokenId : null,
              epoch: mismatch == 'epoch' ? _tokenId : null,
            );
            await peer.snapshot(state);
          };
          await expectLater(
            target.connect(subnet),
            throwsA(isA<NearbyException>()),
          );
          expect(target.remote, isNull);
          expect(target.connected, isFalse);
        });
      }

      test(
        'disconnection stops playback and keeps only the last display snapshot',
        () async {
          final authed = Completer<_Peer>();
          script = (peer, _) async {
            authed.complete(peer);
            final state = nearbySnapshotFixture();
            (state['playback']! as Map)['playing'] = true;
            await peer.snapshot(state);
          };
          await target.connect(subnet);
          expect(target.snapshot.playing, isTrue);
          final disconnected = target.states.firstWhere(
            (state) => state.connection == PlaybackConnection.disconnected,
          );
          (await authed.future).socket.destroy();
          await disconnected;
          expect(target.snapshot.playing, isFalse);
          expect(target.snapshot.media?.title, 'Movie.mp4');
          expect(target.connected, isFalse);
          await expectLater(target.pause(), throwsA(_code('not_connected')));
        },
      );
    },
    skip: address == null || prefix == null
        ? 'Set NEARBY_TEST_ADDRESS and NEARBY_TEST_PREFIX from an actual LAN adapter.'
        : false,
  );
}

Matcher _code(String code) =>
    isA<NearbyException>().having((e) => e.code, 'code', code);
