import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meowwatch_mobile/app/app_controller.dart';
import 'package:meowwatch_mobile/app/app_services.dart';
import 'package:meowwatch_mobile/core/playback/playback_target.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';
import 'package:meowwatch_mobile/main.dart';
import 'package:video_player/video_player.dart';

import 'support/native_focus_stage_client.dart';
import 'support/test_text_entry.dart';

const _video = String.fromEnvironment('TOGETHER_FOCUS_VIDEO_URL');
const _bridge = String.fromEnvironment('TOGETHER_FOCUS_BRIDGE_URL');
const _poll = Duration(milliseconds: 150);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'real Together room pauses on native focus loss',
    (tester) async {
      expect(Platform.isAndroid, isTrue);
      expect(_video, isNotEmpty);
      expect(_bridge, isNotEmpty);
      final app = await openAppServices();
      addTearDown(app.close);
      expect((await app.billing.configure()).succeeded, isTrue);
      final evidence = <String, Object?>{
        'result': 'running',
        'runtimeBoundary':
            'Android MainApp production services in integration APK; '
            'one native decoder and a separate TLS client in the same process',
        'cases': <Map<String, Object?>>[],
        'operatingSystemVersion': Platform.operatingSystemVersion,
      };
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['togetherFocus'] = evidence;
      await tester.pumpWidget(MainApp(controller: app));
      final name = find.byKey(const Key('display-name-field'));
      await _wait(tester, () => name.evaluate().isNotEmpty, 'onboarding');
      await enterTogetherTestText(tester, name, 'Focus Host');
      FocusManager.instance.primaryFocus?.unfocus();
      await _tap(tester, find.byKey(const Key('onboarding-continue-button')));
      await _wait(
        tester,
        () => find.byKey(const Key('home-scroll-view')).evaluate().isNotEmpty,
        'home',
      );
      await _tap(tester, find.byKey(const Key('start-room-button')));
      await _wait(
        tester,
        () => app.inPlayer && app.isConnected && app.room != null,
        'hosted room: ${app.message}',
        seconds: 90,
      );
      final room = app.room!;
      expect(room.isHost, isTrue);
      final peer = SyncplayClient();
      addTearDown(peer.dispose);
      final error = await peer
          .connectUntilJoin(
            server: room.config.server,
            port: room.config.port,
            room: room.config.room,
            username: 'Focus Protocol Peer',
            password: room.config.password,
          )
          .timeout(const Duration(seconds: 60));
      expect(error, isNull);
      expect(peer.hasCompletedHello, isTrue);
      await _wait(
        tester,
        () => app.peers.contains(peer.username),
        'real TLS peer',
      );
      await _tap(tester, find.widgetWithText(TextButton, 'Video'));
      await _wait(
        tester,
        () => find.text('Choose what to watch').evaluate().isNotEmpty,
        'media sheet',
      );
      await enterTogetherTestText(tester, find.byType(TextField), _video);
      FocusManager.instance.primaryFocus?.unfocus();
      await _tap(tester, find.text('Use this link'));
      await _wait(
        tester,
        () {
          final native = app.target.snapshot;
          return find.byType(VideoPlayer).evaluate().isNotEmpty &&
              native.ready &&
              native.duration.inSeconds >= 170 &&
              native.error == null &&
              !native.buffering &&
              !native.playing &&
              peer.lastObservedRoomState?.paused == true;
        },
        'settled initial native and peer pause',
        seconds: 70,
      );
      await _tap(tester, _control('Play'));
      await _wait(
        tester,
        () =>
            app.target.snapshot.playing &&
            app.target.snapshot.position.inMilliseconds > 1000 &&
            peer.lastObservedRoomState?.paused == false,
        'native and peer playing',
        seconds: 35,
      );
      evidence['roomId'] = room.id;
      evidence['peerCompletedTlsHello'] = peer.hasCompletedHello;
      final peerPausePosition = app.target.snapshot.position;
      peer.updateLocalState(position: peerPausePosition, paused: true);
      peer.notifyLocalChange(doSeek: false);
      await _wait(
        tester,
        () =>
            !app.target.snapshot.playing &&
            peer.lastObservedRoomState?.paused == true,
        'native pause from TLS peer before early Play',
      );
      final earlyReady = await _stage(tester, 'early-short-ready');
      peer.updateLocalState(
        position: app.target.snapshot.position,
        paused: false,
      );
      peer.notifyLocalChange(doSeek: false);
      await _wait(
        tester,
        () =>
            app.target.snapshot.playing &&
            peer.lastObservedRoomState?.paused == false &&
            peer.lastObservedRoomState?.setBy == peer.username,
        'actual TLS peer Play before brief focus loss',
        seconds: 3,
      );
      final earlyBefore = _snapshot(app, peer);
      final earlyMonitor = _EarlyNativePauseMonitor(app, peer);
      final earlyCase = <String, Object?>{
        'peerName': peer.username,
        'tlsPeerPlay': true,
        'ready': earlyReady,
        'before': earlyBefore,
        'testSidePauseDuringInterruption': false,
      };
      evidence['earlyShort'] = earlyCase;
      try {
        earlyCase['acquire'] = await _stage(tester, 'early-short-acquire');
        await _wait(
          tester,
          () =>
              !app.target.snapshot.playing &&
              app.target.snapshot.error == null &&
              peer.lastObservedRoomState?.paused == true,
          'early native and TLS room pause',
          seconds: 25,
        );
        earlyCase['paused'] = _snapshot(app, peer);
        final releaseWatch = Stopwatch()..start();
        while (releaseWatch.elapsed < const Duration(seconds: 4)) {
          await tester.pump(_poll);
        }
        earlyMonitor.requireNoPlay();
        final afterRelease = _snapshot(app, peer);
        _requireStable(
          earlyCase['paused'] as Map<String, Object?>,
          afterRelease,
        );
        earlyCase['afterRelease'] = afterRelease;
        expect(app.room?.id, room.id);
        expect(app.isConnected, isTrue);
        expect(peer.hasCompletedHello, isTrue);
      } finally {
        earlyCase['noAutoplayMonitor'] = earlyMonitor.receipt();
        await earlyMonitor.close();
      }
      final earlyReleased = earlyCase['afterRelease'] as Map<String, Object?>;
      await _tap(tester, _control('Play'));
      await _wait(
        tester,
        () =>
            app.target.snapshot.playing &&
            app.target.snapshot.position.inMilliseconds >
                (earlyReleased['nativePositionMs'] as int) + 500 &&
            peer.lastObservedRoomState?.paused == false,
        'early explicit replay observed by peer',
        seconds: 30,
      );
      earlyCase['explicitReplay'] = _snapshot(app, peer);
      for (final mode in ['permanent', 'transient']) {
        final settledPlaying = await _settlePlaying(tester, app, peer, mode);
        final before = _snapshot(app, peer);
        expect(before['nativePlaying'], isTrue);
        expect(before['peerPaused'], isFalse);
        final acquired = await _stage(tester, '$mode-acquire');
        await _wait(
          tester,
          () =>
              !app.target.snapshot.playing &&
              app.target.snapshot.error == null &&
              peer.lastObservedRoomState?.paused == true,
          '$mode native and peer pause',
          seconds: 25,
        );
        final paused = _snapshot(app, peer);
        expect(
          (paused['nativePositionMs'] as int) >=
              (before['nativePositionMs'] as int) - 1000,
          isTrue,
        );
        final caseEvidence = <String, Object?>{
          'mode': mode,
          'settledPlaying': settledPlaying,
          'before': before,
          'paused': paused,
          'acquire': acquired,
          'testSidePauseDuringInterruption': false,
        };
        (evidence['cases'] as List<Map<String, Object?>>).add(caseEvidence);
        final monitor = _NoAutoplayMonitor(app, peer);
        try {
          final heldWatch = Stopwatch()..start();
          while (heldWatch.elapsed < const Duration(seconds: 4)) {
            await tester.pump(_poll);
          }
          final held = _snapshot(app, peer);
          _requireStable(paused, held);
          monitor.requireNoPlay();
          caseEvidence['held'] = held;
          final released = await _stage(tester, '$mode-release');
          caseEvidence['release'] = released;
          final releaseWatch = Stopwatch()..start();
          while (releaseWatch.elapsed < const Duration(seconds: 4)) {
            await tester.pump(_poll);
          }
          final afterRelease = _snapshot(app, peer);
          _requireStable(held, afterRelease);
          monitor.requireNoPlay();
          caseEvidence['afterRelease'] = afterRelease;
          expect(app.room?.id, room.id);
          expect(app.isConnected, isTrue);
          expect(peer.hasCompletedHello, isTrue);
        } finally {
          caseEvidence['noAutoplayMonitor'] = monitor.receipt();
          await monitor.close();
        }
        final afterRelease =
            caseEvidence['afterRelease'] as Map<String, Object?>;
        await _tap(tester, _control('Play'));
        await _wait(
          tester,
          () =>
              app.target.snapshot.playing &&
              app.target.snapshot.position.inMilliseconds >
                  (afterRelease['nativePositionMs'] as int) + 500 &&
              peer.lastObservedRoomState?.paused == false,
          '$mode explicit replay observed by peer',
          seconds: 30,
        );
        final replay = _snapshot(app, peer);
        caseEvidence['explicitReplay'] = replay;
      }
      evidence['result'] = 'passed';
      evidence['completedAtUtc'] = DateTime.now().toUtc().toIso8601String();
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 9)),
  );
}

