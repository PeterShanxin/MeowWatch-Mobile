# Two-device Android evidence tools

These scripts launch two real Android Virtual Devices, capture their native
displays independently, and optionally compose the recordings side by side.
They never generate or substitute app screens.

CI requests a maximum recording edge of 1600 pixels for the phone and 1280
for the tablet at 3 Mbps. Before each native segment, the recorder reads the
current default-display geometry and chooses proportional, even output bounds
without upscaling. Each raw display dump and `recording-sizes.tsv` retain the
source and requested dimensions. The recorder does not change display geometry,
native timestamps or real recording gaps. Rotation during a segment retains
Android screenrecord behavior; fresh footage must establish whether reduced
encoding load improves stalls. CLI callers that omit these options retain
the original full-resolution, 8 Mbps behavior.

The production journey's manual `compact_capture` option requests a 960-pixel
maximum edge for both recordings, retaining 3 Mbps and the actual display
layouts. The default remains 1600/1280. `ci_together.sh` also accepts the
`MEOWWATCH_PHONE_RECORD_MAX_EDGE` and `MEOWWATCH_TABLET_RECORD_MAX_EDGE`
environment values through the recorder's existing validation. This is a
recording-cost comparison: the accepted 5137e58 run's actual playback windows
contain only about 1–3 captured frames per second. A compact take must pass the
same product gates and be inspected for motion and legibility before selection;
lower resolution alone does not prove the cause or cure of sparse native frames.

Before either recorder or the driven command starts, each task-owned Android
directory must pass an actual `.mp4` creation/removal probe. Preparation uses a
20-second readiness window with bounded ADB calls and retains failed probes in
`storage-readiness.log`. A successful `mkdir` alone is insufficient during cold
boot: MediaProvider may not yet have attached the external storage volume.
Storage probes may repeat before capture; a failed recording is never restarted
as though no evidence had been lost.

Recorder startup requires a live host ADB process, a uniquely identified native
PID stable across two observations, and a nonempty original MP4. A transient PID
or an immediate file-open error cannot release the showcase command. Startup is
bounded, and the original segment diagnostics are retained on failure. After
startup, a failed recorder stops the task-owned showcase command promptly;
available segments are still collected, the run fails, and no replacement take
is silently started. Native 170-second rotations remain separate segments with
their real timing gaps.

## Cold-boot admission and two-player CI displays

