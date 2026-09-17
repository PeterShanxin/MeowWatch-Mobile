# Android runtime playback evidence

The Android runtime smoke test exercises the production `LocalMobileTarget`
with the official Flutter `video_player` plugin. It does not replace the player
with a fake or call plugin APIs through a mock.

## What the smoke test checks

On an Android runtime, the test:

1. opens a direct HTTPS MP4 through `LocalMobileTarget`;
2. mounts the production controller in a real `VideoPlayer` texture widget;
3. verifies initialization, decoded video dimensions, and duration;
4. verifies that play advances the reported position;
5. verifies that pause keeps the position stable;
6. seeks and checks the resulting reported position;
7. tears down the texture, reopens the media with a new controller, renders it,
   and disposes the target; and
8. captures PNG screenshots of the actual Android Flutter surface while video
   is playing through the test-only `NativeScreenshots` helper.

The helper converts the surface only around each capture, preserves the normal
`binding.takeScreenshot` reporting path, and attempts to restore the native
surface in `finally`, including capture failures. It registers the SDK teardown
once per test and explicitly schedules frames before capture and after restore.
The short settling period is not a native completion acknowledgement: inspect
the original Android recording to verify that rendering continues between
screenshots. This uses Flutter 3.44.0 implementation details; see the exact
upstream references in
[`tools/native_capture/README.md`](../tools/native_capture/README.md) before
changing the Flutter pin.

The primary smoke fixture remains Flutter's official `bee.mp4` `video_player`
documentation asset:

- media: <https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4>
- source and license declaration:
  <https://github.com/flutter/assets-for-api-docs#origin-of-third-party-content>

The Flutter repository declares this 1.3 MB asset CC0. Keeping the sample small
reduces CI network exposure while still exercising Android's real media stack,
network data source, decoder, texture, and player controls.

### Shipped sample check

After the bee playback/reopen checks, the
[`integration test`](../integration_test/playback_smoke_test.dart) now loads
`sampleVideo()` through a fresh `LocalMobileTarget`. This is the exact public
Sintel trailer selected by the production media picker's **Try a short film**
action; its URL, title and attribution live in
[`sample_video.dart`](../lib/core/media/sample_video.dart).

The added check requires an initially paused, ready player with a duration of
51–53 seconds, mounts its real video texture, plays until the native position
reaches at least 900 ms, and captures `sample-sintel-playing.png`. It then pauses
and seeks to 10 seconds with the existing 800 ms tolerance. The `shippedSample`
entry in `result.json` records the URL, title, duration, decoded dimensions,
advanced/seek positions and screenshot name separately from the bee result.