final class _EarlyNativePauseMonitor {
  _EarlyNativePauseMonitor(AppController app, SyncplayClient peer) {
    if (!app.target.snapshot.playing ||
        peer.lastObservedRoomState?.paused != false) {
      throw TestFailure('early native monitor must arm while playing');
    }
    _native = app.target.states.listen((state) {
      nativeEvents++;
      if (nativeStateSamples.length < 256) {
        nativeStateSamples.add({
          'elapsedMs': _clock.elapsedMilliseconds,
          'positionMs': state.position.inMilliseconds,
          'playing': state.playing,
          'buffering': state.buffering,
          'ready': state.ready,
          'playRequested': app.playRequested,
        });
      }
      if (!state.playing) {
        firstNativePauseElapsedMs ??= _clock.elapsedMilliseconds;
      } else if (firstNativePauseElapsedMs != null) {
        forbidden.add({
          'elapsedMs': _clock.elapsedMilliseconds,
          'positionMs': state.position.inMilliseconds,
        });
      }
    });
    _room = peer.observedRoomState.listen((state) {
      roomEvents++;
      if (state.paused) {
        firstRoomPauseElapsedMs ??= _clock.elapsedMilliseconds;
      } else if (firstRoomPauseElapsedMs != null) {
        forbiddenRoomPlay.add({
          'elapsedMs': _clock.elapsedMilliseconds,
          'positionMs': state.position.inMilliseconds,
        });
      }
    });
  }

