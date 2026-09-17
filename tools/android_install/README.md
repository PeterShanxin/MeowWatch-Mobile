# Normal Android install gate

This gate builds and installs MeowWatch's normal `lib/main.dart` application.
It does not use a Flutter integration-test target or test driver.

The GitHub workflow builds two normal `lib/main.dart` APKs. The debug APK uses
the project's public RevenueCat Test Store key through the app's debug-only
default, while the release APK explicitly disables billing because Test Store
keys cannot run in release builds. Both APKs are signed with Flutter's Android
debug key, so they are installable evidence and **are not Play
production-signed or store-submission-ready**.

The debug and release jobs use fresh API 35 Google APIs x86_64 AVDs. A further
debug job uses API 29 to check the adaptive icon and older splash resource path.
The runner removes
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
media gate for cold/warm Android `ACTION_SEND` and `ACTION_VIEW` review flows,
including native room invitations that wait for explicit Join.

The workflow runs:

```sh
python3 -m tools.android_install.runner \
  --serial emulator-5554 \
  --build-mode debug \
  --apk build/android-install-package/meowwatch-debug-test-store.apk
```

The release matrix job uses `--build-mode release` and
`meowwatch-debug-key-release.apk` instead.

If Google's SDK setup package shows its exact system ANR dialog during launch,
the runner retains the dialog XML, focused window and screenshot, confirms the
device is an emulator, then closes only that setup dialog and retries launch
once. A successful launch followed by the same delayed system dialog shares
that one recovery allowance during first-screen observation, without relaunching
the app or extending the original 55-second deadline. That path also requires
the original app PID to remain unchanged. It rechecks the dialog and exact
focused window immediately before tapping. App ANRs, unrelated
dialogs and a second setup failure remain failures; original launch diagnostics
are retained alongside the successful attempt.

Android's `am start -W` can report `Status: timeout` before the first Flutter
frame is ready. Only an exit-zero response naming exactly MeowWatch's
`MainActivity`, with that activity independently focused, proceeds to the
existing 55-second UI-readiness gate. This does not count as launch acceptance:
all onboarding, stable-process, recording and app-log checks still apply.
The original timeout output and `activityManagerWaitTimedOut` flag are retained.
ADB command timeouts, ambiguous responses, app ANRs and other focused activities
are not accepted through this path.

Before installation, the runner waits up to 20 seconds for its owned external
storage directory and an actual MP4 write probe. It retains every failed probe
in `storage-readiness.log`. An existing evidence directory is never reused.

Native recording runs in the foreground with an explicitly announced PID.
After the UI checks, the runner verifies ownership and requests a graceful stop.
If the first 20-second drain expires, it records process diagnostics and waits
only through the original 90-second native limit plus 20 seconds for finalization.
A forced termination never passes: the recorder must exit successfully, produce
a finalized MP4, and pass a complete `ffmpeg` decode. The runner requires
`ffmpeg` and `ffprobe`; `recording-metadata.json` retains the actual video duration,
dimensions and the elapsed time when stop was requested. These timings expose
the captured coverage rather than asserting that every launch frame was captured.

Evidence comes from a public-hosted Android emulator, not a physical device.
The gate proves clean installation, first launch and native incoming review for
each APK. The debug artifact contains a real Test Store client configuration,
but this gate does not complete a purchase; dedicated native purchase workflows
cover that flow. Neither job proves Play signing, Play distribution or
physical-device behavior.
