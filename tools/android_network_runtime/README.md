# Android network interruption gate

This gate runs the real MainApp on one dedicated API 35 emulator. An independent
SyncplayClient and LocalMobileTarget in the same app process provide a second
real STARTTLS connection and Android decoder. Only the host player is rendered.
This is **one emulator and one process**, not a two-device or physical-phone test.
Both clients lose that emulator's network together.

The acceptance APK contains only the x86_64 ABI used by this dedicated AVD;
normal-application install workflows separately build the distributable APKs.
Each `svc` request retains bounded stdout/stderr and its exit code before the
existing radio-state confirmation. An exit code alone never proves that Android
changed the radio. Playback, radio confirmation and outage thresholds are unchanged.

The production UI starts a host room, loads the controlled 90-second fixture, and
starts playback. One free hosted session must be consumed. A successful socket
probe records the actual public Syncplay endpoint's resolved address and port.
The external runner then disables wifi and mobile data with `adb -s <owned serial>
shell svc`. It admits only the explicitly named `meowwatch_network_*` AVD with
`ro.kernel.qemu=1` and API 35, records both original radio settings before mutation,
and restores both in `finally`, including partial command failure. It never
changes host or physical-device networking, routing, or firewalls.

The test requires a failed socket connection to the **same resolved endpoint**,
both real clients disconnected, native auto-pause, and the visible MainApp loss
label. Only this observation releases the runner to restore the original radio
state. After automatic TLS rejoin, the room, media and host quota ledger must
remain the same. Healthy native controllers must retain their identity. A decoder
that actually failed during the outage may reopen once, paused at its retained
position: the gate requires the original failed controller ID and error, followed
by exactly one loading/ready transition to a new ID with the same media and a
position difference no greater than 350 ms. Both sources must become ready within
30 seconds. Controller identities must then remain stable through Play/Pause/Seek.

The optional `decoder_failure` workflow variant adds controlled failed-source
acceptance. The standard `normal` variant and all its checks remain unchanged.
For this variant, the fixture server keeps HTTP 200/206 Range headers and a live
response, sends an initial buffer, then paces the body and never sends bytes at
or beyond 90% of the file. CI uses `ffprobe` packet positions to prove that the
video keyframe preceding the 85-second seek starts beyond this cap. The server
records every delivered byte span and cap wait on the host monotonic clock.
Its 160 KiB/s pace leaves roughly 107 seconds between the initial 8 MiB burst
and the 90% cap for the current fixture; live playback still has to pass.
After the real cached-IP socket failure and automatic pause, the variant pauses
at a separate checkpoint immediately before the controlled seek. The runner
verifies the same app PID, both radios off, and no cap wait before its host
monotonic boundary, then acknowledges the test. The guest's original native
controller then seeks to 85 seconds
while both radios remain off. It must report a native error and target failure
within 25 seconds before the runner restores connectivity. The runner verifies
the actual delivered intervals remained below the cap before restoration.
It rejects every cap wait at or before the offline boundary and accepts only
later controlled waits; a later wait is not mandatory. Missing or misordered
clocks fail. The local `10.0.2.2` fixture may remain reachable after guest
radios are disabled. The byte cap prevents its server from supplying the late
keyframe if a request still reaches it; transport loss may instead fail the
request before a cap wait. The public Syncplay socket proof establishes the
real radio outage, and the original decoder must report an actual error.
The runner then checks the server's exact PID, birth token, command, port and
cap configuration and sends one local `SIGUSR1` to release the body cap. It
waits up to five seconds for the server's timestamped release receipt before
restoring either radio. The release allows the paused replacement decoder to
read the same HTTP media at 85 seconds; no LAN control endpoint is exposed.
Recovery then requires guest `ready → failed → loading → ready`, the original
native error and ID, one new ID, retained clock, unchanged URI, and paused state;
the healthy host ID must remain unchanged. Existing explicit controls and quota
checks still apply. This proves a controlled cache miss during a real Android
radio outage, not that a natural radio outage always fails a decoder.
Nine live paused observations spanning
at least 800 ms establish no autoplay. Explicit UI Play must advance both native
players; Pause and Seek must reach the peer and settle within 350 ms. No simulated
disconnect, connectivity plugin, manual reconnect, or acceptance retry is used.

When both radios originally were enabled, recovery enables Wi-Fi first and
requires two fresh observations of the same connected default Wi-Fi network
before restoring mobile data. The check is bounded to 30 seconds with each ADB
read bounded to five seconds; ambiguous or cellular defaults do not qualify.
This avoids creating a second outage when Android retires a temporary cellular
connection after Wi-Fi takes over. Each observation retains its network ID,
reason and output hashes. A failed readiness check still restores both original
settings and fails without acknowledging recovery. Final cleanup always uses
the ordinary exact-state restoration path.

