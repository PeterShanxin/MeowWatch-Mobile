# Android runtime playback evidence

The Android runtime smoke test exercises the production `LocalMobileTarget`
with the official Flutter `video_player` plugin. It does not replace the player
with a fake or call plugin APIs through a mock.

## What the smoke test proves

On an Android runtime, the test:

1. opens a direct HTTPS MP4 through `LocalMobileTarget`;
2. mounts the production controller in a real `VideoPlayer` texture widget;
3. verifies initialization, decoded video dimensions, and duration;
4. verifies that play advances the reported position;
5. verifies that pause keeps the position stable;
6. seeks and checks the resulting reported position;
7. tears down the texture, reopens the media with a new controller, renders it,
   and disposes the target; and
8. calls `convertFlutterSurfaceToImage()` and captures PNG screenshots of the
   actual Android Flutter surface while video is playing.

The sample is Flutter's official `bee.mp4` `video_player` documentation asset:

- media: <https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4>
- source and license declaration:
  <https://github.com/flutter/assets-for-api-docs#origin-of-third-party-content>

The Flutter repository declares this 1.3 MB asset CC0. Keeping the sample small
reduces CI network exposure while still exercising Android's real media stack,
network data source, decoder, texture, and player controls.

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

The uploaded artifact contains both screenshots, the structured result,
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