[Run 35199455129](https://github.com/PeterShanxin/MeowWatch-Mobile/actions/runs/35199455129)
passes on an API 35 x86_64 emulator at `70575be`: the trailer decodes at
854 × 480, reports 52,209 ms, advances to 1,175 ms and seeks to 10,000 ms.
The native screenshot was inspected and shows the trailer's opening mountain
scene. This smoke loads the media item directly; the separate production
journey's new picker-tap check still needs fresh native execution.

## Run it on an Android device or emulator

Start or connect an Android runtime, then run from the repository root:

```sh
flutter pub get --enforce-lockfile
flutter drive \
  --driver=test_driver/playback_smoke_driver.dart \
  --target=integration_test/playback_smoke_test.dart \
  -d <android-device-id>
```

The driver writes evidence to `build/android-runtime-artifacts/`:

- `screenshots/playback-playing.png`
- `screenshots/playback-reopened.png`
- `screenshots/sample-sintel-playing.png` (new shipped-sample check)
- `result.json`

The screenshots are accepted only when the driver receives a nontrivial PNG.
The state assertions and image artifacts are complementary: position changes
alone do not prove a rendered surface, while a screenshot alone does not prove
working play, pause, seek, reopen, and disposal behavior.

## Hosted emulator workflow

`.github/workflows/android-runtime.yml` runs on an x64 Ubuntu 24.04 GitHub-hosted
runner with KVM and an API 35 `google_apis` x86_64 Pixel 6 AVD. It runs for:

- relevant pull requests, using the unprivileged `pull_request` event;
- relevant pushes to `main`; and
- manual `workflow_dispatch` runs.

The workflow grants only `contents: read`, persists no checkout credentials,
uses no secrets, and pins every third-party action to a reviewed full commit
SHA. The selected releases were current when this workflow was added:

| Action | Release | Pinned commit |
| --- | --- | --- |
| `actions/checkout` | v6.0.2 | `de0fac2e4500dabe0009e67214ff5f5447ce83dd` |
| `subosito/flutter-action` | v2.23.0 | `1a449444c387b1966244ae4d4f8c696479add0b2` |
| `ReactiveCircus/android-emulator-runner` | v2.38.0 | `a421e43855164a8197daf9d8d40fe71c6996bb0d` |
| `actions/upload-artifact` | v5.0.0 | `330a01c490aca151604b8cf639adc76d48f6c5d4` |

The runner action follows its documented KVM setup for GitHub-hosted Linux.
Flutter is fixed to 3.44.0 so toolchain changes do not silently alter the gate.

The exact CI runtime invocation is:

```sh
flutter build apk \
  --debug \
  --target=integration_test/playback_smoke_test.dart
flutter drive \
  --driver=test_driver/playback_smoke_driver.dart \
  --target=integration_test/playback_smoke_test.dart \
  --use-application-binary=build/app/outputs/flutter-apk/app-debug.apk \
  -d emulator-5554
```

The uploaded artifact contains the screenshots, the structured result,
`flutter-drive.log`, Android `logcat`, runtime properties, MediaCodec state,
SurfaceFlinger layer names, and a start-to-finish Android screen recording.
These files identify the actual runtime and help distinguish network, decoder,
rendering, and assertion failures.

The APK is built before the emulator starts, and `flutter drive` installs that
exact prebuilt binary. The workflow starts the Android-native `screenrecord`
process immediately before invoking `flutter drive` and stops it only after the
command completes. This keeps compilation time out of the video while retaining
the complete install, launch, rendered playback, and test-completion sequence.

Android limits a single recording to 180 seconds, so the recorder uses
consecutive 170-second segments named `playback-smoke-000.mp4`,
`playback-smoke-001.mp4`, and so on. The workflow records the exact remote
process ID, sends only that process SIGINT so the active MP4 is finalized, then
pulls every segment into the artifact's `recording/` directory. A 15-minute
bound on `flutter drive` leaves time to finalize and upload recordings even
when the smoke test hangs or fails. The gate fails if it cannot identify its
owned recorder, pull the recording, or find a nontrivial MP4. `screenrecord.log`
records recorder and pull diagnostics.

This recording is the initial Android playback feasibility showcase. It shows
the minimal real video surface used by the smoke test from start to finish; it
is not the final MeowWatch product demo or proof that all product flows are
complete.

## Evidence boundary

A passing hosted run proves the production Flutter adapter works with Android's
platform media and texture stack on that API 35 x86_64 emulator. The logs show
which codec implementation that run selected. It is not proof of a physical
ARM phone's hardware decoder, audio output, lifecycle behavior, LAN pairing,
RevenueCat, or Cast. Those remain real-device acceptance checks. A local
Windows 11 ARM host without supported AVD acceleration also cannot replace the
hosted runtime result.

## Two-device phone and tablet evidence

`tools/android_multi_device/` prepares a truthful two-client hosted test:

- a Pixel 6 profile on `emulator-5554`, portrait, 2 vCPUs and 3072 MiB RAM;
- a Pixel Tablet profile on `emulator-5556`, landscape, 2 vCPUs and 3072 MiB
  RAM; and
- Android 35 `google_apis` x86_64 images accelerated through Linux KVM.

The standard public `ubuntu-24.04` runner currently provides 4 x64 vCPUs,
16 GB RAM and 14 GB SSD. This allocation intentionally uses all four virtual
CPU slots but only 6 GB of configured guest RAM, leaving host memory for the
Android SDK, adb, graphics emulation, the test driver, and evidence processing.
Build the APK before launching both AVDs. Do not run concurrent Flutter or
Gradle builds while both emulators are active.

The phone allocation was raised from 2 GB after the simultaneous decode and
record run showed Android low-memory kills. Recorder failures now retain each
device's diagnostics independently, including per-segment recorder stderr.

Android assigns one console/adb port pair per emulator and recommends even
console ports. The scripts use 5554 and 5556, which deterministically produce
the serials `emulator-5554` and `emulator-5556`. Device-targeting adb operations
use `-s`, while server startup and device inventory remain global. An
unqualified device command is ambiguous when two devices are connected.

Run the sequence documented in
[`tools/android_multi_device/README.md`](../tools/android_multi_device/README.md).
The launcher verifies Linux x86_64, writable KVM access, acceleration, installed
device profiles, and both boot-complete signals. It uses current `swiftshader`
software graphics rather than the deprecated `swiftshader_indirect` mode; KVM
still accelerates the x86_64 virtual CPUs.

For the production two-client smoke, `build_together_apks.sh` builds the two
roles serially before either AVD starts. Both APKs receive the same unique
`TOGETHER_ROOM`, `SYNCPLAY_SERVER`, and `SYNCPLAY_PORT`; only
`TOGETHER_ROLE=host|guest` differs. `run_together_smoke.sh` then launches the
two prebuilt binaries concurrently on their explicit serials, using host VM
service ports 39101 and 39102 and separate role-labeled artifact directories.
Its evidence records both APK hashes, the target/driver paths, room, endpoint,
serials, command environment, logs, and exit codes. The default endpoint is
`syncplay.pl:8995`; STARTTLS behavior remains the production client's
responsibility and must stay fail-closed. The build, driver, and recorder
scripts reject nonempty output directories so a retry cannot silently reuse
evidence from an earlier run.

The two-device target needs media longer than the approximately four-second
Flutter sample because it exercises alternating control rounds and seeks.
`prepare_fixture.sh` downloads the official sample at a reviewed SHA-256 and
generates an approximately 90-second MP4 with FFmpeg `-stream_loop` and codec
copy. Flutter's asset repository identifies `bee.mp4` as CC0. Codec copy repeats
the original H.264 video packets and AAC audio packets without inventing or
re-encoding frames; the result is a repeated test fixture, not a polished demo.
Its provenance, source and output hashes, durations, and stream metadata are
saved alongside the fixture.

The scoped Python server binds only host loopback on `127.0.0.1:18765` and is
stopped by its recorded task-owned PID. Android Emulator defines `10.0.2.2` as
the alias for host loopback, so both AVDs consume
`http://10.0.2.2:18765/sync-fixture.mp4`. The URL is compiled into both APKs as
`TOGETHER_VIDEO_URL` and is repeated in command provenance. This local media
path removes public CDN timing from the synchronization assertion while the
STARTTLS Together Session still uses the configured public Syncplay server.

Each native screenrecord process is limited to 170 seconds, but the evidence
tool rotates consecutive segments while the two prebuilt drives run.
[`ci_together.sh`](../tools/android_multi_device/ci_together.sh) bounds the
default smoke wrapper to 360 seconds and each drive to 330 seconds. Its
`--production-ui` journey uses a 600-second wrapper and 540-second drive limit,
covering the eight-minute integration-test deadline plus app startup. The
outer bounds leave time to finalize evidence after success, assertion failure,
or timeout. All original segments and hashes are retained.

Each AVD runs its own Android-native `screenrecord` process. The evidence tool
refuses to touch a pre-existing recorder, records the new process ID for each
serial and segment, and stops only those PIDs. Android caps one native recording
at 180 seconds. The two first capture commands start a few milliseconds apart;
their measured host-side start delta is saved in `recording-session.tsv`.

Native `screenrecord` does not expose a reliable fixed-frame-rate option. The
composition step therefore preserves every native segment and separately
produces a 1920x1080 H.264 showcase at constant 30 fps. The
[`schema-v2 compositor`](../tools/android_multi_device/compose_side_by_side.py)
uses every segment's saved host command timestamp and original MP4. It places
each segment on one estimated timeline, showing black `RECORDING GAP` panels
for missing intervals and after the shorter device ends. The composition lasts
through the longer timeline. It drops or duplicates existing frames for 30 fps,
preserves aspect ratio, adds neutral borders, and labels the real source serial.
The unedited native segments, timing files and SHA-256 hashes remain the primary
evidence.

Starting the next segment requires a new native process, so a short rotation
gap can occur at a 170-second boundary. The legacy concatenated `native.mp4`
closes these gaps; the showcase does not use its concatenated contents. Host
command timestamps also do not establish exact first-frame times. If estimated
segment intervals overlap, the later segment takes over at its timestamp and
the manifest records the overlapping tail. Approximate alignment is a viewing
aid, not proof of frame-exact playback synchronization. Native player
observations establish the tested convergence behavior.

A passing two-AVD run demonstrates two separate Android application processes,
responsive phone/tablet layouts, and whatever real client interaction the
driving command performs. It does not prove two physical devices, ARM hardware
decoding, cellular behavior, multicast/LAN discovery, Bluetooth, Cast hardware,
or store billing. Emulator networking can also differ from a home LAN; those
claims require named physical runtimes and separate evidence.

References:

- [GitHub-hosted runner resources and Android acceleration](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [Android Emulator ports and command-line options](https://developer.android.com/studio/run/emulator-commandline)
- [Targeting one of multiple devices with adb](https://developer.android.com/tools/adb#devicestatus)
- [Android screenrecord limits](https://developer.android.com/tools/adb#screenrecord)
- [Android Emulator KVM and graphics acceleration](https://developer.android.com/studio/run/emulator-acceleration)
- [Android Emulator host-loopback alias](https://developer.android.com/studio/run/emulator-networking-address)
- [Flutter bee.mp4 CC0 origin declaration](https://github.com/flutter/assets-for-api-docs#origin-of-third-party-content)
