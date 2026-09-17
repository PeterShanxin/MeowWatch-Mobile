# Billing and hosting allowance

The app uses the official `purchases_flutter` SDK behind `BillingService`.
`RevenueCatBillingService` never fabricates a product, price, receipt, or Plus
entitlement. An unconfigured build keeps free hosting/joining available and
reports purchases as unavailable.

## RevenueCat setup

1. In the RevenueCat project, create the `meowwatch_plus` entitlement.
2. Create a Test Store subscription product and attach it to that entitlement.
3. Add the product to a monthly package in an offering and make the offering
   current. A single monthly package is sufficient. Choose test pricing in the
   dashboard; there is no hardcoded production price in the app.
4. Pass that app's **public SDK key** when building:

   ```powershell
   flutter run --dart-define=REVENUECAT_API_KEY=<public-sdk-key>
   ```

   Use the Test Store SDK key only in a debug build. The repository includes
   the project's public Test Store key as the debug default; it cannot charge
   real money. Never use a secret/server key in a client build.
5. Verify the current Shipaton Next Gen purchase-testing requirements before
   submission. A Test Store integration alone does not establish eligibility.

Release and profile builds have no default billing key. Supply an Android
platform public SDK key for a commercial build. The app rejects a `test_` key
before invoking the SDK outside debug mode: RevenueCat otherwise displays a
Wrong API Key dialog and closes the app. A release build without a platform
key keeps the free product usable and clearly reports purchases unavailable.
The Shipaton Test Store demo uses the normal `lib/main.dart` **debug APK**.
See [RevenueCat's Test Store guidance](https://www.revenuecat.com/docs/test-and-launch/sandbox/test-store).

The adapter reads `Offerings.current`; labels, localized prices, currency and
subscription period come from each `Package.storeProduct`. It uses
`Purchases.purchase(PurchaseParams.package(package))` and `restorePurchases()`.
The SDK manages the anonymous app user identity until account integration is
added. Do not invent a user ID or call logout on every launch.

The bundled Android SDK 10.20.0 implements Test Store `restorePurchases()` as
a current-customer information query, without consulting Google Play purchase
history. The production purchase rehearsal invalidates CustomerInfo cache
immediately before Settings Restore and verifies the same active customer.
This proves a real SDK restore query, not recovery after uninstall or loss of
anonymous identity. Those are separate platform-store acceptance checks. See
the [SDK restore implementation](https://github.com/RevenueCat/purchases-android/blob/10.20.0/purchases/src/main/kotlin/com/revenuecat/purchases/PurchasesOrchestrator.kt#L755)
and [RevenueCat identity guidance](https://www.revenuecat.com/docs/customers/identifying-customers).

## Application integration

Create one billing service and one allowance policy for the app lifetime:

```dart
final billing = RevenueCatBillingService();
final store = await FileHostingQuotaStore.inApplicationSupport();
final hosting = LocalHostingAccessPolicy(
  store: store,
  isPlus: () => billing.isPlus,
);
await billing.configure();
```

`BillingService` implements `Listenable`. The RevenueCat implementation is a
`ChangeNotifier`; `customerInfoStream` additionally emits SDK customer updates.
Read the current `customerInfo`/`isPlus` when subscribing because the stream
does not replay earlier events. `isBusy`, `lastResult`, `isConfigured`,
`currentOffering`, and `packages` expose loading and error states without SDK
calls from widgets.

Call `refresh()` when the app resumes and before presenting an upgrade. SDK
listeners are not server push notifications: RevenueCat updates cached customer
information through requests, purchases and restores. The SDK's caching and
offline entitlement behavior remain authoritative. The application does not
persist a second, potentially divergent Plus flag.

`configure()`, `refresh()`, `purchase(package)`, and `restore()` return a
`BillingResult`. Handle `success`, `cancelled`, `failure`, and `unavailable`
explicitly. A successful operation is **not** proof of Plus: recheck `isPlus`,
which requires active `meowwatch_plus` in SDK customer information. A restore may
succeed with no entitlement. Settings reports the result of the requested restore
operation even if a cached entitlement remains active; cached Plus must not mask
a network or store failure. Cancellation/failure never changes room identity
or quota and never grants access. Simultaneous purchase operations are rejected.

Keep guest joining independent of allowance checks. For a new hosted room, call
`canHostNow()` before committing the intent and show the paywall if false. A
resumed room passes its original persistent `sessionId` to `canHostNow`.
Creating a room, showing its invitation or selecting a video consumes nothing.

Persist a unique session ID with the hosted room before its first connection.
Keep it across app restart, network reconnect, room re-entry and playback target
changes; only an intentional new room/session gets a new ID. The quota policy
persists started IDs; the room layer persists which ID belongs to the current
room. Do not derive the ID from a display name that a different room can reuse.

At the real start boundary, await:

```dart
final result = await hosting.recordSessionStarted(
  sessionId: persistedRoomSessionId,
  isCreator: true,
  peerCount: connectedRemotePeerCount,
  synchronizedPlaybackActive: true,
);
if (!result.allowed) {
  // Pause/withhold synchronized playback and present the Plus paywall.
}
```

`peerCount` excludes this client. Call at the activation boundary before allowing
paid-only playback to continue. `explicitStart: true` can substitute for active
synchronized playback, but still requires creator status and a successfully
joined peer. Guests return `guest`; missing prerequisites return `notStarted`.
Those outcomes do not consume allowance. Start results distinguish
`freeStarted`, `plusStarted`, `alreadyStarted`, and `quotaExceeded`.

The initial `canHostNow()` check is advisory: two pending rooms can both appear
eligible, so always enforce the serialized `recordSessionStarted()` result.
Storage exceptions must show a retryable error and withhold the new session,
rather than silently proceeding or resetting the allowance.

## Persistence and limits

The production store writes one app-private JSON ledger, flushes it, then
renames it over the previous ledger. A committed record contains both the
session ID and its local date, preventing partial date-only consumption. Reads
and writes are serialized by the policy. A failed write does not mutate an
in-memory allowance; retries reread storage. A leftover partial `.pending` file
is ignored and overwritten by the next successful write. Corrupt committed data
fails closed and is not silently deleted.

Free sessions consume one allowance for the local calendar date **when they
actually start**. Midnight makes a new daily allowance available, but replaying
yesterday's ID consumes none of it. Recorded sessions remain resumable after
Plus expires. Sessions started with Plus do not consume the free allowance.
`remainingFreeHostsToday()` reports 0 or 1 even for Plus; Plus access is separate.
Dates and started IDs are retained rather than pruned automatically.

This is the spec's accepted local Shipaton accounting, not commercial fraud
prevention. Clearing app data, reinstalling, modifying storage, changing device
time to an unused date, or changing devices can bypass it. There is no
cross-device or cross-process transaction guarantee; use a single policy/store
instance. Returning to an already consumed date does not reset that date.
For commercial enforcement, replace the policy/store with authenticated server
accounting. File flush plus rename protects ordinary process-crash consistency;
it is not a claim of guaranteed recovery from every filesystem/power failure.

## Verification

Run:

```powershell
flutter test --no-pub test/core/billing
flutter analyze --no-pub lib/core/billing test/core/billing
```

Tests exercise local-date rollover, saved ID replay/restart, guest access,
creator/peer/start prerequisites, concurrent starts, Plus expiry, failed writes,
corrupt data, and real file replacement/reopening. Adapter tests run the official
Flutter SDK against an intercepted native method channel to check purchases,
restores, cancellation, failures, entitlement updates and offering metadata.
These tests do not prove a live store purchase or device integration.

Device/Test Store acceptance remains required: purchase success, cancellation,
failure, restore with and without Plus, expiration, relaunch with entitlement,
and immediate unlimited hosting after purchase. Also verify free room creation,
peer arrival, actual playback, reconnect, midnight rollover and target changes
through the app UI. Do not claim those checks passed without device evidence.

### Live Android Test Store integration test

The catalog created for this project is recorded in
[REVENUECAT_SETUP.md](REVENUECAT_SETUP.md). The runtime test
`integration_test/billing_smoke_test.dart` uses the production billing adapter
and the installed native RevenueCat SDK, with no channel mocks or fabricated
customer information. It accepts **only** a Test Store key starting with `test_`
to prevent accidental real-store purchases.

Start with the non-purchasing catalog check on an Android device/emulator:

```powershell
flutter test integration_test/billing_smoke_test.dart -d <android-device-id> --dart-define=REVENUECAT_API_KEY=<public-test-store-key>
```

This verifies SDK configuration, a fresh customer-info request, current offering
`default`, package `$rc_monthly`, product `meowwatch_plus_monthly`, and real SDK
price/currency/period metadata. It does **not** prove the entitlement mapping:
an unpurchased customer can legitimately have no entitlements. That mapping is
asserted only after a successful purchase.

Use the purchase matrix on a Test Store customer without active Plus:

```powershell
flutter test integration_test/billing_smoke_test.dart -d <android-device-id> --dart-define=REVENUECAT_API_KEY=<public-test-store-key> --dart-define=REVENUECAT_TEST_MODE=matrix
```

The test first restores with no active entitlement, then makes three purchase
attempts in order: **cancel**, **failure**, **success**. Each attempt emits
`RC_SMOKE_STAGE <outcome>` to the host log and waits up to 90 seconds for a real
native result. Select the corresponding option in the RevenueCat dialog. The
test requires cancellation/failure to leave Plus inactive, then verifies that
success activates the sandbox `meowwatch_plus` entitlement for the expected
product. A fresh server request and restore must retain that entitlement.
The failure outcome specifically requires RevenueCat's
`testStoreSimulatedPurchaseError`; network/plugin errors do not qualify.

For automated native interaction and recording, use the
[prebuilt-APK runner](../tools/billing_runtime/README.md). It reacts only to the
current drive log's stage markers, checks the focused app and exact native
dialog/product/buttons, and derives taps from fresh accessibility bounds. Its
host driver saves reports and native evidence under
`build/billing-runtime-artifacts`. The runner never invokes a build; compile the
requested test mode and public SDK key into the APK separately.

RevenueCat's Android Test Store dialog is native Android UI. Flutter widget
finders cannot click its buttons. A person can operate it, or the host can use
adb/UIAutomator in parallel with the running test. Inspect each current dialog
before tapping; button labels differ between SDK versions, so do not assume
screen coordinates or match the Flutter instruction text instead of the dialog.
For example, capture an accessibility dump in the second terminal:

```powershell
adb -s <android-device-id> shell uiautomator dump /sdcard/meowwatch-billing-ui.xml
adb -s <android-device-id> shell cat /sdcard/meowwatch-billing-ui.xml
adb -s <android-device-id> shell input tap <observed-button-center-x> <observed-button-center-y>
```

Capture the native dialog and selected option as external evidence, especially
for the failure case: a generic store/network error alone does not establish
that the intended failure button was exercised. Flutter-only screenshots do not
prove the native dialog was visible. A missing response times out and fails;
there is no automatic fake-success fallback. Dismiss any leftover dialog after
an interrupted run before starting another test.

Save the `RC_SMOKE_RESULT` JSON line, including its SHA-256 `customerHash`.
Integration test drivers can also read the same data under
`reportData.revenueCatTestStore`. The evidence includes the actual localized
price, verified steps, timestamps, and entitlement expiration when available;
it omits the SDK key and raw customer ID.

For a separate process-relaunch/restore check, stop the app and run against the
same installed app data before the entitlement expires:

```powershell
adb -s <android-device-id> shell am force-stop <application-id>
flutter test integration_test/billing_smoke_test.dart -d <android-device-id> --dart-define=REVENUECAT_API_KEY=<public-test-store-key> --dart-define=REVENUECAT_TEST_MODE=relaunch --dart-define=REVENUECAT_EXPECT_CUSTOMER_HASH=<hash-from-matrix>
```

Do not clear app data or uninstall between these runs. The relaunch mode makes
no purchase and requires the same customer and active sandbox Plus before and
after restore. Reconstructing a Dart service in one process is not claimed as a
process-relaunch test; retain the external stop/start evidence.

To check actual expiration, wait for that Test Store subscription to expire and
run the same command with `REVENUECAT_TEST_MODE=expired`. This mode invalidates
the SDK cache, requires the original customer's historical Plus entitlement to
be inactive with a past expiration timestamp, and requires restore to leave it
inactive. It never changes the device clock or grants/revokes entitlements in
test code. RevenueCat currently documents a five-minute renewal interval and
approximately 25 minutes total for monthly Test Store subscriptions; verify the
actual entitlement response rather than inferring expiry from elapsed time.

These device modes are executable acceptance checks, not evidence that they
have already passed. They do not test the app's paywall visuals, real-money
Google Play billing, uninstall recovery, cross-device identity transfer, or
hosting/playback integration. Record those checks separately. See RevenueCat's
[Test Store documentation](https://www.revenuecat.com/docs/test-and-launch/sandbox/test-store)
and its [native Android dialog testing example](https://www.revenuecat.com/blog/engineering/testing-test-store).

Official references:

- [Flutter SDK installation](https://www.revenuecat.com/docs/getting-started/installation/flutter)
- [Making purchases](https://www.revenuecat.com/docs/getting-started/making-purchases)
- [Customer information and updates](https://www.revenuecat.com/docs/customers/customer-info)
- [SDK configuration](https://www.revenuecat.com/docs/getting-started/configuring-sdk)
