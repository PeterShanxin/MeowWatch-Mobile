import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:meowwatch_mobile/app/app_controller.dart';
import 'package:meowwatch_mobile/core/billing/billing_service.dart';
import 'package:meowwatch_mobile/core/billing/hosting_access_policy.dart';
import 'package:meowwatch_mobile/core/sync/endpoint_settings.dart';
import 'package:meowwatch_mobile/data/app_repository.dart';

import '../../support/sync_playback_fakes.dart';

class UiTestRepository extends AppRepository {
  UiTestRepository() : super(File('unused-ui-test-history.json'));

  @override
  Future<void> save() async {}
}

class UiTestBilling extends ChangeNotifier implements BillingService {
  bool plus = false;

  @override
  bool get isPlus => plus;
  @override
  bool get isConfigured => true;
  @override
  bool get isBusy => false;
  @override
  CustomerInfo? get customerInfo => null;
  @override
  Stream<CustomerInfo> get customerInfoStream => const Stream.empty();
  @override
  Offering? get currentOffering => null;
  @override
  List<Package> get packages => const [];
  @override
  BillingResult? get lastResult => null;
  @override
  Future<BillingResult> configure() async =>
      const BillingResult(BillingStatus.success);
  @override
  Future<BillingResult> purchase(Package package) async =>
      const BillingResult(BillingStatus.success);
  @override
  Future<BillingResult> refresh() async =>
      const BillingResult(BillingStatus.success);
  @override
  Future<BillingResult> restore() async =>
      const BillingResult(BillingStatus.success);
}

class UiTestHosting implements HostingAccessPolicy {
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

class UiTestApp {
  UiTestApp._(this.controller, this.repository);

  final AppController controller;
  final UiTestRepository repository;

  static UiTestApp create() {
    final repository = UiTestRepository();
    final controller = AppController(
      repository: repository,
      billing: UiTestBilling(),
      hosting: UiTestHosting(),
      phone: SyncTestTarget(),
      endpointSettings: MemoryEndpointSettings(),
    );
    return UiTestApp._(controller, repository);
  }

  Future<void> close() => controller.close();
}
