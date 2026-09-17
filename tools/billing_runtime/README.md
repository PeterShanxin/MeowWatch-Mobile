# Native Android RevenueCat Test Store runner

`run_billing_smoke.py` drives an **already-built debug integration-test APK**.
It does not invoke a Flutter/Gradle build, clear app data, uninstall the app,
change RevenueCat identity, or manufacture entitlements. Python 3.11+ is required;
the Python tools use only the standard library. Flutter and adb must be installed.

## Run a prebuilt purchase matrix

The APK must have been built from `integration_test/billing_smoke_test.dart` with
`REVENUECAT_TEST_MODE=matrix` and the project's public Test Store SDK key via
`REVENUECAT_API_KEY`. These are **compile-time** values. Passing defines only to
the runner or host driver cannot change a prebuilt APK. The test itself rejects
non-Test-Store keys. Coordinate the build separately with the project owner.

```powershell
python tools/billing_runtime/run_billing_smoke.py --serial emulator-5554 --apk build/app/outputs/flutter-apk/app-debug.apk --expect-mode matrix
```

Use an explicitly selected test device with no active Plus entitlement. Keep
other automation and human taps off this device while the test is running.
`--adb` and `--flutter` accept executable paths if they are not on PATH.
The runner calls `flutter drive --use-application-binary=... --no-pub` with
`test_driver/billing_smoke_driver.dart`; it never runs `flutter build`.

The driver writes `reportData` on success **and failure** to
`build/billing-runtime-artifacts/<run-id>/result.json`. The runner checks both
Flutter's exit code and the report's required verified steps. A smoke-only APK
cannot pass a requested purchase matrix.

## Native interaction guard

The runner reads the current drive process's output and responds only to these
test markers, exactly once and in order:

1. `RC_SMOKE_STAGE cancel`
2. `RC_SMOKE_STAGE failure`
3. `RC_SMOKE_STAGE success`

At each stage it records native Android video and obtains new UIAutomator XML.
Before tapping it requires all of the following:

- The current focused window belongs to `com.meowwatch.meowwatch_mobile`.
- Visible, enabled nodes have the same exact package.
- A native `android:id/alertTitle` says exactly `Test Store Purchase`.
- The native message identifies `Product: meowwatch_plus_monthly`, RevenueCat,
  and a test purchase.
- The native dialog exposes all three distinct, enabled, clickable Android
  buttons with expected native resource IDs and complete labels.
- The requested button has positive bounds inside the observed screenshot.

The current Android SDK uses `Cancel`, `Test failed purchase`, and
`Test valid purchase`. The documented full variants `Failed Purchase` and
`Successful Purchase` are also accepted. Matching ignores case to support
Android's uppercase button transformation; it does not accept partial labels.

The runner captures a screenshot, then reads **another fresh XML/window snapshot**
before computing the selected button's center. It has no preset coordinates,
OCR guesses, back-button fallback, or blind repeated tap. Each XML dump uses a
unique remote path, so an unsuccessful dump cannot reuse an older file. A wrong
window, changed product, unknown SDK dialog layout, missing stage, or missing
button fails with diagnostics instead of broadening the selector.

Focus comes from `dumpsys window displays`, which emits `mCurrentFocus` on the
API 35 emulator. The `windows` section lists visible windows and IME targets but
can omit focus entirely; those fields are not accepted as substitutes. The
captured regression fixture from run 35056405179 documents this distinction.
Missing, foreign, or ambiguous current-focus entries still prevent every tap.

On a verified emulator only, the driver can close two narrowly identified
system-infrastructure ANRs that may obscure an otherwise live MeowWatch
activity: Pixel Launcher and `com.google.android.googlesdksetup`. Recovery
requires the exact allowlisted package in `mCurrentFocus`, MeowWatch as the
exact underlying `mFocusedApp`, the exact system ANR title, and one enabled,
clickable `android:id/aerr_close` button from package `android`. The driver
captures XML, window state, and a screenshot, then repeats every check before
one close tap. At most two such recoveries are allowed across a run. App ANRs,
other packages, other actions, physical devices, and changed observations
remain hard failures.

The failure integration assertion requires RevenueCat's
`testStoreSimulatedPurchaseError`; a generic network error cannot pass that step.

## Evidence and cleanup

Each run directory contains:

- `flutter-drive.log`: current run log and `RC_SMOKE_RESULT` evidence.
- `result.json`: integration-test `reportData`, even for Dart test failures.
- `run.json`: runner verdict, APK SHA-256, selected serial and observed taps.
- `<stage>-before.xml`, `<stage>-window.txt`, `<stage>-before.png`,
  `<stage>-after.png`: native evidence for each purchase outcome.
- `<stage>-<launcher|setup>-recovery-<n>.*` and the matching recovery log:
  exact system-ANR evidence and the bounded close action, when recovery occurs.
- `<stage>.mp4` and `<stage>.log`: native screen recording and recorder log.
- `*-failure.*`: accessibility/window/screenshot diagnostics when available.

Recordings must contain MP4 headers and finalized metadata and exceed the
minimum size check. This is a basic container check; inspect the videos as part
of acceptance. A recording failure makes the runtime run fail.

