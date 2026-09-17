#!/usr/bin/env python3
"""Own one API 35 AVD radio interruption and retain native recovery evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import signal
import subprocess
import threading
import time
from typing import Callable

from tools.android_install.runner import Adb, PACKAGE, RuntimeFailure, ARTIFACT_ROOT
from tools.android_lifecycle_runtime.run import LifecycleRecording, recording_size
from tools.android_native_ui.observer import NativeUiObserver


RUNTIME = "One dedicated API 35 AVD; one MainApp process; two real TLS clients/native decoders"
PHASES = ("app-ready", "players-ready", "initial-ready", "offline-confirmed",
          "reconnected-confirmed", "recovery-confirmed", "teardown-complete")
REQUIRED = {
    "initial_real_tls_native_playback_and_consumed_host",
    "physical_avd_network_unreachable_and_visible_auto_pause",
    "same_room_media_controllers_quota_and_no_autoplay",
    "explicit_production_play_pause_seek_and_real_peer_sync",
}
RUN_ID = re.compile(r"[A-Za-z0-9_-]{1,80}")
AVD_NAME = re.compile(r"meowwatch_network_[A-Za-z0-9_]{1,80}")
MARKER = "NETWORK_CHECKPOINT "


def parse_checkpoint(line: str, run_id: str) -> dict | None:
    if MARKER not in line:
        return None
    try:
        value = json.loads(line.split(MARKER, 1)[1].strip())
    except (TypeError, ValueError) as error:
        raise RuntimeFailure("malformed network checkpoint") from error
    if not isinstance(value, dict) or value.get("runId") != run_id:
        raise RuntimeFailure("network checkpoint belongs to another run")
    if value.get("phase") not in PHASES or type(value.get("pid")) is not int or value["pid"] <= 0:
        raise RuntimeFailure("invalid network checkpoint phase or Android PID")
    return value


def require_owned_avd(adb: Adb, avd_name: str) -> None:
    if re.fullmatch(r"emulator-[0-9]+", adb.serial) is None or not AVD_NAME.fullmatch(avd_name):
        raise RuntimeFailure("an explicitly named task AVD and emulator serial are required")
    name = adb.run("emu", "avd", "name").stdout.decode("utf-8").splitlines()
    name = [line.strip() for line in name if line.strip() and line.strip() != "OK"]
    if name != [avd_name]:
        raise RuntimeFailure("connected AVD is not the named network test AVD")
    if adb.run("shell", "getprop", "ro.kernel.qemu").stdout.strip() != b"1":
        raise RuntimeFailure("refusing radio changes on a physical Android device")
    if adb.run("shell", "getprop", "ro.build.version.sdk").stdout.strip() != b"35":
        raise RuntimeFailure("network acceptance requires API 35")


def parse_radio(value: bytes) -> bool:
    if value.strip() not in (b"0", b"1"):
        raise RuntimeFailure("initial Android radio setting is ambiguous; no mutation permitted")
    return value.strip() == b"1"


class Radios:
    """Restore both original settings even if disable only partially succeeds."""

    def __init__(self, adb: Adb, avd_name: str, record: Callable[[dict], None]):
        self.adb, self.avd_name, self.record = adb, avd_name, record
        self.initial: dict[str, bool] | None = None
        self.changed = False

    def read(self, timeout: float = 10) -> dict[str, bool]:
        deadline = time.monotonic() + timeout
        result = {}
        for name, key in (("wifi", "wifi_on"), ("data", "mobile_data")):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeFailure("Android radio observation exceeded its original deadline")
            result[name] = parse_radio(self.adb.run(
                "shell", "settings", "get", "global", key, timeout=remaining).stdout)
        return result

    def capture_initial(self) -> None:
        require_owned_avd(self.adb, self.avd_name)
        self.initial = self.read()
        if not any(self.initial.values()):
            raise RuntimeFailure("initial AVD must have an enabled network radio")
        self.record({"operation": "initial-radios", "state": self.initial})

    def _apply(self, desired: dict[str, bool], operation: str) -> None:
        require_owned_avd(self.adb, self.avd_name)
        failures: list[str] = []
        for name in ("wifi", "data"):
            try:
                self.adb.run("shell", "svc", name, "enable" if desired[name] else "disable", timeout=10)
            except (OSError, RuntimeFailure, subprocess.TimeoutExpired) as error:
                failures.append(f"{name}: {error}")
        actual = None
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            actual = self.read(timeout=max(0, deadline - time.monotonic()))
            if actual == desired:
                break
            time.sleep(0.2)
        self.record({"operation": operation, "requested": desired, "actual": actual,
                     "commandErrors": failures})
        if failures or actual != desired:
            raise RuntimeFailure(f"Android radio {operation} failed; original state must be restored")

    def disable(self) -> None:
        if self.initial is None:
            raise RuntimeFailure("original radio state has not been captured")
        self.changed = True
        self._apply({"wifi": False, "data": False}, "disable")

    def restore(self) -> None:
        if self.changed and self.initial is not None:
            self._apply(self.initial, "restore")


def validate_result(result: dict, run_id: str) -> None:
    if result.get("runId") != run_id or result.get("passed") is not True:
        raise RuntimeFailure("the integration test did not report a successful owned run")
    if set(result.get("verified", [])) != REQUIRED or result.get("teardownErrors") != []:
        raise RuntimeFailure("required recovery assertions or test teardown are incomplete")
    probes = {item.get("phase"): item for item in result.get("observations", [])
              if isinstance(item, dict) and str(item.get("phase", "")).startswith("probe-")}
    if any(probes.get(phase, {}).get("reachable") is not reachable for phase, reachable in (
            ("probe-healthy", True), ("probe-offline", False), ("probe-restored", True))):
        raise RuntimeFailure("successful, unreachable, and restored real socket probes are required")
    healthy = probes["probe-healthy"]
    for phase in ("probe-offline", "probe-restored"):
        if (probes[phase].get("address") != healthy.get("resolvedAddress")
                or probes[phase].get("port") != healthy.get("port")):
            raise RuntimeFailure("network probes must target the same resolved server and port")
    if not healthy.get("resolvedAddress") or type(healthy.get("port")) is not int:
        raise RuntimeFailure("the live endpoint is missing from socket evidence")


def stop_owned_process(process: subprocess.Popen | None) -> None:
    if process is None or process.poll() is not None:
        return
    # All spawned groups belong to this runner; never select by executable name.
    os.killpg(process.pid, signal.SIGINT)
    try:
        process.wait(timeout=15)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)


class Runner:
    def __init__(self, serial: str, avd_name: str, apk: Path, run_id: str, output: Path):
        if not RUN_ID.fullmatch(run_id):
            raise RuntimeFailure("invalid network run ID")
        self.adb = Adb(serial, run_id)
        self.observer = NativeUiObserver(self.adb)
        self.avd_name, self.apk, self.run_id = avd_name, apk.resolve(strict=True), run_id
        self.output = output
        self.events: list[dict] = []
        self.recordings: list[dict] = []
        self.radios = Radios(self.adb, avd_name, self.event)
        self.recording: LifecycleRecording | None = None
        self.process: subprocess.Popen | None = None
        self.logcat: subprocess.Popen | None = None
        self.readers: list[threading.Thread] = []
        self.checkpoints: queue.Queue[dict | Exception] = queue.Queue()
        self.phase_index = 0
        self.android_pid: int | None = None
        self.acknowledgements: list[str] = []
        self.errors: list[str] = []
        self.admitted = False

    def write(self, name: str, value: object) -> None:
        (self.output / name).write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")

    def event(self, value: dict) -> None:
        self.events.append({"atMonotonic": time.monotonic(), **value})
        self.write("events.json", self.events)

    def capture(self, phase: str) -> None:
        require_owned_avd(self.adb, self.avd_name)
        directory = self.output / "observations" / phase
        directory.mkdir(parents=True, exist_ok=True)
        commands = {
            "connectivity.txt": ("shell", "dumpsys", "connectivity"),
            "wifi.txt": ("shell", "dumpsys", "wifi"),
            "data.txt": ("shell", "dumpsys", "telephony.registry"),
            "addresses.txt": ("shell", "ip", "address", "show"),
            "routes.txt": ("shell", "ip", "route", "show", "table", "all"),
            "radios.txt": ("shell", "settings", "list", "global"),
            "window.txt": ("shell", "dumpsys", "window", "displays"),
        }
        for filename, command in commands.items():
            result = self.adb.run(*command, timeout=10, check=False)
            (directory / filename).write_bytes(result.stdout)
            (directory / f"{filename}.stderr").write_bytes(result.stderr)
            if result.returncode:
                raise RuntimeFailure(f"native {phase} evidence command failed: {filename}")
        (directory / "screen.png").write_bytes(self.adb.screenshot())
        # Before launch and after test unmount, network restoration has no
        # application hierarchy to inspect. Acceptance phases must use fresh
        # native accessibility snapshots without waiting for a moving timeline
        # to become idle, and without pausing playback to aid the observer.
        if phase not in {"initial-network", "finally-restored"}:
            xml, window = self.observer.observe()
            (directory / "ui.xml").write_text(xml, encoding="utf-8")
            (directory / "observer-window.txt").write_text(window, encoding="utf-8")
            self.write("native-ui-observer.json", {
                "installation": self.observer.installation,
                "observations": self.observer.observations,
            })
        self.event({"operation": "native-observation", "phase": phase,
                    "radios": self.radios.read(), "directory": str(directory)})

    def ack(self, phase: str) -> None:
        require_owned_avd(self.adb, self.avd_name)
        current = self.adb.run("shell", "pidof", PACKAGE).stdout.strip()
        if current != str(self.android_pid).encode("ascii"):
            raise RuntimeFailure("MainApp process changed while the network test was active")
        path = f"files/network-{self.run_id}-{phase}"
        self.acknowledgements.append(path)
        # Both interpolated fields are fixed phases or validated run IDs. The
        # acknowledgement is local app-owned test data, reachable without IP.
        command = f"printf '%s' '{self.run_id}:{phase}' > '{path}'"
        self.adb.run("shell", "run-as", PACKAGE, "sh", "-c", f'"{command}"')
        self.event({"operation": "acknowledgement", "phase": phase})

    def stop_test_app(self) -> None:
        require_owned_avd(self.adb, self.avd_name)
        current = self.adb.run("shell", "pidof", PACKAGE, check=False).stdout.strip()
        if current and current != str(self.android_pid).encode("ascii"):
            raise RuntimeFailure("refusing to stop a replacement MeowWatch process")
        self.adb.run("shell", "am", "force-stop", PACKAGE)

    def remove_ack(self, path: str) -> None:
        require_owned_avd(self.adb, self.avd_name)
        # flutter drive uninstalls its integration APK when it exits. A
        # successful package query establishes that its sandbox is already gone;
        # a failed query or an installed app's failed rm must still fail cleanup.
        installed = self.adb.run("shell", "pm", "list", "packages", "--user", "0", PACKAGE)
        packages = installed.stdout.decode("utf-8").splitlines()
        if installed.stderr.strip() or any(
                re.fullmatch(r"package:[A-Za-z0-9_.]+", line) is None for line in packages):
            raise RuntimeFailure("cannot establish whether the integration app is still installed")
        if f"package:{PACKAGE}" not in packages:
            self.event({"operation": "remove-ack", "path": path,
                        "status": "app-already-uninstalled", "packageQuery": packages})
            return
        self.adb.run("shell", "run-as", PACKAGE, "rm", "-f", path)

    def remove_device_evidence(self) -> None:
        if self.admitted:
            require_owned_avd(self.adb, self.avd_name)
        self.adb.cleanup()

    def remove_observer(self) -> None:
        if self.observer.owns_package:
            require_owned_avd(self.adb, self.avd_name)
        self.observer.cleanup()

    def start_recording(self) -> None:
        size = recording_size(self.adb.run("shell", "wm", "size").stdout.decode("utf-8"))
        recording = LifecycleRecording(self.adb, self.output, len(self.recordings) + 1, size)
        self.recording = recording
        self.recordings.append(recording.metadata)
        recording.start()

    def finish_recording(self, phase: str | None = None) -> None:
        if self.recording is not None:
            recording = self.recording
            self.recording = None
            try:
                recording.finish(required_phase=phase)
            finally:
                self.write("recordings.json", self.recordings)

    def observe_checkpoint(self, value: dict) -> None:
        phase = value["phase"]
        failed_teardown = phase == "teardown-complete" and value.get("passed") is False
        if not failed_teardown and (self.phase_index >= len(PHASES) or phase != PHASES[self.phase_index]):
            raise RuntimeFailure(f"duplicate or out-of-order checkpoint: {phase}")
        current = self.adb.run("shell", "pidof", PACKAGE).stdout.strip()
        if current != str(value["pid"]).encode("ascii"):
            raise RuntimeFailure("checkpoint PID is not the current MainApp process")
        if self.android_pid is not None and value["pid"] != self.android_pid:
            raise RuntimeFailure("MainApp restarted; this is a same-process network gate")
        self.android_pid = value["pid"]
        self.event({"operation": "checkpoint", **value})
        if failed_teardown:
            # finally runs after any app assertion failure. Retain that first
            # failure without crediting phases the test never reached.
            failure = value.get("failure")
            if isinstance(failure, dict) and failure.get("stage") and failure.get("message"):
                raise RuntimeFailure(f"integration failed during {failure['stage']}: {failure['message']}")
            previous = PHASES[self.phase_index - 1] if self.phase_index else "startup"
            raise RuntimeFailure(f"integration test failed after {previous}; see flutter-drive.log and result.json")
        self.phase_index += 1
        if phase == "app-ready":
            self.capture(phase)
            self.ack("bootstrap-observed")
        elif phase == "players-ready":
            self.start_recording()
            self.ack("recording-ready")
        elif phase == "initial-ready":
            self.capture(phase)
            self.finish_recording(phase)
            self.start_recording()
            self.radios.disable()
            self.capture("radios-disabled")
            self.ack("network-disabled")
        elif phase == "offline-confirmed":
            self.capture(phase)
            if self.radios.read() != {"wifi": False, "data": False}:
                raise RuntimeFailure("radios changed before the offline observation")
            self.finish_recording(phase)
            self.start_recording()
            self.radios.restore()
            self.capture("radios-restored")
            self.ack("network-restored")
        elif phase == "reconnected-confirmed":
            self.capture(phase)
            self.finish_recording(phase)
            self.start_recording()
            self.ack("controls-ready")
        elif phase == "recovery-confirmed":
            self.capture(phase)
            self.finish_recording(phase)
            self.ack("evidence-complete")
        elif value.get("passed") is not True:
            raise RuntimeFailure("integration teardown did not complete successfully")

    def start_processes(self) -> None:
        def reader(process: subprocess.Popen, filename: str, checkpoints: bool) -> None:
            assert process.stdout is not None
            with (self.output / filename).open("w", encoding="utf-8") as log:
                for line in process.stdout:
                    log.write(line)
                    log.flush()
                    if checkpoints:
                        try:
                            value = parse_checkpoint(line, self.run_id)
                            if value is not None:
                                self.checkpoints.put(value)
                        except RuntimeFailure as error:
                            self.checkpoints.put(error)

        # Do not clear any shared log buffer. A fresh dedicated AVD plus the
        # run-ID/PID checks establish the evidence boundary.
        self.logcat = subprocess.Popen(self.adb.prefix + ["logcat", "-v", "threadtime", "-T", "1"],
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                       encoding="utf-8", errors="replace", start_new_session=True)
        thread = threading.Thread(target=reader, args=(self.logcat, "logcat.txt", True), daemon=True)
        self.readers.append(thread)
        thread.start()
        environment = dict(os.environ, NETWORK_RUN_ID=self.run_id)
        command = ["flutter", "drive", "--no-pub", "--driver=test_driver/network_interruption_driver.dart",
                   "--target=integration_test/network_interruption_test.dart",
                   f"--use-application-binary={self.apk}", "--host-vmservice-port=39107",
                   "-d", self.adb.serial]
        self.write("command.json", command)
        self.process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                        text=True, encoding="utf-8", errors="replace", env=environment,
                                        start_new_session=True)
        thread = threading.Thread(target=reader, args=(self.process, "flutter-drive.log", False), daemon=True)
        self.readers.append(thread)
        thread.start()

    def run(self) -> bool:
        self.output.mkdir(parents=True, exist_ok=False)
        self.write("runtime.json", {"runtime": RUNTIME, "runId": self.run_id,
                                   "serial": self.adb.serial, "avdName": self.avd_name,
                                   "apkSha256": hashlib.sha256(self.apk.read_bytes()).hexdigest()})
        try:
            self.radios.capture_initial()
            self.admitted = True
            if self.adb.run("shell", "pidof", PACKAGE, check=False).stdout.strip():
                raise RuntimeFailure("dedicated AVD unexpectedly already has a running MeowWatch process")
            ARTIFACT_ROOT.mkdir(parents=True, exist_ok=True)
            self.adb.prepare_storage()
            self.write("native-ui-observer-installation.json", self.observer.install())
            self.capture("initial-network")
            self.start_processes()
            deadline = time.monotonic() + 600
            while time.monotonic() < deadline:
                try:
                    checkpoint = self.checkpoints.get(timeout=0.2)
                except queue.Empty:
                    checkpoint = None
                if isinstance(checkpoint, Exception):
                    raise checkpoint
                if checkpoint is not None:
                    self.observe_checkpoint(checkpoint)
                assert self.process is not None and self.logcat is not None
                if self.process.poll() is not None:
                    if self.process.returncode != 0:
                        raise RuntimeFailure(f"flutter drive failed with exit {self.process.returncode}")
                    if self.phase_index != len(PHASES):
                        raise RuntimeFailure("flutter drive exited before every owned checkpoint completed")
                    break
                if self.logcat.poll() is not None:
                    raise RuntimeFailure("native logcat capture exited during the acceptance run")
            else:
                raise RuntimeFailure("network runtime exceeded its original 600-second deadline")
            result = json.loads((self.output / "result.json").read_text(encoding="utf-8"))
            validate_result(result, self.run_id)
            if len(self.recordings) != 4 or any(item["status"] != "verified" for item in self.recordings):
                raise RuntimeFailure("four complete native recording phases are required")
        except Exception as error:
            self.errors.append(f"{type(error).__name__}: {error}")
        finally:
            def cleanup(name: str, action: Callable[[], object]) -> None:
                try:
                    action()
                    self.event({"operation": "cleanup", "name": name, "passed": True})
                except Exception as error:
                    self.errors.append(f"{name}: {error}")
                    self.event({"operation": "cleanup", "name": name, "passed": False, "error": str(error)})
            # Restore before stopping the driver so even a failed test can run
            # its own app/TLS/decoder teardown with the original network state.
            cleanup("restore-original-radios", self.radios.restore)
            if self.admitted:
                cleanup("final-network-evidence", lambda: self.capture("finally-restored"))
            cleanup("finish-native-recording", self.finish_recording)
            cleanup("stop-owned-driver", lambda: stop_owned_process(self.process))
            cleanup("stop-owned-logcat", lambda: stop_owned_process(self.logcat))
            for thread in self.readers:
                thread.join(timeout=5)
                if thread.is_alive():
                    self.errors.append("owned evidence reader did not stop")
            cleanup("remove-owned-native-ui-observer", self.remove_observer)
            if self.android_pid is not None:
                cleanup("force-stop-owned-test-app", self.stop_test_app)
                for path in self.acknowledgements:
                    cleanup("remove-owned-ack", lambda path=path: self.remove_ack(path))
            cleanup("remove-owned-device-evidence", self.remove_device_evidence)
            self.write("recordings.json", self.recordings)
            self.write("native-ui-observer.json", {
                "installation": self.observer.installation,
                "observations": self.observer.observations,
                "removed": not self.observer.owns_package,
            })
            self.write("gate.json", {"passed": not self.errors, "errors": self.errors,
                                     "runtime": RUNTIME, "completedPhases": list(PHASES[:self.phase_index]),
                                     "originalRadios": self.radios.initial})
        return not self.errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--avd-name", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--apk", type=Path, required=True)
    args = parser.parse_args()
    if os.name != "posix":
        parser.error("this dedicated CI AVD runner requires POSIX process-group ownership")
    def interrupted(signum: int, _frame: object) -> None:
        raise RuntimeFailure(f"runner interrupted by signal {signum}")
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        runner = Runner(args.serial, args.avd_name, args.apk, args.run_id,
                        Path("build/android-network-artifacts") / args.run_id)
        return 0 if runner.run() else 1
    except (RuntimeFailure, OSError, ValueError) as error:
        print(str(error), flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
