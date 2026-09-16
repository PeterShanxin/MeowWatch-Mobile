import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meowwatch_mobile/core/billing/billing_service.dart';
import 'package:meowwatch_mobile/core/billing/revenuecat_billing_service.dart';

const _date = '2026-09-16T10:00:00Z';

Map<String, Object?> customer({
  bool plus = false,
  String entitlement = 'meowwatch_plus',
}) {
  final info = {
    'identifier': entitlement,
    'isActive': plus,
    'willRenew': true,
    'latestPurchaseDate': _date,
    'originalPurchaseDate': _date,
    'productIdentifier': 'test_product',
    'isSandbox': true,
  };
  return {
    'entitlements': {
      'all': {entitlement: info},
      'active': {if (plus) entitlement: info},
    },
    'allPurchaseDates': <String, String>{},
    'activeSubscriptions': <String>[],
    'allPurchasedProductIdentifiers': <String>[],
    'nonSubscriptionTransactions': <Object>[],
    'firstSeen': _date,
    'originalAppUserId': 'test-anonymous-id',
    'allExpirationDates': <String, String>{},
    'requestDate': _date,
  };
}

final _package = {
  'identifier': r'$rc_monthly',
  'packageType': 'MONTHLY',
  'presentedOfferingContext': {'offeringIdentifier': 'test-offering'},
  'product': {
    'identifier': 'test_product',
    'description': 'Test subscription',
    'title': 'Test monthly',
    'price': 2.99,
    'priceString': 'SGD 2.99',
    'currencyCode': 'SGD',
    'subscriptionPeriod': 'P1M',
  },
};

final _offering = {
  'identifier': 'test-offering',
  'serverDescription': 'A test fixture, not a production price',
  'metadata': <String, Object>{},
  'availablePackages': [_package],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('purchases_flutter');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late RevenueCatBillingService billing;
  late List<MethodCall> calls;
  late Map<String, Object?> currentCustomer;
  PlatformException? purchaseError;
  PlatformException? offeringsError;
  Completer<void>? purchaseGate;

  setUp(() {
    calls = [];
    purchaseError = null;
    offeringsError = null;
    purchaseGate = null;
    currentCustomer = customer();
    billing = RevenueCatBillingService(apiKey: 'test_unit_fixture');
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'setupPurchases':
          return null;
        case 'getCustomerInfo':
        case 'restorePurchases':
          return currentCustomer;
        case 'getOfferings':
          if (offeringsError != null) throw offeringsError!;
          return {
            'all': {'test-offering': _offering},
            'current': _offering,
          };
        case 'purchasePackage':
          if (purchaseGate != null) await purchaseGate!.future;
          if (purchaseError != null) throw purchaseError!;
          return {
            'customerInfo': currentCustomer,
            'transaction': {
              'transactionIdentifier': 'fixture-transaction',
              'productIdentifier': 'test_product',
              'purchaseDate': _date,
            },
          };
        default:
          throw StateError('Unexpected SDK method ${call.method}');
      }
    });
  });

  tearDown(() {
    billing.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'missing key and secret key never configure SDK or grant access',
    () async {
      for (final key in ['', 'sk_not_a_client_key']) {
        final disabled = RevenueCatBillingService(apiKey: key);
        expect((await disabled.configure()).status, BillingStatus.unavailable);
        expect(disabled.isPlus, isFalse);
        expect((await disabled.restore()).status, BillingStatus.unavailable);
        disabled.dispose();
      }
      expect(calls, isEmpty);
    },
  );

  test(
    'configure exposes actual offering price and notifies subscribers',
    () async {
      var changes = 0;
      billing.addListener(() => changes++);
      final event = billing.customerInfoStream.first;
      expect((await billing.configure()).succeeded, isTrue);
      expect((await event).originalAppUserId, 'test-anonymous-id');
      expect(changes, greaterThan(0));
      expect(billing.currentOffering!.identifier, 'test-offering');
      expect(billing.packages.single.storeProduct.priceString, 'SGD 2.99');
      expect(billing.isPlus, isFalse);
      await billing.configure();
      expect(
        calls.where((call) => call.method == 'setupPurchases'),
        hasLength(1),
      );
    },
  );

  test(
    'purchase and restore grant access only with active Plus entitlement',
    () async {
      await billing.configure();
      expect(
        (await billing.purchase(billing.packages.single)).succeeded,
        isTrue,
      );
      expect(billing.isPlus, isFalse);
      currentCustomer = customer(plus: true, entitlement: 'another_product');
      await billing.restore();
      expect(billing.isPlus, isFalse);
      currentCustomer = customer(plus: true);
      expect(
        (await billing.purchase(billing.packages.single)).succeeded,
        isTrue,
      );
      expect(billing.isPlus, isTrue);
      currentCustomer = customer();
      await billing.refresh();
      expect(billing.isPlus, isFalse);
      currentCustomer = customer(plus: true);
      expect((await billing.restore()).succeeded, isTrue);
      expect(billing.isPlus, isTrue);
    },
  );

  test('cancellation and store failure never grant access', () async {
    await billing.configure();
    purchaseError = PlatformException(code: '1');
    expect(
      (await billing.purchase(billing.packages.single)).status,
      BillingStatus.cancelled,
    );
    expect(billing.isPlus, isFalse);
    purchaseError = PlatformException(code: '10');
    expect(
      (await billing.purchase(billing.packages.single)).status,
      BillingStatus.failure,
    );
    expect(billing.isPlus, isFalse);
    expect(billing.isBusy, isFalse);
  });

  test(
    'listener revocation updates entitlement and observable stream',
    () async {
      await billing.configure();
      final changed = billing.customerInfoStream.first;
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('Purchases-CustomerInfoUpdated', customer(plus: true)),
        ),
        (_) {},
      );
      await changed;
      expect(billing.isPlus, isTrue);
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('Purchases-CustomerInfoUpdated', customer()),
        ),
        (_) {},
      );
      expect(billing.isPlus, isFalse);
    },
  );

  test(
    'concurrent purchase rejected instead of sending duplicate charges',
    () async {
      await billing.configure();
      purchaseGate = Completer<void>();
      final pending = billing.purchase(billing.packages.single);
      expect(billing.isBusy, isTrue);
      expect(
        (await billing.purchase(billing.packages.single)).status,
        BillingStatus.unavailable,
      );
      purchaseGate!.complete();
      await pending;
      expect(
        calls.where((call) => call.method == 'purchasePackage'),
        hasLength(1),
      );
    },
  );

  test(
    'offerings outage preserves entitlement but clears stale packages',
    () async {
      await billing.configure();
      currentCustomer = customer(plus: true);
      offeringsError = PlatformException(code: '23');
      expect((await billing.refresh()).status, BillingStatus.failure);
      expect(billing.isPlus, isTrue);
      expect(billing.packages, isEmpty);
      offeringsError = null;
      expect((await billing.refresh()).succeeded, isTrue);
      expect(billing.packages, hasLength(1));
    },
  );
}
