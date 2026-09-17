import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'package:meowwatch_mobile/app/app_controller.dart';
import 'package:meowwatch_mobile/app/app_services.dart';
import 'package:meowwatch_mobile/core/billing/file_hosting_quota_store.dart';
import 'package:meowwatch_mobile/core/billing/hosting_access_policy.dart';
import 'package:meowwatch_mobile/core/billing/revenuecat_billing_service.dart';
import 'package:meowwatch_mobile/core/playback/local_mobile_target.dart';
import 'package:meowwatch_mobile/core/session/playback_sync_bridge.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';
import 'package:meowwatch_mobile/data/app_repository.dart';
import 'package:meowwatch_mobile/main.dart';

import '../tools/native_capture/native_screenshot.dart';

const _runId = String.fromEnvironment('NETWORK_RUN_ID');
const _videoUrl = 'http://10.0.2.2:18765/sync-fixture.mp4';
const _runtime =
    'API 35 emulator; one MainApp process; two real STARTTLS clients and '
    'two Android decoders; only the host player is rendered';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'real Android network loss and recovery preserve Together',
    (tester) async {
      expect(Platform.isAndroid, isTrue);
      expect(RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(_runId), isTrue);
      final support = await getApplicationSupportDirectory();
      final repositoryFile = File(
        '${support.path}/network-$_runId-history.json',
      );
      final quotaFile = File('${support.path}/network-$_runId-quota.json');
      expect(await repositoryFile.exists(), isFalse);
      expect(await quotaFile.exists(), isFalse);
      final observations = <Map<String, Object?>>[];
      final verified = <String>[];
      final screenshots = <String>[];
      final subscriptions = <StreamSubscription<dynamic>>[];
      final clients = <SyncplayClient>[];
      final peerErrors = <String>[];
      final billing = RevenueCatBillingService(apiKey: revenueCatPublicKey);
      // Two decoders share this test process. Production phones keep their
      // default exclusive audio policy; this does not model two devices.
      final phone = LocalMobileTarget(mixWithOthers: true);
      final peerTarget = LocalMobileTarget(mixWithOthers: true);
      final peer = SyncplayClient();
      final peerBridge = PlaybackSyncBridge(
        target: peerTarget,
        sync: peer,
        authorizePlayback: () async => true,
        onError: (error) => peerErrors.add(error.toString()),
      );
      final hosting = LocalHostingAccessPolicy(
        store: FileHostingQuotaStore(quotaFile),
        isPlus: () => billing.isPlus,
      );
      final app = AppController(
        repository: AppRepository(repositoryFile),
        billing: billing,
        hosting: hosting,
        phone: phone,
        createSyncClient: () {
          final client = SyncplayClient();
          clients.add(client);
          subscriptions.add(
            client.connectionState.listen((state) {
              observations.add(_connection('host', state));
            }),
          );
          return client;
        },
      );
      subscriptions.add(
        peer.connectionState.listen((state) {
          observations.add(_connection('guest', state));
        }),
      );
      final nativeScreenshots = NativeScreenshots(binding);
      var completed = false;
      final teardownErrors = <String>[];

      Future<void> screenshot(String phase) async {
        final name = 'network-$phase';
        expect(
          await nativeScreenshots
              .take(tester, name)
              .timeout(const Duration(seconds: 30)),
          isNotEmpty,
        );
        screenshots.add(name);
      }

      Future<void> checkpoint(String phase, String acknowledgement) async {
        debugPrintSynchronously(
          'NETWORK_CHECKPOINT ${jsonEncode({'runId': _runId, 'phase': phase, 'pid': pid})}',
        );
        final ack = File('${support.path}/network-$_runId-$acknowledgement');
        final clock = Stopwatch()..start();
        while (!await ack.exists()) {
          if (clock.elapsed > const Duration(seconds: 100)) {
            throw TestFailure(
              'External ADB runner did not acknowledge $phase.',
            );
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(await ack.readAsString(), '$_runId:$acknowledgement');
      }

      try {
        expect(
          (await billing.configure().timeout(
            const Duration(seconds: 60),
          )).succeeded,
          isTrue,
        );
        expect(
          billing.isPlus,
          isFalse,
          reason: 'A fresh free customer is required.',
        );
        expect(await hosting.remainingFreeHostsToday(), 1);
        await tester.pumpWidget(MainApp(controller: app));
        await _wait(
          tester,
          () =>
              find.byKey(const Key('display-name-field')).evaluate().isNotEmpty,
          'production onboarding',
        );
        final tag = _runId.substring(_runId.length > 8 ? _runId.length - 8 : 0);
        await tester.enterText(
          find.byKey(const Key('display-name-field')),
          'NetworkHost $tag',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await _tap(tester, find.byKey(const Key('onboarding-continue-button')));
        await _wait(
          tester,
          () => find.byKey(const Key('home-scroll-view')).evaluate().isNotEmpty,
          'production home',
        );
        await checkpoint('app-ready', 'bootstrap-observed');
        await _tap(tester, find.byKey(const Key('start-room-button')));
        await _wait(
          tester,
          () => app.isConnected && app.room != null,
          'production host STARTTLS join',
          seconds: 90,
        );
        final room = app.room!;
        expect(room.isHost, isTrue);
        final guestName = 'NetworkPeer $tag';
        expect(
          await peer
              .connectUntilJoin(
                server: room.config.server,
                port: room.config.port,
                room: room.config.room,
                username: guestName,
              )
              .timeout(const Duration(seconds: 60)),
          isNull,
        );
        peerBridge.start();
        await _wait(
          tester,
          () => app.peers.contains(peer.username),
          'real peer',
        );
        await _tap(tester, find.widgetWithText(TextButton, 'Video'));
        await _wait(
          tester,
          () => find.text('Choose what to watch').evaluate().isNotEmpty,
          'production media sheet',
        );
        await tester.enterText(
          find.byType(TextField).hitTestable().last,
          _videoUrl,
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await _tap(tester, find.text('Use this link'));
        await _wait(
          tester,
          () =>
              phone.snapshot.ready &&
              find.byType(VideoPlayer).evaluate().isNotEmpty,
          'native host decoder',
          seconds: 70,
        );
        final media = phone.snapshot.media!;
        expect(media.uri, Uri.parse(_videoUrl));
        await peerBridge.load(media).timeout(const Duration(seconds: 70));
        final hostController = phone.controller;
        final guestController = peerTarget.controller;
        expect(hostController, isNotNull);
        expect(guestController, isNotNull);
        expect(
          phone.snapshot.duration,
          greaterThan(const Duration(seconds: 80)),
        );
        await checkpoint('players-ready', 'recording-ready');
        await _playControl(tester, play: true);
        await _advancing(
          tester,
          app,
          peerBridge,
          phone,
          peerTarget,
          observations,
          'initial',
        );
        await _wait(
          tester,
          () => !app.busy && !app.needsPlus,
          'host authorization',
        );
        expect(await hosting.remainingFreeHostsToday(), 0);
        final quota = await quotaFile.readAsString();
        final address = await _probe(
          room.config.server,
          room.config.port,
          observations,
          'healthy',
          reachable: true,
        );
        await screenshot('initial');
        verified.add('initial_real_tls_native_playback_and_consumed_host');
        await checkpoint('initial-ready', 'network-disabled');

        await _probe(
          address!,
          room.config.port,
          observations,
          'offline',
          reachable: false,
        );
        await _wait(
          tester,
          () =>
              !app.isConnected &&
              peer.lastConnectionState?.status !=
                  SyncConnectionStatus.connected &&
              !phone.snapshot.playing &&
              !peerTarget.snapshot.playing &&
              !app.playRequested &&
              !peerBridge.playRequested,
          'real network loss and automatic pause',
          seconds: 45,
        );
        await _wait(
          tester,
          () =>
              find
                  .text('Reconnecting · playback paused')
                  .hitTestable()
                  .evaluate()
                  .isNotEmpty ||
              find
                  .text('Connection lost · playback paused')
                  .hitTestable()
                  .evaluate()
                  .isNotEmpty,
          'visible production disconnect state',
        );
        await _paused(
          tester,
          app,
          peerBridge,
          phone,
          peerTarget,
          observations,
          'offline',
          requireSynchronized: false,
        );
        expect(app.room?.id, room.id);
        expect(phone.snapshot.media?.uri, media.uri);
        expect(identical(phone.controller, hostController), isTrue);
        expect(await quotaFile.readAsString(), quota);
        await screenshot('offline');
        verified.add('physical_avd_network_unreachable_and_visible_auto_pause');
        await checkpoint('offline-confirmed', 'network-restored');

        await _wait(
          tester,
          () =>
              app.isConnected &&
              peer.lastConnectionState?.status ==
                  SyncConnectionStatus.connected &&
              app.peers.contains(peer.username),
          'automatic real TLS reconnect and peer roster',
          seconds: 90,
        );
        await _probe(
          address,
          room.config.port,
          observations,
          'restored',
          reachable: true,
        );
        await _wait(
          tester,
          () => find
              .text('Together in this room')
              .hitTestable()
              .evaluate()
              .isNotEmpty,
          'visible recovered connection',
        );
        await _paused(
          tester,
          app,
          peerBridge,
          phone,
          peerTarget,
          observations,
          'reconnected-without-autoplay',
          requireSynchronized: false,
        );
        expect(app.room?.id, room.id);
        expect(app.room?.contextKey, room.contextKey);
        expect(app.room?.isHost, isTrue);
        expect(phone.snapshot.media?.uri, media.uri);
        expect(peerTarget.snapshot.media?.uri, media.uri);
        expect(identical(phone.controller, hostController), isTrue);
        expect(identical(peerTarget.controller, guestController), isTrue);
        expect(await hosting.remainingFreeHostsToday(), 0);
        expect(await quotaFile.readAsString(), quota);
        expect(app.needsPlus, isFalse);
        await screenshot('reconnected-paused');
        verified.add('same_room_media_controllers_quota_and_no_autoplay');
        await checkpoint('reconnected-confirmed', 'controls-ready');

        await _playControl(tester, play: true);
        await _advancing(
          tester,
          app,
          peerBridge,
          phone,
          peerTarget,
          observations,
          'explicit-play-after-reconnect',
        );
        await _playControl(tester, play: false);
        await _paused(
          tester,
          app,
          peerBridge,
          phone,
          peerTarget,
          observations,
          'explicit-pause-after-reconnect',
        );
        final slider = find.byType(Slider).hitTestable().first;
        await _wait(
          tester,
          () => slider.evaluate().isNotEmpty,
          'production seek control',
        );
        final geometry = tester.getRect(slider);
        await tester.tapAt(
          Offset(geometry.left + geometry.width * 0.4, geometry.center.dy),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await _wait(
          tester,
          () =>
              phone.snapshot.position > const Duration(seconds: 20) &&
              (phone.snapshot.position - peerTarget.snapshot.position).abs() <
                  const Duration(milliseconds: 350),
          'explicit production seek reaches real peer',
          seconds: 30,
        );
        await _paused(
          tester,
          app,
          peerBridge,
          phone,
          peerTarget,
          observations,
          'explicit-seek-after-reconnect',
        );
        expect(await quotaFile.readAsString(), quota);
        expect(peerErrors, isEmpty);
        expect(tester.takeException(), isNull);
        observations.add({
          'phase': 'identity-and-quota',
          'roomId': room.id,
          'server': room.config.server,
          'port': room.config.port,
          'room': room.config.room,
          'media': media.uri.toString(),
          'quotaBeforeLoss': jsonDecode(quota),
          'quotaAfterRecovery': jsonDecode(await quotaFile.readAsString()),
          'sameHostController': identical(phone.controller, hostController),
          'sameGuestController': identical(
            peerTarget.controller,
            guestController,
          ),
          'hostClientCount': clients.length,
        });
        await screenshot('recovery-controls');
        verified.add('explicit_production_play_pause_seek_and_real_peer_sync');
        await checkpoint('recovery-confirmed', 'evidence-complete');
        completed = true;
      } finally {
        Future<void> cleanup(
          String name,
          Future<void> Function() action,
        ) async {
          try {
            await action().timeout(const Duration(seconds: 15));
          } catch (error) {
            teardownErrors.add('$name: $error');
          }
        }

        await cleanup(
          'unmount',
          () => tester.pumpWidget(const SizedBox.shrink()),
        );
        await cleanup('peer bridge', peerBridge.dispose);
        await cleanup('peer TLS', peer.dispose);
        await cleanup('peer decoder', peerTarget.close);
        await cleanup('MainApp services', app.close);
        for (final subscription in subscriptions) {
          await cleanup('connection subscription', subscription.cancel);
        }
        binding.reportData = {
          'runId': _runId,
          'runtime': _runtime,
          'passed': completed && teardownErrors.isEmpty,
          'verified': verified,
          'observations': observations,
          'screenshots': screenshots,
          'teardownErrors': teardownErrors,
        };
        debugPrintSynchronously(
          'NETWORK_CHECKPOINT ${jsonEncode({'runId': _runId, 'phase': 'teardown-complete', 'pid': pid, 'passed': completed && teardownErrors.isEmpty})}',
        );
        expect(teardownErrors, isEmpty);
      }
    },
    timeout: const Timeout(Duration(minutes: 9)),
  );
}

Map<String, Object?> _connection(String role, SyncConnectionState state) => {
  'phase': 'connection',
  'role': role,
  'status': state.status.name,
  'atUtc': DateTime.now().toUtc().toIso8601String(),
  'message': state.message,
};

Future<String?> _probe(
  String address,
  int port,
  List<Map<String, Object?>> observations,
  String phase, {
  required bool reachable,
}) async {
  Socket? socket;
  final clock = Stopwatch()..start();
  try {
    socket = await Socket.connect(
      address,
      port,
      timeout: const Duration(seconds: 5),
    );
    final resolved = socket.remoteAddress.address;
    observations.add({
      'phase': 'probe-$phase',
      'address': address,
      'port': port,
      'resolvedAddress': resolved,
      'reachable': true,
      'elapsedMs': clock.elapsedMilliseconds,
    });
    expect(
      reachable,
      isTrue,
      reason:
          'Android can still reach the same real TLS endpoint while radios are disabled.',
    );
    return resolved;
  } on SocketException catch (error) {
    observations.add({
      'phase': 'probe-$phase',
      'address': address,
      'port': port,
      'reachable': false,
      'elapsedMs': clock.elapsedMilliseconds,
      'error': '$error',
    });
    expect(
      reachable,
      isFalse,
      reason: 'Required live network probe failed: $error',
    );
    return null;
  } finally {
    socket?.destroy();
  }
}

Future<void> _wait(
  WidgetTester tester,
  bool Function() condition,
  String description, {
  int seconds = 30,
}) async {
  final clock = Stopwatch()..start();
  while (!condition()) {
    if (clock.elapsed > Duration(seconds: seconds)) {
      throw TestFailure('Timed out after ${seconds}s: $description');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _wait(
    tester,
    () => finder.hitTestable().evaluate().isNotEmpty,
    'tappable $finder',
  );
  await tester.tap(finder.hitTestable().first);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _playControl(WidgetTester tester, {required bool play}) async {
  final label = play ? 'Play' : 'Pause';
  final finder = find.byWidgetPredicate(
    (widget) =>
        widget is Tooltip &&
        (widget.message == label || widget.message == '$label together'),
  );
  await _tap(tester, finder);
}

Future<List<int>> _nativePositions(
  LocalMobileTarget host,
  LocalMobileTarget guest,
) async => [
  (await host.controller!.position.timeout(
    const Duration(seconds: 5),
  ))!.inMilliseconds,
  (await guest.controller!.position.timeout(
    const Duration(seconds: 5),
  ))!.inMilliseconds,
];

Future<void> _advancing(
  WidgetTester tester,
  AppController app,
  PlaybackSyncBridge bridge,
  LocalMobileTarget host,
  LocalMobileTarget guest,
  List<Map<String, Object?>> observations,
  String phase,
) async {
  final start = await _nativePositions(host, guest);
  final samples = <Map<String, Object?>>[];
  final clock = Stopwatch()..start();
  while (clock.elapsed < const Duration(seconds: 30)) {
    final positions = await _nativePositions(host, guest);
    final playing =
        app.playRequested &&
        bridge.playRequested &&
        host.snapshot.playing &&
        guest.snapshot.playing;
    samples.add({
      'elapsedMs': clock.elapsedMilliseconds,
      'nativeMs': positions,
      'playing': playing,
    });
    if (playing &&
        positions[0] > start[0] + 1500 &&
        positions[1] > start[1] + 1500 &&
        (positions[0] - positions[1]).abs() < 1000) {
      observations.add({'phase': phase, 'nativeAdvancementSamples': samples});
      return;
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  throw TestFailure(
    'Both native decoders did not advance in $phase: ${jsonEncode(samples)}',
  );
}

Future<void> _paused(
  WidgetTester tester,
  AppController app,
  PlaybackSyncBridge bridge,
  LocalMobileTarget host,
  LocalMobileTarget guest,
  List<Map<String, Object?>> observations,
  String phase, {
  bool requireSynchronized = true,
}) async {
  final clock = Stopwatch()..start();
  final samples = <Map<String, Object?>>[];
  Stopwatch? stable;
  List<int>? first;
  var count = 0;
  while (clock.elapsed < const Duration(seconds: 45)) {
    final position = await _nativePositions(host, guest);
    final paused =
        !app.playRequested &&
        !bridge.playRequested &&
        !host.snapshot.playing &&
        !guest.snapshot.playing;
    final settled =
        paused &&
        (!requireSynchronized || (position[0] - position[1]).abs() < 350) &&
        (first == null ||
            ((position[0] - first[0]).abs() < 100 &&
                (position[1] - first[1]).abs() < 100));
    samples.add({
      'elapsedMs': clock.elapsedMilliseconds,
      'nativeMs': position,
      'paused': paused,
    });
    if (settled) {
      first ??= position;
      stable ??= Stopwatch()..start();
      count++;
      if (count >= 9 && stable.elapsed >= const Duration(milliseconds: 800)) {
        observations.add({
          'phase': phase,
          'stableSamples': count,
          'stableElapsedMs': stable.elapsedMilliseconds,
          'samples': samples,
        });
        return;
      }
    } else {
      stable = null;
      first = null;
      count = 0;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw TestFailure(
    'Native pause did not settle in $phase: ${jsonEncode(samples)}',
  );
}
