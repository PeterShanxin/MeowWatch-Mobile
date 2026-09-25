import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'sibling conflicts preserve labels, actions and traversal',
    (WidgetTester tester) async {
      final showMore = ValueNotifier<bool>(false);
      addTearDown(showMore.dispose);
      var playTaps = 0;
      var moreTaps = 0;

      // Keep this fragment cached while its sibling gains or loses a tap action.
      final primary = Semantics(
        label: 'Play',
        button: true,
        onTap: () => playTaps++,
        explicitChildNodes: true,
        child: const SizedBox(width: 120, height: 40, child: Text('Details')),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: Semantics(
              container: true,
              child: ValueListenableBuilder<bool>(
                valueListenable: showMore,
                child: primary,
                builder: (context, visible, child) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    child!,
                    if (visible)
                      Semantics(
                        label: 'More',
                        button: true,
                        onTap: () => moreTaps++,
                        child: const SizedBox(width: 120, height: 40),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      SemanticsNode onlyNode(String label) {
        final finder = find.semantics.byLabel(label);
        expect(finder, findsOne);
        return finder.evaluate().single;
      }

      final detailsId = onlyNode('Details').id;
      void checkState(bool visible) {
        expect(tester.takeException(), isNull);
        final play = onlyNode('Play');
        final details = onlyNode('Details');
        expect(
          play,
          matchesSemantics(
            label: 'Play',
            textDirection: TextDirection.ltr,
            isButton: true,
            hasTapAction: true,
            children: <Matcher>[
              matchesSemantics(
                label: 'Details',
                textDirection: TextDirection.ltr,
              ),
            ],
          ),
        );
        expect(details.id, detailsId);
        expect(details.attached, isTrue);
        expect(details.parent, same(play));
        expect(
          tester.semantics.simulatedAccessibilityTraversal().map(
            (node) => node.label,
          ),
          orderedEquals(<String>['Play', 'Details', if (visible) 'More']),
        );
        final moreFinder = find.semantics.byLabel('More');
        if (visible) {
          expect(
            onlyNode('More'),
            matchesSemantics(
              label: 'More',
              textDirection: TextDirection.ltr,
              isButton: true,
              hasTapAction: true,
            ),
          );
        } else {
          expect(moreFinder, findsNothing);
        }
        final previousPlayTaps = playTaps;
        final previousMoreTaps = moreTaps;
        tester.semantics.tap(find.semantics.byLabel('Play'));
        expect(playTaps, previousPlayTaps + 1);
        expect(moreTaps, previousMoreTaps);
        if (visible) {
          tester.semantics.tap(moreFinder);
          expect(moreTaps, previousMoreTaps + 1);
          expect(playTaps, previousPlayTaps + 1);
        }
      }

      checkState(false);
      for (var round = 0; round < 2; round++) {
        showMore.value = true;
        await tester.pumpAndSettle();
        checkState(true);
        showMore.value = false;
        await tester.pumpAndSettle();
        checkState(false);
      }
      expect(playTaps, 5);
      expect(moreTaps, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
    semanticsEnabled: true,
  );
}
