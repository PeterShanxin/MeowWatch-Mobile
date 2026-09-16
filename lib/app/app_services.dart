import 'package:flutter/foundation.dart';

import '../core/billing/file_hosting_quota_store.dart';
import '../core/billing/hosting_access_policy.dart';
import '../core/billing/revenuecat_billing_service.dart';
import '../core/playback/local_mobile_target.dart';
import '../data/app_repository.dart';
import 'app_controller.dart';

/// Public client configuration for the Shipaton Test Store build. This key
/// cannot access RevenueCat administration or charge a real payment method.
const revenueCatPublicKey = String.fromEnvironment(
  'REVENUECAT_API_KEY',
  defaultValue: kDebugMode ? 'test_gjKDzmyNmHmuDfibegUnKQKTpRh' : '',
);
bool get usesTestStore => revenueCatPublicKey.startsWith('test_');

Future<AppController> openAppServices() async {
  final repository = await AppRepository.open();
  final store = await FileHostingQuotaStore.inApplicationSupport();
  final billing = RevenueCatBillingService(apiKey: revenueCatPublicKey);
  return AppController(
    repository: repository,
    billing: billing,
    hosting: LocalHostingAccessPolicy(
      store: store,
      isPlus: () => billing.isPlus,
    ),
    phone: LocalMobileTarget(),
  );
}
