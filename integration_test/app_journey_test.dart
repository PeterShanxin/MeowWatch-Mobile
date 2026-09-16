import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meowwatch_mobile/main.dart';
import 'package:video_player/video_player.dart';

const _videoUrl = String.fromEnvironment(
  'APP_JOURNEY_VIDEO_URL',
  defaultValue:
      'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
);
const _pollInterval = Duration(milliseconds: 150);
final _videoTitle = Uri.parse(_videoUrl).pathSegments.last;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'production app journey renders, plays, persists, and loads Plus offering',
    (tester) async {
      expect(
        Platform.isAndroid,
        isTrue,
        reason: 'This journey is an Android rendered-product gate.',
      );

      final screenshots = <String>[];
      final verified = <String>[];
      final observations = <String, Object?>{};

      await binding.convertFlutterSurfaceToImage();
      await tester.pumpWidget(const MainApp());

      final initial = await _waitForAny(
        tester,
        [
          find.byKey(const Key('display-name-field')),
          find.byKey(const Key('home-scroll-view')),
        ],
        'production app bootstrap',
        timeout: const Duration(seconds: 40),
      );
      verified.add('production_app_bootstrap');

      if (initial.evaluate().first.widget.key ==
          const Key('display-name-field')) {
        await tester.enterText(initial, 'Mochi');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(milliseconds: 200));
        await _tap(
          tester,
          find.byKey(const Key('onboarding-continue-button')),
          'continue onboarding',
        );
        await _waitFor(
          tester,
          find.byKey(const Key('home-scroll-view')),
          'home after first-launch name',
          timeout: const Duration(seconds: 20),
        );
        await _waitForGone(
          tester,
          find.byKey(const Key('display-name-field')),
          'onboarding route',
        );
        verified.add('first_launch_name_saved');
        observations['onboarding'] = 'completed';
      } else {
        verified.add('existing_profile_reused');
        observations['onboarding'] = 'already_complete';
      }

      await _capture(binding, tester, screenshots, 'home');
      verified.add('home_rendered');

      await _tap(
        tester,
        find.byKey(const Key('join-room-button')),
        'open join sheet',
      );
      final joinField = find.byKey(const Key('join-code-field'));
      await _waitFor(tester, joinField, 'join sheet');
      await tester.enterText(joinField, 'movie@host:notaport');
      await _tap(
        tester,
        find.byKey(const Key('join-submit-button')),
        'validate malformed room code',
      );
      const joinError =
          'That code looks off — ask your friend to copy and paste it again.';
      await _waitFor(tester, find.text(joinError), 'inline join validation');
      expect(
        joinField,
        findsOneWidget,
        reason: 'Malformed input must stay in the sheet without networking.',
      );
      verified.add('invalid_join_rejected_locally');
      observations['invalidJoinError'] = joinError;
      await _capture(binding, tester, screenshots, 'join-invalid');

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.binding.handlePopRoute();
      await _waitForGone(tester, joinField, 'join sheet');
      await _waitFor(
        tester,
        find.byKey(const Key('home-scroll-view')),
        'home after cancelling join',
      );

      await _tap(
        tester,
        find.byKey(const Key('local-mode-button')),
        'enter local mode',
      );
      await _waitForAny(tester, [
        find.byTooltip('Back to home'),
        find.text('Local mode'),
      ], 'local player in the current layout');
      verified.add('local_mode_opened');

      await _tap(
        tester,
        find.widgetWithText(TextButton, 'Video'),
        'open media sheet',
      );
      await _waitFor(tester, find.text('Choose what to watch'), 'media sheet');
      final mediaField = find.byType(TextField);
      expect(mediaField, findsOneWidget);
      await tester.enterText(mediaField, _videoUrl);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 150));
      await _tap(tester, find.text('Use this link'), 'load direct media URL');

      await _waitFor(
        tester,
        find.byType(VideoPlayer),
        'real Android video texture',
        timeout: const Duration(seconds: 70),
      );
      final sliderFinder = find.byType(Slider);
      await _waitFor(tester, sliderFinder, 'playback slider');
      await _waitForCondition(
        tester,
        () => _slider(tester).max > 1000,
        'loaded playback duration',
      );
      final viewSize = tester.view.physicalSize / tester.view.devicePixelRatio;
      if (viewSize.height >= viewSize.width) {
        await _waitFor(tester, find.text(_videoTitle), 'loaded media title');
      }
      verified.addAll([
        'official_direct_video_loaded',
        'android_video_texture_rendered',
        'playback_metadata_loaded',
      ]);

      final startPosition = _slider(tester).value;
      final play = await _waitForAny(tester, [
        find.byTooltip('Play'),
        find.byTooltip('Play together'),
      ], 'enabled play control');
      await _tap(tester, play, 'play video');
      final pause = await _waitForAny(tester, [
        find.byTooltip('Pause'),
        find.byTooltip('Pause together'),
      ], 'pause control after playing');
      await _waitForCondition(
        tester,
        () => _slider(tester).value >= startPosition + 350,
        'video position to advance',
        timeout: const Duration(seconds: 20),
      );
      final advancedPosition = _slider(tester).value;
      verified.add('video_advanced_via_ui');

      await _tap(tester, pause, 'pause video');
      await _waitForAny(tester, [
        find.byTooltip('Play'),
        find.byTooltip('Play together'),
      ], 'play control after pausing');
      final pausedPosition = _slider(tester).value;
      await _capture(binding, tester, screenshots, 'video-advanced-paused');
      await tester.pump(const Duration(milliseconds: 900));
      final pauseDrift = (_slider(tester).value - pausedPosition).abs();
      expect(
        pauseDrift,
        lessThan(500),
        reason: 'The rendered UI must remain paused after tapping pause.',
      );
      verified.add('video_paused_via_ui');

      final slider = _slider(tester);
      final tappableSlider = sliderFinder.hitTestable();
      await _waitFor(tester, tappableSlider, 'tappable playback slider');
      final sliderRect = tester.getRect(tappableSlider);
      await tester.tapAt(
        Offset(sliderRect.left + sliderRect.width * 0.68, sliderRect.center.dy),
      );
      await tester.pump(_pollInterval);
      await _waitForCondition(
        tester,
        () => _slider(tester).value > slider.max * 0.5,
        'slider seek to later position',
        timeout: const Duration(seconds: 15),
      );
      final soughtPosition = _slider(tester).value;
      expect(soughtPosition, greaterThan(advancedPosition));
      await _capture(binding, tester, screenshots, 'video-paused-sought');
      verified.add('video_seeked_via_ui');

      await _tap(tester, find.byTooltip('Back to home'), 'leave local player');
      await _waitFor(
        tester,
        find.byKey(const Key('home-scroll-view')),
        'home with saved history',
        timeout: const Duration(seconds: 20),
      );
      final resumeKey = ValueKey('resume-local|$_videoUrl');
      await _waitFor(tester, find.byKey(resumeKey), 'Continue Watching entry');
      await tester.ensureVisible(find.byKey(resumeKey));
      await tester.pump(const Duration(milliseconds: 200));
      await _capture(binding, tester, screenshots, 'continue-watching');
      verified.add('continue_watching_persisted');

      await _tap(tester, find.byKey(resumeKey), 'resume Continue Watching');
      await _waitFor(
        tester,
        find.byType(VideoPlayer),
        'resumed Android video texture',
        timeout: const Duration(seconds: 70),
      );
      await _waitFor(tester, sliderFinder, 'resumed playback slider');
      await _waitForCondition(
        tester,
        () => _slider(tester).value >= soughtPosition - 1200,
        'saved playback position to resume',
        timeout: const Duration(seconds: 15),
      );
      final resumedPosition = _slider(tester).value;
      await _capture(binding, tester, screenshots, 'continue-resumed');
      verified.add('continue_watching_resumed');

      await _tap(
        tester,
        find.byTooltip('Back to home'),
        'return home after resume',
      );
      await _waitFor(
        tester,
        find.byKey(const Key('home-scroll-view')),
        'home before Plus',
      );
      final plusButton = find.widgetWithText(TextButton, 'Plus');
      await _waitFor(
        tester,
        plusButton,
        'Plus entry for clean Test Store customer',
        timeout: const Duration(seconds: 20),
      );
      await _tap(tester, plusButton, 'open Plus');
      await _waitFor(tester, find.text('More movie nights.'), 'Plus sheet');
      final monthlyPackage = find.byKey(
        const ValueKey(r'purchase-$rc_monthly'),
      );
      await _waitFor(
        tester,
        monthlyPackage,
        'RevenueCat monthly offering',
        timeout: const Duration(seconds: 70),
      );
      final packageLabels = tester
          .widgetList<Text>(
            find.descendant(of: monthlyPackage, matching: find.byType(Text)),
          )
          .map((widget) => widget.data)
          .whereType<String>()
          .toList(growable: false);
      final localizedPrice = packageLabels.singleWhere(
        (label) => label.startsWith('Continue · '),
      );
      expect(find.textContaining('RevenueCat Test Store'), findsOneWidget);
      observations['offeringCta'] = localizedPrice;
      await tester.ensureVisible(monthlyPackage);
      await tester.pump(const Duration(milliseconds: 200));
      await _capture(binding, tester, screenshots, 'plus-offering');
      verified.add('revenuecat_offering_rendered');

      await _tap(tester, find.text('Maybe tomorrow'), 'dismiss Plus safely');
      await _waitForGone(tester, find.text('More movie nights.'), 'Plus sheet');
      await _waitFor(
        tester,
        find.byKey(const Key('home-scroll-view')),
        'home after dismissing Plus',
      );
      verified.add('plus_dismissed_without_purchase');

      final view = tester.view;
      final logicalSize = view.physicalSize / view.devicePixelRatio;
      observations.addAll({
        'videoUrl': _videoUrl,
        'advancedPositionMs': advancedPosition.round(),
        'pausedDriftMs': pauseDrift.round(),
        'soughtPositionMs': soughtPosition.round(),
        'resumedPositionMs': resumedPosition.round(),
      });
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['appJourney'] = <String, Object?>{
        'result': 'passed',
        'platform': Platform.operatingSystem,
        'operatingSystemVersion': Platform.operatingSystemVersion,
        'device': <String, Object>{
          'runtime': 'Android',
          'reportedVersion': Platform.operatingSystemVersion,
        },
        'locale': tester.platformDispatcher.locale.toLanguageTag(),
        'viewport': <String, Object>{
          'physicalWidth': view.physicalSize.width.round(),
          'physicalHeight': view.physicalSize.height.round(),
          'devicePixelRatio': view.devicePixelRatio,
          'logicalWidth': logicalSize.width,
          'logicalHeight': logicalSize.height,
          'orientation': logicalSize.width > logicalSize.height
              ? 'landscape'
              : 'portrait',
        },
        'screenshots': screenshots,
        'verifiedSteps': verified,
        'observations': observations,
        'completedAtUtc': DateTime.now().toUtc().toIso8601String(),
      };

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
    timeout: const Timeout(Duration(minutes: 7)),
  );
}

