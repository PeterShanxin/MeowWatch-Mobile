#!/usr/bin/env python3
"""Prove permanent and transient audio-focus loss while MainApp stays foreground."""

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
    Runner as LifecycleRunner, button, playback, require_paused_stability, require_playing_advance,
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


def require_transient_focus(raw: str, helper_uid: int, app_uid: int) -> list[dict]:
    stack = focus_stack(raw)
    helper = {"package": HELPER, "uid": helper_uid, "gain": "GAIN_TRANSIENT", "loss": "none"}
    app = {"package": PACKAGE, "uid": app_uid, "gain": "GAIN", "loss": "LOSS_TRANSIENT"}
    if (len(stack) < 2 or stack[-1] != helper or stack[-2] != app
            or sum(row["package"] == HELPER for row in stack) != 1
            or sum(row["package"] == PACKAGE for row in stack) != 1):
        raise RuntimeFailure("the transient helper did not interrupt the exact current MainApp focus owner")
    return stack


def probe_events(raw: str, nonce: str, uid: int, pid: int | None = None, *, gain: int = 1) -> list[dict]:
    if gain not in (1, 2):
        raise ValueError("focus proof requires permanent or transient gain")
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
        if (set(row) != {"protocol", "nonce", "sequence", "event", "result", "gain", "pid", "uid",
                         "elapsedRealtimeMs", "requestStartedElapsedRealtimeMs"}
                or row["protocol"] != 2 or row["nonce"] != nonce or row["gain"] != gain
                or row["uid"] != uid or row["pid"] != int(match[1])
                or (pid is not None and row["pid"] != pid)
                or row["sequence"] != len(result) + 1
                or type(row["elapsedRealtimeMs"]) is not int
                or type(row["requestStartedElapsedRealtimeMs"]) is not int
                or not 0 < row["requestStartedElapsedRealtimeMs"] <= row["elapsedRealtimeMs"]
                or (result and (row["elapsedRealtimeMs"] < result[-1]["elapsedRealtimeMs"]
                                or row["requestStartedElapsedRealtimeMs"] != result[0]["requestStartedElapsedRealtimeMs"]))):
            raise RuntimeFailure("focus helper event identity, order or device clock is invalid")
        if row["event"] not in ("requested", "released") or row["result"] != 1:
            raise RuntimeFailure("focus helper was denied, interrupted or reached its watchdog")
        result.append(row)
    return result


def require_prompt_pause(request: dict, observation: dict, xml: str, app_pid: str) -> dict:
    """Conservative device-clock upper bound, including the entire UI traversal."""
    start = request.get("requestStartedElapsedRealtimeMs")
    granted = request.get("elapsedRealtimeMs")
    capture_start = observation.get("captureStartedAtElapsedRealtimeMs")
    capture_end = observation.get("captureCompletedAtElapsedRealtimeMs")
    if (any(type(value) is not int for value in (start, granted, capture_start, capture_end))
            or not 0 < start <= granted <= capture_start <= capture_end
            or request.get("event") != "requested" or request.get("result") != 1
            or observation.get("status") != "success"
            or observation.get("applicationPid") != int(app_pid)
            or observation.get("applicationPidAfter") != int(app_pid)
            or observation.get("xmlSha256") != hashlib.sha256(xml.encode()).hexdigest()):
        raise RuntimeFailure("focus pause timing is not bound to a fresh same-process hierarchy")
    elapsed = capture_end - start
    if elapsed > 4000:
        raise RuntimeFailure("audio-focus pause was not observed within four device-clock seconds")
    return {"requestStartedAtElapsedRealtimeMs": start,
            "pausedHierarchyCompletedAtElapsedRealtimeMs": capture_end,
            "pauseUpperBoundMs": elapsed, "limitMs": 4000}


