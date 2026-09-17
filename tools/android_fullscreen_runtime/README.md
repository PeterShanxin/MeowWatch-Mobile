# Native Android fullscreen gate

The workflow runs the normal **release `lib/main.dart` APK** on separate dedicated
API 35 `pixel_6` and `pixel_tablet` AVD jobs. It reuses the lifecycle runner's normal
installation, real native video, incoming-share review, standalone NativeUiObserver
and original screenrecord validation. No integration-test bootstrap or production
testing hook is used; the video is the reviewed 90-second fixture served locally
to the AVD. Python tests alone do not prove Android fullscreen behavior.

The native UI opens the fixture and exercises normal Play/Pause, then taps
`Enter full screen`. The acceptance decision requires **actual** `statusBars`
and `navigationBars` `visible=false` in Display 0's `WindowInsetsStateController`.
Requested hide flags, the absence of a Flutter button, a cropped recording, or
elapsed time cannot satisfy this requirement. The current display dimensions,
InsetsState frame and rotation must agree. The phone must go from natural
portrait to landscape; the tablet must retain its original size and rotation.

At the first `07-entered-fullscreen` observation only, the runner may acknowledge
Android's first-use `ImmersiveModeConfirmation` tip once. It requires the exact
focused system window over the same MeowWatch MainActivity process, the native
`immersive_cling_title` and `immersive_cling_description` labels, and the sole
enabled, visible `android:id/ok` / `Got it` button. It re-verifies the owned API 35
AVD, retains the original XML/window/PNG, then re-reads the idle system dialog
with UIAutomator and validates its current focus, geometry and button bounds
immediately before tapping. Changed or ambiguous content receives no tap; a
changed PID or uncertain tap fails the gate. No other dialog or later phase can
use this acknowledgement, and no global settings are changed. Fresh app UI still
comes from NativeUiObserver within the original 35-second phase budget and must
pass all existing bar, rotation, surface and paused-player assertions. The
`immersiveConfirmations` receipt records whether this branch was exercised; the
tip occurs in the explicitly unrecorded orientation transition between segments.

In fullscreen, the gate observes the controls automatically hiding during
playback, then uses a native center tap to show them. It does not claim to prove
tap-to-hide behavior. A bounded observation must show the real media timeline
advancing by at least two seconds before the runner taps Pause using that fresh
hierarchy. Pause must then keep the position stable. The first system Back must return to the normal player with
the same app PID, fixture and paused position. Both real system bars and the
original orientation policy/geometry must return. A second Back returns home.
No room, media or playback state is injected through a test channel.

Three original recording segments cover normal playback, fullscreen, and the
restored player/home. Each recorder is stopped and its ownership cleared **before**
an orientation-changing action; the next segment uses the current rotated display
dimensions, not the unrotated `wm size`. The reused recorder verifies full decoding
and Android frame-clock coverage through its final observation. Rotation gaps are
explicit and are not claimed as continuous footage. Original PNGs are uncropped
and must exactly match the native display dimensions. UI XML, complete window
dumps, screenshots, full logcat, media provenance and cleanup results are retained.
Visible accessibility bounds are checked against the physical display; maintainers
must still inspect the original images for visual clipping and overflow.

Each segment dispatches its existing next operation once after the exact owned
recorder PID/command is verified, then waits for a complete live picture and device
clock within the original twenty-second launch deadline. These operations are
normal Play, fullscreen Play, and the second Back to home. No additional Play,
synthetic animation, input retry or recording timeout is added. The fullscreen
paused/same-process/Insets proof remains before the second recorder and Play;
the restored paused-player screenshot remains before the third recorder and Back.

The dispatch's host/device clock is retained separately from media readiness.
The callback is not proof that its button-tap instant appears in the MP4. The
actual first video-frame time is retained, and finalized frame-clock coverage is
required for the first successful post-action observation (`03-normal-playing`,
`08-controls-auto-hidden`, `15-normal-return-home`), together with the unchanged
final observation/tail and complete-decode checks. No file is trimmed or padded.

This order addresses the static-screen wait in phone run `35253732711`: its second
recording encoded thirteen valid landscape frames but retained them in one MP4
chunk until stop, while the driver waited for that chunk before sending Play.
The first two segments now supply their intended playback during readiness. A
short Home transition can still remain buffered or produce no later post-roll
picture; the third segment must fail in that case. Native evidence is required
to establish its behavior, and no extra UI motion or relaxed coverage substitutes
for that evidence.

The runner admits only the named `meowwatch_fullscreen_<phone|tablet>_*` API 35
emulator before any install/removal. It never changes global orientation, display
size, host settings or a physical device. App/helper/recorder cleanup remains owned
and fails the gate if incomplete. The fixture server is stopped only if this shell
successfully started it.

Contract checks (no Android SDK required):

```sh
python3 -m unittest tools.android_fullscreen_runtime.test_run -v
bash -n tools/android_fullscreen_runtime/ci.sh
```

Native acceptance is pending until both matrix jobs and the original-image review
pass. This establishes emulator behavior, not physical-phone/tablet acceptance.
