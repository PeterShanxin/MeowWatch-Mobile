# Native Android app journey capture

This runner exercises the prebuilt production-app integration target through
five responsive viewports on one explicitly selected Android emulator. The
profiles are honest `wm size` and `wm density` overrides on the same AVD:

| `UI_PROFILE` | Override | Density | Orientation | Approx. logical viewport |
| --- | --- | --- | --- | --- |
| `phone` | 1080x2400 | 420 | portrait | 411x914 |
| `small` | 720x1280 | 320 | portrait | 360x640 |
| `tablet` | 1600x2560 | 320 | portrait | 800x1280 |
| `tablet-landscape` | 2560x1600 | 320 | landscape | 1280x800 |
| `landscape` | 1600x720 | 320 | landscape | 800x360 |

Both landscape profiles use explicit landscape bounds at rotation 0. This
avoids depending on a user-rotation override that Android can revert during
the launcher-to-app transition. The driver still checks the actual Flutter
orientation before accepting a passing journey. These labels describe rendered
viewport coverage, not live rotation transitions; lifecycle and rotation
recovery require separate acceptance. They also do not establish five hardware
devices, physical density behavior, OEM layouts, or ARM decoding.

## Quick-guide coverage — native execution pending

The [production journey](../../integration_test/app_journey_test.dart) now
opens the first-use quick guide before completing onboarding. It checks and
captures all three steps, advances through them, and verifies that the entered
display name remains intact when the guide closes. Later, it opens the guide
from Settings, verifies that replay starts at step 1, captures it, closes it and
continues to Appearance.

These checks add four native screenshot artifacts under each clean profile's
`screenshots/` directory:

- `quick-guide-1.png`, `quick-guide-2.png`, `quick-guide-3.png`;
- `quick-guide-replay.png`.

They also add `first_use_guide_completed_name_preserved` and
`settings_guide_replayed_and_closed` to `appJourney.verifiedSteps`. A fresh
onboarding run is expected to produce **13 screenshots and 18 verified steps**.
The new guide checks are **awaiting native execution and visual inspection**;
the earlier nine-screenshot, 16-step runs do not cover them. Settings replay is
checked from Home in this journey, not during active room playback.

## Run and collect evidence

Build `integration_test/app_journey_test.dart` before starting the emulator.
The hosted journey compiles `APP_JOURNEY_VIDEO_URL` as the locally served
90-second fixture URL so the UI playback assertions do not reach the end of the
four-second source clip. Then use this as the single `script` command of an
Android emulator runner:

```sh
bash tools/app_journey/run.sh \
  --serial emulator-5554 \
  --apk build/app/outputs/flutter-apk/app-debug.apk
```

The script validates that the selected serial is an emulator, installs the
prebuilt APK, and calls `pm clear com.meowwatch.meowwatch_mobile` exactly once
immediately before each clean journey. It passes `UI_PROFILE` to the driver and
runs the profiles sequentially with a 750-second outer bound each. Test failures
do not suppress later profile evidence; the process exits with the first
nonzero profile status.

Native `screenrecord` begins before each `flutter drive` command and rotates
170-second segments until the command exits. Every device command uses the
explicit serial. Only the recorder PID observed for that serial is signalled,
and the script never stops the emulator. Before/after native screenshots,
screenrecord segments, logcat, display/window state, codec state, SurfaceFlinger
layers, hashes, and actual exit codes are stored under
`build/app-journey-artifacts/<profile>/native/`. Driver screenshots and
`result.json` remain directly under the corresponding profile directory.

The integration driver owns its `screenshots/` directory. Native evidence is
staged separately under `build/app-journey-runner/<profile>` while the test runs
and moved beside the driver output only after the driver exits, so neither
writer can remove or partially overwrite the other's files.

The original `wm` override, density override, accelerometer-rotation setting,
and user-rotation setting are captured before the first profile and restored on
success, failure, timeout, or signal. `device-restore.tsv` records each restore
operation's exit status. A restore or evidence failure fails an otherwise
successful run.
