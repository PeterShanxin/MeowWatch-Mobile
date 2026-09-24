# Native Android lifecycle acceptance

This gate exercises the installed, normal `lib/main.dart` release APK through ADB
and the Android accessibility API. It does not use an integration-test application,
injected player, app-private instrumentation endpoint, or screenshot recognition.
The workflow builds the APK it installs. A manual invocation must supply that same
normal application build; the runner cannot determine its Dart entrypoint itself.

The dedicated API 35 Google APIs x86_64 Pixel 6 AVD is reinstalled before testing.
Do not run this gate on a personal device: it intentionally removes this package
and its data. The runner requires an explicit `emulator-*` serial and checks
`ro.kernel.qemu=1` before installation. It leaves the application installed and
stopped, removes its separately installed observer helper, and stops only the fixture server
whose ownership the existing server helper verifies.

Before any application removal or installation, the runner waits up to 20 seconds
for its unique external-storage directory to become writable. It reuses the normal
install gate's bounded mkdir/touch probes and retains their errors in this run's
`storage-readiness.log`. A partial directory is cleaned without stopping or
modifying the application if storage readiness fails.

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
8. Only after those restored-pause checks pass, explicitly tap the native **Play**
   control. Observe playback, wait four seconds, and require at least two displayed
   seconds of further progress in the same new application PID. This proves that
   the user can manually continue watching after process restart.

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
python3 -m unittest tools.android_lifecycle_runtime.test_run tools.android_native_ui.test_observer -v
bash tools/android_multi_device/prepare_fixture.sh \
  --output build/android-lifecycle-fixture --seconds 90
flutter build apk --release --target=lib/main.dart \
  --dart-define=REVENUECAT_API_KEY=
python3 -m tools.android_native_ui.build --platform 35 --build-tools 36.0.0
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

The separate [native UI observer](../android_native_ui/README.md) is a test-only
APK whose instrumentation targets its own package. It never instruments or
restarts MeowWatch. It reads `UiAutomation.getRootInActiveWindow` directly without
an idle wait, returns bounded XML through a nonce-bound Base64 result, and checks
the actual app PID before and after every capture. Exact MeowWatch window focus
and the existing timeline/source/action semantics are still required.
`nativeUiObserver` records the helper hash and target; `nativeUiObservations`
records each snapshot's nonce, device/host times, app PID, node count and XML hash.
The workflow retains the helper build/signature/manifest evidence as well.

Two original native `screenrecord` MP4 segments supplement the XML assertions:
initial fixture review/playback, then the immediate pre-HOME sample through
foreground, explicit replay, new-process restoration and manual continuation.
Each is limited to
180 seconds and uses an even, proportional size within 432 x 960 at 2 Mbps.
This changes only the recorder output; the device display, application layout
and original PNG screenshots retain their normal dimensions. The Pixel 6
1080 x 2400 display records at exactly 432 x 960, without stretching.
The runner waits for a complete H.264 picture in the MP4 media payload before
sampling the Android `/proc/uptime` clock and starting UI actions. A single
up-to-three-second timeout while reading either the live media prefix or that clock is
recorded and retried only inside the original 20-second readiness deadline.
`readinessProbe` retains the safe operation name, probe attempt, timeout limit
and host monotonic time for every such timeout; it never retains raw command
arguments. The deadline is not extended, and both a complete picture NAL and a
valid device clock must both complete by that deadline. Each command timeout is
capped by the deadline's remaining time. Other ADB and validation errors are not
retried. It checks the exact recorder PID and output path before
sending SIGINT, refuses an existing recorder, and transfers only its own files.
`ffprobe` must confirm exactly one video stream with the expected dimensions;
Android's additional metadata data streams are allowed. The video duration must
cover the device's ready-to-stop elapsed interval with at most three seconds
missing. Both endpoints use Android `/proc/uptime`; host times are retained
separately. Early exits, truncated footage, a failed full `ffmpeg` decode, missing
device clock observations or cleanup failures cannot leave a passing result.
No recording is padded.

After the owned recorder has exited and closed its output, but **before pull**,
the runner queries the finalized remote file with `stat` and `sha256sum`.
Each command has a three-second timeout and addresses only the exact generated
recording path. A positive size of at most 64 MiB is required before hashing;
each response is limited to 512 bytes in the receipt and must identify one
unambiguous result. The pulled byte count and SHA-256 must match that device
receipt. `recorderExitedAtMonotonic`, `deviceFileReceipt`,
`pullStartedAtMonotonic` and `deviceFileMatchesPulledFile` retain the order and
outcome. A missing/invalid query or mismatch fails the run, but full original
decoding still runs first whenever the other original prerequisites permit it.
An existing decode error and its untouched `.decode.log` take precedence over
the added file-query failure; the latter remains separately visible.
`firstDecodeError` also retains the exit code, original stderr byte count/hash
and its first 4096 bytes. If a diagnostic log cannot be written, the write error
is recorded without replacing that original decode failure or skipping cleanup.

