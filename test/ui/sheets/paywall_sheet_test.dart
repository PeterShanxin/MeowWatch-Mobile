import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/billing/billing_service.dart';
import 'package:meowwatch_mobile/main.dart';
import 'package:meowwatch_mobile/ui/paywall/paywall_sheet.dart';

import 'sheet_test_support.dart';

void main() {
  testWidgets('opening Plus can refresh billing with the whole app listening', (
    tester,
  ) async {
    final billing = TestBilling();
    await billing.configure();
    final app = createTestApp(billing: billing);
    await tester.pumpWidget(MainApp(controller: app));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Plus'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(billing.refreshCalls, 1);
    expect(find.text('More movie nights.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await app.close();
  });

  testWidgets('shows store price and returns true only after Plus activates', (
    tester,
  ) async {
    final billing = TestBilling();
    final app = createTestApp(billing: billing);
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showPaywallSheet(context, app: app);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('More movie nights.'), findsOneWidget);
    expect(find.textContaining('SGD 7.77'), findsOneWidget);
    expect(find.textContaining('no real charge'), findsOneWidget);
    expect(billing.configureCalls, 1);

    await tester.ensureVisible(find.textContaining('Continue'));
    await tester.tap(find.textContaining('Continue'));
    await tester.pumpAndSettle();
    expect(billing.purchaseCalls, 1);
    expect(billing.isPlus, isTrue);
    expect(result, isTrue);
    await app.close();
  });

  testWidgets(
    'cancelled purchase stays recoverable and Maybe tomorrow is false',
    (tester) async {
      final billing = TestBilling(purchaseStatus: BillingStatus.cancelled);
      final app = createTestApp(billing: billing);
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showPaywallSheet(context, app: app);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.textContaining('Continue'));
      await tester.tap(find.textContaining('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Purchase cancelled.'), findsOneWidget);
      expect(billing.isPlus, isFalse);
      expect(result, isNull);

      await tester.ensureVisible(find.text('Maybe tomorrow'));
      await tester.tap(find.text('Maybe tomorrow'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      await app.close();
    },
  );
}