Each Android recorder is launched with a 90-second limit. Its exact PID is
returned by its own launching shell. Before stopping it, the runner checks
`/proc/<pid>/cmdline` for `screenrecord` and the unique task-owned output path;
it never kills processes by executable name. If ownership cannot be confirmed,
it refuses to signal that remote PID, reports failure, and relies on the bounded
recorder limit. Cleanup removes only the exact remote files allocated by this
run. Flutter cancellation targets only the process tree launched by the runner.
The runner does not clear shared logcat buffers or stop an emulator.

For `smoke`, `relaunch`, or `expired`, use the corresponding prebuilt APK and
`--expect-mode`; no purchase tap is permitted. Relaunch/expiry builds must also
carry the original `REVENUECAT_EXPECT_CUSTOMER_HASH`, described in
[BILLING.md](../../docs/BILLING.md). Preserve the installed app data and retain
separate process-stop evidence. The runner does not prove Google Play billing,
the production paywall UI, or cross-device identity recovery.

## Process relaunch and real expiration journey

`run_relaunch_journey.py` closes the missing process boundary in one bounded
Test Store run. It drives the real matrix APK with the guarded native dialogs,
captures only the SHA-256 customer identity, records the exact running Android
PID, force-stops the package and waits for that PID to disappear. It then builds
the relaunch mode incrementally with the same customer hash, starts a distinct
process without clearing or uninstalling app data, and requires the real SDK to
load active Plus. Immediately before restore, the integration test invalidates
RevenueCat customer-info cache; Test Store restore then performs its documented
customer-info query and must keep Plus active for the same hashed customer.

After relaunch, the runner builds `expiry_wait` with the same customer hash and
waits for the purchased monthly entitlement to actually expire. Each segment
polls the real SDK about every 30 seconds for up to three minutes, invalidating
customer-info cache before every refresh. Segments fit the existing bounded
driver; a successful segment that still has Plus reports `expiryPending: true`
and cannot pass the journey. Repeated segments preserve installed app data and
use the same expiry APK. Network/test failures are not retried as pending.

Acceptance requires the same customer hash, entitlement/product and original
purchase date as the initial successful purchase. Renewal and expiration dates
are retained from the SDK, and may advance normally. The final historical
entitlement must be inactive, with a past expiration and a customer-info response
at or after that expiration. Cache-invalidated restore must still return the
same inactive entitlement. No clock changes, dashboard grants/revocations, or
fabricated customer data are used. The separate `expired` mode retains its
immediate strict assertion; it does not wait or accept active Plus.

The default expiry wait is 35 minutes, configurable with
`--expiry-timeout-seconds` from 300 to 2400. The runner bounds the full journey
to 55 minutes, with short cleanup afterward; CI allows 65 minutes including
setup/build. RevenueCat documents about 25 minutes for a monthly Test Store
subscription, but elapsed time never proves expiry. A deadline with Plus still
active fails and preserves the observations.

The runner records all three APK hashes, both relaunch PIDs and entitlement
snapshots. A passing run establishes same-customer SDK relaunch and expiration
behavior through replacement debug APK installs. It does not prove
uninstall/reinstall recovery, lost anonymous identity recovery, Google Play
restore, a physical device, or production paywall/hosting UI. The new expiry
phase still requires native execution; earlier matrix/relaunch passes do not
establish expiration acceptance.

The standalone `billing-relaunch.yml` workflow builds the matrix APK before
starting its API 35 emulator, then runs:

```sh
REVENUECAT_TEST_STORE_KEY=test_... \
python3 tools/billing_runtime/run_relaunch_journey.py \
  --serial emulator-5554 \
  --matrix-apk build/app/outputs/flutter-apk/app-debug.apk
```

Artifacts are written under `build/billing-relaunch-artifacts/<run-id>/`.
`run.json` updates after each phase and completed expiry segment, with
`passed: false` and `expiryVerified: false` until the final assertions succeed.
`expiry-01/`, `expiry-02/`, etc. retain each segment's drive log and report;
`RC_SMOKE_EXPIRY_OBSERVATION` lines retain intermediate SDK snapshots while a
segment is running. Nested driver results also remain under
`build/billing-runtime-artifacts/`. Customer identity is stored only as SHA-256;
reports omit the SDK key and raw RevenueCat customer identifier. Purchase-dialog
recordings cover the matrix; the expiry phase is SDK/state evidence, not a
continuous recorded production UI journey.

## Test the guard without a device

```powershell
python -m unittest discover -s tools/billing_runtime -p "test_*.py" -v
flutter analyze --no-pub integration_test/billing_smoke_test.dart test_driver/billing_smoke_driver.dart
```

Selector tests use XML fixtures and fake adb boundaries only to check that
unsafe targets are refused. They are not purchase/device acceptance evidence.

Official source references, checked for the implemented dialog contract:

- [Android Test Store dialog implementation](https://github.com/RevenueCat/purchases-android/blob/main/purchases/src/main/kotlin/com/revenuecat/purchases/simulatedstore/SimulatedStoreBillingWrapper.kt)
- [Native AlertDialog helper](https://github.com/RevenueCat/purchases-android/blob/main/purchases/src/main/kotlin/com/revenuecat/purchases/utils/AlertDialogHelper.kt)
- [RevenueCat native Android testing guide](https://www.revenuecat.com/blog/engineering/testing-test-store)
- [Test Store renewal and expiration schedule](https://www.revenuecat.com/docs/test-and-launch/sandbox/test-store#subscription-renewals-and-expiration)
- [Android display focus dump](https://android.googlesource.com/platform/frameworks/base/+/android15-release/services/core/java/com/android/server/wm/DisplayContent.java)