  final Stopwatch _clock = Stopwatch()..start();
  late final StreamSubscription<PlaybackSnapshot> _native;
  late final StreamSubscription<PeerPlayState> _room;
  final List<Map<String, Object>> forbidden = [];
  final List<Map<String, Object>> forbiddenRoomPlay = [];
  final List<Map<String, Object>> nativeStateSamples = [];
  int nativeEvents = 0;
  int roomEvents = 0;
  int? firstNativePauseElapsedMs;
  int? firstRoomPauseElapsedMs;

  void requireNoPlay() {
    if (firstNativePauseElapsedMs == null ||
        firstRoomPauseElapsedMs == null ||
        forbidden.isNotEmpty ||
        forbiddenRoomPlay.isNotEmpty) {
      throw TestFailure(
        'early focus must pause native playback and the room without resuming',
      );
    }
  }

  Map<String, Object?> receipt() => {
    'monitoredMs': _clock.elapsedMilliseconds,
    'nativeEvents': nativeEvents,
    'nativeStateSamples': List<Map<String, Object>>.of(nativeStateSamples),
    'droppedNativeStateSamples': nativeEvents - nativeStateSamples.length,
    'roomEvents': roomEvents,
    'sawNativePause': firstNativePauseElapsedMs != null,
    'sawRoomPause': firstRoomPauseElapsedMs != null,
    'firstNativePauseElapsedMs': firstNativePauseElapsedMs,
    'firstRoomPauseElapsedMs': firstRoomPauseElapsedMs,
    'forbiddenNativePlayEvents': List<Map<String, Object>>.of(forbidden),
    'forbiddenRoomPlayEvents': List<Map<String, Object>>.of(forbiddenRoomPlay),
  };

  Future<void> close() async {
    _clock.stop();
    await _native.cancel();
    await _room.cancel();
  }
}

final class _NoAutoplayMonitor {
  _NoAutoplayMonitor(AppController app, SyncplayClient peer) {
    _native = app.target.states.listen((state) {
      nativeEvents++;
      if (state.playing) {
        forbidden.add({
          'source': 'nativePlayer',
          'elapsedMs': _clock.elapsedMilliseconds,
          'positionMs': state.position.inMilliseconds,
        });
      }
    });
    _room = peer.observedRoomState.listen((state) {
      roomEvents++;
      if (!state.paused) {
        forbidden.add({
          'source': 'tlsRoom',
          'elapsedMs': _clock.elapsedMilliseconds,
          'positionMs': state.position.inMilliseconds,
        });
      }
    });
    if (app.target.snapshot.playing ||
        peer.lastObservedRoomState?.paused != true) {
      forbidden.add({'source': 'armingState', 'elapsedMs': 0});
    }
  }

  final Stopwatch _clock = Stopwatch()..start();
  late final StreamSubscription<PlaybackSnapshot> _native;
  late final StreamSubscription<PeerPlayState> _room;
  final List<Map<String, Object>> forbidden = [];
  int nativeEvents = 0;
  int roomEvents = 0;

  void requireNoPlay() {
    if (forbidden.isNotEmpty) {
      throw TestFailure(
        'Native or TLS room autoplayed during focus interruption',
      );
    }
  }

