# Two-device Android evidence tools

These scripts launch two real Android Virtual Devices, capture their native
displays independently, and optionally compose the recordings side by side.
They never generate or substitute app screens.

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
39102, and collects the driver's fixed role-specific artifact directories. Its
six-minute bound is enclosed by continuous 170-second native segments, so pass,
failure, and timeout are captured from command start through exit. Every `adb`
call that targets a device includes the serial; do the same in custom commands.
The server-start and device-inventory calls are intentionally global. If no
command is supplied, recording lasts for `--seconds`.

The phone is portrait and the tablet is landscape. Every native segment retains
the real rendered pixels from its AVD. The recorder saves host timestamps for
both first segments. Composition uses those timestamps to add black pre-roll to
the later source, converts to constant 30 fps by dropping or duplicating
existing frames, scales without changing aspect ratio, adds neutral framing and
serial labels, and uses the shorter duration. It does not pretend unequal
recorder starts were simultaneous, interpolate motion, add fake UI, or claim a
frame came from a physical device.

The Bash composition entry point delegates to the portable Python helper. The
helper also runs directly on Windows and writes a source/alignment manifest,
SHA-256 file, and ffprobe report beside the MP4:

```sh
python tools/android_multi_device/compose_side_by_side.py \
  phone.mp4 tablet.mp4 recording-session.tsv review.mp4 \
  --result-label "RUN RESULT: FAILED - PAUSE CONVERGENCE"
```

The optional result label must describe the observed run. Every composition is
marked `Development test / synchronization verification in progress`; device
labels come from the timing evidence and say that the sources are native
recordings. Composition never turns a failed or incomplete verification into a
success claim.

Starting the next native segment requires a new `screenrecord` process, so a
small rotation gap can occur at each 170-second boundary. The per-segment TSV
timestamps expose those boundaries. The concatenated video and side-by-side
composition close those gaps for convenient review; use the original segments,
timings, and hashes when exact elapsed-time evidence matters.

Evidence is stored below serial-labeled directories and includes before/after
screenshots, logcat, device properties, display/window state, MediaCodec state,
SurfaceFlinger layers, native-video hashes, and ffprobe metadata when available.

Fixture license evidence: [Flutter assets-for-api-docs origin list](https://github.com/flutter/assets-for-api-docs#origin-of-third-party-content).
Emulator address evidence: [Android Emulator network address space](https://developer.android.com/studio/run/emulator-networking-address).
