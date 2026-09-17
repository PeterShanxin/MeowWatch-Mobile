import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/ui/app_theme.dart';
import 'package:meowwatch_mobile/ui/help/quick_guide_sheet.dart';

Future<void> _openGuide(WidgetTester tester, {double textScale = 1}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: meowWatchTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showQuickGuideSheet(context),
            child: const Text('Open guide'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open guide'));
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final button = find.byKey(Key(key));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('explains the real media contract and can finish or go back', (
    tester,
  ) async {
    await _openGuide(tester);
    expect(find.text('Pick your video'), findsOneWidget);
    expect(find.textContaining('Webpages and protected'), findsOneWidget);

    await _tapKey(tester, 'quick-guide-next');
    expect(find.text('Bring a friend'), findsOneWidget);
    expect(
      find.textContaining('everyone needs their own copy'),
      findsOneWidget,
    );
    await _tapKey(tester, 'quick-guide-back');
    expect(find.text('Pick your video'), findsOneWidget);
    await _tapKey(tester, 'quick-guide-next');
    await _tapKey(tester, 'quick-guide-next');
    expect(find.text('Press play together'), findsOneWidget);
    expect(
      find.textContaining('one new hosted session per local day'),
      findsOneWidget,
    );
    expect(find.text('Got it'), findsOneWidget);

    await _tapKey(tester, 'quick-guide-next');
    expect(find.byKey(const Key('quick-guide-sheet')), findsNothing);
    await tester.tap(find.text('Open guide'));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 3'), findsOneWidget);
    await _tapKey(tester, 'quick-guide-close');
    expect(find.byKey(const Key('quick-guide-sheet')), findsNothing);
  });

  testWidgets('skip dismisses from an unfinished step', (tester) async {
    await _openGuide(tester);
    await _tapKey(tester, 'quick-guide-next');
    await _tapKey(tester, 'quick-guide-skip');
    expect(find.byKey(const Key('quick-guide-sheet')), findsNothing);
    expect(find.text('Open guide'), findsOneWidget);
  });

  for (final layout in [
    (
      name: 'small phone with keyboard',
      size: const Size(320, 568),
      inset: 240.0,
    ),
    (name: 'landscape phone', size: const Size(800, 360), inset: 0.0),
    (name: 'landscape tablet', size: const Size(1280, 800), inset: 0.0),
  ]) {
    testWidgets('${layout.name} guide works at 200% text', (tester) async {
      tester.view.physicalSize = layout.size;
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = FakeViewPadding(bottom: layout.inset);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);

      await _openGuide(tester, textScale: 2);
      for (var step = 1; step <= 3; step++) {
        expect(find.text('Step $step of 3'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _tapKey(tester, 'quick-guide-next');
        expect(tester.takeException(), isNull);
      }
      expect(find.byKey(const Key('quick-guide-sheet')), findsNothing);
    });
  }
}
