#!/usr/bin/env python3
"""Prove permanent Android audio-focus loss while the normal app stays foreground."""

from __future__ import annotations

import argparse
from dataclasses import asdict
import hashlib
import json
from pathlib import Path
import re
import secrets
import signal
import subprocess
import time

from tools.android_install.runner import Adb, PACKAGE, RuntimeFailure, install_output_succeeded, focused_component
from tools.android_lifecycle_runtime.run import (
    Runner as LifecycleRunner, button, require_paused_stability, require_playing_advance,
)
from tools.android_native_ui.observer import DEFAULT_APK, ObserverIntegrityFailure
from tools.incoming_media_runtime.run import exact


HELPER = "com.meowwatch.audio_focus_probe"
SERVICE = f"{HELPER}/.FocusService"
HELPER_APK = Path("build/android-interruption-helper/audio-focus-probe.apk")
AVD_NAME = re.compile(r"meowwatch_interruption_[A-Za-z0-9_]{1,80}")
FOCUS_HEADER = "Audio Focus stack entries (last is top of stack):"
LIFECYCLE_TAGS = ("wm_on_resume_called", "wm_pause_activity", "wm_stop_activity", "wm_on_paused_called",
                  "wm_on_stop_called", "am_pause_activity", "am_stop_activity", "am_anr", "am_crash")


def require_owned_avd(adb: Adb, avd_name: str) -> None:
    if re.fullmatch(r"emulator-[0-9]+", adb.serial) is None or not AVD_NAME.fullmatch(avd_name):
        raise RuntimeFailure("an explicitly named interruption task AVD and emulator serial are required")
    names = adb.run("emu", "avd", "name", timeout=10).stdout.decode("utf-8").splitlines()
    names = [line.strip() for line in names if line.strip() and line.strip() != "OK"]
    if names != [avd_name]:
        raise RuntimeFailure("connected AVD is not the named interruption test AVD")
    if adb.run("shell", "getprop", "ro.kernel.qemu", timeout=10).stdout.strip() != b"1":
        raise RuntimeFailure("audio-focus acceptance requires the owned emulator")
    if (adb.run("shell", "getprop", "ro.build.version.sdk", timeout=10).stdout.strip() != b"35"
            or adb.run("shell", "getprop", "ro.product.cpu.abi", timeout=10).stdout.strip() != b"x86_64"):
        raise RuntimeFailure("audio-focus acceptance requires the dedicated API 35 x86_64 AVD")


def package_uid(raw: str, package: str) -> int:
    match = re.fullmatch(r"package:" + re.escape(package) + r" uid:([1-9][0-9]*)\s*", raw)
    if match is None or not 10000 <= int(match[1]) < 100000:
        raise RuntimeFailure("expected one exact user-0 package UID")
    return int(match[1])


def focus_stack(raw: str) -> list[dict]:
    if raw.count(FOCUS_HEADER) != 1:
        raise RuntimeFailure("Android audio-focus stack is missing or ambiguous")
    section = raw.replace("\r\n", "\n").split(FOCUS_HEADER, 1)[1].removeprefix("\n").split("\n\n", 1)[0]
    result = []
    for line in section.splitlines():
        if not line.strip():
            continue
        if not line.lstrip().startswith("source:"):
            raise RuntimeFailure("Android audio-focus stack format is unrecognized")
        matches = re.findall(r" -- (pack|gain|loss|uid): ([^\r\n]*?)(?= -- |$)", line)
        fields = dict(matches)
        if len(matches) != 4 or set(fields) != {"pack", "gain", "loss", "uid"} or not fields["uid"].isdigit():
            raise RuntimeFailure("Android focus-owner identity is incomplete")
        result.append({"package": fields["pack"], "uid": int(fields["uid"]),
                       "gain": fields["gain"], "loss": fields["loss"]})
    return result


def require_focus(raw: str, package: str, uid: int) -> list[dict]:
    stack = focus_stack(raw)
    expected = {"package": package, "uid": uid, "gain": "GAIN", "loss": "none"}
    if not stack or stack[-1] != expected or sum(row["package"] == package for row in stack) != 1:
        raise RuntimeFailure("the exact expected package does not own active permanent audio focus")
    return stack


