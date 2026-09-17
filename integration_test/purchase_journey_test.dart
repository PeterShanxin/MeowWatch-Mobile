import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meowwatch_mobile/app/app_services.dart';
import 'package:meowwatch_mobile/core/billing/billing_service.dart';
import 'package:meowwatch_mobile/core/billing/file_hosting_quota_store.dart';
import 'package:meowwatch_mobile/core/sync/syncplay_client.dart';
import 'package:meowwatch_mobile/main.dart';
import 'package:purchases_flutter/purchases_flutter.dart'
    show Purchases, PurchasesErrorCode;
import 'package:video_player/video_player.dart';

const _video = String.fromEnvironment(
  'PURCHASE_JOURNEY_VIDEO_URL',
  defaultValue:
      'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
);
const _poll = Duration(milliseconds: 150);
const _runtime =
    'Android MainApp; one native player and independent headless TLS peer in one process';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'production paywall unlocks themes and further hosted sessions',
    (tester) async {
      expect(Platform.isAndroid, isTrue);
      expect(usesTestStore, isTrue);
      // The same service factory and durable files as a normal app launch.
      // The external runner provides a clean, explicitly selected emulator.
      final app = await openAppServices();
      addTearDown(app.close);
      // MainApp leaves configuration to the owner of an injected controller.
      expect((await app.billing.configure()).succeeded, isTrue);
      final ledger = await FileHostingQuotaStore.inApplicationSupport();
      final screenshots = <String>[];
      final verified = <String>[];
      final sessions = <Map<String, Object?>>[];
      final evidence = <String, Object?>{
        'result': 'running',
        'runtime': _runtime,
        'verified': verified,
        'screenshots': screenshots,
        'sessions': sessions,
        'operatingSystemVersion': Platform.operatingSystemVersion,
      };
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['purchaseJourney'] = evidence;

      Future<void> capture(String name) async {
        await tester.pump(const Duration(milliseconds: 300));
        expect(await binding.takeScreenshot(name), isNotEmpty);
        screenshots.add(name);
      }

      await binding.convertFlutterSurfaceToImage();
      await tester.pumpWidget(MainApp(controller: app));
      final name = find.byKey(const Key('display-name-field'));
      await _wait(tester, () => name.evaluate().isNotEmpty, 'clean onboarding');
      await tester.enterText(name, 'Movie Night Host');
      FocusManager.instance.primaryFocus?.unfocus();
      await _tap(tester, find.byKey(const Key('onboarding-continue-button')));
      await _home(tester);
      await _wait(
        tester,
        () => app.billing.isConfigured && !app.billing.isBusy,
        'real RevenueCat configuration',
        seconds: 70,
      );
      expect(app.billing.isPlus, isFalse);
      expect(await app.hosting.remainingFreeHostsToday(), 1);
      expect(await ledger.read(), isNull);
      final customer = app.billing.customerInfo!.originalAppUserId;
      evidence['customerHash'] = sha256
          .convert(utf8.encode(customer))
          .toString();
      verified.add('clean_production_services_and_free_customer');
      await capture('free-home');

      Future<void> runHostedSession(String stage, {required bool free}) async {
        await _tap(tester, find.byKey(const Key('start-room-button')));
        await _wait(
          tester,
          () => app.inPlayer && app.isConnected && app.room != null,
          'Start a room through production UI: ${app.message}',
          seconds: 90,
        );
        final room = app.room!;
        expect(room.isHost, isTrue);
        expect(sessions.map((item) => item['id']), isNot(contains(room.id)));
        final peer = SyncplayClient();
        try {
          final error = await peer
              .connectUntilJoin(
                server: room.config.server,
                port: room.config.port,
                room: room.config.room,
                username: 'Purchase Protocol Peer',
                password: room.config.password,
              )
              .timeout(const Duration(seconds: 60));
          expect(error, isNull);
          expect(peer.hasCompletedHello, isTrue);
          await _wait(
            tester,
            () => app.peers.contains(peer.username),
            'TLS peer',
          );
          if (free) expect(await app.hosting.remainingFreeHostsToday(), 1);
          await _tap(tester, find.widgetWithText(TextButton, 'Video'));
          await _wait(
            tester,
            () => find.text('Choose what to watch').evaluate().isNotEmpty,
            'media sheet',
          );
          await tester.enterText(find.byType(TextField), _video);
          FocusManager.instance.primaryFocus?.unfocus();
          await _tap(tester, find.text('Use this link'));
          await _wait(
            tester,
            () =>
                find.byType(VideoPlayer).evaluate().isNotEmpty &&
                app.target.snapshot.duration.inMilliseconds > 1000,
            'native video',
            seconds: 70,
          );
          final initialPosition = app.target.snapshot.position;
          await _tap(tester, find.byTooltip('Play together'));
          await _wait(
            tester,
            () =>
                app.target.snapshot.playing &&
                app.target.snapshot.position.inMilliseconds >
                    initialPosition.inMilliseconds + 500 &&
                peer.lastObservedRoomState?.paused == false,
            'native play and real server play observation',
            seconds: 30,
          );
          expect(await app.hosting.remainingFreeHostsToday(), 0);
          final stored = jsonDecode((await ledger.read())!) as Map;
          final entry = (stored['sessions'] as Map)[room.id] as Map;
          expect(entry['usedFreeHost'], free);
          sessions.add({
            'stage': stage,
            'id': room.id,
            'server': '${room.config.server}:${room.config.port}',
            'usedFreeHost': entry['usedFreeHost'],
            'nativePositionMs': app.target.snapshot.position.inMilliseconds,
            'peerObservedPlaying': peer.lastObservedRoomState?.paused == false,
            'peerCompletedTlsHello': peer.hasCompletedHello,
            'plus': app.billing.isPlus,
            'remainingFreeHosts': await app.hosting.remainingFreeHostsToday(),
          });
          await capture(stage);
          await _tap(tester, find.byTooltip('Pause together'));
          await _wait(
            tester,
            () => !app.target.snapshot.playing,
            'native pause',
          );
          await _tap(tester, find.byTooltip('Leave room'));
          await _home(tester);
        } finally {
          await peer.dispose();
        }
      }

      await runHostedSession('free-host-playing', free: true);
      verified.add('one_free_host_consumed_via_ui_and_real_tls_peer');
      final freeLedger = await ledger.read();
      // A second new host must reach the real production paywall.
      await _tap(tester, find.byKey(const Key('start-room-button')));
      final purchase = find.byKey(const ValueKey(r'purchase-$rc_monthly'));
      await _wait(
        tester,
        () => purchase.evaluate().isNotEmpty,
        'quota paywall',
        seconds: 70,
      );
      expect(app.room, isNull);
      expect(app.billing.isPlus, isFalse);
      expect(await ledger.read(), freeLedger);
      expect(find.textContaining('RevenueCat Test Store'), findsOneWidget);
      final package = app.billing.packages.singleWhere(
        (item) => item.identifier == r'$rc_monthly',
      );
      expect(package.storeProduct.identifier, 'meowwatch_plus_monthly');
      evidence['localizedPrice'] = package.storeProduct.priceString;
      await capture('quota-paywall');
      verified.add('next_host_opens_production_paywall');

      for (final stage in ['cancel', 'failure', 'success']) {
        final resultMessage = stage == 'cancel'
            ? 'Purchase cancelled.'
            : 'The store could not complete this request. Please try again.';
        final expectedStatus = stage == 'cancel'
            ? BillingStatus.cancelled
            : stage == 'failure'
            ? BillingStatus.failure
            : BillingStatus.success;
        final expectedErrorCode = switch (stage) {
          'cancel' =>
            PurchasesErrorCode.purchaseCancelledError.index.toString(),
          'failure' =>
            PurchasesErrorCode.testStoreSimulatedPurchaseError.index.toString(),
          _ => null,
        };
        BillingResult? observedPurchaseResult;
        var observedPurchaseBusy = false;
        void observePurchaseResult() {
          if (app.billing.isBusy) {
            observedPurchaseBusy = true;
            return;
          }
          if (!observedPurchaseBusy || observedPurchaseResult != null) return;
          final result = app.billing.lastResult;
          if (result?.status == expectedStatus &&
              result?.errorCode == expectedErrorCode) {
            observedPurchaseResult = result;
          }
        }

        app.billing.addListener(observePurchaseResult);
        try {
          // Only coordinates the external native dialog driver; this never
          // supplies a receipt, entitlement, purchase result, or quota value.
          debugPrint('RC_SMOKE_STAGE $stage');
          await _tap(tester, purchase);
          await _wait(
            tester,
            () =>
                !app.billing.isBusy &&
                (stage == 'success'
                    ? app.billing.isPlus && purchase.evaluate().isEmpty
                    : find.text(resultMessage).evaluate().isNotEmpty),
            'official native Test Store $stage result',
            seconds: 90,
          );
          if (stage == 'success') {
            expect(app.billing.isPlus, isTrue);
            expect(
              app
                  .billing
                  .customerInfo!
                  .entitlements
                  .active['meowwatch_plus']
                  ?.isActive,
              isTrue,
            );
            await _wait(
              tester,
              () => purchase.evaluate().isEmpty,
              'paywall dismissal',
            );
            // Purchase retries the original Start intent. Prove that this room is
            // usable later, but first leave through the product navigation.
            await _wait(
              tester,
              () => app.inPlayer && app.isConnected,
              'purchased host retry',
              seconds: 90,
            );
            await capture('purchase-unlocked-room');
            await _tap(tester, find.byTooltip('Leave room'));
            await _home(tester);
          } else {
            // MainApp may refresh customer info on native-dialog resume. Capture
            // this purchase's settled SDK result before refresh can overwrite it.
            expect(
              observedPurchaseResult,
              isNotNull,
              reason:
                  'The $stage UI appeared without this purchase reporting the '
                  'expected RevenueCat error code $expectedErrorCode.',
            );
            expect(observedPurchaseResult!.status, expectedStatus);
            expect(observedPurchaseResult!.errorCode, expectedErrorCode);
            evidence['${stage}ErrorCode'] = observedPurchaseResult!.errorCode;
            expect(find.text(resultMessage), findsOneWidget);
            expect(app.billing.isPlus, isFalse);
            expect(app.room, isNull);
            expect(await ledger.read(), freeLedger);
            await _wait(
              tester,
              () => purchase.evaluate().isNotEmpty,
              'retryable paywall',
            );
            await capture('purchase-$stage');
          }
          verified.add('native_${stage}_through_production_paywall');
        } finally {
          app.billing.removeListener(observePurchaseResult);
        }
      }

      await _tap(tester, find.byTooltip('Profile and settings'));
      // Test Store restore queries the current customer. Invalidate its cache
      // to exercise a real query without fabricating an entitlement transition.
      await Purchases.invalidateCustomerInfoCache();
      await _tap(tester, find.text('Restore purchases'));
      await _wait(
        tester,
        () => find
            .text('Restored. MeowWatch Plus is active.')
            .evaluate()
            .isNotEmpty,
        'same-customer SDK restore result',
        seconds: 70,
      );
      expect(app.billing.isPlus, isTrue);
      expect(app.billing.lastResult?.status, BillingStatus.success);
      final restoreKeptSameCustomer =
          app.billing.customerInfo!.originalAppUserId == customer;
      expect(
        restoreKeptSameCustomer,
        isTrue,
        reason: 'Settings restore must complete for the current SDK customer.',
      );
      evidence['restoreKeptSameCustomer'] = restoreKeptSameCustomer;
      expect(await ledger.read(), freeLedger);
      await tester.ensureVisible(
        find.text('Restored. MeowWatch Plus is active.'),
      );
      await capture('plus-restored');
      verified.add(
        'sdk_restore_via_settings_retains_entitlement_for_same_customer',
      );
      verified.add('sdk_restore_after_customer_info_cache_invalidation');

      await _tap(tester, find.byKey(const Key('choose-appearance-button')));
      await _tap(tester, find.byKey(const Key('theme-choice-cinemaNoir')));
      await _wait(tester, () => app.theme == 'cinemaNoir', 'paid theme');
      await _wait(
        tester,
        () => find.text('Cinema Noir applied.').evaluate().isNotEmpty,
        'saved theme feedback',
      );
      expect(app.repository.theme, 'cinemaNoir');
      final persisted =
          jsonDecode(await app.repository.file.readAsString()) as Map;
      expect(persisted['theme'], 'cinemaNoir');
      await capture('plus-theme-applied');
      verified.add('premium_theme_selected_via_ui_and_persisted');
      await tester.binding.handlePopRoute();
      await _wait(
        tester,
        () => find.byKey(const Key('theme-choice-cozy')).evaluate().isEmpty,
        'appearance dismissal',
      );
      await tester.binding.handlePopRoute();
      await _home(tester);

      await runHostedSession('plus-host-one-playing', free: false);
      await runHostedSession('plus-host-two-playing', free: false);
      verified.add('two_distinct_paid_hosts_via_ui_with_real_tls_peer');
      final finalLedger = jsonDecode((await ledger.read())!) as Map;
      expect((finalLedger['sessions'] as Map).length, 3);
      evidence.addAll({
        'result': 'passed',
        'finalPlus': app.billing.isPlus,
        'remainingFreeHosts': await app.hosting.remainingFreeHostsToday(),
        'theme': app.theme,
        'completedAtUtc': DateTime.now().toUtc().toIso8601String(),
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

Future<void> _home(WidgetTester tester) => _wait(
  tester,
  () => find.byKey(const Key('home-scroll-view')).evaluate().isNotEmpty,
  'home',
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _wait(tester, () => finder.evaluate().isNotEmpty, 'control $finder');
  await tester.ensureVisible(finder);
  // Let sheet transitions and scroll animations stop before deriving a hit.
  await tester.pump(const Duration(milliseconds: 450));
  await _wait(
    tester,
    () => finder.hitTestable().evaluate().isNotEmpty,
    'tappable $finder',
  );
  await tester.tap(finder.hitTestable());
  await tester.pump(_poll);
}

Future<void> _wait(
  WidgetTester tester,
  bool Function() condition,
  String description, {
  int seconds = 20,
}) async {
  final watch = Stopwatch()..start();
  while (!condition()) {
    if (watch.elapsed >= Duration(seconds: seconds)) {
      throw TestFailure('Timed out waiting for $description.');
    }
    await tester.pump(_poll);
  }
}
