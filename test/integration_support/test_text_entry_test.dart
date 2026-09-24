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
}