def probe_events(raw: str, nonce: str, uid: int, pid: int | None = None) -> list[dict]:
    result = []
    for line in raw.splitlines():
        if nonce not in line:
            continue
        match = re.fullmatch(r"\s*\d+\.\d+\s+([0-9]+)\s+[0-9]+\s+I\s+MWFocusProbe\s*:\s*(\{.*\})", line)
        if match is None:
            raise RuntimeFailure("focus helper event has no verified Android log PID")
        try:
            row = json.loads(match[2])
        except json.JSONDecodeError as error:
            raise RuntimeFailure("focus helper event JSON is invalid") from error
        if (set(row) != {"protocol", "nonce", "sequence", "event", "result", "gain", "pid", "uid", "uptimeMs"}
                or row["protocol"] != 1 or row["nonce"] != nonce or row["gain"] != 1
                or row["uid"] != uid or row["pid"] != int(match[1])
                or (pid is not None and row["pid"] != pid)
                or row["sequence"] != len(result) + 1
                or not isinstance(row["uptimeMs"], int) or row["uptimeMs"] <= 0
                or (result and row["uptimeMs"] < result[-1]["uptimeMs"])):
            raise RuntimeFailure("focus helper event identity, order or device clock is invalid")
        if row["event"] not in ("requested", "released") or row["result"] != 1:
            raise RuntimeFailure("focus helper was denied, interrupted or reached its watchdog")
        result.append(row)
    return result


def lifecycle_events(raw: str) -> list[str]:
    result = []
    for line in raw.splitlines():
        if not line.strip() or line.startswith("--------- beginning of"):
            continue
        if re.match(r"\s*\d+\.\d+\s+\d+\s+\d+\s+I\s+", line) is None:
            raise RuntimeFailure("Activity lifecycle log format is invalid")
        if PACKAGE in line or HELPER in line:
            result.append(line.strip())
    return result


def require_foreground_history(before: list[str], after: list[str]) -> None:
    if after != before:
        raise RuntimeFailure("the Activity paused/stopped, a test package failed, or lifecycle history changed during focus acceptance")


def require_resumed_baseline(history: list[str], pid: str) -> None:
    callback = re.compile(r"\d+\.\d+\s+" + re.escape(pid)
                          + r"\s+\d+\s+I\s+wm_on_resume_called\s*:")
    if not any(callback.match(line) and PACKAGE + ".MainActivity" in line for line in history):
        raise RuntimeFailure("current app PID has no native Activity resume callback in the lifecycle baseline")


