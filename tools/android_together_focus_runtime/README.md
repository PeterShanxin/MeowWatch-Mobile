# Together room Android audio-focus gate

This gate builds a debug **integration APK** whose test opens the normal `MainApp`
and production services. It hosts one real room, joins an independent headless
Syncplay client over TLS, and plays one native Android video decoder. The peer
is a separate TLS client in the same app process, not a second Android device or
decoder. The gate does not establish behavior of an unmodified release APK or
physical phone.

The host loopback stage bridge issues two fresh, nonce-bound native focus helper
requests after the native player and peer both report settled playback.
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
