import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

void _expectInside(Rect bounds, Rect viewport) {
  expect(bounds.left, greaterThanOrEqualTo(viewport.left - 0.01));
  expect(bounds.top, greaterThanOrEqualTo(viewport.top - 0.01));
  expect(bounds.right, lessThanOrEqualTo(viewport.right + 0.01));
  expect(bounds.bottom, lessThanOrEqualTo(viewport.bottom + 0.01));
}

void _expectTextEdgeVisible(
  WidgetTester tester,
  Finder text,
  Finder viewport, {
  required bool last,
}) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final offset = last ? paragraph.text.toPlainText().length - 1 : 0;
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: offset + 1),
      )
      .single;
  _expectInside(
    box.toRect().shift(paragraph.localToGlobal(Offset.zero)),
    tester.getRect(viewport),
  );
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
    (name: 'short landscape', size: const Size(800, 360)),
    (name: 'portrait phone', size: const Size(390, 844)),
  ]) {
    testWidgets('${layout.name} initially shows each title and instruction', (
      tester,
    ) async {
      tester.view.physicalSize = layout.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _openGuide(tester);
      for (final step in [
        (title: 'Pick your video', instruction: 'Open a video on this device'),
        (title: 'Bring a friend', instruction: 'Start a room and share'),
        (title: 'Press play together', instruction: 'Once everyone'),
      ]) {
        final viewport = tester.getRect(
          find.byKey(const Key('quick-guide-body')),
        );
        _expectInside(tester.getRect(find.text(step.title)), viewport);
        _expectInside(
          tester.getRect(find.textContaining(step.instruction)),
          viewport,
        );
        final next = find.byKey(const Key('quick-guide-next'));
        expect(next.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(next);
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const Key('quick-guide-sheet')), findsNothing);
    });
  }

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
        final next = find.byKey(const Key('quick-guide-next'));
        expect(next.hitTestable(), findsOneWidget);
        if (step > 1) {
          expect(
            find.byKey(const Key('quick-guide-back')).hitTestable(),
            findsOneWidget,
          );
        }
        if (step < 3) {
          expect(
            find.byKey(const Key('quick-guide-skip')).hitTestable(),
            findsOneWidget,
          );
        }
        final buttonBounds = tester.getRect(next);
        expect(buttonBounds.top, greaterThanOrEqualTo(0));
        expect(
          buttonBounds.bottom,
          lessThanOrEqualTo(layout.size.height - layout.inset),
        );
        final body = find.byKey(const Key('quick-guide-body'));
        await tester.drag(body, const Offset(0, -300));
        await tester.pumpAndSettle();
        expect(
          tester
              .state<ScrollableState>(
                find.descendant(of: body, matching: find.byType(Scrollable)),
              )
              .position
              .pixels,
          greaterThan(0),
        );
        expect(tester.getRect(next), buttonBounds);
        expect(next.hitTestable(), findsOneWidget);
        for (final paragraph in [
          find.textContaining(
            [
              'Open a video on this device',
              'Start a room and share',
              'Once everyone',
            ][step - 1],
          ),
          find.textContaining(
            [
              'Webpages and protected',
              'everyone needs their own copy',
              'one new hosted session per local day',
            ][step - 1],
          ),
        ]) {
          for (final last in [false, true]) {
            await Scrollable.ensureVisible(
              tester.element(paragraph),
              alignment: last ? 1 : 0,
            );
            await tester.pumpAndSettle();
            _expectTextEdgeVisible(tester, paragraph, body, last: last);
            expect(tester.getRect(next), buttonBounds);
            for (final key in [
              'quick-guide-next',
              if (step > 1) 'quick-guide-back',
              if (step < 3) 'quick-guide-skip',
            ]) {
              expect(find.byKey(Key(key)).hitTestable(), findsOneWidget);
            }
          }
        }
        await _tapKey(tester, 'quick-guide-next');
        expect(tester.takeException(), isNull);
      }
      expect(find.byKey(const Key('quick-guide-sheet')), findsNothing);
    });
  }
}
