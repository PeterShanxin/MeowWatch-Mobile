# Foreground Android audio-focus acceptance

This gate uses the normal `lib/main.dart` release APK on a dedicated API 35
Google APIs x86_64 Pixel 6 emulator. It tests an actual independent Android audio
focus client while MeowWatch remains foreground. It does not inject playback
events, instrument MeowWatch, simulate its player, or tap Pause to produce the
interrupted state.

The gate runs two separate Local-mode cases on the same source and app process:
permanent `AUDIOFOCUS_GAIN`, then transient `AUDIOFOCUS_GAIN_TRANSIENT`. It does
not prove GSM calls, audible output, physical hardware, Together room continuity,
a remote client's behavior, or quota preservation.

## Required behavior and evidence

1. Install the normal APK and the independent observer/helper into a dedicated
   emulator. The required `--avd-name` must have the task-specific
   `meowwatch_interruption_` prefix and exactly match `adb emu avd name`. The gate
   also checks the emulator serial, qemu marker and API-35/x86_64 runtime before
   the inherited clean install can remove app data, and revalidates that same
   identity before cleanup. It refuses a pre-existing focus helper. It removes
   prior MeowWatch data, as the existing
   lifecycle clean-install gate does; never use a personal emulator.
2. Share and explicitly open the reviewed 180-second fixture. Require actual
   Local mode, source/timeline/duration/Play semantics and at least two displayed
   seconds of native playback progress after pressing Play.
3. Verify the MeowWatch package UID owns the top `GAIN`/`none` entry in Android's
   current AudioService focus stack. Historical log text cannot satisfy this.
4. Start a separately installed foreground media service with a fresh nonce.
   It requests permanent `AUDIOFOCUS_GAIN` through the real AudioManager. Both
   its `AUDIOFOCUS_REQUEST_GRANTED` result and Android's current top focus owner
   must identify the exact helper UID. The result is also bound to its live PID,
   logcat PID, nonce, increasing sequence and device elapsed realtime.
5. Without a Pause tap, require a complete paused hierarchy within four seconds
   of the helper's timestamp immediately before `requestAudioFocus`. Both clocks
   use Android `elapsedRealtime`, including time asleep. The hierarchy must
   start after the granted result, finish within 4,000 ms of the request start,
   and match the sampled XML hash and unchanged application PID. This is an
   upper bound including traversal, not a precise decoder pause timestamp.
   The pre-request displayed position remains diagnostic: hierarchy return and
   command transport delays must not be counted as application reaction time.
   The controlled fixture, previous advancing sample and unchanged foreground
   history do not by themselves exclude an unrelated spontaneous pause between
   observations. After a four-second hold, its
   position must remain stable within one displayed second and the helper must
   still own focus.
6. Explicitly abandon the same focus request. Verify the release result and
   absence of the helper from the current focus stack. The same source remains
   paused for another four seconds, with at most one displayed second of drift.
7. Explicitly tap Play. Require MeowWatch to regain Android audio focus and
   playback to advance by at least two displayed seconds.
8. With playback running again, issue a fresh nonce-bound transient request from
   the same independent helper. Require Android's current focus stack to show
   the helper as top `GAIN_TRANSIENT` owner and MeowWatch immediately below it
   with `LOSS_TRANSIENT`. Without a Pause tap, require a complete paused native
   hierarchy within four device-clock seconds of the request start and stable
   displayed position through a four-second hold. The displayed duration must
   stay unchanged, position must not rewind, and the app PID must stay the same.
9. Abandon that transient request. Do not tap Play. Require a fresh native
   playing hierarchy within ten device-clock seconds of the helper's release
   event, the MeowWatch focus owner restored, and at least two displayed
   seconds of further progress after a four-second interval. Both pause and
   resume timing receipts include complete hierarchy traversal; they are upper
   bounds, not decoder event timestamps.

Every focus checkpoint verifies the same MeowWatch PID and focused window.
The baseline must contain a native resume callback logged by the current app
PID, proving that Activity lifecycle logging is available. Original Android
Activity lifecycle logs are compared from immediately before the interruption
through both focus cases: a new MeowWatch resume/pause/stop callback, a MeowWatch or
helper ANR/crash, or disappeared log history fails the gate. Therefore an Activity
background transition cannot be mistaken for successful foreground audio-focus
handling. The helper contains no Activity. The preparation-only emulator ANR
handling inherited from the lifecycle runner is disabled after fixture review.

