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

  LocalMobileTarget createTarget({bool mixWithOthers = false}) {
    final target = LocalMobileTarget(mixWithOthers: mixWithOthers);
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

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions creation) async {
    final playerId = _nextPlayerId++;
    _activePlayerId = playerId;
    options.add(creation.videoPlayerOptions);
    mixModesAtCreation.add(_mixWithOthers);
    final events = StreamController<VideoEvent>();
    events.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(minutes: 5),
        size: const Size(1280, 720),
      ),
    );
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
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {
    _mixWithOthers = mixWithOthers;
  }
}