The launcher creates a phone with physical `720x1600` pixels at `280` dpi and a
tablet with physical `1280x800` pixels at `160` dpi. These fixed AVD settings keep
the original profiles' approximately `411.43x914.29` dp and `1280x800` dp geometry
while reducing pixel work on the shared software-rendering host. They are a
resource-limited two-native-player CI configuration, not the independent
full-resolution five-layout acceptance. Any CPU improvement remains to be
measured. No `wm` size or density override is applied.
The new AVDs also set `skin.name` and `skin.path` to those same `WxH` sizes:
the [emulator's skin resolver](https://android.googlesource.com/platform/external/qemu/+/refs/heads/emu-master-dev/android/emu/avd/src/android/avd/info.c#1599)
checks `skin.path` before falling back to the configured LCD size.

Before read-only admission, a separate `prepare_sdk_setup.py` step may recover
one eligible system ANR per task-created emulator within a shared 90-second
budget. It verifies the actual AVD name, debuggable emulator properties and
absence of MeowWatch. Recovery additionally requires completed boot/provisioning, a uniquely focused
`com.google.android.googlesdksetup` ANR window and a matching `am_anr` event.
The separate Launcher case is restricted to Linux x86_64 runners and a measured
API 35 x86_64 guest. It requires the exact system package
`com.google.android.apps.nexuslauncher`, user-0 package UID, live process UID/PID
matching the latest Launcher ANR, and resolved/focused Home equal to that
package's `NexusLauncherActivity`. A same-named non-system package or another
Home component cannot qualify. The two cases share one recovery allowance per
device; historical SDK Setup events cannot authorize a second recovery.
Both devices pass these safety checks before either is changed. Normal screens
receive no mutation, including Home with historical GMS or other ANR events.
Normal provisioning with unresolved Home or Settings FallbackHome also receives
no mutation and proceeds to the existing read-only gate's bounded wait.
All well-formed user-0 ANR history remains in the evidence; unrelated history
never authorizes recovery. Ambiguous state, another package's current ANR
window, installed MeowWatch or an unverified device fails preparation.

An eligible recovery saves the original PNG and window/event evidence, rechecks
the same conditions, and force-stops only the eligible exact package once.
Android dismisses the ANR window asynchronously; only that original window ID
may retire during bounded observation. The old window must disappear before
the single HOME intent is sent to the verified launcher. Both settling phases
share a 30-second window, and final success requires Home owning both focus
fields with no remaining ANR window. Launcher recovery also requires the same
system UID and a new live Launcher PID. It retains every command outcome,
before/after snapshot and original ANR event. Failure or uncertainty is never
retried. Any new, changed or missing ANR history between confirmation and the
post-recovery checks stops further mutation. No package is disabled, log cleared,
provisioning/security setting changed, or MeowWatch ANR dismissed.
`sdk-setup-preparation/` holds this separate
pre-installation record; it never substitutes for the following fresh admission.

Before the launcher returns, `device_readiness.py` reads both devices within a
shared 240-second budget. Both must pass three consecutive device-time windows
of at least five seconds: completed boot/provisioning, stopped boot animation,
resolved Home owning both focused window and application, no observed system
dialog or new ANR, CPU idle at least 20%, CPU PSI `some` stall at most 20%, and
memory PSI `full` stall at most 1%. A failed window resets the joint count.
Missing measurements or a failure on either device reject the entire run.
These limits are the test runner's resource policy, not Android guarantees.

Sampling is read-only. PSI uses cumulative `total` deltas and the device elapsed
clock; system-level CPU `full=0` is not evidence of idleness. If shell PSI reads
are denied, only a verified debuggable emulator may use `su 0` to read the same
proc files. The actual access path is recorded; unavailable privilege or data
fails explicitly. No dialog is dismissed, app stopped, or permission, SELinux,
adbd or ANR timeout changed by this gate.

Each session retains AVD config snapshots plus `device-readiness/sample-*.json`
and `result.json`: raw command outputs, device counters, window decisions,
physical size/density readback, requested RAM, any emulator-reported RAM increase,
and guest-visible `MemTotal`. Requested 3072 MiB is not reported as actual RAM.
Unexpected physical geometry or a display override fails. The production invite
server starts only after this gate, before recording; its TTL remains 900 seconds.

```sh
python3 -m unittest tools.android_multi_device.test_device_readiness -v
```

## Media fixture HTTP contract

`start_fixture_server.sh` runs the repository's `fixture_server.py` on
`127.0.0.1`; emulators still use `10.0.2.2:18765`. It serves only the prepared
`sync-fixture.mp4` and optional byte-identical `Bee.mp4` alias. Query-bearing
shared links select the same file; missing videos remain real 404 responses.
Directory listings, other files, traversal and symlink media are rejected.

GET supports a single closed, open-ended or suffix byte range with 206,
`Content-Range` and the exact partial `Content-Length`. Invalid, multiple and
unsatisfied byte ranges return 416 with the full size. Unknown units are ignored.
HEAD returns full metadata without a body and ignores Range, as required by
[HTTP semantics](https://www.rfc-editor.org/rfc/rfc9110.html#section-14.2).
An unmatched If-Range validator falls back to a full response. Each client has
its own file handle; a cancelled or stalled reader does not block another.
The handler inherits the stock server's `None` socket timeout; no new transfer
deadline is introduced by the Range experiment.

`http-server.log` retains bounded JSON request records: UTC start, safe asset
name, selected range, status, completed socket-write bytes, monotonic elapsed
time and outcome. Actual socket timeouts are recorded as `timeout`, separately
from peer reset/broken-pipe `cancelled`; a timeout before headers has status 0.
Query text and arbitrary paths/header values
are never logged. Bytes describe completed writes, not decoder consumption;
a failed write may have delivered a partial final chunk. At 4096 records the
log emits an explicit limit marker and stops adding request records. Server
readiness and response headers are retained separately from app acceptance.

The server receipt binds its Linux PID to the complete command, fixture directory,
port and process birth token. Startup captures that token from its verified
child before HTTP readiness, then retains it unchanged. Failure cleanup requires
the original birth token; missing identity never authorizes a signal. Stop
refuses a changed identity, rechecks before
a TERM fallback, and verifies exit; it never stops all Python processes.

This replaces the prior stock Python server's full-file 200 response to seek
requests. It is a fixture transport experiment, not proof that networking caused
the captured movie stalls. Native app assertions, fixture bytes and recording
geometry remain unchanged; fresh original recordings must establish any effect.

```sh
python3 -m unittest tools.android_multi_device.test_fixture_server \
  tools.android_multi_device.test_fixture_contract -v
```

The HTTP contracts run on Windows and Linux. Linux additionally executes real
start/stop scripts and verifies port-conflict cleanup, refusal of an unrelated
PID or changed birth token, and successful shutdown of the owned server.

## Hosted Ubuntu sequence

The production workflow prepares SDK packages once, before media generation and
APK compilation. `prepare_sdk_packages.py` invokes the existing selected SDK's
`sdkmanager` with `--sdk_root` and `--verbose` for `platform-tools`, `emulator`,
`platforms;android-35` and `system-images;android-35;google_apis;x86_64`. It records
tool metadata/version, exact arguments, original stdout/stderr bytes, exit or
timeout outcome and free disk space in `sdk-preparation/`. A failed or uncertain
install stops that run; there is no retry, cache removal or tool-version change.
Successful installation must also have matching `package.xml` paths, image
API/tag/ABI properties and nonempty required tool/image files. This validates
installed metadata and file presence, not an independent archive checksum or
bootability; emulator acceleration, boot and read-only admission remain required.

The launcher never installs packages. It validates the selected SDK before any
emulator command and uses executables only from that SDK. In the production
workflow, `MEOWWATCH_ANDROID_SDK_PREPARATION` points to a receipt bound to the
GitHub run, attempt, head, SDK root and installed metadata. The launcher rejects
stale or changed receipts and saves `sdk-validation.json`. Existing callers may
omit the receipt when they have already installed the exact packages; they still
must pass the same file/metadata validation. Installation diagnostics improve
the evidence for ZIP failures; they do not establish their underlying cause.

Generate the long-form media fixture and build both role-specific APKs serially
before starting the AVDs so compilation does not compete with two emulators for
CPU and RAM. Enable KVM and export `ANDROID_SDK_ROOT` before the final command.
The generated output directories must be empty at the start; the scripts refuse
stale files instead of mixing them into a later run.

```sh
python3 -m tools.android_multi_device.prepare_sdk_packages prepare \
  --sdk-root "$ANDROID_SDK_ROOT" \
  --output build/android-multi-device/sdk-preparation
export MEOWWATCH_ANDROID_SDK_PREPARATION="$PWD/build/android-multi-device/sdk-preparation/result.json"
room="mw-ci-${GITHUB_RUN_ID:-local}-$(date -u +%s)"
bash tools/android_multi_device/prepare_fixture.sh
bash tools/android_multi_device/build_together_apks.sh \
  --room "$room" \
  --server syncplay.pl \
  --port 8995 \
  --video-url http://10.0.2.2:18765/sync-fixture.mp4

bash tools/android_multi_device/ci_together.sh
```

The production phone/tablet workflow defaults to `debug`, including pull
requests. A manual dispatch may select `runtime_mode: profile` for an AOT
diagnostic recording with the same production UI target, host/guest roles,
explicit test expectations, native capture, and ANR guards. The build writes
`mode` to `apks/build-provenance.tsv`; the runner checks that mode and both APK
hashes before launching devices. Profile builds explicitly set an empty
`REVENUECAT_API_KEY`: they cannot use the debug-only Test Store key, and this
free-host journey does not exercise purchase or entitlement configuration.
For an equivalent local diagnostic, pass `--mode profile` to both
`build_together_apks.sh` and `ci_together.sh`; omit it for the original debug
path.

Profile turns off Dart and Flutter framework `assert` checks, even though this
journey's explicit `expect` calls and thrown test failures still execute. It
does not replace debug correctness or the separate real RevenueCat purchase
gate, and it does not guarantee smoother playback. Review the complete
original phone and tablet native recordings and their segments, recording
timing/gap manifest, driver observations, and device logs before attributing a
change in visible motion to the app, recorder, or hosted emulator. A passing
driver or side-by-side composition alone is insufficient motion evidence.

Flutter 3.44's integration binding uses a real IME, while
`WidgetTester.enterText` sends a special test client ID that Flutter accepts
only in debug mode. The production Together test keeps `tester.enterText` for
debug runs. In profile diagnostics it focuses the same visible text field and
injects a `TextEditingValue` through its `EditableTextState`, then verifies
that the field actually retained the full value before continuing through the
normal UI submit and validation path. This is test-only synthetic text input,
not physical keyboard proof. Profile runs still require a successful real
guest join, native playback, and every existing explicit test expectation.

`ci_together.sh` starts the loopback-only fixture server, launches the two AVDs,
records the complete smoke, composes valid native recordings, and then stops
the task-owned AVDs and server even when a stage fails. It preserves the first
test or tooling exit code; cleanup failures only replace an otherwise successful
result. Each run uses a session-scoped `ANDROID_AVD_HOME` for AVD creation,
emulator lookup, and deletion, so hosted-runner user-home settings cannot split
those operations across different directories. The lower-level scripts remain
available for local diagnosis.

`prepare_fixture.sh` downloads Flutter's official `bee.mp4` at a reviewed,
pinned SHA-256. Flutter documents that file as CC0. FFmpeg stream-copies and
repeats the original H.264/AAC packets into an approximately 90-second fixture;
it does not synthesize, interpolate, or re-encode frames. The Python server
binds only `127.0.0.1:18765`. Android Emulator maps host loopback through
`10.0.2.2`, so both isolated AVDs load the same real MP4 at
`http://10.0.2.2:18765/sync-fixture.mp4`.

Replace the provided smoke runner with another test or automation command only
when the repository uses another integration target. The provided runner drives
prebuilt host and guest APKs concurrently, uses host VM service ports 39101 and
39102, and collects the driver's fixed role-specific artifact directories. The
default recording window is six minutes with 330-second drives; production UI
uses ten minutes with 540-second drives. Both use consecutive 170-second native
segments; process rotation and transfers can leave recording gaps. Every `adb`
call that targets a device includes the serial; do the same in custom commands.
The server-start and device-inventory calls are intentionally global. If no
command is supplied, recording lasts for `--seconds`.

Every native segment retains the real rendered pixels and observed orientation
from its AVD. Inspect the current window geometry and `recording-sizes.tsv`;
a hardware profile's natural dimensions do not prove its current orientation.
The recorder saves a host timestamp
immediately before each ADB `screenrecord` command. Composition reads every
segment's timestamp and original MP4, places it at its estimated offset, and
shows black `RECORDING GAP` panels between available intervals and after the
shorter device ends. The output lasts through the longer available timeline.
It converts to 30 fps by dropping or duplicating existing frames, preserves
aspect ratio, and adds neutral framing and serial labels.

ADB command time is not first-frame time: launch latency is unknown, and media
durations can overlap the next command timestamp. The later segment takes over
at its timestamp; the manifest records any overlapping tail, and the original
files retain all frames. These approximate timestamps cannot establish precise
playback synchronization. The compositor does not interpolate motion, add fake
UI, or claim an AVD frame came from physical hardware.

The Bash composition entry point delegates to the portable Python helper. The
helper also runs directly on Windows and writes a source/alignment manifest,
SHA-256 file, and ffprobe report beside the MP4:

```sh
python tools/android_multi_device/compose_side_by_side.py \
  phone-emulator-5554/native.mp4 tablet-emulator-5556/native.mp4 \
  recording-session.tsv review.mp4 \
  --result-label "RUN RESULT: FAILED - PAUSE CONVERGENCE"
```

The optional result label must describe the observed run. Every composition is
marked `Development test / synchronization verification in progress`; device
labels come from the timing evidence and say that the sources are native
recordings. Composition never turns a failed or incomplete verification into a
success claim.

The input layout must include each device's `segments/` directory and
`recorder-control/phone-segments.tsv` and `tablet-segments.tsv` beside the
session timing file. The positional `native.mp4` paths identify the device
directories; their concatenated contents are not used. Missing native files
remain explicit gaps. Missing timing rows or an unbounded missing final segment
fail composition instead of guessing a timeline.

A segment with explicit zero video duration is retained only when FFmpeg fully
decodes it without errors to exactly one frame. Its original file, hash, probe,
decode check and command-time anchor remain in the manifest with status
`retained-but-no-duration`. That frame is not rendered and receives no invented
duration; the device panel shows `RECORDING GAP / No timed frames`. Other native
segments with positive durations must bound the overall timeline. All-untimed
inputs or an untimed final anchor beyond that known bound still fail.

Starting the next native segment requires a new `screenrecord` process, so a
small rotation gap can occur at each 170-second boundary. The per-segment TSV
timestamps expose those boundaries. The legacy concatenated `native.mp4`
closes those gaps and is not an elapsed-time representation. The side-by-side
composition preserves estimated gaps; retain the original segments, timing
metadata, and hashes as primary evidence.

Evidence is stored below serial-labeled directories and includes before/after
screenshots, logcat, device properties, display/window state, MediaCodec state,
SurfaceFlinger layers, native-video hashes, and ffprobe metadata when available.

Fixture license evidence: [Flutter assets-for-api-docs origin list](https://github.com/flutter/assets-for-api-docs#origin-of-third-party-content).
Emulator address evidence: [Android Emulator network address space](https://developer.android.com/studio/run/emulator-networking-address).
