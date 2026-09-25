import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../integration_test/support/test_text_entry.dart';

void main() {
  testWidgets('profile entry fires onChanged and preserves form validation', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final changes = <String>[];
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: form,
            child: TextFormField(
              key: const Key('entry'),
              controller: controller,
              onChanged: changes.add,
              validator: (value) =>
                  value == 'valid-room' ? null : 'Invalid room',
            ),
          ),
        ),
      ),
    );

    await enterTogetherTestText(
      tester,
      find.byKey(const Key('entry')),
      'room://real-invite',
      profileMode: true,
    );

    expect(controller.text, 'room://real-invite');
    expect(changes, ['room://real-invite']);
    expect(form.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Invalid room'), findsOneWidget);
  });

  testWidgets('profile entry cannot silently fill a read-only field', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            key: const Key('read-only'),
            controller: controller,
            readOnly: true,
          ),
        ),
      ),
    );

    Object? failure;
    try {
      await enterTogetherTestText(
        tester,
        find.byKey(const Key('read-only')),
        'must not appear',
        profileMode: true,
      );
    } catch (error) {
      failure = error;
    }
    expect(failure, isA<TestFailure>());
    expect(controller.text, isEmpty);
  });

  testWidgets('debug entry retains the existing tester input path', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            key: const Key('debug-entry'),
            controller: controller,
          ),
        ),
      ),
    );

    await enterTogetherTestText(
      tester,
      find.byKey(const Key('debug-entry')),
      'Mochi',
      profileMode: false,
    );

    expect(controller.text, 'Mochi');
  });

  for (final profileMode in [false, true]) {
    testWidgets('entry refocuses a retained composer ($profileMode)', (
      tester,
    ) async {
      // Match the integration binding from the first entry: no stub client ID
      // or clearClient callback. The real IME owns that platform channel.
      tester.testTextInput.unregister();
      addTearDown(tester.testTextInput.register);
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final changes = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              key: const Key('composer'),
              controller: controller,
              onChanged: changes.add,
            ),
          ),
        ),
      );
      final field = find.byKey(const Key('composer'));
      await enterTogetherTestText(
        tester,
        field,
        'Ready for movie night!',
        profileMode: profileMode,
      );
      final original = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      await tester.showKeyboard(field);
      controller.clear();
      original.widget.focusNode.unfocus();
      await tester.pump();
      expect(original.widget.focusNode.hasFocus, isFalse);
      expect(tester.binding.focusedEditable, same(original));

      await enterTogetherTestText(
        tester,
        field,
        'https://example.com/movie.mp4',
        profileMode: profileMode,
      );

      expect(tester.state(find.byType(EditableText)), same(original));
      expect(original.widget.focusNode.hasFocus, isTrue);
      expect(controller.text, 'https://example.com/movie.mp4');
      expect(changes, [
        'Ready for movie night!',
        'https://example.com/movie.mp4',
      ]);
    });
  }
}
