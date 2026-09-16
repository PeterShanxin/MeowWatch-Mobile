import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/ui/home/onboarding_screen.dart';

import 'ui_test_support.dart';

void main() {
  testWidgets('offers generated identity and forwards an optional name', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = UiTestApp.create();
    String? submitted;

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          app: fixture.controller,
          onContinue: (name) async => submitted = name,
        ),
      ),
    );

    expect(
      find.text('Leave blank to continue as ${fixture.controller.username}.'),
      findsOneWidget,
    );
    final headline = tester.widget<Text>(
      find.text('Close the distance.\nKeep the movie night.'),
    );
    expect(headline.style?.fontFamily, 'DMSerifDisplay');
    expect(headline.style?.fontSize, 40);
    await tester.enterText(
      find.byKey(const Key('display-name-field')),
      'Mochi',
    );
    await tester.ensureVisible(
      find.byKey(const Key('onboarding-continue-button')),
    );
    await tester.tap(find.byKey(const Key('onboarding-continue-button')));
    await tester.pump();
    expect(submitted, 'Mochi');
    await fixture.close();
  });

  testWidgets('small keyboard layout scrolls without clipping at 200%', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final fixture = UiTestApp.create();

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: OnboardingScreen(
          app: fixture.controller,
          onContinue: (_) async {},
        ),
      ),
    );

    await tester.ensureVisible(find.byKey(const Key('display-name-field')));
    await tester.tap(find.byKey(const Key('display-name-field')));
    await tester.pump();
    expect(find.byKey(const Key('onboarding-scroll-view')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await fixture.close();
  });
}
