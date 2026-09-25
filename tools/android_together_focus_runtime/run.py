#!/usr/bin/env python3
"""Coordinate real Android focus loss with a MainApp Together integration journey."""

from __future__ import annotations

import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
import secrets
import signal
import subprocess
import threading
import time

from tools.android_install.runner import Adb, PACKAGE, RuntimeFailure, focused_component, install_output_succeeded
from tools.android_interruption_runtime.run import (
    HELPER, HELPER_APK, SERVICE, LIFECYCLE_TAGS, lifecycle_events,
    package_uid, probe_events, require_focus, require_foreground_history,
    require_prompt_pause, require_resumed_baseline, require_transient_focus,
    focus_stack,
)
from tools.android_lifecycle_runtime.run import playback
from tools.android_native_ui.observer import DEFAULT_APK, NativeUiObserver


STAGES = ("permanent-acquire", "permanent-release", "transient-acquire", "transient-release")
AVD_NAME = re.compile(r"meowwatch_interruption_[0-9]+_[0-9]+")


def validate_journey(value: object, stages: list[dict]) -> dict:
    if not isinstance(value, dict) or not isinstance(value.get("togetherFocus"), dict):
        raise RuntimeFailure("integration driver has no Together focus report")
    journey = value["togetherFocus"]
    if (journey.get("result") != "passed" or journey.get("peerCompletedTlsHello") is not True
            or len(stages) != 4 or [item["stage"] for item in stages] != list(STAGES)):
        raise RuntimeFailure("native stages or real TLS peer were not completed")
    cases = journey.get("cases")
    if not isinstance(cases, list) or len(cases) != 2:
        raise RuntimeFailure("both focus modes need complete Together snapshots")
    for mode, case in zip(("permanent", "transient"), cases):
        if not isinstance(case, dict) or case.get("mode") != mode or case.get("testSidePauseDuringInterruption") is not False:
            raise RuntimeFailure("focus case identity or no-test-pause policy is missing")
        settled = case.get("settledPlaying")
        if (not isinstance(settled, dict) or type(settled.get("continuousPlayingMs")) is not int
                or settled["continuousPlayingMs"] < 4000
                or type(settled.get("nativeAdvanceMs")) is not int
                or settled["nativeAdvanceMs"] < 2000
                or settled.get("peerUnpausedThroughout") is not True):
            raise RuntimeFailure("focus request did not follow settled room playback")
        monitor = case.get("noAutoplayMonitor")
        if (not isinstance(monitor, dict) or type(monitor.get("monitoredMs")) is not int
                or monitor["monitoredMs"] < 8000
                or type(monitor.get("nativeEvents")) is not int
                or type(monitor.get("roomEvents")) is not int or monitor["roomEvents"] < 1
                or monitor.get("forbiddenPlayEvents") != []):
            raise RuntimeFailure("continuous native/peer no-autoplay monitoring failed")
        if (case.get("acquire") != stages[list(STAGES).index(f"{mode}-acquire")]
                or case.get("release") != stages[list(STAGES).index(f"{mode}-release")]):
            raise RuntimeFailure("Dart did not receive the exact native stage receipts")
        snapshots = [case.get(key) for key in ("before", "paused", "held", "afterRelease", "explicitReplay")]
        if any(not isinstance(row, dict) for row in snapshots):
            raise RuntimeFailure("native player snapshots are incomplete")
        before, paused, held, released, replay = snapshots
        for row in snapshots:
            if (row.get("nativeReady") is not True or row.get("nativeError") is not None
                    or type(row.get("nativePositionMs")) is not int or row["nativePositionMs"] < 0
                    or type(row.get("nativeDurationMs")) is not int or row["nativeDurationMs"] < 170000
                    or type(row.get("peerPositionMs")) is not int):
                raise RuntimeFailure("native decoder or peer position evidence is invalid")
        if (before.get("nativePlaying") is not True or before.get("peerPaused") is not False
                or any(row.get("nativePlaying") is not False or row.get("peerPaused") is not True
                       for row in (paused, held, released))
                or replay.get("nativePlaying") is not True or replay.get("peerPaused") is not False
                or replay["nativePositionMs"] <= released["nativePositionMs"] + 500
                or abs(held["nativePositionMs"] - paused["nativePositionMs"]) > 1500
                or abs(released["nativePositionMs"] - held["nativePositionMs"]) > 1500):
            raise RuntimeFailure("focus pause, no-autoplay or explicit replay did not hold")
    return journey