The optional `startup_action` is for a caller's already-planned native operation
that supplies changing frames while a static-screen MP4 is still buffered. The
default lifecycle and other callers keep their existing order. When supplied,
the callback runs once after the launched PID's exact `screenrecord` executable,
arguments and owned output path are checked. It receives the original launch
deadline; ownership, the pre-dispatch device clock, the callback and picture/clock
readiness all share that same twenty-second budget. A failed or uncertain callback
is retained and never retried; the caller must still stop and collect its owned
recorder. A completed callback or a live PID is never media readiness.

`startupAction` retains ownership/dispatch/completion host times, the device
elapsed clock immediately before dispatch and failure details. `startedAtMonotonic`
and `mediaReadyAtDeviceElapsedSeconds` are still assigned only after a complete
live picture and device clock are confirmed, **after** the callback. The callback
instant is not claimed as captured footage. Callers record their first successful
post-action native observation and screenshot using `observe_startup_result`;
the finalized original frame clock must cover that observation as well as the
existing final required observation. Missing or uncovered initial observations
fail after full decode. The first frame's offset from the dispatch clock is
diagnostic only: a first frame after a button tap can still capture the subsequently
verified state. No test requires or fabricates a frame before that tap.

The lower output size is a single-variable recording-cost diagnosis, not a
confirmed CPU or software-encoder fix. Run `35223362716` at 720 x 1600 recorded
the required observation at device elapsed 116.29 seconds through a last frame
at 117.51941565 seconds, but stopped at 124.53 seconds. Its duration was
58.690544 seconds against a 62.6-second measured segment, so the unchanged
three-second gate failed despite successful post-roll picture progress.
432 x 960 uses 36% of the previous output pixels while retaining 2 Mbps.
If a fresh run still has a comparable tail lag, investigate capture/codec/output
queuing instead of repeatedly lowering resolution or increasing tolerance.

Each recorder also collects auxiliary `native/lifecycle-XX.codec-*` evidence:
a device `date` baseline before launch, one `dumpsys media.codec` after picture
readiness, and codec-tag logcat output after stopping, including failure exits.
The log request is restricted to the observed recorder PID and the device-clock
baseline (rounded down to its second); it never clears logcat. Only CCodec,
Codec2Client, ACodec, OMXClient, MediaCodec, C2SoftAvcEnc, CCodecBufferChannel,
MPEG4Writer and screenrecord tags are selected. Encoder/muxer shutdown evidence
uses this same bounded request, not a second unrestricted log dump.
The codec-state dump belongs to this controlled CI emulator; it is not a general
device diagnostic collector. Each of the three commands has a three-second
timeout. Each saved stdout/stderr stream is capped at 256 KiB, with original
byte counts, truncation, nonzero exits and partial timeout output recorded in
`codecEvidence`. An unavailable baseline skips the log request explicitly.
These diagnostics do not substitute for or change acceptance: a failed or
missing diagnostic is reported, and cannot turn a failed recording into a pass.
Use the actual codec component evidence before attributing lag to software
encoding; a low frame count and SwiftShader graphics alone do not establish it.

After the final successful native observation and its screenshot in each segment,
the runner samples `/proc/uptime` as `requiredThroughDeviceElapsedSeconds` and
keeps recording during an eight-second bounded post-roll window. It reads only
new bytes from the original recording, counts complete H.264 picture NALs, and
requires at least one new picture beyond the file size observed at the start of
that window. Partial NALs, container/header growth, or a running process are not
picture progress. This is a recording-progress hint, not proof that the final
observation was captured. A post-roll failure still stops the owned recorder
and preserves the original file and failure metadata.

A timed-out live-byte read retries the same byte range within that original
eight-second window. Its partial output is discarded and recorded as a timeout;
it cannot advance the evidence cursor. Results arriving after the deadline are
rejected. Final native frame timestamps, full decode and duration checks still
decide coverage. This prevents a transient two-second ADB read timeout from
ending the recorder before its allotted drain window has elapsed.

