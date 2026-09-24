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
state. After automatic TLS rejoin, the room, media, both native controllers, and
host quota ledger must remain the same. Nine live paused observations spanning
at least 800 ms establish no autoplay. Explicit UI Play must advance both native
players; Pause and Seek must reach the peer and settle within 350 ms. No simulated
disconnect, connectivity plugin, manual reconnect, or acceptance retry is used.

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

Local contract checks (no Android SDK required):

```sh
python3 -m unittest discover -s tools/android_network_runtime -p 'test_*.py'
bash -n tools/android_network_runtime/ci.sh
```

Runtime proof is pending until the workflow's native gate is green. Python and
widget tests do not prove Android radio behavior, hardware, LAN, or two devices.
