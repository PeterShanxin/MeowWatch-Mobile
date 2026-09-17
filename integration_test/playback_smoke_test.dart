import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meowwatch_mobile/core/media/media_item.dart';
import 'package:meowwatch_mobile/core/playback/local_mobile_target.dart';
import 'package:meowwatch_mobile/core/playback/playback_target.dart';
import 'package:video_player/video_player.dart';

import '../tools/native_capture/native_screenshot.dart';

const _sampleVideoUrl =
    'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'production mobile target renders and controls real Android video',
    (tester) async {
      expect(
        Platform.isAndroid,
        isTrue,
        reason: 'This smoke test is intentionally an Android runtime gate.',
      );

      final target = LocalMobileTarget();
      addTearDown(target.close);
      final media = MediaItem.fromUrl(_sampleVideoUrl);

      await target.load(media);
      expect(target.snapshot.connection, PlaybackConnection.ready);
      expect(target.snapshot.duration, greaterThan(const Duration(seconds: 2)));
      expect(target.controller, isNotNull);
      expect(target.controller!.value.isInitialized, isTrue);
      expect(target.controller!.value.size.width, greaterThan(0));
      expect(target.controller!.value.size.height, greaterThan(0));

      final screenshots = NativeScreenshots(binding);
      await tester.pumpWidget(_PlaybackSurface(controller: target.controller!));
      await tester.pump(const Duration(milliseconds: 300));

      final start = target.snapshot.position;
      await target.play();
      final advanced = await _waitForSnapshot(
        tester,
        target,
        (snapshot) =>
            snapshot.playing &&
            snapshot.position >= start + const Duration(milliseconds: 700),
      );
      expect(advanced.connection, PlaybackConnection.ready);

      await tester.pump(const Duration(milliseconds: 300));
      final playingPng = await screenshots.take(tester, 'playback-playing');
      expect(playingPng, isNotEmpty);

      await target.pause();
      final paused = await _waitForSnapshot(
        tester,
        target,
        (snapshot) => !snapshot.playing,
      );
      final pausedAt = paused.position;
      await tester.pump(const Duration(milliseconds: 900));
      final pauseDrift = (target.snapshot.position - pausedAt).inMilliseconds
          .abs();
      expect(
        pauseDrift,
        lessThan(350),
        reason: 'A paused Android player must not continue advancing.',
      );

      final seekPosition = target.snapshot.duration > const Duration(seconds: 6)
          ? const Duration(seconds: 4)
          : Duration(
              microseconds: target.snapshot.duration.inMicroseconds ~/ 2,
            );
      await target.seek(seekPosition);
      final sought = await _waitForSnapshot(
        tester,
        target,
        (snapshot) =>
            (snapshot.position - seekPosition).inMilliseconds.abs() < 800,
      );
      expect(sought.playing, isFalse);

      final firstController = target.controller;
      await tester.pumpWidget(const SizedBox.shrink());
      await target.load(media, position: const Duration(seconds: 1));
      expect(target.snapshot.connection, PlaybackConnection.ready);
      expect(target.controller, isNot(same(firstController)));
      expect(
        (target.snapshot.position - const Duration(seconds: 1)).inMilliseconds
            .abs(),
        lessThan(800),
      );

      await tester.pumpWidget(_PlaybackSurface(controller: target.controller!));
      await target.play();
      await _waitForSnapshot(
        tester,
        target,
        (snapshot) =>
            snapshot.playing &&
            snapshot.position >= const Duration(milliseconds: 1500),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final reopenedPng = await screenshots.take(tester, 'playback-reopened');
      expect(reopenedPng, isNotEmpty);

      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['androidRuntime'] = <String, dynamic>{
        'platform': Platform.operatingSystem,
        'videoUrl': _sampleVideoUrl,
        'durationMs': target.snapshot.duration.inMilliseconds,
        'videoWidth': target.controller!.value.size.width,
        'videoHeight': target.controller!.value.size.height,
        'advancedPositionMs': advanced.position.inMilliseconds,
        'seekPositionMs': sought.position.inMilliseconds,
        'screenshots': <String>['playback-playing', 'playback-reopened'],
      };

      await tester.pumpWidget(const SizedBox.shrink());
      await target.close();
      expect(target.controller, isNull);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<PlaybackSnapshot> _waitForSnapshot(
  WidgetTester tester,
  LocalMobileTarget target,
  bool Function(PlaybackSnapshot snapshot) predicate, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 200));
    final snapshot = target.snapshot;
    if (predicate(snapshot)) return snapshot;
    if (snapshot.connection == PlaybackConnection.failed) {
      throw TestFailure(snapshot.error ?? 'Android playback failed.');
    }
  }
  throw TestFailure(
    'Timed out waiting for Android playback state. Last snapshot: '
    'connection=${target.snapshot.connection}, '
    'playing=${target.snapshot.playing}, '
    'position=${target.snapshot.position}.',
  );
}

class _PlaybackSurface extends StatelessWidget {
  const _PlaybackSurface({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }
}
