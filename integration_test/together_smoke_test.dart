import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meowwatch_mobile/app/app_controller.dart';
import 'package:meowwatch_mobile/core/billing/file_hosting_quota_store.dart';
import 'package:meowwatch_mobile/core/billing/hosting_access_policy.dart';
import 'package:meowwatch_mobile/core/billing/revenuecat_billing_service.dart';
import 'package:meowwatch_mobile/core/connect/room_config.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/playback/local_mobile_target.dart';
import 'package:meowwatch_mobile/data/app_repository.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../tools/native_capture/native_screenshot.dart';

const _role = String.fromEnvironment('TOGETHER_ROLE', defaultValue: 'host');
const _room = String.fromEnvironment('TOGETHER_ROOM');
const _server = String.fromEnvironment(
  'SYNCPLAY_SERVER',
  defaultValue: 'syncplay.pl',
);
const _port = int.fromEnvironment('SYNCPLAY_PORT', defaultValue: 8995);
const _video = String.fromEnvironment(
  'TOGETHER_VIDEO_URL',
  defaultValue:
      'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'two Android video clients synchronize over real STARTTLS',
    (tester) async {
      expect(Platform.isAndroid, isTrue);
      expect(
        _room,
        isNotEmpty,
        reason: 'Use a unique TOGETHER_ROOM shared by both APKs.',
      );
      expect(['host', 'guest'], contains(_role));
      final host = _role == 'host';
      final root = await getApplicationSupportDirectory();
      final repository = AppRepository(
        File('${root.path}/together-$_room-$_role.json'),
      );
      final billing = RevenueCatBillingService(apiKey: '');
      final target = LocalMobileTarget();
      final quota = LocalHostingAccessPolicy(
        store: FileHostingQuotaStore(
          File('${root.path}/quota-$_room-$_role.json'),
        ),
        isPlus: () => billing.isPlus,
      );
      final app = AppController(
        repository: repository,
        billing: billing,
        hosting: quota,
        phone: target,
      );
      addTearDown(app.close);
      await app.setName(host ? 'Phone' : 'Tablet');
      final ticket = RoomTicket(
        id: '$_room-$_role',
        isHost: host,
        config: RoomConfig(
          server: _server,
          port: _port,
          room: _room,
          username: app.username,
        ),
      );
      expect(await app.connect(ticket), isTrue, reason: app.message);
      await app.load(MediaItem.fromUrl(_video));
      expect(target.snapshot.ready, isTrue, reason: app.message);
      expect(
        target.snapshot.duration,
        greaterThan(const Duration(seconds: 10)),
        reason:
            'Use a long video fixture so rendezvous and screenshots do not reach EOF.',
      );
      final screenshots = NativeScreenshots(binding);
      await tester.pumpWidget(_RuntimeSurface(app: app, target: target));

      Future<void> until(
        bool Function() condition,
        String stage, {
        int seconds = 45,
      }) async {
        final clock = Stopwatch()..start();
        while (!condition()) {
          if (clock.elapsed > Duration(seconds: seconds)) {
            throw TestFailure(
              '$_role: $stage timed out; connected=${app.isConnected}, '
              'peers=${app.peers}, playing=${target.snapshot.playing}, '
              'position=${target.snapshot.position}, error=${app.message}',
            );
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      bool received(String text) => app.messages.any(
        (message) => !message.isMine && message.text == text,
      );
      Future<void> waitMessage(String text) =>
          until(() => received(text), text);
      Future<void> signal(String text) async {
        app.sendChat(text);
        await tester.pump(const Duration(milliseconds: 200));
      }

      Future<int> waitPausePosition(int round) async {
        final prefix = 'paused $round at ';
        int? position;
        await until(() {
          for (final message in app.messages) {
            if (!message.isMine && message.text.startsWith(prefix)) {
              position = int.tryParse(message.text.substring(prefix.length));
              if (position != null && position! >= 0) return true;
            }
          }
          return false;
        }, 'authoritative pause position $round');
        return position!;
      }

      await until(
        () => app.peers.isNotEmpty && app.peerFiles.isNotEmpty,
        'peer media and presence',
        seconds: 90,
      );
      // A rendezvous prevents a fast client from moving the room before both
      // real Android decoders have accepted their media.
      await signal('$_role ready');
      await waitMessage(host ? 'guest ready' : 'host ready');

      final observed = <Map<String, Object>>[];
      Future<void> capture(String stage) async {
        observed.add({
          'stage': stage,
          'at': DateTime.now().toUtc().toIso8601String(),
          'positionMs': target.snapshot.position.inMilliseconds,
          'playing': target.snapshot.playing,
          'peers': app.peers.toList(),
        });
        await tester.pump();
        await screenshots.take(tester, '$_role-$stage');
      }

      for (var round = 0; round < 2; round++) {
        final controlling = (round == 0) == host;
        if (controlling) {
          await app.seek(Duration.zero);
          await app.togglePlay();
          await until(
            () =>
                target.snapshot.playing &&
                target.snapshot.position.inMilliseconds >= 900,
            'local play',
          );
          await signal('playing $round');
          await waitMessage('saw play $round');
          debugPrint(
            'PAUSE_INTENT $_role round=$round '
            'requested=${app.playRequested} '
            'nativePlaying=${target.snapshot.playing} '
            'buffering=${target.snapshot.buffering}',
          );
          await app.togglePlay();
          await until(
            () => !app.playRequested && !target.snapshot.playing,
            'local pause before signaling the peer',
          );
          final pausedPosition = await target.controller!.position;
          expect(pausedPosition, isNotNull);
          await signal('paused $round at ${pausedPosition!.inMilliseconds}');
          await capture('paused-controller-$round');
          await waitMessage('saw pause $round');
          await app.seek(const Duration(seconds: 4));
          await signal('sought $round');
          await waitMessage('saw seek $round');
        } else {
          await waitMessage('playing $round');
          await until(
            () =>
                target.snapshot.playing &&
                target.snapshot.position.inMilliseconds >= 500,
            'peer play',
          );
          await capture('playing-$round');
          await signal('saw play $round');
          final expectedPosition = await waitPausePosition(round);
          // The bridge pauses before applying the room's authoritative seek.
          // Measure stability only once both native operations have converged.
          await until(
            () =>
                !target.snapshot.playing &&
                (target.snapshot.position.inMilliseconds - expectedPosition)
                        .abs() <
                    350,
            'peer pause and authoritative position',
          );
          final position = target.snapshot.position;
          await tester.pump(const Duration(milliseconds: 800));
          expect(
            (target.snapshot.position - position).inMilliseconds.abs(),
            lessThan(350),
          );
          observed.add({
            'stage': 'pause-convergence-$round',
            'controllerPositionMs': expectedPosition,
            'peerPositionMs': target.snapshot.position.inMilliseconds,
            'driftMs': (target.snapshot.position - position).inMilliseconds
                .abs(),
            'at': DateTime.now().toUtc().toIso8601String(),
          });
          await capture('paused-peer-$round');
          await signal('saw pause $round');
          await waitMessage('sought $round');
          await until(
            () => (target.snapshot.position.inMilliseconds - 4000).abs() < 700,
            'peer seek',
          );
          expect(target.snapshot.playing, isFalse);
          await capture('seek-$round');
          await signal('saw seek $round');
        }
      }

      if (host) {
        await signal('Send me a reaction');
        await until(() => app.reaction?.emoji == '❤️', 'reaction');
        await capture('reaction');
        await signal('reaction received');
        await waitMessage('typing ready');
        app.sendTyping(true);
        await waitMessage('typing received');
        app.sendTyping(false);
        await waitMessage('disconnecting');
        await until(() => app.peers.isEmpty, 'peer departure');
        expect(target.snapshot.playing, isFalse);
        await until(() => app.peers.isNotEmpty, 'peer re-entry', seconds: 90);
        await waitMessage('rejoined');
        expect(await quota.remainingFreeHostsToday(), 0);
        expect(await quota.canHostNow(sessionId: ticket.id), isTrue);
        expect(await quota.canHostNow(sessionId: 'another-session'), isFalse);
        await signal('host quota verified');
      } else {
        await waitMessage('Send me a reaction');
        app.sendReaction('❤️');
        await waitMessage('reaction received');
        await signal('typing ready');
        await until(() => app.typing.isNotEmpty, 'typing indicator');
        await signal('typing received');
        await signal('disconnecting');
        await app.leavePlayer();
        await tester.pump(const Duration(seconds: 2));
        expect(await app.connect(ticket), isTrue, reason: app.message);
        await until(() => app.peers.isNotEmpty, 'roster after re-entry');
        await signal('rejoined');
        await waitMessage('host quota verified');
        expect(await quota.remainingFreeHostsToday(), 1);
      }
      await capture('complete');
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['together'] = {
        'role': _role,
        'room': _room,
        'server': '$_server:$_port',
        'platform': Platform.operatingSystem,
        'video': _video,
        'observations': observed,
        'remainingFreeHosts': await quota.remainingFreeHostsToday(),
        'result': 'passed',
      };
      // Keep both clients present until both reports have been assembled.
      await signal('$_role complete');
      await waitMessage(host ? 'guest complete' : 'host complete');
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

/// Runtime evidence harness; this is deliberately labelled and not presented
/// as the final product UI or submitted as polished demo footage.
class _RuntimeSurface extends StatelessWidget {
  const _RuntimeSurface({required this.app, required this.target});
  final AppController app;
  final LocalMobileTarget target;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: app,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'MeowWatch · $_role runtime test',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                '${app.username} · ${app.connection.status.name} · ${app.peers.join(', ')}',
              ),
              const SizedBox(height: 24),
              AspectRatio(
                aspectRatio: target.controller!.value.aspectRatio,
                child: VideoPlayer(target.controller!),
              ),
              const SizedBox(height: 16),
              Text(
                '${target.snapshot.playing ? 'Playing' : 'Paused'} · ${target.snapshot.position}',
              ),
              if (app.reaction != null)
                Text(app.reaction!.emoji, style: const TextStyle(fontSize: 40)),
              ...app.messages.reversed
                  .take(5)
                  .map(
                    (message) => Text('${message.username}: ${message.text}'),
                  ),
            ],
          ),
        ),
      ),
    ),
  );
}
