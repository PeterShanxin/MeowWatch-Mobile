import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'billing_service.dart';

/// Own one instance for the app lifetime; refresh when resuming the app and
/// before presenting the paywall. RevenueCat listeners are not server pushes.
class RevenueCatBillingService extends ChangeNotifier
    implements BillingService {
  RevenueCatBillingService({
    String apiKey = const String.fromEnvironment('REVENUECAT_API_KEY'),
  }) : _apiKey = apiKey.trim();

  static const plusEntitlement = 'meowwatch_plus';
  final String _apiKey;
  final _customerInfoController = StreamController<CustomerInfo>.broadcast();
  CustomerInfo? _customerInfo;
  Offering? _currentOffering;
  BillingResult? _lastResult;
  bool _configured = false;
  bool _busy = false;
  bool _disposed = false;

  @override
  Stream<CustomerInfo> get customerInfoStream => _customerInfoController.stream;
  @override
  CustomerInfo? get customerInfo => _customerInfo;
  @override
  bool get isPlus =>
      _customerInfo?.entitlements.active[plusEntitlement]?.isActive == true;
  @override
  bool get isConfigured => _configured;
  @override
  bool get isBusy => _busy;
  @override
  Offering? get currentOffering => _currentOffering;
  @override
  List<Package> get packages =>
      List.unmodifiable(_currentOffering?.availablePackages ?? <Package>[]);
  @override
  BillingResult? get lastResult => _lastResult;

  void _onCustomerInfo(CustomerInfo info) {
    if (_disposed) return;
    _customerInfo = info;
    _customerInfoController.add(info);
    notifyListeners();
  }

  @override
  Future<BillingResult> configure() => _run(() async {
    if (_apiKey.isEmpty) {
      return const BillingResult(
        BillingStatus.unavailable,
        message: 'Purchases are not available in this build.',
        errorCode: 'missing_public_sdk_key',
      );
    }
    if (_apiKey.startsWith('sk_')) {
      return const BillingResult(
        BillingStatus.unavailable,
        message: 'Purchases could not be configured.',
        errorCode: 'server_key_not_allowed',
      );
    }
    if (!_configured) {
      await Purchases.configure(PurchasesConfiguration(_apiKey));
      _configured = true;
      if (_disposed) {
        return const BillingResult(BillingStatus.unavailable);
      }
      Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);
    }
    return _refresh();
  });

  Future<BillingResult> _refresh() async {
    _onCustomerInfo(await Purchases.getCustomerInfo());
    // Clear stale prices before loading. A failed fetch must not sell an old
    // offering after a dashboard change.
    _currentOffering = null;
    _currentOffering = (await Purchases.getOfferings()).current;
    return const BillingResult(BillingStatus.success);
  }

  @override
  Future<BillingResult> refresh() => _run(_refresh, needsConfiguration: true);

  @override
  Future<BillingResult> purchase(Package package) => _run(() async {
    final result = await Purchases.purchase(PurchaseParams.package(package));
    _onCustomerInfo(result.customerInfo);
    return const BillingResult(BillingStatus.success);
  }, needsConfiguration: true);

  @override
  Future<BillingResult> restore() => _run(() async {
    _onCustomerInfo(await Purchases.restorePurchases());
    return const BillingResult(BillingStatus.success);
  }, needsConfiguration: true);

  Future<BillingResult> _run(
    Future<BillingResult> Function() action, {
    bool needsConfiguration = false,
  }) async {
    if (_disposed || _busy) {
      return const BillingResult(
        BillingStatus.unavailable,
        message: 'Please wait for the current purchase operation to finish.',
        errorCode: 'billing_not_ready',
      );
    }
    if (needsConfiguration && !_configured) {
      _lastResult = const BillingResult(
        BillingStatus.unavailable,
        message: 'Purchases are not available in this build.',
        errorCode: 'billing_not_configured',
      );
      notifyListeners();
      return _lastResult!;
    }
    _busy = true;
    notifyListeners();
    try {
      _lastResult = await action();
    } on PlatformException catch (error) {
      final cancelled =
          error.code ==
          PurchasesErrorCode.purchaseCancelledError.index.toString();
      _lastResult = BillingResult(
        cancelled ? BillingStatus.cancelled : BillingStatus.failure,
        message: cancelled
            ? 'Purchase cancelled.'
            : 'The store could not complete this request. Please try again.',
        errorCode: error.code,
      );
    } on Exception {
      _lastResult = const BillingResult(
        BillingStatus.failure,
        message: 'Purchases are temporarily unavailable. Please try again.',
        errorCode: 'billing_unavailable',
      );
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
    return _lastResult!;
  }

  @override
  void dispose() {
    _disposed = true;
    if (_configured) {
      Purchases.removeCustomerInfoUpdateListener(_onCustomerInfo);
    }
    unawaited(_customerInfoController.close());
    super.dispose();
  }
}