Slider _slider(WidgetTester tester) =>
    tester.widget<Slider>(find.byType(Slider));

Future<void> _capture(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  List<String> screenshots,
  String name,
) async {
  await tester.pump(const Duration(milliseconds: 250));
  final bytes = await binding.takeScreenshot(name);
  expect(bytes, isNotEmpty, reason: 'Screenshot $name was empty.');
  screenshots.add(name);
}

Future<void> _tap(
  WidgetTester tester,
  Finder finder,
  String description,
) async {
  await _waitFor(tester, finder, description);
  var hitTarget = finder.hitTestable();
  if (hitTarget.evaluate().isEmpty) {
    await tester.ensureVisible(finder);
    await _waitForStableGeometry(tester, finder, description);
    hitTarget = finder.hitTestable();
    await _waitFor(tester, hitTarget, '$description to become tappable');
  }
  await tester.tap(hitTarget);
  await tester.pump(_pollInterval);
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder,
  String description, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  await _waitForCondition(
    tester,
    () => finder.evaluate().isNotEmpty,
    description,
    timeout: timeout,
  );
  await _waitForStableGeometry(tester, finder, description, timeout: timeout);
}

Future<void> _waitForGone(
  WidgetTester tester,
  Finder finder,
  String description, {
  Duration timeout = const Duration(seconds: 15),
}) => _waitForCondition(
  tester,
  () => finder.evaluate().isEmpty,
  '$description to close',
  timeout: timeout,
);

