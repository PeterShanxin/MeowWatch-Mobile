import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/app/app_controller.dart';
import 'package:meowwatch_mobile/core/connect/room_config.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/platform/immersive_mode.dart';
import 'package:meowwatch_mobile/core/playback/local_mobile_target.dart';
import 'package:meowwatch_mobile/core/sync/endpoint_settings.dart';
import 'package:meowwatch_mobile/core/sync/peer_state.dart';
import 'package:meowwatch_mobile/data/app_repository.dart';
import 'package:meowwatch_mobile/ui/app_theme.dart';
import 'package:meowwatch_mobile/ui/room/room_screen.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../home/ui_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.meowwatch.mobile/fullscreen');
  const fullscreenKey = ValueKey('fullscreen-player');
  const surfaceKey = ValueKey('fullscreen-video-surface');
  late VideoPlayerPlatform originalPlatform;
  late _VideoPlatform platform;
  late LocalMobileTarget target;
  late AppController app;
  late GlobalKey<RoomScreenState> roomKey;
  late List<bool> modeCalls;
  late List<String> modeMethods;
  late List<Completer<void>> delayedReplies;
  Future<void> Function(bool)? modeBehavior;
  var leaves = 0;
  var deviceOpens = 0;
  var loadOpens = 0;

  void setUpFixture() {
    originalPlatform = VideoPlayerPlatform.instance;
    platform = _VideoPlatform();
    VideoPlayerPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    target = LocalMobileTarget();
    app = AppController(
      repository: UiTestRepository(),
      billing: UiTestBilling(),
      hosting: UiTestHosting(),
      phone: target,
      endpointSettings: MemoryEndpointSettings(),
    );
    roomKey = GlobalKey<RoomScreenState>();
    modeCalls = [];
    modeMethods = [];
    delayedReplies = [];
    modeBehavior = null;
    leaves = 0;
    deviceOpens = 0;
    loadOpens = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          modeMethods.add(call.method);
          final enabled = call.arguments as bool;
          modeCalls.add(enabled);
          await modeBehavior?.call(enabled);
          return null;
        });
  }

  Future<void> flushPlatform(WidgetTester tester) async {
    // Platform replies and the initialized video stream can complete in the
    // real zone. Explicitly advance the fake clock by zero too: pump() alone
    // flushes microtasks, but leaves Timer.run callbacks pending.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(Duration.zero);
  }

  Future<void> waitUntil(
    WidgetTester tester,
    bool Function() completed,
    String description,
  ) async {
    for (var turn = 0; !completed() && turn < 20; turn++) {
      await flushPlatform(tester);
    }
    expect(completed(), isTrue, reason: description);
  }

  Future<void> verifyModes(WidgetTester tester, List<bool> expected) async {
    await waitUntil(
      tester,
      () => modeCalls.length >= expected.length,
      'The platform received every requested window transition.',
    );
    await flushPlatform(tester);
    expect(modeCalls, expected);
  }

  void fullscreenTest(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (tester) async {
      // Register channels and create timer-owning collaborators in the same
      // fake-async zone as pump(), then finish the shared platform queue before
      // that zone is destroyed. A package:test tearDown runs too late.
      setUpFixture();
      Object? bodyError;
      StackTrace? bodyStack;
      try {
        // Finish constructor microtasks before runAsync waits on the native
        // boundary. A policy queue created in the fake zone cannot otherwise
        // complete while runAsync holds that zone's clock.
        await tester.pump(Duration.zero);
        await body(tester);
      } catch (error, stack) {
        bodyError = error;
        bodyStack = stack;
      } finally {
        modeBehavior = null;
        for (final reply in delayedReplies) {
          if (!reply.isCompleted) reply.complete();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        var platformDrained = false;
        Object? drainError;
        unawaited(
          ImmersiveMode.setEnabled(false).then<void>(
            (_) {
              platformDrained = true;
            },
            onError: (Object error) {
              drainError = error;
              platformDrained = true;
            },
          ),
        );
        for (var turn = 0; !platformDrained && turn < 20; turn++) {
          await flushPlatform(tester);
        }
        await tester.runAsync(app.close);
        await tester.runAsync(platform.closeStreams);
        VideoPlayerPlatform.instance = originalPlatform;
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        if (bodyError == null) {
          expect(
            platformDrained,
            isTrue,
            reason: 'Finish the shared mode queue.',
          );
          expect(drainError, isNull);
          expect(modeMethods, everyElement('setEnabled'));
        } else if (!platformDrained || drainError != null) {
          debugPrint('Additional fullscreen cleanup failure: $drainError');
        }
      }
      if (bodyError != null) Error.throwWithStackTrace(bodyError, bodyStack!);
    });
  }

  Completer<void> delayedReply() {
    final reply = Completer<void>();
    delayedReplies.add(reply);
    return reply;
  }

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(800, 360),
    double textScale = 1,
    bool? accessibleNavigation = false,
    bool loaded = true,
    bool room = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.runAsync(app.useLocalMode);
    if (loaded) {
      await tester.runAsync(
        () => target.load(
          MediaItem(
            uri: Uri.parse('https://video.example/Bee.mp4'),
            title: 'Bee.mp4 — a longer descriptive video title',
          ),
          position: const Duration(seconds: 12),
        ),
      );
    }
    if (room) {
      app.room = const RoomTicket(
        id: 'fullscreen-room',
        isHost: false,
        config: RoomConfig(
          server: 'syncplay.example',
          port: 8995,
          room: 'Movie night',
          username: 'Mochi',
        ),
      );
      app.connection = const SyncConnectionState(
        status: SyncConnectionStatus.connected,
      );
      app.peers.add('Bean');
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: meowWatchTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            accessibleNavigation: accessibleNavigation,
          ),
          child: child!,
        ),
        home: RoomScreen(
          key: roomKey,
          app: app,
          onLoad: () => loadOpens++,
          onInvite: () {},
          onDevices: () => deviceOpens++,
          onLeave: () => leaves++,
          onStartRoom: () {},
          onTogglePlay: () => unawaited(app.togglePlay()),
          onSeek: (position) => unawaited(app.seek(position)),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> enter(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Enter full screen'));
    await tester.pump();
    await flushPlatform(tester);
    await waitUntil(
      tester,
      () => modeCalls.contains(true),
      'The immersive entry reached the platform.',
    );
    await flushPlatform(tester);
    expect(find.byKey(fullscreenKey), findsOneWidget);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await flushPlatform(tester);
    await flushPlatform(tester);
  }

  fullscreenTest('only a loaded native phone video offers full screen', (
    tester,
  ) async {
    await open(tester, loaded: false);
    expect(find.byTooltip('Enter full screen'), findsNothing);
    expect(roomKey.currentState!.exitFullscreen(), isFalse);
    expect(modeCalls, isEmpty);
    await close(tester);
  });

  fullscreenTest(
    'entry and Back reuse the texture, decoder, room and position',
    (tester) async {
      await open(tester, room: true);
      final controller = target.controller;
      final videoState = tester.state(find.byType(VideoPlayer));
      final ticket = app.room;
      final position = target.snapshot.position;
      final playCalls = platform.playCalls;
      final pauseCalls = platform.pauseCalls;
      final seeks = platform.seekCalls;
      await enter(tester);

      await verifyModes(tester, [true]);
      expect(tester.state(find.byType(VideoPlayer)), same(videoState));
      expect(target.controller, same(controller));
      expect(platform.created, 1);
      expect(platform.disposed, isEmpty);
      expect(app.room, same(ticket));
      expect(app.peers, {'Bean'});
      expect(target.snapshot.position, position);
      expect(platform.playCalls, playCalls);
      expect(platform.pauseCalls, pauseCalls);
      expect(platform.seekCalls, seeks);
      expect(find.byTooltip('Leave room'), findsNothing);
      expect(find.byTooltip('Room chat').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('Choose playback screen'));
      expect(deviceOpens, 1);

      expect(roomKey.currentState!.exitFullscreen(), isTrue);
      expect(roomKey.currentState!.exitFullscreen(), isFalse);
      await tester.pump();
      await flushPlatform(tester);
      await verifyModes(tester, [true, false]);
      expect(find.byKey(fullscreenKey), findsNothing);
      expect(tester.state(find.byType(VideoPlayer)), same(videoState));
      expect(target.controller, same(controller));
      expect(platform.created, 1);
      expect(platform.disposed, isEmpty);
      expect(leaves, 0);
      expect(app.room, same(ticket));
      await close(tester);
    },
  );

  for (final layout in [
    (name: 'portrait phone', size: const Size(360, 640), scale: 2.0),
    (name: 'short landscape', size: const Size(640, 280), scale: 2.0),
    (name: 'large text tablet', size: const Size(1280, 800), scale: 3.0),
  ]) {
    fullscreenTest('${layout.name} fits full-screen video and 48px controls', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await open(
          tester,
          size: layout.size,
          textScale: layout.scale,
          accessibleNavigation: true,
        );
        await enter(tester);
        expect(
          tester.getRect(find.byKey(surfaceKey)),
          Offset.zero & layout.size,
        );
        final videoBounds = tester.getRect(find.byType(VideoPlayer));
        expect(videoBounds.width / videoBounds.height, closeTo(16 / 9, .001));
        expect(videoBounds.width, lessThanOrEqualTo(layout.size.width));
        expect(videoBounds.height, lessThanOrEqualTo(layout.size.height));
        for (final tooltip in [
          'Exit full screen',
          'Choose playback screen',
          'Choose video',
          'Play together',
        ]) {
          final finder = find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == tooltip,
          );
          expect(finder.hitTestable(), findsOneWidget);
          final bounds = tester.getRect(finder);
          expect(bounds.width, greaterThanOrEqualTo(48));
          expect(bounds.height, greaterThanOrEqualTo(48));
          final data = tester.getSemantics(finder).getSemanticsData();
          expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
        }
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Exit full screen'));
        await tester.pump();
        expect(find.byTooltip('Enter full screen'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await close(tester);
      } finally {
        semantics.dispose();
      }
    });
  }

  fullscreenTest('playing controls hide, tap reveals them, pause keeps them', (
    tester,
  ) async {
    await open(tester);
    await tester.runAsync(target.play);
    await tester.pump();
    await enter(tester);
    await tester.pump(const Duration(seconds: 4));
    expect(find.byTooltip('Exit full screen'), findsNothing);
    expect(find.byKey(fullscreenKey), findsOneWidget);
    await tester.tapAt(tester.getCenter(find.byKey(surfaceKey)));
    await tester.pump();
    expect(find.byTooltip('Pause together').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('Pause together'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(target.snapshot.playing, isFalse);
    expect(find.byTooltip('Exit full screen'), findsOneWidget);
    expect(find.byTooltip('Play together').hitTestable(), findsOneWidget);
    await tester.tapAt(tester.getCenter(find.byKey(surfaceKey)));
    await tester.pump();
    expect(find.byTooltip('Exit full screen'), findsOneWidget);
    await close(tester);
  });

  fullscreenTest('accessible navigation keeps playing controls available', (
    tester,
  ) async {
    await open(tester, accessibleNavigation: true);
    await tester.runAsync(target.play);
    await enter(tester);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byTooltip('Pause together').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Exit full screen').hitTestable(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(fullscreenKey), findsNothing);
    expect(target.snapshot.playing, isTrue);
    expect(leaves, 0);
    await close(tester);
  });

  fullscreenTest(
    'disabling accessible navigation restores timed control hiding',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await open(tester, accessibleNavigation: null);
      await tester.runAsync(target.play);
      await enter(tester);
      await tester.pump(const Duration(seconds: 4));
      expect(find.byTooltip('Exit full screen'), findsOneWidget);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      expect(find.byTooltip('Exit full screen'), findsNothing);
      await close(tester);
    },
  );

  fullscreenTest(
    'paused entry, accessible observation, and Play resume timed hiding',
    (tester) async {
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await open(tester, accessibleNavigation: null);
      await enter(tester);
      expect(target.snapshot.playing, isFalse);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(accessibleNavigation: true);
      await tester.pump(const Duration(seconds: 4));
      expect(find.byTooltip('Exit full screen'), findsOneWidget);

      await tester.tap(find.byTooltip('Play together'));
      await tester.pump();
      expect(target.snapshot.playing, isTrue);
      await tester.pump(const Duration(seconds: 4));
      expect(find.byTooltip('Pause together'), findsOneWidget);

      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      expect(find.byTooltip('Exit full screen'), findsNothing);
      expect(target.snapshot.playing, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(find.byTooltip('Exit full screen').hitTestable(), findsOneWidget);
      await close(tester);
    },
  );

  fullscreenTest(
    'returning from keyboard to touch resumes timed control hiding',
    (tester) async {
      await open(tester);
      await tester.runAsync(target.play);
      await enter(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        FocusManager.instance.highlightMode,
        FocusHighlightMode.traditional,
      );
      await tester.pump(const Duration(seconds: 4));
      expect(find.byTooltip('Exit full screen'), findsOneWidget);
      // Touch changes input modality while focus may remain inside the controls.
      await tester.tap(find.byTooltip('Pause together'));
      await tester.pump();
      await tester.tap(find.byTooltip('Play together'));
      await tester.pump();
      expect(FocusManager.instance.highlightMode, FocusHighlightMode.touch);
      await tester.pump(const Duration(seconds: 4));
      expect(find.byTooltip('Exit full screen'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(find.byTooltip('Exit full screen').hitTestable(), findsOneWidget);
      // Once the control subtree is mounted again, traversal can focus it.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      expect(find.byTooltip('Exit full screen').hitTestable(), findsOneWidget);
      await close(tester);
    },
  );

  fullscreenTest(
    'a playback error reveals controls and leaves recovery usable',
    (tester) async {
      await open(tester, size: const Size(640, 280), textScale: 2);
      await tester.runAsync(target.play);
      await enter(tester);
      await tester.pump(const Duration(seconds: 4));
      expect(find.byTooltip('Exit full screen'), findsNothing);
      await tester.runAsync(() async {
        platform.failPlayback();
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      await flushPlatform(tester);
      expect(find.byTooltip('Exit full screen').hitTestable(), findsOneWidget);
      expect(
        find.text('Playback stopped. Try opening the video again.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Choose another video'));
      await tester.pump();
      await tester.tap(find.text('Choose another video'));
      expect(loadOpens, 1);
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );

  fullscreenTest(
    'Back during pending entry stays exited after its late reply',
    (tester) async {
      final pending = delayedReply();
      modeBehavior = (enabled) => enabled ? pending.future : Future.value();
      await open(tester);
      await enter(tester);
      expect(roomKey.currentState!.exitFullscreen(), isTrue);
      await tester.pump();
      expect(find.byKey(fullscreenKey), findsNothing);
      pending.complete();
      await tester.pump();
      await flushPlatform(tester);
      await verifyModes(tester, [true, false]);
      expect(find.byKey(fullscreenKey), findsNothing);
      expect(leaves, 0);
      expect(platform.created, 1);
      await close(tester);
    },
  );

  fullscreenTest('unmount during entry restores system mode after late reply', (
    tester,
  ) async {
    final pending = delayedReply();
    modeBehavior = (enabled) => enabled ? pending.future : Future.value();
    await open(tester);
    await enter(tester);
    await close(tester);
    pending.complete();
    await tester.pump();
    await flushPlatform(tester);
    await verifyModes(tester, [true, false]);
    expect(tester.takeException(), isNull);
  });

  fullscreenTest('rapid entry exit entry keeps the final requested layout', (
    tester,
  ) async {
    final pending = delayedReply();
    var firstEntry = true;
    modeBehavior = (enabled) async {
      if (enabled && firstEntry) {
        firstEntry = false;
        await pending.future;
      }
    };
    await open(tester);
    await enter(tester);
    expect(roomKey.currentState!.exitFullscreen(), isTrue);
    await tester.pump();
    await tester.tap(find.byTooltip('Enter full screen'));
    await tester.pump();
    pending.complete();
    await tester.pump();
    await flushPlatform(tester);
    await verifyModes(tester, [true, false, true]);
    expect(find.byKey(fullscreenKey), findsOneWidget);
    expect(platform.created, 1);
    expect(leaves, 0);
    await close(tester);
    expect(modeCalls.last, isFalse);
  });

  fullscreenTest(
    'entry failure returns to the player and reports the problem',
    (tester) async {
      modeBehavior = (enabled) async {
        if (enabled) throw PlatformException(code: 'unavailable');
      };
      await open(tester);
      final controller = target.controller;
      await tester.tap(find.byTooltip('Enter full screen'));
      await tester.pump();
      await waitUntil(
        tester,
        () => find
            .text('Could not enter full screen. Please try again.')
            .evaluate()
            .isNotEmpty,
        'Entry failure is reported in the player.',
      );
      expect(find.byKey(fullscreenKey), findsNothing);
      expect(
        find.text('Could not enter full screen. Please try again.'),
        findsOneWidget,
      );
      expect(target.controller, same(controller));
      await verifyModes(tester, [true, false]);
      expect(leaves, 0);
      await close(tester);
    },
  );

  fullscreenTest('exit failure leaves a usable player and an explicit retry', (
    tester,
  ) async {
    var failExit = true;
    modeBehavior = (enabled) async {
      if (!enabled && failExit) throw PlatformException(code: 'unavailable');
    };
    await open(tester);
    await enter(tester);
    await tester.tap(find.byTooltip('Exit full screen'));
    await tester.pump();
    await waitUntil(
      tester,
      () => find
          .text('Could not restore the system controls. Please try again.')
          .evaluate()
          .isNotEmpty,
      'Exit failure offers an explicit retry.',
    );
    expect(find.byKey(fullscreenKey), findsNothing);
    expect(
      find.text('Could not restore the system controls. Please try again.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Retry').hitTestable(), findsOneWidget);
    expect(tester.getRect(find.text('Retry')).bottom, lessThanOrEqualTo(360));
    failExit = false;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await flushPlatform(tester);
    await verifyModes(tester, [true, false, false]);
    expect(leaves, 0);
    await close(tester);
  });

  for (final replaceRoom in [false, true]) {
    fullscreenTest(
      replaceRoom
          ? 'stale exit Retry cannot change a replacement room full screen'
          : 'stale exit Retry cannot undo a later full-screen entry',
      (tester) async {
        var failExit = true;
        modeBehavior = (enabled) async {
          if (!enabled && failExit) {
            throw PlatformException(code: 'unavailable');
          }
        };
        await open(tester);
        await enter(tester);
        await tester.tap(find.byTooltip('Exit full screen'));
        await tester.pump();
        await waitUntil(
          tester,
          () => find.byType(SnackBarAction).evaluate().isNotEmpty,
          'The failed exit exposes its Retry action.',
        );
        final staleRetry = tester
            .widget<SnackBarAction>(find.byType(SnackBarAction))
            .onPressed;
        await verifyModes(tester, [true, false]);
        failExit = false;

        if (replaceRoom) {
          await close(tester);
          await open(tester);
        }
        await enter(tester);
        // The error may still be entering when the user re-enters fullscreen.
        // Advance both its onVisible callback and subsequent exit animation.
        for (var turn = 0; turn < 4; turn++) {
          await tester.pump(const Duration(milliseconds: 300));
          await flushPlatform(tester);
        }
        final currentModes = List<bool>.of(modeCalls);
        expect(currentModes.last, isTrue);

        // A queued tap from the old error must not override a newer intent,
        // including after its RoomScreen has been disposed.
        staleRetry();
        await tester.pump();
        await flushPlatform(tester);
        await verifyModes(tester, currentModes);
        expect(find.byKey(fullscreenKey), findsOneWidget);
        expect(find.text('Retry'), findsNothing);
        expect(
          find.text('Could not restore the system controls. Please try again.'),
          findsNothing,
        );
        expect(leaves, 0);
        await close(tester);
      },
    );
  }

  fullscreenTest('retiring a queued mode error preserves other app messages', (
    tester,
  ) async {
    var failExit = true;
    modeBehavior = (enabled) async {
      if (!enabled && failExit) throw PlatformException(code: 'unavailable');
    };
    await open(tester);
    await enter(tester);
    final otherMessage =
        ScaffoldMessenger.of(
          tester.element(find.byKey(fullscreenKey)),
        ).showSnackBar(
          const SnackBar(content: Text('Another app message'), persist: true),
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Exit full screen'));
    await tester.pump();
    await verifyModes(tester, [true, false]);
    await flushPlatform(tester);
    failExit = false;
    await enter(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Another app message'), findsOneWidget);

    otherMessage.close();
    for (var turn = 0; turn < 4; turn++) {
      await tester.pump(const Duration(milliseconds: 300));
      await flushPlatform(tester);
    }
    expect(find.text('Another app message'), findsNothing);
    expect(find.text('Retry'), findsNothing);
    expect(
      find.text('Could not restore the system controls. Please try again.'),
      findsNothing,
    );
    expect(find.byKey(fullscreenKey), findsOneWidget);
    await verifyModes(tester, [true, false, true]);
    expect(tester.takeException(), isNull);
    await close(tester);
  });
}

// Only the native video and immersive platform boundaries are replaced. The
// fixture builds the real LocalMobileTarget, VideoPlayer and RoomScreen.
class _VideoPlatform extends VideoPlayerPlatform {
  final _events = <int, StreamController<VideoEvent>>{};
  final _positions = <int, Duration>{};
  final disposed = <int>[];
  int created = 0;
  int playCalls = 0;
  int pauseCalls = 0;
  int seekCalls = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = ++created;
    _positions[id] = Duration.zero;
    _events[id] = StreamController<VideoEvent>()
      ..add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(minutes: 5),
          size: const Size(1280, 720),
        ),
      );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      Texture(textureId: options.playerId);

  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
  }

  @override
  Future<void> play(int playerId) async {
    playCalls++;
  }

  @override
  Future<void> pause(int playerId) async {
    pauseCalls++;
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    seekCalls++;
    _positions[playerId] = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async => _positions[playerId]!;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  void failPlayback() => _events[created]!.addError(
    PlatformException(code: 'VideoError', message: 'Decoder unavailable'),
  );

  Future<void> closeStreams() async {
    for (final events in _events.values) {
      await events.close();
    }
  }
}
