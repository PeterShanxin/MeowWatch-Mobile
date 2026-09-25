import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/playback/local_mobile_target.dart';
import 'package:meowwatch_mobile/core/playback/playback_target.dart';
import 'package:meowwatch_mobile/core/session/playback_sync_bridge.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../support/sync_playback_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VideoPlayerPlatform originalPlatform;
  late _FakeVideoPlayerPlatform platform;
  late List<LocalMobileTarget> targets;

  setUpAll(() {
    originalPlatform = VideoPlayerPlatform.instance;
  });

  setUp(() {
    platform = _FakeVideoPlayerPlatform();
    targets = [];
    VideoPlayerPlatform.instance = platform;
  });

  tearDown(() async {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    for (final target in targets.reversed) {
      await target.close();
    }
    await platform.closeStreams();
    VideoPlayerPlatform.instance = originalPlatform;
  });

  LocalMobileTarget createTarget({
    bool mixWithOthers = false,
    Future<void> Function(int playerId, bool required)?
    configureInterruptionPolicy,
  }) {
    final target = LocalMobileTarget(
      mixWithOthers: mixWithOthers,
      configureInterruptionPolicy: configureInterruptionPolicy,
    );
    targets.add(target);
    return target;
  }

  test(
    'pause broadcasts the stopped native position despite a late poll',
    () async {
      final target = createTarget();
      final sync = SyncTestCore();
      final bridge = PlaybackSyncBridge(
        target: target,
        sync: sync,
        authorizePlayback: () async => true,
      )..start();
      final oldPoll = Completer<Duration>();
      final pollStarted = Completer<void>();
      const cachedPosition = Duration(milliseconds: 3668);
      const stoppedPosition = Duration(milliseconds: 4109);
      try {
        await bridge.load(_media('pause-position'));
        await bridge.seek(cachedPosition);
        platform.nextPosition = oldPoll;
        platform.positionRequested = pollStarted;
        await bridge.play();
        await pollStarted.future.timeout(const Duration(seconds: 5));
        expect(target.snapshot.position, cachedPosition);

        platform.positionOnPause = stoppedPosition;
        final changesBeforePause = sync.changes.length;
        await bridge.pause();
        expect(target.snapshot.playing, isFalse);
        expect(target.snapshot.position, stoppedPosition);
        expect(sync.published.last.position, stoppedPosition);
        expect(sync.published.last.paused, isTrue);
        expect(sync.changes.length, changesBeforePause + 1);

        oldPoll.complete(cachedPosition);
        await _flushEvents();
        expect(target.controller!.value.position, cachedPosition);
        expect(target.snapshot.position, stoppedPosition);
        expect(sync.published.last.position, stoppedPosition);
        expect(sync.changes.length, changesBeforePause + 1);
        await bridge.play();
        expect(target.snapshot.position, stoppedPosition);
        expect(sync.published.last.position, stoppedPosition);
        expect(sync.published.last.paused, isFalse);
      } finally {
        if (!oldPoll.isCompleted) oldPoll.complete(cachedPosition);
        await _flushEvents();
        await bridge.dispose();
        await sync.dispose();
      }
    },
  );

  test('pause beyond the duration still replays from the beginning', () async {
    final target = createTarget();
    await target.load(_media('completed'));
    final duration = target.snapshot.duration;
    platform.positionOnPause = duration + const Duration(milliseconds: 250);

    await target.pause();
    expect(target.snapshot.position, duration);
    expect(target.snapshot.playing, isFalse);
    await target.play();
    expect(target.snapshot.position, Duration.zero);
    expect(await target.controller!.position, Duration.zero);
    expect(target.snapshot.playing, isTrue);
  });

  test('pause clamps a negative native position to zero', () async {
    final target = createTarget();
    await target.load(_media('negative-position'));
    platform.positionOnPause = const Duration(milliseconds: -50);

    await target.pause();
    expect(target.snapshot.position, Duration.zero);
    expect(target.snapshot.playing, isFalse);
  });

  for (final nextCommand in ['seek', 'play', 'load', 'close']) {
    test('late pause position cannot overwrite a newer $nextCommand', () async {
      final target = createTarget();
      await target.load(_media('first'));
      await target.seek(const Duration(milliseconds: 3668));
      final position = Completer<Duration>();
      final readStarted = Completer<void>();
      platform.nextPosition = position;
      platform.positionRequested = readStarted;
      final pausing = target.pause();
      try {
        await readStarted.future.timeout(const Duration(seconds: 5));
        switch (nextCommand) {
          case 'seek':
            await target.seek(const Duration(seconds: 8));
          case 'play':
            await target.play();
          case 'load':
            await target.load(
              _media('second'),
              position: const Duration(seconds: 8),
            );
          case 'close':
            await target.close();
        }
        final accepted = target.snapshot;
        position.complete(const Duration(milliseconds: 4109));
        await pausing;
        expect(target.snapshot.media, same(accepted.media));
        expect(target.snapshot.position, accepted.position);
        expect(target.snapshot.playing, accepted.playing);
      } finally {
        if (!position.isCompleted) position.complete(Duration.zero);
        await pausing;
      }
    });
  }

  test('native creation uses each target audio policy after reload', () async {
    final mixedTarget = createTarget(mixWithOthers: true);
    final productionTarget = LocalMobileTarget();
    targets.add(productionTarget);

    await mixedTarget.load(_media('mixed-first'));
    await productionTarget.load(_media('exclusive'));
    await mixedTarget.load(_media('mixed-reloaded'));

    expect(platform.mixModesAtCreation, [true, false, true]);
    expect(
      platform.options.every((options) => options!.allowBackgroundPlayback),
      isTrue,
      reason: 'Audio policy must not change app-owned lifecycle handling.',
    );
  });

  test('hung native slowdown cannot block the 1x reset', () async {
    final target = LocalMobileTarget(
      rateCommandTimeout: const Duration(milliseconds: 20),
    );
    targets.add(target);
    await target.load(_media('rate-timeout'));
    await target.play();
    platform.rates.clear();
    final gate = Completer<void>();
    platform.nextRateGate = gate;

    await expectLater(
      target.setPlaybackRate(0.90),
      throwsA(isA<TimeoutException>()),
    );
    await target.setPlaybackRate(1);
    expect(platform.rates, [0.90, 1]);
    gate.complete();
    await _flushEvents();
    expect(platform.rates.last, 1);
  });

  test(
    'room policy reaches each decoder and teardown restores Local Mode',
    () async {
      final configured = <(int, bool)>[];
      final target = createTarget(
        configureInterruptionPolicy: (id, required) async {
          configured.add((id, required));
        },
      );
      final sync = SyncTestCore();
      final bridge = PlaybackSyncBridge(
        target: target,
        sync: sync,
        authorizePlayback: () async => true,
      )..start();
      try {
        await bridge.load(_media('first-room-source'));
        final firstId = target.controller!.playerId;
        expect(configured, [(firstId, true)]);
        await bridge.load(_media('replacement-room-source'));
        final secondId = target.controller!.playerId;
        expect(secondId, isNot(firstId));
        expect(configured.last, (secondId, true));
        await bridge.dispose();
        expect(configured.last, (secondId, false));
        final count = configured.length;
        await target.play();
        expect(configured.length, count);
        expect(target.snapshot.playing, isTrue);
      } finally {
        await bridge.dispose();
        await sync.dispose();
      }
    },
  );

  test('old room teardown cannot clear a replacement room policy', () async {
    final configured = <bool>[];
    final target = createTarget(
      configureInterruptionPolicy: (_, required) async {
        configured.add(required);
      },
    );
    final oldRoom = Object();
    final newRoom = Object();
    await target.requireExplicitResume(oldRoom);
    await target.load(_media('overlapping-rooms'));
    await target.requireExplicitResume(newRoom);
    await target.releaseExplicitResume(oldRoom);
    expect(configured, [true]);
    await target.releaseExplicitResume(newRoom);
    expect(configured, [true, false]);
    await target.releaseExplicitResume(oldRoom);
    expect(configured, [true, false]);
  });

  test('focus events route only to the active owned decoder', () async {
    final first = createTarget(configureInterruptionPolicy: (_, _) async {});
    final second = createTarget(configureInterruptionPolicy: (_, _) async {});
    final firstOwner = Object();
    final secondOwner = Object();
    await first.requireExplicitResume(firstOwner);
    await second.requireExplicitResume(secondOwner);
    await first.load(_media('focus-first'));
    await second.load(_media('focus-second'));
    final firstId = first.controller!.playerId;
    final secondId = second.controller!.playerId;
    final firstEvents = <int>[];
    final secondEvents = <int>[];
    final firstSub = first.focusInterruptions.listen(firstEvents.add);
    final secondSub = second.focusInterruptions.listen(secondEvents.add);
    addTearDown(() async {
      await firstSub.cancel();
      await secondSub.cancel();
    });

    await first.play();
    await second.play();
    await _sendFocusInterruption(firstId, 1);
    expect(firstEvents, [1]);
    expect(secondEvents, isEmpty);
    expect(first.playRequested, isFalse);
    expect(second.playRequested, isTrue);

    await _sendFocusInterruption(firstId, 1);
    await _sendFocusInterruption(firstId, 0);
    await _sendFocusInterruption(-1, 2);
    expect(firstEvents, [1]);
    await _sendFocusInterruption(secondId, 4);
    expect(secondEvents, [4]);
    await _sendFocusInterruption(secondId, 3);
    expect(secondEvents, [4]);

    await first.load(_media('focus-replaced'));
    final replacementId = first.controller!.playerId;
    await _sendFocusInterruption(firstId, 2);
    expect(firstEvents, [1]);
    await _sendFocusInterruption(replacementId, 1);
    expect(firstEvents, [1, 1]);

    await second.close();
    await _sendFocusInterruption(secondId, 5);
    expect(secondEvents, [4]);
    await first.releaseExplicitResume(firstOwner);
    await first.play();
    var localUiUpdates = 0;
    first.addListener(() => localUiUpdates++);
    final playsBeforeLocalFocus = platform.playCalls;
    final pausesBeforeLocalFocus = platform.pauseCalls;
    await _sendFocusInterruption(replacementId, 2);
    expect(firstEvents, [1, 1]);
    expect(first.playRequested, isFalse);
    expect(localUiUpdates, greaterThan(0));
    expect(platform.playCalls, playsBeforeLocalFocus);
    expect(platform.pauseCalls, pausesBeforeLocalFocus);
    platform.emit(VideoEvent(eventType: VideoEventType.bufferingStart));
    platform.emit(
      VideoEvent(
        eventType: VideoEventType.isPlayingStateUpdate,
        isPlaying: false,
      ),
    );
    await _flushEvents();
    expect(first.playRequested, isFalse);
    platform.emit(
      VideoEvent(
        eventType: VideoEventType.isPlayingStateUpdate,
        isPlaying: true,
      ),
    );
    await _flushEvents();
    expect(first.playRequested, isTrue);
    expect(platform.playCalls, playsBeforeLocalFocus);
    expect(platform.pauseCalls, pausesBeforeLocalFocus);
    await first.requireExplicitResume(firstOwner);
    await _sendFocusInterruption(replacementId, 2);
    expect(firstEvents, [1, 1]);
    await _sendFocusInterruption(replacementId, 3);
    expect(firstEvents, [1, 1, 3]);
  });

  test(
    'Play waits for a new room policy during pending Local Mode reset',
    () async {
      final configured = <bool>[];
      final reset = Completer<void>();
      final newPolicy = Completer<void>();
      var holdReset = false;
      var holdPolicy = false;
      final target = createTarget(
        configureInterruptionPolicy: (_, required) async {
          configured.add(required);
          if (!required && holdReset) await reset.future;
          if (required && holdPolicy) await newPolicy.future;
        },
      );
      final oldRoom = Object();
      final newRoom = Object();
      await target.requireExplicitResume(oldRoom);
      await target.load(_media('policy-transition'));
      holdReset = true;
      final releasing = target.releaseExplicitResume(oldRoom);
      await _flushEvents();
      final playing = target.play();
      holdPolicy = true;
      final acquiring = target.requireExplicitResume(newRoom);
      reset.complete();
      await _flushEvents();
      expect(configured, [true, false, true]);
      expect(platform.playCalls, 0);
      newPolicy.complete();
      await Future.wait([releasing, acquiring, playing]);
      expect(platform.playCalls, 1);
      expect(target.snapshot.playing, isTrue);
    },
  );

  test('unconfirmed native policy blocks Play and can be retried', () async {
    var reject = false;
    final target = createTarget(
      configureInterruptionPolicy: (_, required) async {
        if (required && reject) throw PlatformException(code: 'policy_failed');
      },
    );
    await target.load(_media('policy-failure'));
    reject = true;
    await expectLater(
      target.requireExplicitResume(Object()),
      throwsA(isA<PlatformException>()),
    );
    await expectLater(target.play(), throwsA(isA<PlatformException>()));
    expect(platform.playCalls, 0);
    reject = false;
    await target.play();
    expect(platform.playCalls, 1);
  });

  test('pause cancels Play waiting for native policy confirmation', () async {
    final policy = Completer<void>();
    var holdPolicy = false;
    final target = createTarget(
      configureInterruptionPolicy: (_, required) async {
        if (required && holdPolicy) await policy.future;
      },
    );
    await target.load(_media('policy-pause'));
    holdPolicy = true;
    final acquiring = target.requireExplicitResume(Object());
    final playing = target.play();
    await _flushEvents();
    await target.pause();
    policy.complete();
    await Future.wait([acquiring, playing]);
    expect(platform.playCalls, 0);
    expect(target.snapshot.playing, isFalse);
  });

  test(
    'buffering preserves the accepted play intent until an explicit pause',
    () async {
      final target = createTarget();
      await target.load(_media('first'));

      expect(
        platform.options.single?.allowBackgroundPlayback,
        isTrue,
        reason: 'AppController, rather than the plugin, owns lifecycle pause.',
      );
      expect(target.playRequested, isFalse);
      expect(target.snapshot.playing, isFalse);

      await target.play();
      platform.emit(VideoEvent(eventType: VideoEventType.bufferingStart));
      platform.emit(
        VideoEvent(
          eventType: VideoEventType.isPlayingStateUpdate,
          isPlaying: false,
        ),
      );
      await _flushEvents();

      expect(target.playRequested, isTrue);
      expect(target.snapshot.buffering, isTrue);
      expect(
        target.snapshot.playing,
        isFalse,
        reason: 'Snapshot reports the native player, not the requested state.',
      );

      final pausesBeforeExplicitPause = platform.pauseCalls;
      await target.pause();
      await _flushEvents();

      expect(target.playRequested, isFalse);
      expect(target.snapshot.playing, isFalse);
      expect(platform.pauseCalls, pausesBeforeExplicitPause + 1);
    },
  );

  test('buffering end does not turn a requested play into a pause', () async {
    final target = createTarget();
    await target.load(_media('buffering-transition'));
    await target.play();
    expect(target.playRequested, isTrue);

    platform.emit(VideoEvent(eventType: VideoEventType.bufferingStart));
    await _flushEvents();
    expect(target.snapshot.buffering, isTrue);

    platform.emit(
      VideoEvent(
        eventType: VideoEventType.isPlayingStateUpdate,
        isPlaying: false,
      ),
    );
    await _flushEvents();
    expect(target.snapshot.playing, isFalse);
    expect(target.playRequested, isTrue);

    // Android emits bufferingEnd before its next isPlaying=true update.
    platform.emit(VideoEvent(eventType: VideoEventType.bufferingEnd));
    await _flushEvents();
    expect(target.snapshot.buffering, isFalse);
    expect(target.snapshot.playing, isFalse);
    expect(target.playRequested, isTrue);

    platform.emit(
      VideoEvent(
        eventType: VideoEventType.isPlayingStateUpdate,
        isPlaying: true,
      ),
    );
    await _flushEvents();
    expect(target.snapshot.playing, isTrue);
    expect(target.playRequested, isTrue);

    // A separate non-buffering native pause still clears the intent.
    platform.emit(
      VideoEvent(
        eventType: VideoEventType.isPlayingStateUpdate,
        isPlaying: false,
      ),
    );
    await _flushEvents();
    expect(target.snapshot.buffering, isFalse);
    expect(target.snapshot.playing, isFalse);
    expect(target.playRequested, isFalse);
  });

  test('load, completion, and player errors clear play intent', () async {
    final target = createTarget();
    await target.load(_media('first'));
    await target.play();
    expect(target.playRequested, isTrue);

    await target.load(_media('second'));
    expect(target.playRequested, isFalse);
    expect(target.snapshot.media?.uri, _media('second').uri);

    await target.play();
    platform.emit(VideoEvent(eventType: VideoEventType.completed));
    await _flushEvents();
    expect(target.playRequested, isFalse);
    expect(target.snapshot.playing, isFalse);

    await target.load(_media('third'));
    await target.play();
    platform.emitError(
      PlatformException(code: 'VideoError', message: 'decoder stopped'),
    );
    await _flushEvents();

    expect(target.playRequested, isFalse);
    expect(target.snapshot.playing, isFalse);
    expect(target.snapshot.connection, PlaybackConnection.failed);
  });

  test(
    'restored source stays loading until its initial seek is confirmed',
    () async {
      final target = createTarget();
      await target.load(_media('restore-clock'));
      final seek = Completer<void>();
      final started = Completer<void>();
      platform.nextSeekGate = seek;
      platform.seekRequested = started;
      final observed = <PlaybackSnapshot>[];
      final subscription = target.states.listen(observed.add);
      const restored = Duration(seconds: 85);
      try {
        final loading = target.load(
          _media('restore-clock'),
          position: restored,
        );
        await started.future;
        platform.emit(VideoEvent(eventType: VideoEventType.bufferingStart));
        platform.emit(VideoEvent(eventType: VideoEventType.bufferingEnd));
        await _flushEvents();
        expect(target.snapshot.connection, PlaybackConnection.loading);
        expect(target.snapshot.position, restored);
        expect(observed.where((state) => state.ready), isEmpty);
        seek.complete();
        await loading;
        await _flushEvents();
        expect(target.snapshot.ready, isTrue);
        expect(target.snapshot.playing, isFalse);
        expect(observed.firstWhere((state) => state.ready).position, restored);
      } finally {
        if (!seek.isCompleted) seek.complete();
        await subscription.cancel();
      }
    },
  );

  test(
    'native error and a later pause retain the last confirmed media clock',
    () async {
      final target = createTarget();
      final media = _media('interrupted-stream');
      const position = Duration(seconds: 38);
      await target.load(media);
      await target.seek(position);
      final duration = target.snapshot.duration;
      await target.play();

      platform.emitError(
        PlatformException(code: 'VideoError', message: 'source disconnected'),
      );
      await _flushEvents();
      expect(target.controller!.value.position, Duration.zero);
      expect(target.controller!.value.duration, Duration.zero);
      expect(target.snapshot.media?.uri, media.uri);
      expect(target.snapshot.position, position);
      expect(target.snapshot.duration, duration);
      expect(target.snapshot.connection, PlaybackConnection.failed);

      final nativeZero = Completer<Duration>()..complete(Duration.zero);
      platform.nextPosition = nativeZero;
      await target.pause();
      expect(target.snapshot.position, position);
      expect(target.snapshot.duration, duration);
      expect(target.snapshot.connection, PlaybackConnection.failed);
    },
  );

  test(
    'a failed same-source reopen retains requested position and known duration',
    () async {
      final target = createTarget();
      final media = _media('failed-reopen');
      const position = Duration(seconds: 44);
      await target.load(media, position: position);
      final duration = target.snapshot.duration;
      platform.emitError(
        PlatformException(code: 'VideoError', message: 'source disconnected'),
      );
      await _flushEvents();
      platform.nextInitializationError = PlatformException(
        code: 'VideoError',
        message: 'network remains unavailable',
      );

      final loading = target.load(media, position: target.snapshot.position);
      expect(target.snapshot.connection, PlaybackConnection.loading);
      expect(target.snapshot.position, position);
      expect(target.snapshot.duration, duration);
      await expectLater(loading, throwsA(isA<PlatformException>()));
      expect(target.snapshot.connection, PlaybackConnection.failed);
      expect(target.snapshot.media?.uri, media.uri);
      expect(target.snapshot.position, position);
      expect(target.snapshot.duration, duration);
      expect(target.playRequested, isFalse);
    },
  );

  test(
    'successful load replaces retained clock with the new native duration',
    () async {
      final target = createTarget();
      final media = _media('successful-reopen');
      await target.load(media, position: const Duration(seconds: 20));
      await target.play();
      expect(target.canReloadAfterConnectionLoss, isTrue);
      platform.emitError(
        PlatformException(code: 'VideoError', message: 'source disconnected'),
      );
      await _flushEvents();

      const pastEnd = Duration(seconds: 400);
      final playsBeforeReload = platform.playCalls;
      final loading = target.load(media, position: pastEnd);
      expect(target.snapshot.connection, PlaybackConnection.loading);
      expect(target.snapshot.position, pastEnd);
      expect(target.snapshot.duration, const Duration(minutes: 5));
      await loading;
      expect(target.snapshot.connection, PlaybackConnection.ready);
      expect(target.snapshot.position, const Duration(minutes: 5));
      expect(target.snapshot.duration, const Duration(minutes: 5));
      expect(target.snapshot.playing, isFalse);
      expect(target.playRequested, isFalse);
      expect(platform.playCalls, playsBeforeReload);

      final other = target.load(_media('different-source'));
      expect(target.snapshot.duration, Duration.zero);
      await other;
      expect(target.snapshot.connection, PlaybackConnection.ready);
      expect(target.snapshot.position, Duration.zero);
      expect(target.snapshot.duration, const Duration(minutes: 5));
    },
  );

  test('resuming the widget lifecycle never undoes an app pause', () async {
    final target = createTarget();
    await target.load(_media('lifecycle'));
    await target.play();
    final playsBeforePause = platform.playCalls;

    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.paused,
    );
    await _flushEvents();
    await target.pause();
    final playsBeforeResume = platform.playCalls;

    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await _flushEvents();

    expect(playsBeforePause, 1);
    expect(playsBeforeResume, 1);
    expect(platform.playCalls, playsBeforeResume);
    expect(target.playRequested, isFalse);
    expect(target.snapshot.playing, isFalse);
  });
}

