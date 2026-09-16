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
only its two intentional, user-facing messages through the production chat UI.

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

Run the focused tests with:

```powershell
python -m unittest tools/production_together/test_coordination_server.py
```
