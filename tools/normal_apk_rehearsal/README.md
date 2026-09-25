# Ordinary APK rehearsal

Run the manual `Normal APK clean-install rehearsal` GitHub Actions workflow.
It builds `lib/main.dart` once as a debug/Test Store APK and installs those same
bytes on one newly created API 35 Pixel 6 and Pixel Tablet emulator. The
existing dual-device launcher prepares Android system setup and checks resource
readiness before either app install. No setup or ANR repair runs during the app
journey.

The runner uses the standalone native UI observer for visible Flutter screens,
Android UIAutomator only for the native RevenueCat Test Store dialog, and
screen captures at each meaningful stage. It fails on an unexpected screen,
stale or missing control, observer failure, or timeout. It does not reset quota,
invoke an integration entry point, simulate billing, or alter the product.

`build/normal-apk-rehearsal/evidence/result.json` records device models, API,
APK SHA-256, phase receipts, and completion or failure. Each captured phase has
the native hierarchy, focused-window dump, and PNG. The workflow uploads the
AVD preparation/readiness receipts and fixture provenance with these results.
This gate is emulator evidence; physical-device acceptance remains separate.
