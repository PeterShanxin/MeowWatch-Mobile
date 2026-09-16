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

   Use the Test Store SDK key for Test Store testing. Never use a secret/server
   key in a client build. No real key is included in this repository.
5. Verify the current Shipaton Next Gen purchase-testing requirements before
   submission. A Test Store integration alone does not establish eligibility.

The adapter reads `Offerings.current`; labels, localized prices, currency and
subscription period come from each `Package.storeProduct`. It uses
`Purchases.purchase(PurchaseParams.package(package))` and `restorePurchases()`.
The SDK manages the anonymous app user identity until account integration is
added. Do not invent a user ID or call logout on every launch.

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
succeed with no entitlement. Cancellation/failure never changes room identity
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

Official references:

- [Flutter SDK installation](https://www.revenuecat.com/docs/getting-started/installation/flutter)
- [Making purchases](https://www.revenuecat.com/docs/getting-started/making-purchases)
- [Customer information and updates](https://www.revenuecat.com/docs/customers/customer-info)
- [SDK configuration](https://www.revenuecat.com/docs/getting-started/configuring-sdk)
