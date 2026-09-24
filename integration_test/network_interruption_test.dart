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
import 'package:meowwatch_mobile/core/billing/billing_service.dart';
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
import 'support/test_text_entry.dart';

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
      final protocolTrace = <Map<String, Object?>>[];
      void trace(String role, String line) {
        final entry = {
          'role': role,
          'atUtc': DateTime.now().toUtc().toIso8601String(),
          'line': line,
        };
        // The full trace remains in logcat; retain the most recent traffic in
        // result.json as well, including when an assertion fails before outage.
        if (protocolTrace.length == 600) protocolTrace.removeAt(0);
        protocolTrace.add(entry);
        debugPrintSynchronously('NETWORK_SYNC ${jsonEncode(entry)}');
      }

      final billing = RevenueCatBillingService(apiKey: revenueCatPublicKey);
      // Two decoders share this test process. Production phones keep their
      // default exclusive audio policy; this does not model two devices.
      final phone = LocalMobileTarget(mixWithOthers: true);
      final peerTarget = LocalMobileTarget(mixWithOthers: true);
      final peer = SyncplayClient(onLog: (line) => trace('guest', line));
      final peerBridge = PlaybackSyncBridge(
        target: peerTarget,
        sync: peer,
        authorizePlayback: () async => true,
        onError: (error) {
          peerErrors.add(error.toString());
          observations.add({
            'phase': 'peer-command-error',
            'atUtc': DateTime.now().toUtc().toIso8601String(),
            'error': error.toString(),
          });
        },
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
          final client = SyncplayClient(onLog: (line) => trace('host', line));
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
      var stage = 'bootstrap';
      Map<String, Object?>? failure;
      Map<String, Object?>? billingSetup;
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
        stage = '$phase / awaiting $acknowledgement';
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
        final billingResult = await billing.configure().timeout(
          const Duration(seconds: 60),
        );
        billingSetup = {
          'status': billingResult.status.name,
          'errorCode': billingResult.errorCode,
          'configured': billing.isConfigured,
          'isPlus': billing.isPlus,
        };
        if (kDebugMode) {
          expect(billingResult.succeeded, isTrue);
          expect(billing.isConfigured, isTrue);
        } else {
          // The normal profile build has no store key. Its real free-host
          // fallback is the subject here; purchase acceptance stays in debug.
          expect(kProfileMode, isTrue);
          expect(revenueCatPublicKey, isEmpty);
          expect(billingResult.status, BillingStatus.unavailable);
          expect(billingResult.errorCode, 'missing_public_sdk_key');
          expect(billing.isConfigured, isFalse);
        }
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
        await enterTogetherTestText(
          tester,
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
        stage = 'host-starttls';
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
        stage = 'guest-starttls';
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
        stage = 'host-media-load';
        await _tap(tester, find.widgetWithText(TextButton, 'Video'));
        final videoField = find.byType(TextField).hitTestable();
        await _wait(
          tester,
          () =>
              find.text('Choose what to watch').evaluate().isNotEmpty &&
              videoField.evaluate().isNotEmpty,
          'production media sheet and URL field',
        );
        await enterTogetherTestText(tester, videoField.last, _videoUrl);
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
        stage = 'guest-media-load';
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
        stage = 'initial-playback';
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

        stage = 'offline-proof-and-auto-pause';
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

        stage = 'automatic-reconnect-without-autoplay';
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

        stage = 'explicit-play-after-reconnect';
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
        stage = 'explicit-pause-after-reconnect';
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
        stage = 'explicit-seek-after-reconnect';
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
      } catch (error, stack) {
        failure = {
          'stage': stage,
          'atUtc': DateTime.now().toUtc().toIso8601String(),
          'message': error.toString(),
          'stackTrace': stack.toString(),
          'host': _playerEvidence(phone, app.playRequested),
          'guest': _playerEvidence(peerTarget, peerBridge.playRequested),
          'hostConnection': app.connection.status.name,
          'guestConnection': peer.lastConnectionState?.status.name,
          'hostRoomState': _roomEvidence(
            clients.isEmpty ? null : clients.last.lastObservedRoomState,
          ),
          'guestRoomState': _roomEvidence(peer.lastObservedRoomState),
          'peerErrors': List<String>.of(peerErrors),
        };
        rethrow;
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
          'buildMode': kProfileMode
              ? 'profile'
              : kReleaseMode
              ? 'release'
              : 'debug',
          'billingSetup': billingSetup,
          'passed': completed && teardownErrors.isEmpty,
          'verified': verified,
          'observations': observations,
          'protocolTrace': protocolTrace,
          'peerErrors': peerErrors,
          'failure': failure,
          'screenshots': screenshots,
          'teardownErrors': teardownErrors,
        };
        // Logcat truncates long lines. Keep this coordination marker bounded;
        // result.json retains the complete failure, samples, and stack trace.
        final message = failure?['message']?.toString().split('\n').first ?? '';
        final terminalFailure = failure == null
            ? null
            : {
                'stage': failure['stage'],
                'message': message.length > 400
                    ? '${message.substring(0, 400)}...'
                    : message,
              };
        debugPrintSynchronously(
          'NETWORK_CHECKPOINT ${jsonEncode({'runId': _runId, 'phase': 'teardown-complete', 'pid': pid, 'passed': completed && teardownErrors.isEmpty, 'failure': terminalFailure})}',
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

Map<String, Object?> _playerEvidence(
  LocalMobileTarget target,
  bool playRequested,
) {
  final snapshot = target.snapshot;
  final value = target.controller?.value;
  return {
    'playRequested': playRequested,
    'targetPlayRequested': target.playRequested,
    'snapshot': {
      'positionMs': snapshot.position.inMilliseconds,
      'durationMs': snapshot.duration.inMilliseconds,
      'playing': snapshot.playing,
      'buffering': snapshot.buffering,
      'connection': snapshot.connection.name,
      'error': snapshot.error,
    },
    'controller': value == null
        ? null
        : {
            'positionMs': value.position.inMilliseconds,
            'playing': value.isPlaying,
            'buffering': value.isBuffering,
            'initialized': value.isInitialized,
            'completed': value.isCompleted,
            'error': value.errorDescription,
          },
  };
}

Map<String, Object?>? _roomEvidence(PeerPlayState? state) => state == null
    ? null
    : {
        'positionMs': state.position.inMilliseconds,
        'paused': state.paused,
        'doSeek': state.doSeek,
        'setBy': state.setBy,
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
  Map<String, Object?> evidence,
  String readStage,
) async => [
  await _nativePosition(host, 'host', evidence, readStage),
  await _nativePosition(guest, 'guest', evidence, readStage),
];

Future<int> _nativePosition(
  LocalMobileTarget target,
  String role,
  Map<String, Object?> evidence,
  String readStage,
) async {
  final controller = target.controller;
  final reads =
      evidence.putIfAbsent(
            'nativePositionReads',
            () => <Map<String, Object?>>[],
          )
          as List<Map<String, Object?>>;
  final index = (evidence['nativePositionReadCount'] as int? ?? 0) + 1;
  evidence['nativePositionReadCount'] = index;
  evidence['nativePositionReadsDropped'] = index > 512 ? index - 512 : 0;
  if (reads.length == 512) reads.removeAt(0);
  final read = <String, Object?>{
    'runId': _runId,
    'pid': pid,
    'phase': evidence['phase'],
    'readStage': readStage,
    'readIndex': index,
    'role': role,
    'controllerId': controller?.playerId,
    'startedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'timeoutMs': 5000,
    'status': 'pending',
  };
  // Retain the pending read before awaiting even the first baseline sample.
  // Full bounded start/end records also survive in raw logcat if teardown fails.
  reads.add(read);
  debugPrintSynchronously(
    'NETWORK_NATIVE_POSITION ${jsonEncode({...read, 'event': 'start'})}',
  );
  final clock = Stopwatch()..start();
  try {
    final position = (await controller!.position.timeout(
      const Duration(seconds: 5),
    ))!.inMilliseconds;
    read['status'] = 'success';
    read['positionMs'] = position;
    return position;
  } catch (error) {
    read['status'] = error is TimeoutException ? 'timeout' : 'error';
    final message = error.toString().split('\n').first;
    read['error'] = message.length > 400 ? message.substring(0, 400) : message;
    rethrow;
  } finally {
    clock.stop();
    read['endedAtUtc'] = DateTime.now().toUtc().toIso8601String();
    read['elapsedMs'] = clock.elapsedMilliseconds;
    debugPrintSynchronously(
      'NETWORK_NATIVE_POSITION ${jsonEncode({...read, 'event': 'end'})}',
    );
  }
}

Future<void> _advancing(
  WidgetTester tester,
  AppController app,
  PlaybackSyncBridge bridge,
  LocalMobileTarget host,
  LocalMobileTarget guest,
  List<Map<String, Object?>> observations,
  String phase,
) async {
  final samples = <Map<String, Object?>>[];
  final evidence = <String, Object?>{
    'phase': phase,
    'startedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'startNativeMs': null,
    'nativeAdvancementSamples': samples,
    'converged': false,
  };
  observations.add(evidence);
  final start = await _nativePositions(host, guest, evidence, 'baseline');
  evidence['startNativeMs'] = start;
  final clock = Stopwatch()..start();
  while (clock.elapsed < const Duration(seconds: 30)) {
    final positions = await _nativePositions(
      host,
      guest,
      evidence,
      'advancing',
    );
    final playing =
        app.playRequested &&
        bridge.playRequested &&
        host.snapshot.playing &&
        guest.snapshot.playing;
    samples.add({
      'elapsedMs': clock.elapsedMilliseconds,
      'nativeMs': positions,
      'playing': playing,
      'host': _playerEvidence(host, app.playRequested),
      'guest': _playerEvidence(guest, bridge.playRequested),
      'guestRoomState': _roomEvidence(bridge.sync.lastObservedRoomState),
    });
    if (playing &&
        positions[0] > start[0] + 1500 &&
        positions[1] > start[1] + 1500 &&
        (positions[0] - positions[1]).abs() < 1000) {
      evidence['converged'] = true;
      evidence['convergedElapsedMs'] = clock.elapsedMilliseconds;
      return;
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  throw TestFailure(
    'Both native decoders did not advance in $phase. '
    'Full native advancement samples are retained in result.json.',
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
  final evidence = <String, Object?>{
    'phase': phase,
    'startedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'samples': samples,
    'converged': false,
  };
  observations.add(evidence);
  Stopwatch? stable;
  List<int>? first;
  var count = 0;
  while (clock.elapsed < const Duration(seconds: 45)) {
    final position = await _nativePositions(host, guest, evidence, 'paused');
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
      'host': _playerEvidence(host, app.playRequested),
      'guest': _playerEvidence(guest, bridge.playRequested),
      'guestRoomState': _roomEvidence(bridge.sync.lastObservedRoomState),
    });
    if (settled) {
      first ??= position;
      stable ??= Stopwatch()..start();
      count++;
      if (count >= 9 && stable.elapsed >= const Duration(milliseconds: 800)) {
        evidence['stableSamples'] = count;
        evidence['stableElapsedMs'] = stable.elapsedMilliseconds;
        evidence['converged'] = true;
        evidence['convergedElapsedMs'] = clock.elapsedMilliseconds;
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
    'Native pause did not settle in $phase. '
    'Full native pause samples are retained in result.json.',
  );
}
