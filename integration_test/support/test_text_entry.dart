import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Enters test text through the focused field and verifies what the UI retained.
///
/// Flutter 3.44's integration binding uses a real IME. WidgetTester.enterText
/// sends client ID -1, which Flutter accepts only with debug asserts enabled.
Future<void> enterTogetherTestText(
  WidgetTester tester,
  Finder field,
  String text, {
  bool profileMode = kProfileMode,
}) async {
  if (profileMode) {
    await tester.showKeyboard(field);
    final editable = tester.state<EditableTextState>(
      find.descendant(
        of: field,
        matching: find.byType(EditableText),
        matchRoot: true,
      ),
    );
    expect(editable.widget.focusNode.hasFocus, isTrue);
    editable.updateEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );
    await tester.pump();
  } else {
    await tester.enterText(field, text);
  }

  final editable = tester.widget<EditableText>(
    find.descendant(
      of: field,
      matching: find.byType(EditableText),
      matchRoot: true,
    ),
  );
  expect(
    editable.controller.text,
    text,
    reason: 'The focused production text field did not retain test input.',
  );
}