def require_prompt_transient_resume(release: dict, observation: dict, xml: str, app_pid: str) -> dict:
    """Bound auto-resume by the complete native hierarchy, not ADB transport time."""
    released = release.get("elapsedRealtimeMs")
    capture_start = observation.get("captureStartedAtElapsedRealtimeMs")
    capture_end = observation.get("captureCompletedAtElapsedRealtimeMs")
    if (any(type(value) is not int for value in (released, capture_start, capture_end))
            or not 0 < released <= capture_start <= capture_end
            or release.get("event") != "released" or release.get("result") != 1
            or release.get("gain") != 2
            or observation.get("status") != "success"
            or observation.get("applicationPid") != int(app_pid)
            or observation.get("applicationPidAfter") != int(app_pid)
            or observation.get("xmlSha256") != hashlib.sha256(xml.encode()).hexdigest()):
        raise RuntimeFailure("transient resume timing is not bound to a fresh same-process hierarchy")
    elapsed = capture_end - released
    if elapsed > 10000:
        raise RuntimeFailure("transient audio-focus auto-resume was not observed within ten device-clock seconds")
    return {"releasedAtElapsedRealtimeMs": released,
            "playingHierarchyCompletedAtElapsedRealtimeMs": capture_end,
            "resumeUpperBoundMs": elapsed, "limitMs": 10000}


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
        self.focus_gain = 1
        self.permanent_completed = False
        self.permanent_helper_events: list[dict] = []
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

    def focus(self, phase: str, owner: str | None, *, transient: bool = False) -> list[dict]:
        raw = self.raw(phase, "audio", "shell", "dumpsys", "audio")
        if owner is None:
            stack = focus_stack(raw)
            if any(row["package"] == HELPER for row in stack):
                raise RuntimeFailure("focus helper remained in the Android focus stack after release")
        else:
            uid = self.helper_uid if owner == HELPER else package_uid(
                self.adb.run("shell", "pm", "list", "packages", "-U", "--user", "0", PACKAGE).stdout.decode(), PACKAGE)
            if transient:
                if owner != HELPER:
                    raise ValueError("only the independent helper may request transient focus")
                app_uid = package_uid(self.adb.run(
                    "shell", "pm", "list", "packages", "-U", "--user", "0", PACKAGE).stdout.decode(), PACKAGE)
                stack = require_transient_focus(raw, uid, app_uid)
            else:
                stack = require_focus(raw, owner, uid)
        self.foreground(phase)
        self.checks.append({"phase": phase, "focusStack": stack, "appPid": self.expected_pid})
        return stack

    def command(self, action: str) -> None:
        if action not in ("acquire", "release"):
            raise ValueError("only fixed focus commands are permitted")
        if self.focus_gain not in (1, 2):
            raise ValueError("only permanent or transient focus may be requested")
        command = "start-foreground-service" if action == "acquire" else "startservice"
        if action == "acquire":
            self.focus_requested = True
        mode = ("--es", "mode", "transient") if action == "acquire" and self.focus_gain == 2 else ()
        phase = f"{'transient-' if self.focus_gain == 2 else ''}focus-{action}"
        value = self.raw(phase, "command", "shell", "am", command, "--user", "0", "-n", SERVICE,
                         "-a", action, "--es", "nonce", self.nonce, *mode)
        if "Error" in value or "Exception" in value or "Starting service:" not in value:
            raise RuntimeFailure("Android did not accept the owned focus service command")
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            raw = self.raw(phase, "events", "logcat", "-d", "-v", "epoch", "MWFocusProbe:I", "*:S")
            events = probe_events(raw, self.nonce, self.helper_uid, self.helper_pid, gain=self.focus_gain)
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

    def run_transient(self) -> dict:
        # A fresh request/nonce makes the transient case independent of the
        # completed permanent-loss case while retaining the same app and media.
        self.nonce = secrets.token_hex(16)
        self.focus_gain = 2
        self.helper_pid = None
        self.helper_events = []
        self.focus_requested = self.focus_released = False
        self.start_recording()
        self.foreground("15-before-transient")
        _, before = self.sample("15-transient-playing", playing=True, screenshot=False)
        self.focus("15-transient-app-focus", PACKAGE)
        self.command("acquire")
        xml, paused = self.sample("16-transient-paused", playing=False)
        pause_timing = require_prompt_pause(self.helper_events[0], self.observer.observations[-1],
                                            xml, self.expected_pid)
        if paused.position_seconds < before.position_seconds - 1 or paused.duration_seconds != before.duration_seconds:
            raise RuntimeFailure("transient audio focus changed the source or rewound the media")
        self.focus("16-transient-held", HELPER, transient=True)
        self.foreground("16-transient-paused")
        time.sleep(4)
        _, held = self.sample("17-transient-held-stable", playing=False)
        require_paused_stability(paused, held)
        self.focus("17-transient-held", HELPER, transient=True)
        self.command("release")
        self.focus("18-transient-released", None)

        def playing(xml: str):
            state = playback(xml, expected_duration_seconds=self.expected_duration_seconds)
            if not state.playing:
                raise RuntimeFailure("transient focus did not automatically resume playback")
            return state

        xml, resumed = self.wait("19-transient-auto-resumed", playing, timeout=10)
        self.samples.append({"phase": "19-transient-auto-resumed",
                             "observedAtMonotonic": time.monotonic(), **asdict(resumed)})
        self.output.joinpath("19-transient-auto-resumed.png").write_bytes(self.adb.screenshot())
        resume_timing = require_prompt_transient_resume(
            self.helper_events[1], self.observer.observations[-1], xml, self.expected_pid)
        if (resumed.duration_seconds != before.duration_seconds
                or resumed.position_seconds < held.position_seconds - 1):
            raise RuntimeFailure("transient auto-resume changed the source or rewound the media")
        self.focus("19-transient-app-focus-regained", PACKAGE)
        self.foreground("19-transient-auto-resumed")
        time.sleep(4)
        _, advanced = self.sample("20-transient-auto-advanced", playing=True)
        advance = require_playing_advance(resumed, advanced)
        self.foreground("20-transient-auto-advanced")
        self.finish_recording(required_phase="20-transient-auto-advanced")
        return {"pauseTiming": pause_timing, "resumeTiming": resume_timing,
                "autoResumeAdvanceSeconds": advance, "observedPause": asdict(paused),
                "observedResume": asdict(resumed), "helperEvents": list(self.helper_events),
                "sameAppPid": self.expected_pid, "manualPlayAfterRelease": False}

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
        xml, paused = self.sample("08-focus-paused", playing=False)
        pause_timing = require_prompt_pause(self.helper_events[0], self.observer.observations[-1],
                                            xml, self.expected_pid)
        if paused.position_seconds < before_focus.position_seconds - 1:
            raise RuntimeFailure("audio-focus interruption unexpectedly rewound the media")
        self.focus("07-focus-held", HELPER)
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
        self.permanent_completed = True
        self.permanent_helper_events = list(self.helper_events)
        transient = self.run_transient()
        report.update(completed=True, initialAdvanceSeconds=initial_advance, replayAdvanceSeconds=replay_advance,
                      pauseTiming=pause_timing,
                      preActionDisplayedAdvanceSeconds=paused.position_seconds - before_focus.position_seconds,
                      observedPause=asdict(paused), samples=self.samples, focusChecks=self.checks,
                      helperEvents=self.permanent_helper_events, transient=transient,
                      permanentCompleted=self.permanent_completed,
                      nativeUiObservations=self.observer.observations,
                      sameAppPid=self.expected_pid, noActivityPauseOrStop=True,
                      scope="Local mode; permanent AUDIOFOCUS_GAIN and separate AUDIOFOCUS_GAIN_TRANSIENT; "
                            "no GSM call, Together room, remote peer or quota proof")
        return report

    def cleanup(self):
        if self.owns_helper or self.cleanup_authorized or self.adb.remote_root_created or self.observer.owns_package or self.recording is not None:
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
                  "permanentCompleted": runner.permanent_completed,
                  "permanentHelperEvents": runner.permanent_helper_events,
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
