# Together room Android audio-focus gate

This gate builds a debug **integration APK** whose test opens the normal `MainApp`
and production services. It hosts one real room, joins an independent headless
Syncplay client over TLS, and plays one native Android video decoder. The peer
is a separate TLS client in the same app process, not a second Android device or
decoder. The gate does not establish behavior of an unmodified release APK or
physical phone.

The host loopback stage bridge issues two fresh, nonce-bound native focus helper
requests after the native player and peer both report settled playback.
Before app installation, the dedicated API 35 AVD runs the repository's
bounded, read-only cold-start observation for up to 60 seconds. Each original
AVD identity, setup state, Home focus, ANR state and screenshot is retained in
the separate boot-readiness artifact. The wait ends only after provisioning
completes and NexusLauncher owns Home, or after a fully identified eligible
system ANR is ready for the existing preparation step. Wrong AVD, an installed
MeowWatch app, invalid measurements and a persistent unfinished startup fail
without a recovery attempt. Then SDK setup preparation runs once. It can
recover only a verified current system Launcher or SDK setup ANR, with original screenshots and process/event
identity retained. A second Home observation five seconds later must still
show the same resolved Home, no current dialog, and no new ANR event. The
preparation receipt is uploaded separately. If an ANR appears after the app
starts, the stage still fails its exact foreground check; its failure receipt
now retains Android ANR events, Launcher process listing, Home resolution,
and the original window dump and screenshot. No app-stage recovery is attempted.
Before those held cases, a separate short transient case pauses through the
real TLS peer and starts the independent helper as a foreground service without
requesting audio focus. A nonce-bound Android log receipt records the live
helper UID, PID, and device clock; the gate verifies that the helper owns no
audio focus and that the app remains foreground. The warm service expires after
15 seconds if unused. The gate then records an Android monotonic uptime marker
and sends a real peer Play. Once native playback and the named peer Play are
visible, the bridge retains its pre-acquire `dumpsys audio` check of the app's
current focus ownership and asks the already running, same-nonce helper to
acquire `AUDIOFOCUS_GAIN_TRANSIENT` before the warm expiry. The helper abandons
focus itself after 350 ms; it
does not wait for screenshots or host polling. The grant and release must both
occur less than 3 seconds after the marker, which predates the peer Play.
A listener armed while native playback is active rejects every native Play
event after its first pause until the test explicitly taps Play. Native UI,
foreground/PID, helper UID/PID/nonce, and post-release focus-stack evidence
are retained for the short case as well. The short case's window is measured
on one device clock; the TLS command receipt has no native timestamp, so the
pre-command marker deliberately gives a stricter bound. Separate host-clock
durations for the app-focus dump, helper service command and event polling are
retained for diagnosis and do not replace the device-clock bound.
`AUDIOFOCUS_GAIN` and `AUDIOFOCUS_GAIN_TRANSIENT` run in separate stages. The
Flutter test never calls pause during an interruption. Both modes require the
native player and peer to pause, stay paused after focus release, and resume
only after tapping the room's Play control. The native observer retains XML and
PNG for each stage, while AudioService stacks, helper events, window focus and
Activity history are retained as text. Position and error snapshots come from
the real playback target. A stage fails if the app loses foreground focus,
changes PID, emits pause/stop lifecycle events, fails to relinquish focus, or
the helper grant cannot be tied to its current UID, PID and nonce. On API 35,
permanent loss can remove the app entry from the focus stack; this gate checks
its ownership immediately before the request and the helper's ownership after.
For the held transient case, Together explicitly pauses its native player and
relinquishes app focus. The gate therefore requires the exact app UID and
client to own focus before interruption, a granted transient request by the
exact helper UID, PID and client, then an Android focus-history abandon by the
same app UID, PID and client. The post-request stack must contain only that
helper as the active transient owner. The Android history records the request
and abandon sequence; it does not label the app's focus callback. Native pause,
room pause and no-autoplay evidence remain required separately.

Dispatch `.github/workflows/android-together-focus.yml` for the native run.
Branches can also dispatch the registered `android-interruption.yml` workflow
with `scope=together`; it calls the same Together workflow at that branch's
commit. The default `scope=local` keeps the normal-release Local Mode gate.
`build/android-together-focus-artifacts` and fixture/server receipts are uploaded
even on failure. Local contract checks are intentionally lightweight:

```sh
python3 -m unittest tools.android_together_focus_runtime.test_run -v
python3 -m tools.android_together_focus_runtime.run --help
bash -n tools/android_together_focus_runtime/ci.sh
```
