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

  for (final input in ['', 'movie@host:notaport']) {
    testWidgets(
      'invalid submission reveals feedback above the landscape keyboard: $input',
      (tester) async {
        tester.view.physicalSize = const Size(800, 360);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(top: 24);
        tester.view.viewInsets = const FakeViewPadding(bottom: 230);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewInsets);
        final fixture = UiTestApp.create();
        String? result;

        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () async {
                      result = await showJoinSheet(
                        context,
                        app: fixture.controller,
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();

          final field = find.byKey(const Key('join-code-field'));
          await tester.enterText(field, input);
          await tester.pumpAndSettle();
          final editable = find.descendant(
            of: field,
            matching: find.byType(EditableText),
          );
          final submit = find.byKey(const Key('join-submit-button'));
          await tester.ensureVisible(submit);
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
          expect(submit.hitTestable(), findsOneWidget);
          expect(editable.hitTestable(), findsNothing);

          await tester.tap(submit);
          await tester.pumpAndSettle();

          final error = find.text(
            input.isEmpty
                ? 'Enter the room code your friend shared.'
                : 'That code looks off — ask your friend to copy and paste it again.',
          );
          final viewport = tester.getRect(
            find
                .descendant(
                  of: find.byKey(const Key('join-sheet-scroll-view')),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          final visible = viewport.intersect(
            const Rect.fromLTRB(0, 24, 800, 130),
          );
          final errorBounds = tester.getRect(error);
          expect(errorBounds.top, greaterThanOrEqualTo(visible.top));
          expect(errorBounds.bottom, lessThanOrEqualTo(visible.bottom));
          expect(errorBounds.left, greaterThanOrEqualTo(visible.left));
          expect(errorBounds.right, lessThanOrEqualTo(visible.right));
          expect(error.hitTestable(), findsOneWidget);
          expect(
            visible.contains(tester.getCenter(editable)),
            isTrue,
            reason:
                'Editable ${tester.getRect(editable)}, error $errorBounds, '
                'field ${tester.getRect(field)}, visible $visible',
          );
          expect(editable.hitTestable(), findsOneWidget);
          final editableBounds = tester.getRect(editable);
          expect(editableBounds.top, greaterThanOrEqualTo(visible.top));
          expect(editableBounds.bottom, lessThanOrEqualTo(visible.bottom));
          expect(
            tester.getSize(find.byKey(const Key('paste-invite-button'))).height,
            greaterThanOrEqualTo(48),
          );
          expect(tester.widget<TextField>(field).controller!.text, input);
          expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
          expect(result, isNull);
          expect(fixture.controller.room, isNull);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await fixture.close();
        }
      },
    );
  }

  testWidgets('header retains accessible and drag dismissal', (tester) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 230);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final fixture = UiTestApp.create();
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    showJoinSheet(context, app: fixture.controller),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final handle = find.byKey(const Key('join-sheet-dismiss'));
      await tester.ensureVisible(handle);
      await tester.pumpAndSettle();
      final node = tester.getSemantics(handle);
      expect(
        node,
        matchesSemantics(
          label: 'Dismiss',
          textDirection: TextDirection.ltr,
          isButton: true,
          hasTapAction: true,
        ),
      );
      expect(tester.getSize(handle), const Size(48, 48));
      tester.semantics.tap(
        find.semantics.byPredicate((candidate) => candidate.id == node.id),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('join-code-field')), findsNothing);
      expect(fixture.controller.room, isNull);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(handle);
      await tester.pumpAndSettle();
      final handleBounds = tester.getRect(handle);
      expect(
        const Rect.fromLTRB(0, 0, 800, 130).contains(handleBounds.center),
        isTrue,
      );
      // The enclosing BottomSheet, rather than this semantic child, owns dragging.
      await tester.flingFrom(handleBounds.center, const Offset(0, 100), 1000);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('join-code-field')), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
      await fixture.close();
    }
  });

  testWidgets(
    'incoming invite is visibly prefilled and requires confirmation',
    (tester) async {
      final fixture = UiTestApp.create();
      const invite =
          'meowwatch://join?room=quiet-otter&server=syncplay.pl&port=8995';
      String? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showJoinSheet(
                    context,
                    app: fixture.controller,
                    initialInvite: invite,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Room invitation received'), findsOneWidget);
      expect(find.text('Room: quiet-otter'), findsOneWidget);
      expect(find.text('Server: syncplay.pl:8995'), findsOneWidget);
      expect(find.text('Join this room'), findsOneWidget);
      expect(result, isNull);
      expect(fixture.controller.room, isNull);

      await tester.tap(find.byKey(const Key('join-submit-button')));
      await tester.pumpAndSettle();
      expect(result, invite);
      expect(fixture.controller.room, isNull);
      await fixture.close();
    },
  );

  testWidgets('an invite carrying a direct video shows it before joining', (
    tester,
  ) async {
    final fixture = UiTestApp.create();
    const invite =
        'meowwatch://join?room=quiet-otter&server=syncplay.pl&port=8995'
        '&video=https%3A%2F%2Fvideo.example%2Fmovie.mp4';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showJoinSheet(
                context,
                app: fixture.controller,
                initialInvite: invite,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Room: quiet-otter'), findsOneWidget);
    expect(find.text('Video: video.example/movie.mp4'), findsOneWidget);
    await fixture.close();
  });

  testWidgets(
    'an invite with no video, or an invalid one, shows no video line',
    (tester) async {
      final fixture = UiTestApp.create();
      for (final invite in [
        'meowwatch://join?room=quiet-otter&server=syncplay.pl&port=8995',
        'meowwatch://join?room=quiet-otter&server=syncplay.pl&port=8995'
            '&video=not+a+direct+link',
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showJoinSheet(
                    context,
                    app: fixture.controller,
                    initialInvite: invite,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Room: quiet-otter'), findsOneWidget);
        expect(find.textContaining('Video:'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      }
      await fixture.close();
    },
  );
}
