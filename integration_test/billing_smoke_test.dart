import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meowwatch_mobile/core/billing/billing_service.dart';
import 'package:meowwatch_mobile/core/billing/revenuecat_billing_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart'
    show Purchases, PurchasesErrorCode;

const _apiKey = String.fromEnvironment('REVENUECAT_API_KEY');
const _mode = String.fromEnvironment(
  'REVENUECAT_TEST_MODE',
  defaultValue: 'smoke',
);
const _expectedCustomerHash = String.fromEnvironment(
  'REVENUECAT_EXPECT_CUSTOMER_HASH',
);
const _entitlement = 'meowwatch_plus';
const _product = 'meowwatch_plus_monthly';
const _networkTimeout = Duration(seconds: 60);
const _nativeDialogTimeout = Duration(seconds: 90);

/// Uses the installed Android SDK and live RevenueCat Test Store. Native store
/// dialogs require a human or external adb/UIAutomator interaction; Flutter
/// widget finders cannot address them. Never substitute method-channel stubs.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real RevenueCat Test Store: $_mode',
    (tester) async {
      expect(Platform.isAndroid, isTrue, reason: 'Requires Android runtime.');
      expect(
        _apiKey.startsWith('test_'),
        isTrue,
        reason:
            'Pass a public Test Store key via REVENUECAT_API_KEY. '
            'This test must never initiate a production-store purchase.',
      );
      expect(
        const {'smoke', 'matrix', 'relaunch', 'expired', 'expiry_wait'},
        contains(_mode),
        reason: 'Unsupported REVENUECAT_TEST_MODE.',
      );

      final billing = RevenueCatBillingService(apiKey: _apiKey);
      addTearDown(billing.dispose);
      final customerUpdates = <Map<String, Object?>>[];
      final customerSubscription = billing.customerInfoStream.listen((info) {
        final observation = _customerInfoEvidence(info);
        customerUpdates.add(observation);
        debugPrint('RC_SMOKE_CUSTOMER_UPDATE ${jsonEncode(observation)}');
      });
      addTearDown(customerSubscription.cancel);
      final stage = ValueNotifier<String>(
        'Connecting to RevenueCat Test Store',
      );
      addTearDown(stage.dispose);
      await tester.pumpWidget(_TestSurface(stage: stage));

      final configured = await billing.configure().timeout(_networkTimeout);
      _expectSuccess(
        configured,
        'SDK configuration and initial offering fetch',
      );
      expect(billing.isConfigured, isTrue);
      // A new native process may still have persisted SDK customer cache.
      await _freshCustomer(billing);
      expect(billing.customerInfo, isNotNull);
      final info = billing.customerInfo!;
      expect(info.originalAppUserId, isNotEmpty);
      expect(DateTime.tryParse(info.requestDate), isNotNull);
      expect(billing.currentOffering?.identifier, 'default');

      final monthly = billing.packages.singleWhere(
        (package) => package.identifier == r'$rc_monthly',
        orElse: () =>
            throw TestFailure('No monthly package in default offering.'),
      );
      expect(monthly.packageType, PackageType.monthly);
      expect(monthly.storeProduct.identifier, _product);
      expect(monthly.storeProduct.subscriptionPeriod, 'P1M');
      expect(monthly.storeProduct.price, greaterThan(0));
      expect(monthly.storeProduct.priceString, isNotEmpty);
      expect(monthly.storeProduct.currencyCode, isNotEmpty);

      final customerHash = sha256
          .convert(utf8.encode(info.originalAppUserId))
          .toString();
      final evidence = <String, Object?>{
        'mode': _mode,
        'customerHash': customerHash,
        'offering': billing.currentOffering!.identifier,
        'package': monthly.identifier,
        'product': monthly.storeProduct.identifier,
        'localizedPrice': monthly.storeProduct.priceString,
        'initialPlus': billing.isPlus,
        'customerRequestDate': info.requestDate,
        'startedAtUtc': DateTime.now().toUtc().toIso8601String(),
        'verified': <String>['sdk', 'offering', 'monthly', 'customer_info'],
        'customerUpdates': customerUpdates,
      };
      final verified = evidence['verified']! as List<String>;
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['revenueCatTestStore'] = evidence;
      debugPrint('RC_SMOKE_CATALOG ${jsonEncode(evidence)}');

      if (_mode == 'matrix') {
        expect(
          billing.isPlus,
          isFalse,
          reason:
              'The purchase matrix needs a Test Store customer without '
              'active Plus. Do not delete app data between purchase and relaunch '
              'checks; use a separate test device/install for a new matrix.',
        );

        _expectSuccess(
          await billing.restore().timeout(_networkTimeout),
          'restore without an active entitlement',
        );
        expect(billing.isPlus, isFalse);
        verified.add('restore_without_plus');

        for (final expected in [
          BillingStatus.cancelled,
          BillingStatus.failure,
        ]) {
          final outcome = expected == BillingStatus.cancelled
              ? 'cancel'
              : 'failure';
          final result = await _nativePurchase(
            tester,
            stage,
            billing,
            monthly,
            outcome,
          );
          expect(
            result.status,
            expected,
            reason: 'Native $outcome result mismatch.',
          );
          if (expected == BillingStatus.failure) {
            expect(
              result.errorCode,
              PurchasesErrorCode.testStoreSimulatedPurchaseError.index
                  .toString(),
              reason:
                  'Only the native Test Store simulated failure counts; '
                  'a network/plugin failure must fail this scenario.',
            );
          }
          expect(billing.isPlus, isFalse);
          await _freshCustomer(billing);
          expect(billing.isPlus, isFalse);
          expect(_customerHash(billing), customerHash);
          evidence['${outcome}ErrorCode'] = result.errorCode;
          verified.add('native_$outcome');
        }

        final purchased = await _nativePurchase(
          tester,
          stage,
          billing,
          monthly,
          'success',
        );
        _expectSuccess(purchased, 'native Test Store purchase');
        _expectActivePlus(billing);
        evidence['purchasedEntitlement'] = _entitlementEvidence(billing);
        verified.add('purchase_activates_plus');
        await _freshCustomer(billing);
        _expectActivePlus(billing);
        expect(_customerHash(billing), customerHash);
        verified.add('server_refresh_keeps_plus');

        _expectSuccess(
          await billing.restore().timeout(_networkTimeout),
          'restore after Test Store purchase',
        );
        _expectActivePlus(billing);
        expect(_customerHash(billing), customerHash);
        verified.add('restore_with_plus');
        evidence['expirationDate'] = billing
            .customerInfo!
            .entitlements
            .active[_entitlement]!
            .expirationDate;
      } else if (_mode == 'relaunch' ||
          _mode == 'expired' ||
          _mode == 'expiry_wait') {
        expect(
          _expectedCustomerHash,
          matches(RegExp(r'^[a-f0-9]{64}$')),
          reason:
              'Pass REVENUECAT_EXPECT_CUSTOMER_HASH from the earlier matrix '
              'result to prevent a fresh anonymous customer passing this check.',
        );
        expect(customerHash, _expectedCustomerHash);

        var expiryPending = false;
        if (_mode == 'expiry_wait') {
          // Each segment fits the unchanged ten-minute host driver. The host
          // enforces the overall wait and never treats a pending segment as
          // expiration acceptance. Every observation comes from the real SDK.
          final observations = <Map<String, Object?>>[];
          evidence['expiryObservations'] = observations;
          final waiting = Stopwatch()..start();
          do {
            await _freshCustomer(billing);
            expect(_customerHash(billing), customerHash);
            final observation = _entitlementEvidence(billing);
            observations.add(observation);
            debugPrint(
              'RC_SMOKE_EXPIRY_OBSERVATION ${jsonEncode(observation)}',
            );
            if (!billing.isPlus) break;
            _expectActivePlus(billing);
            if (waiting.elapsed >= const Duration(minutes: 3)) break;
            stage.value =
                'Waiting for real Test Store expiration\n'
                'Plus is still active; ${observations.length} fresh SDK checks';
            await tester.pump();
            await Future<void>.delayed(const Duration(seconds: 30));
          } while (true);
          waiting.stop();
          expiryPending = billing.isPlus;
          evidence['expiryPending'] = expiryPending;
          verified.add('expiry_polling_fresh_customer');
        }

        if (_mode == 'relaunch') {
          _expectActivePlus(billing);
          verified.add('same_customer_plus_after_process_relaunch');
        } else if (!expiryPending) {
          // `expired` remains an immediate strict assertion, with no wait or
          // active-entitlement fallback.
          _expectExpiredPlus(billing);
          verified.add('same_customer_entitlement_expired');
          evidence['expiredEntitlement'] = _entitlementEvidence(billing);
          evidence['expirationDate'] = billing
              .customerInfo!
              .entitlements
              .all[_entitlement]!
              .expirationDate;
        }

        if (!expiryPending) {
          // Test Store restore queries customer info, not platform history.
          await Purchases.invalidateCustomerInfoCache().timeout(
            _networkTimeout,
          );
          verified.add('restore_cache_invalidated');
          _expectSuccess(
            await billing.restore().timeout(_networkTimeout),
            'restore in $_mode state',
          );
          // Retain the real SDK response even when the strict state assertion
          // fails, so a renewal can be distinguished from a stale callback.
          evidence['restoredEntitlement'] = _entitlementEvidence(billing);
          debugPrint(
            'RC_SMOKE_RESTORE_OBSERVATION '
            '${jsonEncode(evidence['restoredEntitlement'])}',
          );
          expect(billing.isPlus, _mode == 'relaunch');
          expect(_customerHash(billing), customerHash);
          if (_mode != 'relaunch') _expectExpiredPlus(billing);
          verified.add(
            _mode == 'relaunch' ? 'restore_relaunch' : 'restore_expired',
          );
        }
      }

      evidence['finalPlus'] = billing.isPlus;
      evidence['completedAtUtc'] = DateTime.now().toUtc().toIso8601String();
      stage.value = evidence['expiryPending'] == true
          ? 'Still waiting for real expiration; no expiry pass recorded'
          : 'RevenueCat $_mode checks passed';
      await tester.pump();
      // Persist stdout in the host run evidence; reportData is also available
      // to an integration_test driver. Neither contains the public SDK key.
      debugPrint('RC_SMOKE_RESULT ${jsonEncode(evidence)}');
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

void _expectSuccess(BillingResult result, String operation) {
  expect(
    result.status,
    BillingStatus.success,
    reason:
        '$operation: ${result.status.name}, '
        '${result.errorCode ?? 'no SDK error code'}, ${result.message ?? ''}',
  );
}

String _customerHash(RevenueCatBillingService billing) => sha256
    .convert(utf8.encode(billing.customerInfo!.originalAppUserId))
    .toString();

void _expectActivePlus(RevenueCatBillingService billing) {
  expect(billing.isPlus, isTrue);
  final entitlement = billing.customerInfo!.entitlements.active[_entitlement];
  expect(entitlement, isNotNull);
  expect(entitlement!.isActive, isTrue);
  expect(entitlement.isSandbox, isTrue);
  expect(entitlement.productIdentifier, _product);
}

void _expectExpiredPlus(RevenueCatBillingService billing) {
  expect(billing.isPlus, isFalse);
  final entitlement = billing.customerInfo!.entitlements.all[_entitlement];
  expect(
    entitlement,
    isNotNull,
    reason: 'Must be a previously purchased entitlement.',
  );
  expect(entitlement!.isActive, isFalse);
  expect(entitlement.isSandbox, isTrue);
  expect(entitlement.productIdentifier, _product);
  final expiration = DateTime.tryParse(entitlement.expirationDate ?? '');
  expect(expiration, isNotNull);
  expect(expiration!.isBefore(DateTime.now().toUtc()), isTrue);
  final requested = DateTime.parse(billing.customerInfo!.requestDate);
  expect(expiration.isAfter(requested), isFalse);
}

Map<String, Object?> _entitlementEvidence(RevenueCatBillingService billing) {
  final info = billing.customerInfo!;
  final entitlement = info.entitlements.all[_entitlement];
  expect(entitlement, isNotNull, reason: 'Purchased entitlement must persist.');
  return _customerInfoEvidence(info);
}

Map<String, Object?> _customerInfoEvidence(CustomerInfo info) {
  final entitlement = info.entitlements.all[_entitlement];
  return <String, Object?>{
    'customerHash': sha256
        .convert(utf8.encode(info.originalAppUserId))
        .toString(),
    'customerRequestDate': info.requestDate,
    'observedAtUtc': DateTime.now().toUtc().toIso8601String(),
    'identifier': entitlement?.identifier,
    'productIdentifier': entitlement?.productIdentifier,
    'isActive': entitlement?.isActive,
    'isSandbox': entitlement?.isSandbox,
    'originalPurchaseDate': entitlement?.originalPurchaseDate,
    'latestPurchaseDate': entitlement?.latestPurchaseDate,
    'expirationDate': entitlement?.expirationDate,
  };
}

Future<void> _freshCustomer(RevenueCatBillingService billing) async {
  await Purchases.invalidateCustomerInfoCache().timeout(_networkTimeout);
  _expectSuccess(
    await billing.refresh().timeout(_networkTimeout),
    'fresh customer info',
  );
}

Future<BillingResult> _nativePurchase(
  WidgetTester tester,
  ValueNotifier<String> stage,
  RevenueCatBillingService billing,
  Package package,
  String outcome,
) async {
  stage.value = 'Choose $outcome in the native RevenueCat Test Store dialog';
  await tester.pump();
  debugPrint('RC_SMOKE_STAGE $outcome');
  return billing
      .purchase(package)
      .timeout(
        _nativeDialogTimeout,
        onTimeout: () => throw TestFailure(
          'No native $outcome response within ${_nativeDialogTimeout.inSeconds}s. '
          'Inspect the device with adb/UIAutomator and choose the matching Test Store '
          'button; Flutter widget finders cannot control the native dialog.',
        ),
      );
}

class _TestSurface extends StatelessWidget {
  const _TestSurface({required this.stage});
  final ValueListenable<String> stage;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      appBar: AppBar(title: const Text('RevenueCat Test Store verification')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ValueListenableBuilder<String>(
            valueListenable: stage,
            builder: (_, value, _) => Text(value, textAlign: TextAlign.center),
          ),
        ),
      ),
    ),
  );
}
