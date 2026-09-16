import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/playback/local_mobile_target.dart';
import 'package:meowwatch_mobile/core/playback/playback_target.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

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

  LocalMobileTarget createTarget() {
    final target = LocalMobileTarget();
    targets.add(target);
    return target;
  }

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
  final List<VideoPlayerOptions?> options = [];
  int _nextPlayerId = 1;
  int? _activePlayerId;
  int playCalls = 0;
  int pauseCalls = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions creation) async {
    final playerId = _nextPlayerId++;
    _activePlayerId = playerId;
    options.add(creation.videoPlayerOptions);
    final events = StreamController<VideoEvent>();
    events.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(minutes: 5),
        size: const Size(1280, 720),
      ),
    );
    _events[playerId] = events;
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
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}