UI positions are native-accessible elapsed labels from the real normal player,
at displayed-second precision. They are not independent millisecond decoder
timestamps. Current focus ownership comes from AudioService, not from those UI
labels. The original 432x960-at-most recordings use the lifecycle recorder's
unchanged picture-readiness, three-second duration-shortfall, eight-second
post-roll and final-frame observation coverage checks. Full-resolution PNGs and
original XML remain supplementary evidence. Three segments separate initial
media loading, permanent interruption and transient interruption; every
inter-segment gap is retained.
The longer fixture uses the same reviewed source packets, allowing both focus
cases and recording transitions to finish before natural end-of-media. Playback
does not loop, and pause/recovery deadlines and progress thresholds are unchanged.

## Helper boundary

`helper/src/com/meowwatch/audio_focus_probe/FocusService.java` targets API 35 and runs as an Android foreground media
service, as required for background focus clients on Android 15. A nonce-bound
acquire command selects permanent or transient gain; release abandons exactly
that request. Its exported
service requires the signature/privileged `android.permission.DUMP` permission,
which allows the emulator shell driver to issue the two fixed commands. There
are no network permissions, instrumentation targets, Activities or receivers.
The helper has `testOnly=true`, cannot back up data, and automatically abandons
focus and stops within 120 seconds. It requests no actual audio playback.

All paths use a fresh evidence directory. Finally cleanup attempts explicit
release, stops/removes only the helper whose absence was confirmed before this
test installed it, removes the owned observer, stops MeowWatch, and uses the
existing ownership-checked fixture server cleanup, only after this invocation
successfully started the server. A rejected startup with prior state cannot stop
that prior server. An uncertain release or
unconfirmed removal fails the run even when earlier observations passed. The
test never clears Android logs, changes volume/audio routing, accepts dialogs
during playback, or relaxes recording/ANR acceptance to obtain a pass.

## Run and inspect

Use `.github/workflows/android-interruption.yml`, or after building the normal
release APK, preparing a fresh API 35 AVD with a unique
`meowwatch_interruption_` name and the reviewed media fixture:

```sh
python3 -m unittest tools.android_interruption_runtime.test_run -v
python3 -m tools.android_native_ui.build --platform 35 --build-tools 36.0.0
python3 -m tools.android_interruption_runtime.build_helper --platform 35 --build-tools 36.0.0
bash tools/android_multi_device/prepare_fixture.sh --output build/android-interruption-fixture --seconds 180
export INTERRUPTION_AVD_NAME=meowwatch_interruption_your_unique_run
bash tools/android_interruption_runtime/ci.sh
```

The CI builds `--release --target=lib/main.dart` with purchase services disabled.
Its AVD name includes the workflow run ID and attempt and is passed unchanged
to the emulator runner and acceptance CLI.
The runner cannot independently determine a manually supplied APK's Dart
entrypoint. The external run limit is eight minutes plus 15 seconds for cleanup.

`build/android-interruption-artifacts/` contains `preparation.json`, helper
installation logs, original AudioService dumps, helper events and command
responses, lifecycle event logs, focused-window dumps, native XML/PNGs, original
recordings and `result.json`. Only `completed: true` with confirmed helper and
observer removal is a pass. The workflow uploads failure evidence too. Python
contract tests and helper compilation do not establish an Android runtime pass.

The package and focus parsing contracts were checked against Android 15 AOSP
[FocusRequester.dump](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-15.0.0_r1/services/core/java/com/android/server/audio/FocusRequester.java)
and [MediaFocusControl.dumpFocusStack](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-15.0.0_r1/services/core/java/com/android/server/audio/MediaFocusControl.java).
The current-PID resume baseline uses the callback emitted by
[Activity.performResume](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-15.0.0_r1/core/java/android/app/Activity.java).
The Android [audio-focus guide](https://developer.android.com/media/optimize/audio-focus)
documents focus-loss behavior and Android 15's foreground-service requirement.

Status: implemented tooling; fresh native execution and rendered evidence review
are required before claiming interruption acceptance.
