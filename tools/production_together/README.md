# Production Together rendezvous

`coordination_server.py` is a small, test-only rendezvous for the two-device
production UI acceptance journey. The host app creates a real random room via
**Start a room**, then publishes the generated invite. The guest fetches it and
enters it through the real **Join a room** sheet.

The server binds only to `127.0.0.1`, stores one invite and at most 64 immutable
role checkpoints in memory, accepts only one configured run ID, limits request
bodies to 8 KiB, and expires the whole run. It does not write files or log
invitation or checkpoint payloads. Android emulators reach the host loopback
listener through `10.0.2.2`.

Bodies declared above 8 KiB are rejected before they are read. The server
closes that connection; depending on the host TCP stack, the client may observe
either HTTP `413` or an immediate connection reset. In both cases no state is
stored, and a fresh connection remains usable.

PUT clients must declare the exact UTF-8 byte length before writing the JSON
body. Chunked requests are rejected. The Android journey uses
`json_request.dart` for both invite and checkpoint publication; its socket test
checks the on-wire headers and a non-ASCII payload.

Start one server for one run:

```powershell
python tools/production_together/coordination_server.py `
  --run-id ci-acceptance-123 `
  --port 18766 `
  --ttl-seconds 600
```

Compile both roles with the same rendezvous values:

```text
--dart-define=TOGETHER_ROOM=ci-acceptance-123
--dart-define=TOGETHER_COORDINATION_URL=http://10.0.2.2:18766/invite
```

Each role enters a run-specific display name through onboarding, within the
24-character product limit. Public Syncplay servers reserve usernames across
rooms, so separate concurrent workflows must also use different run IDs to
avoid server-side renames. The final ledger records both expected names.

The contract is deliberately small:

- `PUT /invite?run=<run-id>` with JSON
  `{"runId":"...","invite":"meowwatch://...","publishedAtUtc":"..."}` stores
  the first valid invite. Repeating the same invite is safe; replacing it is
  rejected.
- `GET /invite?run=<run-id>` returns `404` while waiting, `200` with
  `{"runId":"...","invite":"meowwatch://..."}` when ready, and `410` after
  expiry.
- `PUT /checkpoint?run=<run-id>` with JSON
  `{"runId":"...","role":"host|guest","checkpoint":"...","value":null}`
  records one test-only control event after the invite exists. Repeating the
  same event is safe; changing its value is rejected.
- `GET /checkpoint?run=<run-id>&role=<role>&checkpoint=<name>` returns `404`
  while waiting, `200` with the immutable event and optional string value, and
  `410` after expiry. The 65th distinct checkpoint is rejected.

Checkpoint traffic coordinates the two instrumented drivers without entering
the production room chat. Playback assertions still read each real app/player;
the rendezvous never supplies a playback result. The acceptance journey sends
two movie-night messages and one playable video URL through production chat.
The second invitation uses a distinct immutable checkpoint, preserving the
first `/invite` value and the existing 64-checkpoint limit.

The full MainApp journey also exercises these production branches:

- The joining device decodes a PNG of the actual generated invitation with
  Android ML Kit, then enters that exact result in **Join a room** and explicitly
  submits it. This proves native image QR decoding and the confirmation/join
  path; it does not establish camera permission or optical camera scanning.
- A peer shares the owned fixture MP4 with a distinct query string. The original
  player remains unchanged while **Watch this too?** is visible. **Load video**
  creates a new native decoder, and both devices must advance and pause together.
  The original room ID, server/port/room, host role and persisted quota ledger
  must remain unchanged.
- Both devices choose a nonexistent MP4 on the owned fixture server. A real
  decoder failure must render the readable error and **Choose another video**.
  That action reloads the valid fixture; the same room must again play and pause
  in sync without another host charge.
- The original host leaves and taps its actual **Continue Watching** entry
  while its peer stays connected. Resume must retain the original room ID and
  endpoint, restore the saved position within 800 ms, and allow synchronized
  playback with the already-consumed free host.
- Both return home. The original guest taps **Recent rooms → Watch together
  again**, creating a different room ID, room name and invitation. The original
  host decodes the new invitation and rejoins through the production sheet.
  Creation and joining leave both quota ledgers untouched. Only the new host's
  first synchronized playback consumes its previously unused free allowance;
  the original host's ledger remains unchanged when joining. Both roles finish
  with zero new free hosts available and their charged session still resumable.

The final branches use the real initially empty file-backed quota stores and
require actual free entitlement state. They do not replace billing, grant Plus,
change the device clock or reset quota between movie nights. Native screenshots,
stage observations and exact ledger/room assertions accompany these steps.
Playback cycles require actual native advancement on both devices. The paused
checkpoint still requires accepted pause intent plus at least nine samples over
800 ms with under 350 ms movement, and the other device must converge within
800 ms. The existing 45-second checkpoint deadline and eight-minute total test
deadline remain unchanged.

The runner must stop its owned server process after both device drivers finish.
The `Production phone and tablet journey` workflow builds both roles and calls
`tools/android_multi_device/ci_together.sh --production-ui`. It owns the
rendezvous, fixture server and two AVDs and records their actual screens. The
shared runner verifies that the compiled target and rendezvous match this mode.
Results and native screenshots are in `build/production-together-artifacts/`;
native segments and the framed review video are in the AVD session directory.
This test starts from first-run UI and uses production room creation and joining;
it remains an instrumented acceptance build, separate from the normal release
APK clean-install workflow.

The production runner supervises each owned host driver with `anr_guard.py`.
During the journey it checks Android's native `am_anr` events for the exact app
package and a PID observed in this run, including fresh `am_proc_start` events.
It records an initial event baseline without clearing logcat, preserves new raw
events by appending them, and saves the first matching ANR separately. Each
probe has a six-second total command budget and runs no UIAutomator operation.
Native focus is also checked before and after each driver; once both finish,
both apps are checked again using the original baselines and observed PIDs.
Thus successful Flutter assertions cannot override a native app ANR.
Both final checks run even when a driver or the first final check fails. A
shared failure latch stops active drivers but never skips a final native check.
Each final check writes into a separate directory and preserves the original
role result as `prior-guard-result.json`; an earlier failed role remains failed
even if its final native check is clean. Missing original baseline evidence
fails that check and triggers bounded diagnostics. Original driver exits and
both final guard exits are retained in `native-anr-exits.tsv`, and any nonzero
exit fails the wrapper.

Any ANR or failed probe creates a shared failure latch. Each active role stops
only its own verified host process group; the guard never closes a native
dialog, force-stops the Android app, changes root access, or restarts ADB.
Failure evidence under each role's `native-anr/` (or `native-anr-final/`) includes
raw window state, screenshot, XML, logcat, and `dumpsys activity lastanr` with an
eight-second limit. All diagnostic commands have individual time limits;
`diagnostics.json` explicitly records incomplete captures. The failure remains
a failure if evidence collection times out. These checks detect native ANRs;
they do not establish the cause of a stall or replace video/playback gates.

Run the focused tests with:

```powershell
python -m unittest tools/production_together/test_coordination_server.py
python -m unittest tools/production_together/test_anr_guard.py
python -m unittest tools/production_together/test_anr_wrapper.py
flutter test tools/production_together/json_request_test.dart
```
