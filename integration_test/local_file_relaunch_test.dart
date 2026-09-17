import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meowwatch_mobile/app/app_controller.dart';
import 'package:meowwatch_mobile/app/app_services.dart';
import 'package:meowwatch_mobile/core/playback/playback_target.dart';
import 'package:meowwatch_mobile/data/app_repository.dart';
import 'package:meowwatch_mobile/main.dart';
import 'package:video_player/video_player.dart';

import '../tools/native_capture/native_screenshot.dart';

const _fixtureTitle = 'meowwatch-saf-fixture.mp4';
const _pollInterval = Duration(milliseconds: 150);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'SAF media remains readable after an Android process restart',
    (tester) async {
      expect(
        Platform.isAndroid,
        isTrue,
        reason: 'This gate exercises Android DocumentsUI and content URIs.',
      );
      final screenshots = NativeScreenshots(binding);

      final app = await openAppServices();
      addTearDown(app.close);
      final matching = app.repository.history
          .where(
            (entry) =>
                entry.media.title == _fixtureTitle &&
                entry.media.uri.scheme == 'content',
          )
          .toList();
      expect(matching.length, lessThanOrEqualTo(1));

      final evidence = matching.isEmpty
          ? await _selectPlayAndPersist(screenshots, tester, app)
          : await _resumeAfterRelaunch(
              screenshots,
              tester,
              app,
              matching.single,
            );
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['localFileRuntime'] = <String, Object?>{
        ...evidence,
        'completed': true,
        'fixtureTitle': _fixtureTitle,
        'rawContentUriReported': false,
        'nativeDocumentsUiRequired': true,
      };
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<Map<String, Object?>> _selectPlayAndPersist(
  NativeScreenshots screenshots,
  WidgetTester tester,
  AppController app,
) async {
  if (app.firstLaunch) await app.setName('Runtime viewer');
  await app.useLocalMode();
  await tester.pumpWidget(MainApp(controller: app));
  await _waitFor(tester, find.text('Your own screening'), 'local player shell');

  await tester.tap(find.text('Video'));
  await tester.pump(_pollInterval);
  await _waitFor(
    tester,
    find.text('Video on this device'),
    'production media sheet',
  );
  // The host runner watches for the real DocumentsUI activity and selects the
  // pushed fixture with exact UIAutomator selectors.
  await tester.tap(find.text('Video on this device'));
  await tester.pump(_pollInterval);

  await _waitForCondition(
    tester,
    () => app.target.snapshot.ready,
    'SAF media decode',
    timeout: const Duration(seconds: 70),
  );
  final loaded = app.target.snapshot;
  expect(loaded.media?.title, _fixtureTitle);
  expect(loaded.media?.uri.scheme, 'content');
  expect(loaded.duration, greaterThan(const Duration(seconds: 15)));
  await _waitFor(tester, find.byType(VideoPlayer), 'native video texture');

  await app.togglePlay();
  await _waitForCondition(
    tester,
    () => app.target.snapshot.position > const Duration(milliseconds: 700),
    'native playback position advancement',
    timeout: const Duration(seconds: 20),
  );
  await app.togglePlay();
  expect(app.target.snapshot.playing, isFalse);

  const requested = Duration(seconds: 8);
  await app.seek(requested);
  await _waitForCondition(
    tester,
    () =>
        (app.target.snapshot.position - requested).abs() <
        const Duration(milliseconds: 1200),
    'native seek completion',
  );
  await app.saveProgress();
  final persisted = app.repository.history
      .where((entry) => entry.media.title == _fixtureTitle)
      .toList();
  expect(persisted, hasLength(1));
  expect(persisted.single.media.uri.scheme, 'content');
  expect(persisted.single.position, greaterThan(const Duration(seconds: 6)));
  expect(persisted.single.duration, loaded.duration);

  await tester.pump(_pollInterval);
  final screenshot = await screenshots.take(tester, 'local-file-selected');
  expect(screenshot.length, greaterThan(4096));
  return <String, Object?>{
    'stage': 1,
    'documentsUiSelectionReturned': true,
    'contentSchemeAccepted': true,
    'nativeDecodeReady': true,
    'nativePlaybackAdvanced': true,
    'nativeSeekCompleted': true,
    'historyPersisted': true,
    'durationMs': persisted.single.duration.inMilliseconds,
    'savedPositionMs': persisted.single.position.inMilliseconds,
    'screenshot': 'local-file-selected',
  };
}

Future<Map<String, Object?>> _resumeAfterRelaunch(
  NativeScreenshots screenshots,
  WidgetTester tester,
  AppController app,
  WatchHistoryEntry saved,
) async {
  expect(saved.media.uri.scheme, 'content');
  expect(saved.duration, greaterThan(const Duration(seconds: 15)));
  expect(saved.position, greaterThan(const Duration(seconds: 6)));

  await tester.pumpWidget(MainApp(controller: app));
  await _waitFor(
    tester,
    find.byKey(const Key('home-scroll-view')),
    'production home after process restart',
  );
  final historyCard = find.text(_fixtureTitle);
  await _waitFor(tester, historyCard, 'saved SAF history entry');
  await tester.tap(historyCard);
  await tester.pump(_pollInterval);

  await _waitForCondition(
    tester,
    () => app.inPlayer && app.target.snapshot.ready,
    'retained SAF permission decode',
    timeout: const Duration(seconds: 70),
  );
  await _waitFor(tester, find.byType(VideoPlayer), 'resumed native texture');
  final resumed = app.target.snapshot;
  expect(resumed.media?.title, _fixtureTitle);
  expect(resumed.media?.uri.scheme, 'content');
  expect(
    (resumed.duration - saved.duration).abs(),
    lessThan(const Duration(milliseconds: 1200)),
  );
  expect(
    resumed.position,
    greaterThanOrEqualTo(saved.position - const Duration(milliseconds: 1500)),
  );

  final beforePlay = resumed.position;
  await app.togglePlay();
  await _waitForCondition(
    tester,
    () =>
        app.target.snapshot.position >
        beforePlay + const Duration(milliseconds: 500),
    'playback after process restart',
    timeout: const Duration(seconds: 20),
  );
  await app.togglePlay();
  expect(app.target.snapshot.connection, PlaybackConnection.ready);
  expect(app.target.snapshot.playing, isFalse);

  await tester.pump(_pollInterval);
  final screenshot = await screenshots.take(tester, 'local-file-relaunched');
  expect(screenshot.length, greaterThan(4096));
  return <String, Object?>{
    'stage': 2,
    'historyRestoredAfterProcessRestart': true,
    'retainedContentGrantVerified': true,
    'nativeDecodeReady': true,
    'nativePlaybackAdvanced': true,
    'durationMs': resumed.duration.inMilliseconds,
    'restoredPositionMs': resumed.position.inMilliseconds,
    'minimumExpectedPositionMs':
        (saved.position - const Duration(milliseconds: 1500)).inMilliseconds,
    'screenshot': 'local-file-relaunched',
  };
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder,
  String label, {
  Duration timeout = const Duration(seconds: 25),
}) => _waitForCondition(
  tester,
  () => finder.evaluate().isNotEmpty,
  label,
  timeout: timeout,
);

Future<void> _waitForCondition(
  WidgetTester tester,
  bool Function() condition,
  String label, {
  Duration timeout = const Duration(seconds: 25),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(_pollInterval);
    if (condition()) return;
  }
  throw TestFailure('Timed out waiting for $label.');
}