Future<void> _flushEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Future<void> _sendFocusInterruption(int playerId, int version) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'com.meowwatch.mobile/player_focus',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onFocusInterruption', {
            'playerId': playerId,
            'interruptionVersion': version,
          }),
        ),
        (_) {},
      );
}

MediaItem _media(String name) => MediaItem(
  uri: Uri.parse('https://video.example/$name.mp4'),
  title: '$name.mp4',
);

final class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  final Map<int, StreamController<VideoEvent>> _events = {};
  final Map<int, Duration> _positions = {};
  final List<VideoPlayerOptions?> options = [];
  final List<bool> mixModesAtCreation = [];
  bool _mixWithOthers = false;
  int _nextPlayerId = 1;
  int? _activePlayerId;
  int playCalls = 0;
  int pauseCalls = 0;
  Duration? positionOnPause;
  Completer<Duration>? nextPosition;
  Completer<void>? positionRequested;
  Completer<void>? nextRateGate;
  Completer<void>? nextSeekGate;
  Completer<void>? seekRequested;
  PlatformException? nextInitializationError;
  final rates = <double>[];

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions creation) async {
    final playerId = _nextPlayerId++;
    _activePlayerId = playerId;
    options.add(creation.videoPlayerOptions);
    mixModesAtCreation.add(_mixWithOthers);
    final events = StreamController<VideoEvent>();
    final initializationError = nextInitializationError;
    nextInitializationError = null;
    if (initializationError != null) {
      events.addError(initializationError);
    } else {
      events.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(minutes: 5),
          size: const Size(1280, 720),
        ),
      );
    }
    _events[playerId] = events;
    _positions[playerId] = Duration.zero;
    return playerId;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  void emit(VideoEvent event) => _events[_activePlayerId]!.add(event);

  void emitError(Object error) => _events[_activePlayerId]!.addError(error);

  Future<void> closeStreams() async {
    await Future.wait(_events.values.map((events) => events.close()));
    _events.clear();
  }

  @override
  Future<void> dispose(int playerId) async {
    if (_activePlayerId == playerId) _activePlayerId = null;
  }

  @override
  Future<void> play(int playerId) async {
    playCalls++;
  }

  @override
  Future<void> pause(int playerId) async {
    pauseCalls++;
    if (positionOnPause != null) _positions[playerId] = positionOnPause!;
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    final gate = nextSeekGate;
    nextSeekGate = null;
    seekRequested?.complete();
    seekRequested = null;
    await gate?.future;
    _positions[playerId] = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async {
    final pending = nextPosition;
    nextPosition = null;
    positionRequested?.complete();
    positionRequested = null;
    if (pending != null) return pending.future;
    return _positions[playerId]!;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {
    rates.add(speed);
    final gate = nextRateGate;
    nextRateGate = null;
    await gate?.future;
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {
    _mixWithOthers = mixWithOthers;
  }
}
