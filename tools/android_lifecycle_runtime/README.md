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
3. Send the actual Android HOME key. Require an Android launcher to have focus for
   an eight-second hold, retaining the same application PID. Foreground the app.
   It must be paused and its position may advance by at most four displayed
   seconds from the last playing observation. This permits ADB/UI capture latency
   while rejecting playback that continued for the full background hold.
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
available. The workflow uploads these plus fixture provenance and local HTTP
server logs even on failure. A missing/false `completed` field is not a pass.

Python tests exercise the runner's acceptance/rejection rules with synthetic XML;
they do not validate Android playback. Only a successful actual workflow run
provides emulator lifecycle evidence. This gate is not physical-device, Cast,
frame-accurate video, audio-output, or manufacturer-specific background-policy
validation. Keep the real workflow result and remaining hardware checks distinct.
