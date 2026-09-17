import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:meowwatch_mobile/app/app_controller.dart';
import 'package:meowwatch_mobile/core/billing/billing_service.dart';
import 'package:meowwatch_mobile/core/billing/hosting_access_policy.dart';
import 'package:meowwatch_mobile/core/sync/endpoint_settings.dart';
import 'package:meowwatch_mobile/data/app_repository.dart';

import '../../support/sync_playback_fakes.dart';

class TestRepository extends AppRepository {
  TestRepository() : super(File('unused-sheet-test-history.json')) {
    displayName = 'Mochi';
  }

  int saves = 0;

  @override
  Future<void> save() async {
    saves++;
  }
}

class TestQuota implements HostingAccessPolicy {
  @override
  Future<bool> canHostNow({String? sessionId}) async => true;

  @override
  Future<int> remainingFreeHostsToday() async => 1;

  @override
  Future<SessionStartResult> recordSessionStarted({
    required String sessionId,
    required bool isCreator,
    required int peerCount,
    required bool synchronizedPlaybackActive,
    bool explicitStart = false,
  }) async => SessionStartResult.freeStarted;
}

class TestEndpointSettings implements EndpointSettings {
  final Map<String, String> values = {};

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async => values[key] = value;
}

class TestBilling extends ChangeNotifier implements BillingService {
  TestBilling({this.plus = false, this.purchaseStatus = BillingStatus.success});

  static final testPackage = Package.fromJson({
    'identifier': r'$rc_monthly',
    'packageType': 'MONTHLY',
    'presentedOfferingContext': {'offeringIdentifier': 'test-offering'},
    'product': {
      'identifier': 'plus_monthly',
      'description': 'Monthly Plus access',
      'title': 'MeowWatch Plus',
      'price': 7.77,
      'priceString': 'SGD 7.77',
      'currencyCode': 'SGD',
      'subscriptionPeriod': 'P1M',
    },
  });

  bool plus;
  BillingStatus purchaseStatus;
  bool grantOnPurchase = true;
  bool grantOnRestore = false;
  BillingResult restoreResult = const BillingResult(BillingStatus.success);
  int configureCalls = 0;
  int refreshCalls = 0;
  int purchaseCalls = 0;
  int restoreCalls = 0;
  bool _configured = false;
  bool _busy = false;
  BillingResult? _lastResult;

  @override
  CustomerInfo? get customerInfo => null;

  @override
  Stream<CustomerInfo> get customerInfoStream => const Stream.empty();

  @override
  Offering? get currentOffering => null;

  @override
  bool get isBusy => _busy;

  @override
  bool get isConfigured => _configured;

  @override
  bool get isPlus => plus;

  @override
  BillingResult? get lastResult => _lastResult;

  @override
  List<Package> get packages => [testPackage];

  @override
  Future<BillingResult> configure() async {
    configureCalls++;
    _configured = true;
    _lastResult = const BillingResult(BillingStatus.success);
    notifyListeners();
    return _lastResult!;
  }

  @override
  Future<BillingResult> refresh() async {
    refreshCalls++;
    _lastResult = const BillingResult(BillingStatus.success);
    notifyListeners();
    return _lastResult!;
  }

  @override
  Future<BillingResult> purchase(Package package) async {
    purchaseCalls++;
    _busy = true;
    notifyListeners();
    await Future<void>.delayed(Duration.zero);
    if (purchaseStatus == BillingStatus.success && grantOnPurchase) plus = true;
    _lastResult = BillingResult(
      purchaseStatus,
      message: purchaseStatus == BillingStatus.cancelled
          ? 'Purchase cancelled.'
          : purchaseStatus == BillingStatus.failure
          ? 'Store unavailable.'
          : null,
    );
    _busy = false;
    notifyListeners();
    return _lastResult!;
  }

  @override
  Future<BillingResult> restore() async {
    restoreCalls++;
    if (grantOnRestore && restoreResult.succeeded) plus = true;
    _lastResult = restoreResult;
    notifyListeners();
    return _lastResult!;
  }
}

AppController createTestApp({
  required TestBilling billing,
  TestRepository? repository,
}) => AppController(
  repository: repository ?? TestRepository(),
  billing: billing,
  hosting: TestQuota(),
  phone: SyncTestTarget(),
  endpointSettings: TestEndpointSettings(),
);