Run-specific logcat checkpoints coordinate external actions. Local sandbox
acknowledgement files allow the test to wait without IP connectivity. The runner
writes each payload to a unique sibling temporary file, closes it, then atomically
renames it to the final path and verifies exact readback. The test's unchanged
exists/read protocol cannot observe a partially written acknowledgement. Unknown
phases, duplicate publication and incorrect readback fail the gate; both paths
are registered for cleanup before writing. Checkpoints
alone never establish network failure: the gate also validates the actual socket
probe sequence and saves `dumpsys connectivity`, wifi/telephony state, radio
settings, addresses/routes, UI XML, screenshots and full logcat/driver output.
Fresh app UI XML comes from the existing standalone NativeUiObserver; it does
not wait for the playing timeline to become idle and does not pause the video.
The helper targets only its own package, checks the app PID and a fresh nonce,
and is installed and removed by this run. Before app launch and after unmount,
network-only observations retain raw screenshots/window state without claiming
an app accessibility hierarchy. Helper installation/removal failures fail the gate.

Every app-phase capture additionally requires exact MainActivity ownership in
both raw and observer focused-window records, and an accessibility hierarchy
containing only app nodes. A successful XML dump alone does not establish that
the app is visible. Before installation, CI reuses the existing dedicated-AVD
Google SDK setup preparation and retains its receipt. During a run, only the
exact Google SDK Setup ANR over the app may receive one bounded Close app action;
its identity and window are rechecked immediately before the tap. Original
obscured captures, event logs and the fresh confirmation are preserved. The
runner then requires new unobscured app window, screenshot and XML evidence.
Another ANR, a changed or ambiguous dialog, a failed close, or a second required
close fails the gate. This recovery never restarts playback or retries a failed
acceptance phase. The gate explicitly reports preflight recovery and in-run
attempts so emulator repair is not presented as a repair-free rehearsal.

Four original screenrecord segments reuse the lifecycle recorder's full decoding
and Android frame-clock checks through each last required observation. Recording
gaps are explicit between assertion phases; this is not continuous whole-journey
coverage. App/TLS/decoder teardown, original-radio restoration and evidence
cleanup must all succeed. A timeout, incomplete evidence, failed restore, wrong
AVD/PID, restart, or unexpected checkpoint fails the gate.

Failed app teardown is a terminal failure even when earlier acceptance phases
were not reached; it does not credit those phases or obscure the app assertion
with a checkpoint-order error. `result.json` retains the first failure's stage,
stack, both playback intents, controller/snapshot buffering and error states,
and all native position samples collected before convergence or timeout. Raw
redacted Syncplay traffic and follow decisions are retained in logcat, with the
last 600 entries also in the result. No playback or outage tolerance is changed
for diagnostics. If Flutter's driver already uninstalled its integration APK,
a successful Android package query establishes that its acknowledgement sandbox
is gone; query failures and failed removal from an installed app still fail cleanup.

Each native position read emits bounded `NETWORK_NATIVE_POSITION` start/end
records with the run and admitted app PID, phase, baseline/advancing/paused stage,
host/guest role, native player ID, per-phase read index, UTC times, monotonic
elapsed milliseconds, outcome and the unchanged 5000 ms timeout. Reads remain
sequential (host, then guest). An error is rethrown with its original stack; a
timed-out read is never retried or replaced with the controller's cached position.
The advancement observation exists before its first baseline read, so a baseline
timeout still retains its role and timing. `result.json` keeps the last 512 reads
per phase plus total/dropped counts; raw logcat retains every emitted record.

After log capture stops, the runner creates `native-position-reads.json` solely
from that existing log. It accepts only the same run/PID and known phase/role/stage
fields, retains the last 4096 records with truncation/rejection counts, and pairs
start/end only for the same read identity and controller. Pending starts and ends
without a matching start in the retained tail are explicit; a missing end does
not establish a native timeout. Missing logs/PID or indexing errors are reported
as unavailable diagnostics in `gate.json`; they cannot replace the first failure
or affect the gate verdict. No additional device query, signal, capture, position
read or success-path wait is introduced. The original 30-second advancement,
pause/outage thresholds and live frame policy remain unchanged. These timings
locate an observed wait; they do not establish whether Android, the platform
channel or Dart scheduling caused it.

The workflow builds a unique APK with `NETWORK_RUN_ID` and creates an AVD named
`NETWORK_AVD_NAME`. `tools/android_network_runtime/ci.sh` starts/stops only its
owned fixture server and runs the Python orchestrator. The orchestrator requires
POSIX process groups (the Linux CI host); never point it at a personal emulator.
Select `variant=decoder_failure` in the manual workflow dispatch for the added
native gate. The APK's `NETWORK_VARIANT` Dart define and the runner's variant
argument must match. The normal PR workflow remains `variant=normal`.

Local contract checks (no Android SDK required):

```sh
python3 -m unittest discover -s tools/android_network_runtime -p 'test_*.py'
bash -n tools/android_network_runtime/ci.sh
```

Runtime proof is pending until the workflow's native gate is green. Python and
widget tests do not prove Android radio behavior, hardware, LAN, or two devices.
