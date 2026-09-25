import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/main.dart';

import '../ui/sheets/sheet_test_support.dart';

void main() {
  for (final size in [const Size(430, 932), const Size(640, 360)]) {
    testWidgets('connection overlay uses readable themed text at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final semantics = tester.ensureSemantics();
      final app = createTestApp(billing: TestBilling())..busy = true;
      try {
        await tester.pumpWidget(MainApp(controller: app));
        await tester.pump();

        for (final label in [app.busyLabel, 'Getting everything ready.']) {
          final text = find.text(label);
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: text, matching: find.byType(RichText)),
          );
          final style = paragraph.text.style!;
          expect(style.decoration, isNot(TextDecoration.underline));
          expect(
            style.color,
            Theme.of(tester.element(text)).colorScheme.onSurface,
          );
          expect(style.fontSize, lessThanOrEqualTo(22));
        }
        expect(tester.takeException(), isNull);
        final cancel = find.widgetWithText(TextButton, 'Cancel');
        await tester.ensureVisible(cancel);
        await tester.pump();
        expect(cancel.hitTestable(), findsOneWidget);
        expect(find.bySemanticsLabel('Cancel'), findsOneWidget);
        expect(find.bySemanticsLabel('Join a room'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
        await app.close();
      }
    });
  }
}
