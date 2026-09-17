# Two-device Android evidence tools

These scripts launch two real Android Virtual Devices, capture their native
displays independently, and optionally compose the recordings side by side.
They never generate or substitute app screens.

CI requests a maximum recording edge of 1600 pixels for the phone and 1280
for the tablet at 3 Mbps. Before each native segment, the recorder reads the
current default-display geometry and chooses proportional, even output bounds
without upscaling. Each raw display dump and `recording-sizes.tsv` retain the
source and requested dimensions. Android display/UI geometry, native timestamps
and real recording gaps are unchanged. Rotation during a segment retains
Android screenrecord behavior; fresh footage must establish whether reduced
encoding load improves stalls. CLI callers that omit these options retain
the original full-resolution, 8 Mbps behavior.

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

## Hosted Ubuntu sequence

Generate the long-form media fixture and build both role-specific APKs serially
before starting the AVDs so compilation does not compete with two emulators for
CPU and RAM. Enable KVM and export `ANDROID_SDK_ROOT` before the final command.
The generated output directories must be empty at the start; the scripts refuse
stale files instead of mixing them into a later run.

```sh
room="mw-ci-${GITHUB_RUN_ID:-local}-$(date -u +%s)"
bash tools/android_multi_device/prepare_fixture.sh
bash tools/android_multi_device/build_together_apks.sh \
  --room "$room" \
  --server syncplay.pl \
  --port 8995 \
  --video-url http://10.0.2.2:18765/sync-fixture.mp4

bash tools/android_multi_device/ci_together.sh
```

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
