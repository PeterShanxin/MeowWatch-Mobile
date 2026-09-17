// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE.flutter file.
// Extracted from Flutter PR #190431 at the commit recorded in provenance.json.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'toggling an overlay child does not leave a parentless attached semantics node',
    (WidgetTester tester) async {
      final controller = OverlayPortalController();
      final siblingController = OverlayPortalController();

      // The second anchor is required: its conflict changes when the other
      // portal is toggled. Keep this structure identical to the upstream case.
      final Widget sibling = OverlayPortal.overlayChildLayoutBuilder(
        controller: siblingController,
        overlayChildBuilder:
            (BuildContext context, OverlayChildLayoutInfo info) =>
                const SizedBox.shrink(),
        child: Semantics(
          explicitChildNodes: true,
          child: const Text('sibling'),
        ),
      );

      Widget portal = OverlayPortal.overlayChildLayoutBuilder(
        controller: controller,
        overlayChildBuilder:
            (BuildContext context, OverlayChildLayoutInfo info) => const Align(
              alignment: Alignment.topLeft,
              child: Text('overlay child'),
            ),
        child: Semantics(explicitChildNodes: true, child: const Text('anchor')),
      );
      portal = Overlay.wrap(child: ExcludeSemantics(child: portal));
      portal = SizedBox(width: 200, height: 100, child: portal);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Overlay(
            initialEntries: <OverlayEntry>[
              OverlayEntry(
                builder: (BuildContext context) => Semantics(
                  container: true,
                  child: Column(children: <Widget>[sibling, portal]),
                ),
              ),
            ],
          ),
        ),
      );

      // Upstream reports corruption becomes observable on the second round trip.
      for (var i = 0; i < 2; i += 1) {
        controller.show();
        await tester.pumpAndSettle();
        expect(find.text('overlay child'), findsOneWidget);

        controller.hide();
        await tester.pumpAndSettle();
        expect(find.text('overlay child'), findsNothing);
      }
    },
    semanticsEnabled: true,
  );
}