  Map<String, Object> receipt() => {
    'monitoredMs': _clock.elapsedMilliseconds,
    'nativeEvents': nativeEvents,
    'roomEvents': roomEvents,
    'forbiddenPlayEvents': List<Map<String, Object>>.of(forbidden),
  };

  Future<void> close() async {
    _clock.stop();
    await _native.cancel();
    await _room.cancel();
  }
}

Future<Map<String, Object>> _settlePlaying(
  WidgetTester tester,
  AppController app,
  SyncplayClient peer,
  String mode,
) async {
  const stableFor = Duration(seconds: 4);
  final deadline = Stopwatch()..start();
  Stopwatch? stable;
  int? firstPosition;
  while (deadline.elapsed < const Duration(seconds: 30)) {
    final native = app.target.snapshot;
    final converged =
        native.ready &&
        native.playing &&
        !native.buffering &&
        native.error == null &&
        peer.lastObservedRoomState?.paused == false;
    if (converged) {
      stable ??= Stopwatch()..start();
      firstPosition ??= native.position.inMilliseconds;
      if (stable.elapsed >= stableFor &&
          native.position.inMilliseconds >= firstPosition + 2000) {
        return {
          'continuousPlayingMs': stable.elapsedMilliseconds,
          'nativeAdvanceMs': native.position.inMilliseconds - firstPosition,
          'peerUnpausedThroughout': true,
        };
      }
    } else {
      stable = null;
      firstPosition = null;
    }
    await tester.pump(_poll);
  }
  throw TestFailure(
    '$mode native and TLS peer did not settle beyond echo window',
  );
}

Map<String, Object?> _snapshot(AppController app, SyncplayClient peer) {
  final native = app.target.snapshot;
  final room = peer.lastObservedRoomState;
  return {
    'nativeReady': native.ready,
    'nativePlaying': native.playing,
    'nativeBuffering': native.buffering,
    'nativePositionMs': native.position.inMilliseconds,
    'nativeDurationMs': native.duration.inMilliseconds,
    'nativeError': native.error,
    'peerPaused': room?.paused,
    'peerPositionMs': room?.position.inMilliseconds,
    'peerSetter': room?.setBy,
  };
}

void _requireStable(Map<String, Object?> a, Map<String, Object?> b) {
  expect(a['nativePlaying'], isFalse);
  expect(b['nativePlaying'], isFalse);
  expect(a['peerPaused'], isTrue);
  expect(b['peerPaused'], isTrue);
  expect(a['nativeError'], isNull);
  expect(b['nativeError'], isNull);
  expect(
    ((b['nativePositionMs'] as int) - (a['nativePositionMs'] as int)).abs(),
    lessThanOrEqualTo(1500),
  );
}

Future<Map<String, Object?>> _stage(WidgetTester tester, String stage) async {
  final result = await tester
      .runAsync<({int? statusCode, String? body, String? error})>(() async {
        try {
          final response = await postNativeFocusStage(
            Uri.parse(_bridge),
            stage,
          );
          return (
            statusCode: response.statusCode,
            body: response.body,
            error: null,
          );
        } catch (error) {
          return (statusCode: null, body: null, error: '$error');
        }
      });
  if (result == null) {
    throw TestFailure('Native stage $stage returned no HTTP result');
  }
  if (result.error != null) {
    throw TestFailure('Native stage $stage request failed: ${result.error}');
  }
  if (result.statusCode != 200) {
    throw TestFailure(
      'Native stage $stage returned HTTP ${result.statusCode}: ${result.body}',
    );
  }
  final Map<String, Object?> receipt;
  try {
    receipt = Map<String, Object?>.from(jsonDecode(result.body!) as Map);
  } catch (error) {
    throw TestFailure('Native stage $stage returned invalid JSON: $error');
  }
  if (receipt['stage'] != stage || receipt['completed'] != true) {
    throw TestFailure('Native stage $stage returned no matching receipt');
  }
  return receipt;
}

Finder _control(String action) => find.byWidgetPredicate(
  (widget) =>
      widget is IconButton &&
      (widget.tooltip == action || widget.tooltip == '$action together'),
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _wait(tester, () => finder.evaluate().isNotEmpty, 'control');
  await tester.ensureVisible(finder);
  await _wait(
    tester,
    () => finder.hitTestable().evaluate().isNotEmpty,
    'tappable $finder',
  );
  await tester.tap(finder.hitTestable());
  await tester.pump(_poll);
}

Future<void> _wait(
  WidgetTester tester,
  bool Function() check,
  String label, {
  int seconds = 20,
}) async {
  final watch = Stopwatch()..start();
  while (!check()) {
    if (watch.elapsed >= Duration(seconds: seconds)) {
      throw TestFailure('Timed out waiting for $label');
    }
    await tester.pump(_poll);
  }
}
