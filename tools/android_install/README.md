# Normal Android install gate

This gate builds and installs MeowWatch's normal `lib/main.dart` application.
It does not use a Flutter integration-test target or test driver.

The GitHub workflow builds two normal `lib/main.dart` APKs. The debug APK uses
the project's public RevenueCat Test Store key through the app's debug-only
default, while the release APK explicitly disables billing because Test Store
keys cannot run in release builds. Both APKs are signed with Flutter's Android
debug key, so they are installable evidence and **are not Play
production-signed or store-submission-ready**.

Each matrix job uses a fresh API 35 Google APIs x86_64 AVD. The runner removes
an existing MeowWatch package if present, performs a non-replacement
`adb install -t`, and launches the exported normal `MainActivity`. Passing
requires all of the following:

- one live MeowWatch process;
- MeowWatch's `MainActivity` in the focused Android window;
- unique exact UIAutomator semantics for the real first-run onboarding title,
  local-storage privacy copy, and enabled Continue action;
- installed package version metadata and the emulator's actual runtime ABI;
- installed package debuggability matching the declared debug/release mode;
- a valid native screenshot and screen recording; and
- no fatal lines in app-process logcat.

After that clean-install proof, the same installed APK runs the native incoming
media gate for cold/warm Android `ACTION_SEND` and `ACTION_VIEW` review flows.

The workflow runs:

```sh
python3 -m tools.android_install.runner \
  --serial emulator-5554 \
  --build-mode debug \
  --apk build/android-install-package/meowwatch-debug-test-store.apk
```

The release matrix job uses `--build-mode release` and
`meowwatch-debug-key-release.apk` instead.

Evidence comes from a public-hosted Android emulator, not a physical device.
The gate proves clean installation, first launch and native incoming review for
each APK. The debug artifact contains a real Test Store client configuration,
but this gate does not complete a purchase; dedicated native purchase workflows
cover that flow. Neither job proves Play signing, Play distribution or
physical-device behavior.
