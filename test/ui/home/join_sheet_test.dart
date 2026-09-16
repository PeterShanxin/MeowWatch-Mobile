import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/ui/join/join_sheet.dart';

import 'ui_test_support.dart';

void main() {
  testWidgets('validates locally and returns the untouched invite', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = UiTestApp.create();
    String? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showJoinSheet(context, app: fixture.controller);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('join-code-field')),
      'meowwatch://wrong?room=movie&server=syncplay.pl&port=8995',
    );
    await tester.tap(find.byKey(const Key('join-submit-button')));
    await tester.pump();
    expect(find.text('This is not a room invitation.'), findsOneWidget);
    expect(fixture.controller.room, isNull);

    const invite =
        'meowwatch://join?room=quiet-otter&server=syncplay.pl&port=8995';
    await tester.enterText(find.byKey(const Key('join-code-field')), invite);
    await tester.tap(find.byKey(const Key('join-submit-button')));
    await tester.pumpAndSettle();
    expect(result, invite);
    expect(fixture.controller.room, isNull);
    await fixture.close();
  });

  testWidgets('keyboard inset keeps the join action in scrollable content', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
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
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showJoinSheet(context, app: fixture.controller),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('join-sheet-scroll-view')), findsOneWidget);
    expect(find.byKey(const Key('join-submit-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await fixture.close();
  });
}