Readiness and post-roll retain bounded `readSummaries`: command start/finish
times, byte offsets/counts and SHA-256 of the already-read bytes. Post-roll also
retains the cumulative prefix digest/count and last complete picture boundary.
Each read is at most 1 MiB; each phase retains the latest 128 summaries and counts
any dropped earlier summaries. These add no reads or recording time. A live MP4
header can legitimately change when the muxer finalizes, so prefix digests are
diagnostic evidence, not a replacement for complete-file or decoder acceptance.

The cause of run `35250983364`'s corrupt final H.264 sample remains unproven.
The device receipt distinguishes device output from pull/transfer changes; it
does not establish a codec or SIGINT fix. Stop mode, capture size/bitrate, full
decode, post-roll and timing tolerances remain unchanged.

Both segments end in independently observed **playing** advancement (`04-advanced`
and `14-restored-play-advanced`). The restored paused state and four-second
no-autoplay interval (`11` and `12`) must pass before the final native Play tap.
A static VFR screen is not required to generate new frames during that paused
interval; subsequent manual playback supplies an actual changing tail. Android's
[buffer-source implementation](https://android.googlesource.com/platform/frameworks/av/+/refs/tags/android-15.0.0_r1/media/module/bqhelper/GraphicBufferSource.cpp#336)
does not enable frame repetition by default, so continued recording alone is
not evidence that a static scene will produce another picture. The final manual
Play never substitutes for or resets the earlier no-autoplay assertions.

The finalized original MP4 must contain one valid Android Winscope v2 frame-clock
metadata record. Its frame count and relative timestamps must agree with the
actual video frames reported by `ffprobe` (within 0.1 ms for muxer quantization).
The first frame must precede, and the last frame must reach or follow, the final
required device observation. Missing, ambiguous, malformed or mismatched clock
metadata fails acceptance. The original three-second duration rule still covers
the entire ready-to-SIGINT interval **including post-roll**; it is not shortened
to the final observation. Continued encoder lag can therefore still fail this
gate even when the key observation is present. Full decoding, recorder ownership
and all playback/HOME/restart assertions remain required.

This clock is defined by Android's own
[screenrecord implementation](https://android.googlesource.com/platform/frameworks/av/+/refs/tags/android-15.0.0_r1/cmds/screenrecord/screenrecord.cpp#444):
Winscope v2 stores each encoded frame's presentation time in the
`elapsedRealtime` clock. It is written only after the encoder output loop ends,
so live file growth cannot establish that timestamp coverage before stopping.
`native/lifecycle-XX.frame-clock.json` retains every parsed device timestamp
alongside its video PTS. The recordings manifest records the required phase,
clock source, first/last frame times, post-roll byte/picture observations, and
any failed post-roll or frame-clock validation.

Run `35219098578` demonstrates why the final observation needs its own gate:
its first segment decoded completely, but its last actual frame was at device
elapsed 123.391883899 seconds, before the final native observation at 125.929
seconds and the stop request at 130.79 seconds. The final video picture displayed
26 seconds while the subsequent original screenshot displayed 29 seconds.
The original duration guard correctly failed it; it provides no HOME or
process-restart acceptance. A fresh native run is needed to establish the
post-roll behavior, and synthetic clock tests do not establish capture quality.

`recordings.json` and `result.json` retain host launch/PID/start/stop/pull times,
device ready/stop times, the original MP4 SHA-256, measured/decoded durations
and failures. There is an
explicitly measured stop/pull/start gap between the two stages, before the fresh
pre-HOME baseline. The segments are not presented as uninterrupted footage.
No playback assertion depends on video appearance, frame rate or these timing
tolerances. Raw segments remain available after a failed test where transfer
is possible.

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

Run `35194003102` stopped at `03-playing` after three ten-second UIAutomator
dump timeouts. The failure screenshot shows actual playback at 30 seconds;
the last completed XML was the earlier paused state. Android's dump command
waits for one second without accessibility events, while the playing timeline
updates about every 100 ms. The independent observer removes this idle-wait
dependency. That failed run provides no HOME/restart evidence, and a fresh native
run is required. The original 45-second phase deadlines, 65-second initial-review
deadline and all playback thresholds remain unchanged.

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
# Hosted rendering load

The dedicated API 35 phone uses 540x1200 pixels at 210 dpi, preserving the
411.43x914.29 dp layout of its original 1080x2400 / 420 dpi Pixel 6 profile.
`prepare_avd.py` verifies the exact task-owned AVD name and original geometry
before changing its pre-launch framebuffer. The artifact retains both configs.
This reduces software rendering work; all pause, replay, process-restart and
native observer assertions remain unchanged. It is emulator evidence.