class Runner(LifecycleRunner):
    def __init__(self, *args, avd_name: str, helper_apk: Path = HELPER_APK, **kwargs):
        super().__init__(*args, **kwargs)
        self.avd_name = avd_name
        self.helper_apk = helper_apk
        self.nonce = secrets.token_hex(16)
        self.owns_helper = False
        self.helper_uid: int | None = None
        self.helper_pid: int | None = None
        self.focus_requested = False
        self.focus_released = False
        self.foreground_baseline: list[str] | None = None
        self.expected_pid: str | None = None
        self.checks: list[dict] = []
        self.helper_events: list[dict] = []

    def prepare(self):
        if not self.helper_apk.is_file():
            raise RuntimeFailure("independent audio-focus helper APK is required")
        # The inherited clean install removes app data, so identify this run's
        # exact AVD before allowing preparation to mutate the connected device.
        require_owned_avd(self.adb, self.avd_name)
        if self.adb.run("shell", "pm", "path", HELPER, check=False).stdout.strip():
            raise RuntimeFailure("refusing to replace a pre-existing focus helper")
        report = super().prepare()
        report["runtime"]["avdName"] = self.avd_name
        self.output.joinpath("preparation.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        # Retain ownership even if the installer result is uncertain; cleanup
        # only removes this previously absent, task-specific helper package.
        self.owns_helper = True
        try:
            result = self.adb.run("install", "--no-incremental", "-t", str(self.helper_apk), timeout=120, check=False)
        except subprocess.TimeoutExpired as error:
            self.output.joinpath("helper-install.stdout.log").write_bytes(error.stdout or b"")
            self.output.joinpath("helper-install.stderr.log").write_bytes(error.stderr or b"")
            raise
        self.output.joinpath("helper-install.stdout.log").write_bytes(result.stdout)
        self.output.joinpath("helper-install.stderr.log").write_bytes(result.stderr)
        if result.returncode != 0 or not install_output_succeeded(result.stdout.decode()):
            raise RuntimeFailure("focus helper installation was not confirmed")
        self.helper_uid = package_uid(self.adb.run("shell", "pm", "list", "packages", "-U", "--user", "0", HELPER).stdout.decode(), HELPER)
        report["focusHelper"] = {"package": HELPER, "uid": self.helper_uid,
                                "apkSha256": hashlib.sha256(self.helper_apk.read_bytes()).hexdigest()}
        self.output.joinpath("preparation.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        return report

    def raw(self, phase: str, name: str, *arguments: str) -> str:
        value = self.adb.run(*arguments, timeout=10).stdout.decode("utf-8", errors="replace")
        self.output.joinpath(f"{phase}-{name}.txt").write_text(value, encoding="utf-8")
        return value

    def foreground(self, phase: str) -> None:
        if self.pid() != self.expected_pid:
            raise ObserverIntegrityFailure("focus acceptance changed the application PID")
        focused_component(self.raw(phase, "window", "shell", "dumpsys", "window", "displays"))
        history = lifecycle_events(self.raw(phase, "activity-events", "logcat", "-b", "events", "-d", "-v", "epoch",
                                            *(tag + ":I" for tag in LIFECYCLE_TAGS), "*:S"))
        if self.foreground_baseline is None:
            require_resumed_baseline(history, self.expected_pid)
            self.foreground_baseline = history
        else:
            require_foreground_history(self.foreground_baseline, history)

    def focus(self, phase: str, owner: str | None) -> list[dict]:
        raw = self.raw(phase, "audio", "shell", "dumpsys", "audio")
        if owner is None:
            stack = focus_stack(raw)
            if any(row["package"] == HELPER for row in stack):
                raise RuntimeFailure("focus helper remained in the Android focus stack after release")
        else:
            uid = self.helper_uid if owner == HELPER else package_uid(
                self.adb.run("shell", "pm", "list", "packages", "-U", "--user", "0", PACKAGE).stdout.decode(), PACKAGE)
            stack = require_focus(raw, owner, uid)
        self.foreground(phase)
        self.checks.append({"phase": phase, "focusStack": stack, "appPid": self.expected_pid})
        return stack

    def command(self, action: str) -> None:
        if action not in ("acquire", "release"):
            raise ValueError("only fixed focus commands are permitted")
        command = "start-foreground-service" if action == "acquire" else "startservice"
        if action == "acquire":
            self.focus_requested = True
        value = self.raw(f"focus-{action}", "command", "shell", "am", command, "--user", "0", "-n", SERVICE,
                         "-a", action, "--es", "nonce", self.nonce)
        if "Error" in value or "Exception" in value or "Starting service:" not in value:
            raise RuntimeFailure("Android did not accept the owned focus service command")
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            raw = self.raw(f"focus-{action}", "events", "logcat", "-d", "-v", "epoch", "MWFocusProbe:I", "*:S")
            events = probe_events(raw, self.nonce, self.helper_uid, self.helper_pid)
            expected = ["requested"] if action == "acquire" else ["requested", "released"]
            if [row["event"] for row in events] == expected:
                self.helper_events = events
                if action == "acquire":
                    actual = self.adb.run("shell", "pidof", HELPER).stdout.decode().strip()
                    if actual != str(events[0]["pid"]):
                        raise RuntimeFailure("granted focus event is not from the current helper process")
                    self.helper_pid = int(actual)
                else:
                    self.focus_released = True
                return
            time.sleep(0.2)
        raise RuntimeFailure("fresh nonce-bound focus service result was not observed")

    def run(self):
        report = self.prepare()
        self.start_recording()
        self.load_fixture()
        xml, _ = self.sample("02-open-paused", playing=False)
        if len(exact(xml, "Local mode")) != 1:
            raise RuntimeFailure("the first focus case requires the actual Local mode")
        self.tap(button(xml, "Play"))
        _, first = self.sample("03-playing", playing=True)
        time.sleep(4)
        _, advanced = self.sample("04-playing-advanced", playing=True)
        initial_advance = require_playing_advance(first, advanced)
        self.expected_pid = self.pid()
        if not self.expected_pid:
            raise RuntimeFailure("playing app process is absent")
        self.foreground("05-foreground-baseline")
        self.focus("05-app-focus", PACKAGE)
        self.finish_recording(required_phase="05-app-focus")
        self.start_recording()
        self.foreground("06-before-focus-request")
        _, before_focus = self.sample("06-immediate-playing", playing=True, screenshot=False)
        self.command("acquire")
        self.focus("07-focus-held", HELPER)
        _, paused = self.sample("08-focus-paused", playing=False)
        if not -1 <= paused.position_seconds - before_focus.position_seconds <= 4:
            raise RuntimeFailure("audio-focus loss did not pause within four displayed seconds")
        self.foreground("08-focus-paused")
        time.sleep(4)
        _, held = self.sample("09-held-stable", playing=False)
        require_paused_stability(paused, held)
        self.focus("09-held-stable", HELPER)
        self.command("release")
        self.focus("10-focus-released", None)
        _, released = self.sample("11-release-paused", playing=False)
        require_paused_stability(held, released)
        time.sleep(4)
        xml, stable = self.sample("12-no-autoplay", playing=False)
        require_paused_stability(released, stable)
        self.foreground("12-no-autoplay")
        if len(exact(xml, "Local mode")) != 1:
            raise RuntimeFailure("interruption changed the playback mode")
        self.tap(button(xml, "Play"))
        _, replay = self.sample("13-explicit-play", playing=True)
        self.focus("13-focus-regained", PACKAGE)
        time.sleep(4)
        _, replay_advanced = self.sample("14-replay-advanced", playing=True)
        replay_advance = require_playing_advance(replay, replay_advanced)
        self.foreground("14-replay-advanced")
        self.finish_recording(required_phase="14-replay-advanced")
        report.update(completed=True, initialAdvanceSeconds=initial_advance, replayAdvanceSeconds=replay_advance,
                      observedPause=asdict(paused), samples=self.samples, focusChecks=self.checks,
                      helperEvents=self.helper_events, nativeUiObservations=self.observer.observations,
                      sameAppPid=self.expected_pid, noActivityPauseOrStop=True,
                      scope="Local mode; permanent AUDIOFOCUS_GAIN; no GSM call, transient focus, room, remote peer or quota proof")
        return report

    def cleanup(self):
        if self.owns_helper or self.cleanup_authorized or self.observer.owns_package or self.recording is not None:
            # A reused serial must not authorize stopping/removing packages or
            # remote evidence on a replacement emulator during failure cleanup.
            require_owned_avd(self.adb, self.avd_name)
        helper_error = None
        try:
            if self.owns_helper:
                try:
                    if self.focus_requested and not self.focus_released:
                        self.command("release")
                except (RuntimeFailure, OSError, subprocess.TimeoutExpired) as error:
                    helper_error = error
                finally:
                    self.adb.run("shell", "am", "force-stop", HELPER)
                    result = self.adb.run("uninstall", HELPER, timeout=60).stdout.decode().strip()
                    if result != "Success" or self.adb.run("shell", "pm", "path", HELPER, check=False).stdout.strip():
                        raise RuntimeFailure("owned focus helper removal was not confirmed")
                    self.owns_helper = False
        finally:
            super().cleanup()
        if helper_error is not None:
            raise RuntimeFailure("focus release was uncertain; owned helper was stopped and removed") from helper_error


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--avd-name", required=True)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--observer-apk", type=Path, default=DEFAULT_APK)
    parser.add_argument("--helper-apk", type=Path, default=HELPER_APK)
    parser.add_argument("--output", type=Path, default=Path("build/android-interruption-artifacts"))
    args = parser.parse_args(argv)
    runner = Runner(args.serial, args.apk, args.fixture, args.output, args.observer_apk,
                    avd_name=args.avd_name, helper_apk=args.helper_apk)
    def expired(_signal, _frame):
        raise RuntimeFailure("audio-focus acceptance exceeded its external time bound")
    signal.signal(signal.SIGTERM, expired)
    report, status = {}, 0
    try:
        report = runner.run()
    except (RuntimeFailure, OSError, ValueError, subprocess.TimeoutExpired) as error:
        status = 1
        report = {"completed": False, "phase": runner.phase, "error": str(error), "samples": runner.samples,
                  "focusChecks": runner.checks, "helperEvents": runner.helper_events,
                  "nativeUiObservations": runner.observer.observations}
        if runner.evidence_started:
            args.output.joinpath("failure.xml").write_text(runner.last_xml, encoding="utf-8")
            args.output.joinpath("failure-window.txt").write_text(runner.last_window, encoding="utf-8")
            try:
                args.output.joinpath("failure.png").write_bytes(runner.adb.screenshot())
            except (RuntimeFailure, OSError, subprocess.TimeoutExpired):
                pass
    finally:
        try:
            runner.cleanup()
        except (RuntimeFailure, OSError, subprocess.TimeoutExpired) as error:
            report.update(completed=False, cleanupError=str(error))
            status = 1
    if runner.evidence_started:
        report.update(recordings=runner.recordings, focusHelperRemoved=not runner.owns_helper,
                      nativeUiObserverRemoved=not runner.observer.owns_package,
                      nativeUiObserverInstallation=runner.observer.installation,
                      observationTimeouts=runner.observation_timeouts,
                      lastCompletedUiObservation=runner.last_observation,
                      preparationAnrRecoveries=runner.preparation_recoveries)
        args.output.joinpath("result.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("ANDROID_INTERRUPTION_RUNTIME_" + ("PASS" if status == 0 else "FAIL"))
    return status


if __name__ == "__main__":
    raise SystemExit(main())
