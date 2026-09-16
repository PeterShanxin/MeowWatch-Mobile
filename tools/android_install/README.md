# Normal Android install gate

This gate builds and installs MeowWatch's normal `lib/main.dart` application.
It does not use a Flutter integration-test target or test driver.

The GitHub workflow creates a release-mode APK with the project's official
public RevenueCat Test Store SDK key. The current Android release build is
signed with Flutter's debug key, so the uploaded APK is installable test
evidence and **is not Play production-signed or store-submission-ready**.

On a fresh API 35 Google APIs x86_64 AVD, the runner removes an existing
MeowWatch package if present, performs a non-replacement `adb install -t`, and
launches the exported normal `MainActivity`. Passing requires all of the
following:

- one live MeowWatch process;
- MeowWatch's `MainActivity` in the focused Android window;
- unique exact UIAutomator semantics for the real first-run onboarding title,
  local-storage privacy copy, and enabled Continue action;
- installed package version metadata and the emulator's actual runtime ABI;
- a valid native screenshot and screen recording; and
- no fatal lines in app-process logcat.

The workflow runs:

```sh
python3 -m tools.android_install.runner \
  --serial emulator-5554 \
  --apk build/android-install-package/meowwatch-debug-key-release.apk
```

Evidence comes from a public-hosted Android emulator, not a physical device.
The gate proves clean installation and first launch of this APK; it does not
prove Play signing, Play distribution, physical-device behavior, or purchase
completion.
