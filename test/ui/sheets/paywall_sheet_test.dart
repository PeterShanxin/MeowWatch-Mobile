import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/app/app_controller.dart';
import 'package:meowwatch_mobile/core/billing/billing_service.dart';
import 'package:meowwatch_mobile/main.dart';
import 'package:meowwatch_mobile/ui/paywall/paywall_sheet.dart';
import 'package:purchases_flutter/purchases_flutter.dart'
    show SubscriptionOption, Period, PeriodUnit;

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
    expect(find.text('Continue · SGD 7.77 / month'), findsOneWidget);
    expect(find.textContaining('accelerated schedule'), findsOneWidget);
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

  for (final (type, iso, expected) in [
    (PackageType.annual, null, 'year'),
    (PackageType.sixMonth, null, '6 months'),
    (PackageType.threeMonth, null, '3 months'),
    (PackageType.twoMonth, null, '2 months'),
    (PackageType.weekly, null, 'week'),
    (PackageType.custom, 'P10D', '10 days'),
    (PackageType.monthly, 'P2W', '2 weeks'),
  ]) {
    testWidgets(
      'store period $iso and package $type have accurate billing units',
      (tester) async {
        final billing = _PlansBilling([_package(type: type, period: iso)]);
        final app = createTestApp(billing: billing);
        await _open(tester, app: app);
        expect(find.text('Continue · €12,34 / $expected'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await app.close();
      },
    );
  }

  testWidgets('unknown terms are not presented as monthly or auto-renewing', (
    tester,
  ) async {
    final billing = _PlansBilling([_package(type: PackageType.custom)]);
    final app = createTestApp(billing: billing);
    await _open(tester, app: app);
    expect(find.text('Continue · €12,34'), findsOneWidget);
    expect(find.textContaining('Review the billing period'), findsOneWidget);
    expect(find.textContaining('/ month'), findsNothing);
    expect(find.textContaining('accelerated schedule'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await app.close();
  });

  testWidgets('prepaid and lifetime plans do not claim automatic renewal', (
    tester,
  ) async {
    for (final plan in [
      _package(type: PackageType.custom, period: 'P3M', prepaid: true),
      _package(type: PackageType.lifetime),
    ]) {
      final billing = _PlansBilling([plan]);
      final app = createTestApp(billing: billing);
      await _open(tester, app: app);
      if (plan.packageType == PackageType.lifetime) {
        expect(find.text('Continue · €12,34 once'), findsOneWidget);
        expect(
          find.text('One-time purchase. No recurring subscription.'),
          findsOneWidget,
        );
      } else {
        expect(find.text('Continue · €12,34 for 3 months'), findsOneWidget);
        expect(
          find.textContaining('Does not renew automatically.'),
          findsOneWidget,
        );
      }
      expect(find.textContaining('accelerated schedule'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await app.close();
    }
  });

  testWidgets(
    'multiple plans expose one accessible selection and purchase the chosen package',
    (tester) async {
      final monthly = _package(type: PackageType.monthly, id: 'monthly');
      final yearly = _package(type: PackageType.annual, id: 'yearly');
      final billing = _PlansBilling([monthly, yearly]);
      final app = createTestApp(billing: billing);
      final semantics = tester.ensureSemantics();
      await _open(tester, app: app);
      expect(find.text('Choose your plan'), findsOneWidget);
      final annual = find.byKey(const ValueKey('plan-yearly'));
      await tester.ensureVisible(annual);
      await tester.tap(annual);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(annual),
        matchesSemantics(
          hasCheckedState: true,
          isChecked: true,
          isInMutuallyExclusiveGroup: true,
          hasEnabledState: true,
          isEnabled: true,
          hasSelectedState: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
          label: 'Yearly\n€12,34 / year',
          textDirection: TextDirection.ltr,
        ),
      );
      final button = find.text('Continue · €12,34 / year');
      expect(find.textContaining('Continue'), findsOneWidget);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(billing.purchased, same(yearly));
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await app.close();
    },
  );

  for (final (size, scale) in [
    (const Size(320, 568), 2.0),
    (const Size(393, 852), 1.0),
    (const Size(768, 1024), 2.0),
  ]) {
    testWidgets(
      'purchase restore and dismiss remain reachable at $size and ${scale}x text',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final billing = _PlansBilling([
          _package(type: PackageType.monthly),
          _package(type: PackageType.annual, id: 'annual'),
        ])..purchaseStatus = BillingStatus.cancelled;
        final app = createTestApp(billing: billing);
        await _open(tester, app: app, scale: scale, bottomPadding: 34);
        expect(tester.takeException(), isNull);
        expect(find.byTooltip('Close').hitTestable(), findsOneWidget);
        final continueButton = find.textContaining('Continue');
        await tester.ensureVisible(continueButton);
        await tester.tap(continueButton);
        await tester.pumpAndSettle();
        expect(billing.purchaseCalls, 1);
        await tester.ensureVisible(find.text('Restore purchases'));
        await tester.tap(find.text('Restore purchases'));
        await tester.pumpAndSettle();
        expect(billing.restoreCalls, 1);
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -2000),
        );
        await tester.pumpAndSettle();
        final dismiss = find.text('Maybe tomorrow');
        expect(dismiss.hitTestable(), findsOneWidget);
        expect(
          tester.getBottomRight(dismiss).dy,
          lessThanOrEqualTo(size.height - 34),
        );
        expect(find.byTooltip('Close').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(dismiss);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await app.close();
      },
    );
  }
}

class _PlansBilling extends TestBilling {
  _PlansBilling(this.plans);
  final List<Package> plans;
  Package? purchased;
  @override
  List<Package> get packages => plans;
  @override
  Future<BillingResult> purchase(Package package) {
    purchased = package;
    return super.purchase(package);
  }
}

Package _package({
  required PackageType type,
  String? period,
  String id = 'plan',
  bool prepaid = false,
}) => Package(
  id,
  type,
  StoreProduct(
    'product-$id',
    'Store description',
    'Store plan',
    12.34,
    '€12,34',
    'EUR',
    subscriptionPeriod: period,
    defaultOption: prepaid
        ? const SubscriptionOption(
            'prepaid',
            'product',
            'product',
            [],
            [],
            true,
            Period(PeriodUnit.month, 3, 'P3M'),
            true,
            null,
            null,
            null,
            null,
            null,
          )
        : null,
  ),
  TestBilling.testPackage.presentedOfferingContext,
);

Future<void> _open(
  WidgetTester tester, {
  required AppController app,
  double scale = 1,
  double bottomPadding = 0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          padding: EdgeInsets.only(bottom: bottomPadding),
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showPaywallSheet(context, app: app),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}