Future<Finder> _waitForAny(
  WidgetTester tester,
  List<Finder> finders,
  String description, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  Finder? found;
  await _waitForCondition(
    tester,
    () {
      for (final finder in finders) {
        if (finder.evaluate().isNotEmpty) {
          found = finder;
          return true;
        }
      }
      return false;
    },
    description,
    timeout: timeout,
  );
  await _waitForStableGeometry(tester, found!, description, timeout: timeout);
  return found!;
}

Future<void> _waitForStableGeometry(
  WidgetTester tester,
  Finder finder,
  String description, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final stopwatch = Stopwatch()..start();
  Rect? previous;
  var stableSamples = 0;
  while (stopwatch.elapsed < timeout) {
    if (finder.evaluate().isNotEmpty) {
      try {
        final current = tester.getRect(finder.first);
        if (previous != null &&
            (current.left - previous.left).abs() < 0.5 &&
            (current.top - previous.top).abs() < 0.5 &&
            (current.width - previous.width).abs() < 0.5 &&
            (current.height - previous.height).abs() < 0.5) {
          stableSamples++;
          if (stableSamples >= 2) return;
        } else {
          stableSamples = 0;
        }
        previous = current;
      } on StateError {
        stableSamples = 0;
        previous = null;
      }
    } else {
      stableSamples = 0;
      previous = null;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw TestFailure(
    'Timed out after ${timeout.inSeconds}s waiting for stable $description.',
  );
}

Future<void> _waitForCondition(
  WidgetTester tester,
  bool Function() condition,
  String description, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed >= timeout) {
      throw TestFailure(
        'Timed out after ${timeout.inSeconds}s waiting for $description.',
      );
    }
    await tester.pump(_pollInterval);
  }
}
