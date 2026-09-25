import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

export 'package:purchases_flutter/purchases_flutter.dart'
    show CustomerInfo, Offering, Package, PackageType, StoreProduct;

enum BillingStatus { success, cancelled, failure, unavailable }

class BillingResult {
  const BillingResult(this.status, {this.message, this.errorCode});

  final BillingStatus status;
  final String? message;
  final String? errorCode;

  bool get succeeded => status == BillingStatus.success;
}

/// A successful transaction alone does not grant Plus: always read [isPlus].
abstract interface class BillingService implements Listenable {
  Future<BillingResult> configure();
  Stream<CustomerInfo> get customerInfoStream;
  CustomerInfo? get customerInfo;
  bool get isPlus;
  bool get isConfigured;
  bool get isBusy;
  Offering? get currentOffering;
  List<Package> get packages;
  BillingResult? get lastResult;
  Future<BillingResult> refresh();
  Future<BillingResult> purchase(Package package);
  Future<BillingResult> restore();
  void dispose();
}
