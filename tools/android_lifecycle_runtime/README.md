# Native Android lifecycle acceptance

This gate exercises the installed, normal `lib/main.dart` release APK through ADB
and Android UIAutomator. It does not use an integration-test application,
injected player, app-private instrumentation endpoint, or screenshot recognition.
The workflow builds the APK it installs. A manual invocation must supply that same
normal application build; the runner cannot determine its Dart entrypoint itself.

The dedicated API 35 Google APIs x86_64 Pixel 6 AVD is reinstalled before testing.
Do not run this gate on a personal device: it intentionally removes this package
and its data. The runner requires an explicit `emulator-*` serial and checks
`ro.kernel.qemu=1` before installation. It leaves the application installed and
stopped, removes only its own remote UI dumps, and stops only the fixture server
whose ownership the existing server helper verifies.

## What must pass

1. Share the actual 90-second fixture URL into the exported normal Activity.
   Complete first-run onboarding and explicitly confirm **Open video**.
2. Observe the fixture name, native-accessible player timeline, 90-second duration,
   and paused controls. Explicitly press **Play**. Two UI observations must show
   increasing elapsed time, by at least two displayed seconds.
3. After saving the playing screenshot, refresh the actual accessible timeline
   and send the Android HOME key without another screenshot transfer in between.
   Require an Android launcher to have focus for an eight-second hold, retaining
   the same application PID. Foreground the app. It must be paused and its
   position may advance by at most four displayed seconds from that immediate
   pre-HOME observation. This permits ADB/UI capture and lifecycle dispatch
   latency while rejecting playback that continued for the full background hold.
4. Observe again after four seconds: still paused, position stable within one
   displayed second. Explicitly press **Play**, then prove progress again.
5. Pause at a nonzero position of at least eight seconds. Send HOME to trigger
   persistence, force-stop the package, and prove its old process is absent.
6. Launch the normal app in a different PID. Locate the fixture's actual
   **Continue Watching** card (up to four swipes within the observed home scroll
   container). Its displayed saved position must match within one second.
7. Tap that card. Require the same filename and 90-second timeline, restored paused
   position within one second, and another four-second observation with no
   autoplay or progress.

The fixture is the existing reviewed, SHA-256-checked CC0 Flutter bee video,
repeated by packet copy using `tools/android_multi_device/prepare_fixture.sh`.
A task-owned loopback HTTP server exposes it only through the emulator's
`10.0.2.2:18765` host alias. There are no credentials or external playback URLs.
The same controlled HTTP source stays available during process restart. This
checks network-source Continue Watching; it does not establish persistence of
Android document-provider grants or offline local-file access.

## Run

Use `.github/workflows/android-lifecycle.yml` (**Android normal application
lifecycle**), or from the repository root on a Linux Android SDK host:

```sh
python3 -m unittest tools.android_lifecycle_runtime.test_run -v
bash tools/android_multi_device/prepare_fixture.sh \
  --output build/android-lifecycle-fixture --seconds 90
flutter build apk --release --target=lib/main.dart \
  --dart-define=REVENUECAT_API_KEY=
# Start a dedicated API 35 emulator-5554 before this command.
bash tools/android_lifecycle_runtime/ci.sh
```

The native run has an eight-minute external limit, plus 15 seconds for timeout
cleanup. Fixture preparation and building are separate bounded workflow steps.
Both fixture/server state and evidence directories must start empty; use a fresh
checkout for another workflow run. Purchase services are disabled for this gate.

`build/android-lifecycle-artifacts/result.json` records the actual Android
model/API/ABI, installed package metadata, APK and fixture hashes, process IDs,
elapsed positions, and sampled monotonic observation times. Every successful
stage saves its original XML and a supplementary screenshot. Failure records the
phase, safe error message, previous samples, last XML, and a screenshot where
available. `failure-window.txt` preserves the focused-window dump paired with
the last XML. The workflow uploads these plus fixture provenance and local HTTP
server logs even on failure. A missing/false `completed` field is not a pass.

Python tests exercise the runner's acceptance/rejection rules with synthetic XML;
they do not validate Android playback. Only a successful actual workflow run
provides emulator lifecycle evidence. This gate is not physical-device, Cast,
frame-accurate video, audio-output, or manufacturer-specific background-policy
validation. Keep the real workflow result and remaining hardware checks distinct.

### Transient UI capture timeouts

The runner retries a timed-out read-only Android UI observation up to three
attempts within the phase's original polling deadline. Each attempt requests a
fresh hierarchy; previously captured XML cannot establish playback progress.
The retry is restricted to observation, so an uncertain timed-out tap is never
repeated automatically. Playback advancement, the eight-second HOME hold,
four-second background-position tolerance, paused stability and process-restart
checks are unchanged.

`result.json` records `observationTimeouts` with safe operation names rather
than raw command arguments. On failure, `lastCompletedUiObservation` identifies
the phase/time associated with the retained diagnostic XML. A screenshot taken
after a timeout may show a later player time than that older XML.

Run `35188550930` stopped before HOME while sampling `04-advanced`: only the
0-second loaded state and 3-second playing state were recorded. The exception
was an unhandled observation `TimeoutExpired`; the supplementary failure image
shows playback at 20 seconds. That run did not retain the timed-out subcommand
and is not a lifecycle pass. This change makes that transient capture failure
retryable and diagnosable; a fresh native run is still required.

### Initial emulator setup dialogs

During `01-fixture-review` only, the runner can close up to two verified Pixel
Launcher or Google SDK Setup ANR dialogs that obscure the MeowWatch activity.
Each action requires an emulator serial, `ro.kernel.qemu=1`, the exact Android
system ANR package/title/close control and MeowWatch as the underlying activity.
The runner captures XML, focus and screenshot evidence and then re-observes the
same dialog before tapping. A close that times out stops the gate rather than
being repeated. `preparationAnrRecoveries` records each attempt and its outcome.

The existing phase deadline is unchanged, and fresh MeowWatch UI must still pass
the original onboarding and media-review checks after recovery. Recovery is
disabled once initial preparation ends: an ANR during playback, HOME, explicit
replay or process-restart observation still fails the gate. MeowWatch ANRs and
unrelated dialogs are never closed by this mechanism.

Run `35191578094` failed during `01-fixture-review`; its original XML and native
screenshot show a Pixel Launcher ANR over onboarding, with no playback samples.
It provides no HOME or restart evidence. This recovery needs a fresh native run;
the Python regressions establish only the strict control and evidence rules.