class FocusSession:
    def __init__(self, adb: Adb, avd_name: str, output: Path, helper_apk: Path, observer_apk: Path):
        self.adb, self.avd_name, self.output = adb, avd_name, output
        self.helper_apk = helper_apk
        self.observer = NativeUiObserver(adb, observer_apk)
        self.helper_owned = False
        self.helper_uid: int | None = None
        self.app_uid: int | None = None
        self.app_pid: str | None = None
        self.nonce: str | None = None
        self.gain = 1
        self.helper_pid: int | None = None
        self.events: list[dict] = []
        self.lifecycle_baseline: list[str] | None = None
        self.completed: list[dict] = []

    def prepare(self) -> dict:
        if (not AVD_NAME.fullmatch(self.avd_name) or not re.fullmatch(r"emulator-[0-9]+", self.adb.serial)):
            raise RuntimeFailure("an explicitly named Together focus AVD is required")
        names = [line.strip() for line in self.adb.run("emu", "avd", "name").stdout.decode().splitlines()
                 if line.strip() and line.strip() != "OK"]
        if names != [self.avd_name]:
            raise RuntimeFailure("connected AVD does not match the task name")
        for key, expected in (("ro.kernel.qemu", b"1"), ("ro.build.version.sdk", b"35"),
                              ("ro.product.cpu.abi", b"x86_64")):
            if self.adb.run("shell", "getprop", key).stdout.strip() != expected:
                raise RuntimeFailure("Together focus requires its dedicated API 35 x86_64 emulator")
        if not self.helper_apk.is_file():
            raise RuntimeFailure("independent focus helper APK is missing")
        if self.adb.run("shell", "pm", "path", HELPER, check=False).stdout.strip():
            raise RuntimeFailure("refusing to replace a pre-existing focus helper")
        self.helper_owned = True
        installed = self.adb.run("install", "--no-incremental", "-t", str(self.helper_apk), timeout=60)
        if not install_output_succeeded(installed.stdout.decode()):
            raise RuntimeFailure("focus helper installation was not confirmed")
        self.helper_uid = package_uid(self.adb.run("shell", "pm", "list", "packages", "-U", "--user", "0", HELPER).stdout.decode(), HELPER)
        observer = self.observer.install()
        return {"serial": self.adb.serial, "avdName": self.avd_name,
                "model": self.adb.run("shell", "getprop", "ro.product.model").stdout.decode().strip(),
                "api": 35, "abi": "x86_64", "physicalDevice": False,
                "helperApkSha256": hashlib.sha256(self.helper_apk.read_bytes()).hexdigest(),
                "observer": observer}

    def raw(self, stage: str, name: str, *command: str) -> str:
        result = self.adb.run(*command, timeout=20).stdout.decode("utf-8", errors="replace")
        (self.output / f"{stage}-{name}.txt").write_text(result, encoding="utf-8")
        return result

    def foreground(self, stage: str) -> None:
        pid = self.adb.run("shell", "pidof", PACKAGE).stdout.decode().strip()
        if not re.fullmatch(r"[0-9]+", pid) or (self.app_pid is not None and pid != self.app_pid):
            raise RuntimeFailure("Together app process is absent or changed")
        self.app_pid = pid
        focused_component(self.raw(stage, "window", "shell", "dumpsys", "window", "displays"))
        history = lifecycle_events(self.raw(stage, "lifecycle", "logcat", "-b", "events", "-d", "-v", "epoch",
                                            *(tag + ":I" for tag in LIFECYCLE_TAGS), "*:S"))
        if self.lifecycle_baseline is None:
            require_resumed_baseline(history, pid)
            self.lifecycle_baseline = history
        else:
            require_foreground_history(self.lifecycle_baseline, history)

    def _events(self, stage: str) -> list[dict]:
        raw = self.raw(stage, "helper-events", "logcat", "-d", "-v", "epoch", "MWFocusProbe:I", "*:S")
        return probe_events(raw, self.nonce, self.helper_uid, self.helper_pid, gain=self.gain)

    def _command(self, stage: str, action: str) -> dict:
        command = "start-foreground-service" if action == "acquire" else "startservice"
        mode = ("--es", "mode", "transient") if self.gain == 2 and action == "acquire" else ()
        result = self.raw(stage, "command", "shell", "am", command, "--user", "0", "-n", SERVICE,
                          "-a", action, "--es", "nonce", self.nonce, *mode)
        if "Starting service:" not in result or "Error" in result or "Exception" in result:
            raise RuntimeFailure("Android rejected the native focus helper command")
        deadline = time.monotonic() + 15
        expected = ["requested"] if action == "acquire" else ["requested", "released"]
        while time.monotonic() < deadline:
            events = self._events(stage)
            if [row["event"] for row in events] == expected:
                self.events = events
                if action == "acquire":
                    actual = self.adb.run("shell", "pidof", HELPER).stdout.decode().strip()
                    if actual != str(events[0]["pid"]):
                        raise RuntimeFailure("focus grant is not from the current helper process")
                    self.helper_pid = int(actual)
                return events[-1]
            time.sleep(0.2)
        raise RuntimeFailure("nonce-bound focus event was not observed")

    def stage(self, stage: str) -> dict:
        if stage != STAGES[len(self.completed)]:
            raise RuntimeFailure("focus stages must be issued once and in order")
        mode, action = stage.split("-")
        self.gain = 1 if mode == "permanent" else 2
        self.foreground(stage + "-before")
        if action == "acquire":
            self.app_uid = package_uid(self.adb.run("shell", "pm", "list", "packages", "-U", "--user", "0", PACKAGE).stdout.decode(), PACKAGE)
            require_focus(self.raw(stage, "app-focus", "shell", "dumpsys", "audio"), PACKAGE, self.app_uid)
            self.nonce = secrets.token_hex(16)
            self.helper_pid = None
            self.events = []
        event = self._command(stage, action)
        xml, window = self.observer.observe()
        (self.output / f"{stage}.xml").write_text(xml, encoding="utf-8")
        (self.output / f"{stage}-observer-window.txt").write_text(window, encoding="utf-8")
        (self.output / f"{stage}.png").write_bytes(self.adb.screenshot())
        native = playback(xml, expected_duration_seconds=180)
        if native.playing:
            raise RuntimeFailure("Together native UI did not show paused playback after focus action")
        capture = self.observer.observations[-1]
        timing = require_prompt_pause(event, capture, xml, self.app_pid) if action == "acquire" else None
        audio = self.raw(stage, "focus-stack", "shell", "dumpsys", "audio")
        if action == "acquire":
            stack = (require_transient_focus(audio, self.helper_uid, self.app_uid) if self.gain == 2
                     else require_focus(audio, HELPER, self.helper_uid))
        else:
            stack = focus_stack(audio)
            if any(row["package"] == HELPER for row in stack):
                raise RuntimeFailure("focus helper remained in the stack after release")
        self.foreground(stage + "-after")
        row = {"stage": stage, "completed": True, "focusStack": stack, "event": event,
               "nativeUi": {"positionSeconds": native.position_seconds, "durationSeconds": native.duration_seconds,
                            "playing": native.playing, "xmlSha256": hashlib.sha256(xml.encode()).hexdigest(),
                            "capture": capture}, "appPid": self.app_pid,
               "pauseTiming": timing}
        self.completed.append(row)
        if action == "release":
            self.adb.run("shell", "am", "force-stop", HELPER)
        return row

    def cleanup(self) -> None:
        if self.helper_owned or self.observer.owns_package:
            names = [line.strip() for line in self.adb.run("emu", "avd", "name").stdout.decode().splitlines()
                     if line.strip() and line.strip() != "OK"]
            if names != [self.avd_name]:
                raise RuntimeFailure("emulator identity changed; refusing helper cleanup")
        errors = []
        if self.helper_owned:
            try:
                self.adb.run("shell", "am", "force-stop", HELPER)
            except Exception as error:
                errors.append(f"focus helper stop: {error}")
            try:
                result = self.adb.run("uninstall", HELPER, timeout=60)
                if result.stdout.strip() != b"Success":
                    raise RuntimeFailure("task focus helper removal was not confirmed")
                self.helper_owned = False
            except Exception as error:
                errors.append(f"focus helper uninstall: {error}")
        try:
            self.observer.cleanup()
        except Exception as error:
            errors.append(f"native UI observer cleanup: {error}")
        if errors:
            raise RuntimeFailure("; ".join(errors))


class StageServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = False

    def __init__(self, session: FocusSession, port: int):
        super().__init__(("127.0.0.1", port), StageHandler)
        self.session = session
        self.lock = threading.Lock()
        self.failed: str | None = None


class StageHandler(BaseHTTPRequestHandler):
    server: StageServer

    def do_POST(self) -> None:
        stage = self.path.removeprefix("/")
        length = self.headers.get("Content-Length", "")
        if stage not in STAGES or not length.isdecimal() or int(length) > 128:
            return self._reply(400, {"error": "invalid stage request"})
        try:
            payload = json.loads(self.rfile.read(int(length)))
        except (ValueError, UnicodeDecodeError):
            return self._reply(400, {"error": "invalid stage body"})
        if payload != {"stage": stage}:
            return self._reply(400, {"error": "stage body mismatch"})
        with self.server.lock:
            if self.server.failed is not None:
                return self._reply(409, {"error": self.server.failed})
            try:
                row = self.server.session.stage(stage)
            except Exception as error:
                self.server.failed = f"{type(error).__name__}: {error}"
                return self._reply(500, {"error": self.server.failed})
        self._reply(200, row)

    def _reply(self, status: int, body: dict) -> None:
        data = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format: str, *args: object) -> None:
        pass


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--avd-name", required=True)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--helper-apk", type=Path, default=HELPER_APK)
    parser.add_argument("--observer-apk", type=Path, default=DEFAULT_APK)
    parser.add_argument("--output", type=Path, default=Path("build/android-together-focus-artifacts"))
    parser.add_argument("--port", type=int, default=18867)
    args = parser.parse_args(argv)
    if not args.apk.is_file() or not 1024 <= args.port <= 65535:
        parser.error("prebuilt integration APK and valid bridge port are required")
    args.output.mkdir(parents=True, exist_ok=True)
    if any(args.output.iterdir()):
        parser.error("evidence directory must start empty")
    adb = Adb(args.serial, "together-focus-" + secrets.token_hex(6))
    session = FocusSession(adb, args.avd_name, args.output, args.helper_apk, args.observer_apk)
    summary = {"passed": False, "runtimeBoundary": "MainApp production services in integration APK; "
               "independent same-process TLS peer; one Android native decoder", "stages": []}
    server = None
    process = None
    def expired(_signal, _frame):
        raise RuntimeFailure("Together focus gate received termination signal")
    signal.signal(signal.SIGTERM, expired)
    try:
        summary["device"] = session.prepare()
        summary["apkSha256"] = hashlib.sha256(args.apk.read_bytes()).hexdigest()
        installed = adb.run("install", "--no-incremental", "-t", str(args.apk), timeout=120)
        if not install_output_succeeded(installed.stdout.decode()):
            raise RuntimeFailure("integration APK installation was not confirmed")
        if adb.run("shell", "pm", "clear", PACKAGE).stdout.strip() != b"Success":
            raise RuntimeFailure("clean app data was not confirmed")
        server = StageServer(session, args.port)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        command = ["flutter", "drive", "--no-pub", "-d", args.serial,
                   "--driver=tools/android_together_focus_runtime/driver.dart",
                   "--target=integration_test/together_focus_journey_test.dart",
                   f"--use-application-binary={args.apk}", "--timeout=540"]
        with (args.output / "flutter-drive.log").open("w", encoding="utf-8") as log:
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, text=True)
            try:
                code = process.wait(timeout=580)
            except subprocess.TimeoutExpired:
                process.terminate()
                code = process.wait(timeout=15)
                raise RuntimeFailure("Together focus Flutter drive exceeded deadline")
        summary["driveExitCode"] = code
        if code != 0:
            raise RuntimeFailure("Together focus integration journey failed")
        report = json.loads((args.output / "journey.json").read_text(encoding="utf-8"))
        summary["journey"] = validate_journey(report, session.completed)
        if server.failed:
            raise RuntimeFailure(server.failed)
        summary["passed"] = True
    except Exception as error:
        summary["error"] = f"{type(error).__name__}: {error}"
        if session.app_pid:
            try:
                (args.output / "failure.png").write_bytes(adb.screenshot())
            except Exception:
                pass
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=10)
        if server is not None:
            server.shutdown()
            server.server_close()
        try:
            session.cleanup()
        except Exception as error:
            summary["cleanupError"] = str(error)
            summary["passed"] = False
        summary["stages"] = session.completed
        summary["nativeUiObservations"] = session.observer.observations
        (args.output / "run.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print("ANDROID_TOGETHER_FOCUS_" + ("PASS" if summary["passed"] else "FAIL"))
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
