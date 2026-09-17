#!/usr/bin/env python3
"""Verify real normal-APK playback across HOME and a separate app process."""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import hashlib
import json
import math
import os
from pathlib import Path
import queue
import re
import signal
import subprocess
import threading
import time
from typing import Callable, Sequence, TypeVar
import xml.etree.ElementTree as ET

from tools.android_install.runner import (
    ACTIVITY, Adb, PACKAGE, RuntimeFailure, focused_component,
    install_output_succeeded, launch_output_succeeded, parse_package_metadata,
    validate_mp4,
)
from tools.incoming_media_runtime.run import center, exact, nodes, require_review
from tools.billing_runtime.native_dialog import (
    LAUNCHER_PACKAGE, SETUP_PACKAGE, UnsafeDialog, image_size,
    select_google_sdk_setup_anr_close, select_pixel_launcher_anr_close,
)
from tools.android_native_ui.observer import DEFAULT_APK, NativeUiObserver, ObserverIntegrityFailure


FIXTURE_NAME = "sync-fixture.mp4"
FIXTURE_URL = "http://10.0.2.2:18765/sync-fixture.mp4"
MAX_OBSERVATION_TIMEOUTS = 3
MAX_PREPARATION_ANR_RECOVERIES = 2
T = TypeVar("T")


class PreparationRecoveryFailure(RuntimeFailure):
    """Preparation recovery must stop rather than repeat an uncertain action."""


def recording_size(display: str) -> tuple[int, int]:
    sizes = re.findall(r"(?m)^(Physical|Override) size: (\d+)x(\d+)\s*$", display)
    if not sizes or len({kind for kind, _, _ in sizes}) != len(sizes):
        raise RuntimeFailure("native recording requires unambiguous Android display dimensions")
    selected = next((row for row in sizes if row[0] == "Override"), sizes[0])
    width, height = int(selected[1]), int(selected[2])
    if not 200 <= width <= 10000 or not 200 <= height <= 10000:
        raise RuntimeFailure("native recording display dimensions are outside supported bounds")
    scale = min(720 / width, 1600 / height, 1)
    return max(2, int(width * scale) // 2 * 2), max(2, int(height * scale) // 2 * 2)


def validate_recording_duration(duration: float, elapsed: float, exited_early: bool) -> None:
    if (not math.isfinite(duration) or not math.isfinite(elapsed) or duration <= 0
            or elapsed <= 0 or duration > 181 or elapsed > 180 or exited_early
            or duration + 3 < elapsed):
        raise RuntimeFailure("native recording ended early or does not cover its measured segment")


class LifecycleRecording:
    """One original, bounded screenrecord segment with verified process ownership."""

    def __init__(self, adb: Adb, output: Path, index: int, size: tuple[int, int]):
        self.adb, self.size = adb, size
        self.output = output / "native" / f"lifecycle-{index:02}.mp4"
        self.remote = f"{adb.remote_prefix}lifecycle-{index:02}.mp4"
        self.process: subprocess.Popen[str] | None = None
        self.reader: threading.Thread | None = None
        self.pid: str | None = None
        self.finished = False
        self.metadata: dict[str, object] = {"file": str(self.output.relative_to(output)).replace("\\", "/"),
                                            "status": "not-started", "width": size[0], "height": size[1],
                                            "timeLimitSeconds": 180}

    def start(self) -> None:
        if (re.fullmatch(r"emulator-[0-9]+", self.adb.serial) is None
                or self.adb.run("shell", "getprop", "ro.kernel.qemu").stdout.strip() != b"1"
                or re.fullmatch(r"/sdcard/meowwatch-install-[A-Za-z0-9_-]+/lifecycle-\d+\.mp4", self.remote) is None):
            raise RuntimeFailure("native recording requires an owned path and verified emulator")
        if self.adb.run("shell", "pidof", "screenrecord", check=False).stdout.strip():
            raise RuntimeFailure("refusing to replace an existing Android screen recorder")
        self.output.parent.mkdir(parents=True, exist_ok=True)
        self.adb.remote_files.append(self.remote)
        width, height = self.size
        command = (f"screenrecord --size {width}x{height} --bit-rate 2000000 --time-limit 180 {self.remote} & "
                   "record_pid=$!; printf 'LIFECYCLE_RECORDER_PID=%s\\n' \"$record_pid\"; wait \"$record_pid\"")
        self.metadata["launchRequestedAtMonotonic"] = time.monotonic()
        self.process = subprocess.Popen(self.adb.prefix + ["shell", command], stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
        observed: queue.Queue[str] = queue.Queue()

        def read_output() -> None:
            assert self.process and self.process.stdout
            for line in self.process.stdout:
                match = re.fullmatch(r"LIFECYCLE_RECORDER_PID=(\d+)\s*", line)
                if match:
                    observed.put(match[1])

        self.reader = threading.Thread(target=read_output, daemon=True)
        self.reader.start()
        try:
            self.pid = observed.get(timeout=10)
        except queue.Empty:
            self.metadata["status"] = "failed"
            raise RuntimeFailure("could not identify the owned lifecycle recorder") from None
        self.metadata.update({"status": "recording", "pid": int(self.pid),
                              "startedAtMonotonic": time.monotonic()})

    def finish(self) -> None:
        if self.finished or self.process is None:
            return
        self.finished = True
        stopped = time.monotonic()
        self.metadata["stopRequestedAtMonotonic"] = stopped
        exited_early = self.process.poll() is not None
        self.metadata["exitedBeforeStopRequest"] = exited_early
        try:
            if not exited_early:
                if self.pid is None:
                    raise RuntimeFailure("native lifecycle recorder PID is missing")
                command = self.adb.run("exec-out", "cat", f"/proc/{self.pid}/cmdline").stdout.decode(
                    "utf-8", errors="replace").split("\x00")
                if command[0].rsplit("/", 1)[-1] != "screenrecord" or self.remote not in command:
                    raise RuntimeFailure("native lifecycle recorder ownership changed; no signal sent")
                self.adb.run("shell", "kill", "-2", self.pid)
            self.process.wait(timeout=20)
            if self.reader:
                self.reader.join(timeout=5)
                if self.reader.is_alive():
                    raise RuntimeFailure("native lifecycle recorder output did not close")
            self.adb.run("pull", self.remote, str(self.output), timeout=40)
            data = self.output.read_bytes()
            validate_mp4(data)
            self.metadata.update({"pulledAtMonotonic": time.monotonic(),
                                  "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)})
            probe = subprocess.run(["ffprobe", "-v", "error", "-show_entries",
                                    "format=duration:stream=codec_type,width,height", "-of", "json", str(self.output)],
                                   capture_output=True, check=False, timeout=15)
            if probe.returncode:
                raise RuntimeFailure("native lifecycle recording could not be decoded by ffprobe")
            try:
                metadata = json.loads(probe.stdout)
                streams = metadata["streams"]
                duration = float(metadata["format"]["duration"])
                if (len(streams) != 1 or streams[0]["codec_type"] != "video"
                        or (streams[0]["width"], streams[0]["height"]) != self.size):
                    raise ValueError()
            except (ValueError, TypeError, KeyError):
                raise RuntimeFailure("native lifecycle recording dimensions or duration are invalid") from None
            elapsed = stopped - float(self.metadata["startedAtMonotonic"])
            self.metadata.update({"videoDurationSeconds": duration, "measuredSegmentSeconds": elapsed})
            validate_recording_duration(duration, elapsed, exited_early)
            self.metadata["status"] = "verified"
        except (RuntimeFailure, OSError, subprocess.TimeoutExpired) as error:
            self.metadata["status"] = "failed"
            self.metadata["error"] = str(error) if isinstance(error, RuntimeFailure) else type(error).__name__
            raise
        finally:
            if self.process.poll() is None:
                # This is our local ADB subprocess, not an unverified Android PID.
                self.process.terminate()
                self.process.wait(timeout=5)
            if self.process.stdout:
                self.process.stdout.close()


@dataclass(frozen=True)
class Playback:
    position_seconds: int
    duration_seconds: int
    playing: bool


def labels(xml: str) -> list[str]:
    return [value for node in nodes(xml)
            for value in (node.get("text", ""), node.get("content-desc", "")) if value]


def parse_time(value: str) -> int | None:
    if re.fullmatch(r"\d+:[0-5]\d(?::[0-5]\d)?", value) is None:
        return None
    total = 0
    for part in value.split(":"):
        total = total * 60 + int(part)
    return total


def button(xml: str, *alternatives: str) -> ET.Element:
    matches = [node for label in alternatives for node in exact(xml, label, clickable=True)]
    if len(matches) != 1:
        raise RuntimeFailure("expected one enabled playback action")
    return matches[0]


def playback(xml: str) -> Playback:
    values = labels(xml)
    if not any(FIXTURE_NAME in value for value in values):
        raise RuntimeFailure("the loaded playback source is not the controlled fixture")
    if not any(node.get("class", "").endswith("SeekBar") for node in nodes(xml)):
        raise RuntimeFailure("the actual player timeline is unavailable")
    times = sorted({parsed for value in values if (parsed := parse_time(value)) is not None})
    if len(times) != 2 or not 89 <= times[1] <= 91 or times[0] >= times[1]:
        raise RuntimeFailure("unique actual elapsed and 90-second duration labels are required")
    play = [node for label in ("Play", "Play together") for node in exact(xml, label, clickable=True)]
    pause = [node for label in ("Pause", "Pause together") for node in exact(xml, label, clickable=True)]
    if len(play) + len(pause) != 1:
        raise RuntimeFailure("player must expose exactly one enabled Play or Pause action")
    return Playback(times[0], times[1], bool(pause))


def require_playing_advance(before: Playback, after: Playback) -> int:
    advance = after.position_seconds - before.position_seconds
    if not before.playing or not after.playing or advance < 2:
        raise RuntimeFailure("native playback did not advance by at least two displayed seconds")
    return advance


def require_paused_stability(before: Playback, after: Playback) -> None:
    if before.playing or after.playing or abs(after.position_seconds - before.position_seconds) > 1:
        raise RuntimeFailure("paused playback advanced or resumed without an explicit Play action")


def require_background_pause(before: Playback, after: Playback, home_seconds: float) -> None:
    advance = after.position_seconds - before.position_seconds
    if not before.playing or after.playing or home_seconds < 8 or not -1 <= advance <= 4:
        raise RuntimeFailure("HOME did not pause native playback within the visible-time tolerance")


def require_restored_position(saved: Playback, restored: Playback) -> None:
    if restored.playing or abs(saved.position_seconds - restored.position_seconds) > 1:
        raise RuntimeFailure("new-process Continue Watching did not restore the paused saved position")


def timed_out_observation(error: subprocess.TimeoutExpired) -> str:
    """Describe only recognized read operations, never raw command payloads."""
    command = error.cmd
    if not isinstance(command, (list, tuple)):
        return "Android UI observation"
    arguments = list(command[3:]) if len(command) > 3 and command[1] == "-s" else []
    if arguments[:3] == ["shell", "uiautomator", "dump"]:
        return "UIAutomator hierarchy dump"
    if arguments[:3] == ["shell", "am", "instrument"]:
        return "native accessibility snapshot"
    if arguments[:2] == ["exec-out", "cat"]:
        return "UI hierarchy transfer"
    if arguments[:4] == ["shell", "dumpsys", "window", "displays"]:
        return "foreground window query"
    return "Android UI observation"


def history_card(xml: str) -> tuple[ET.Element, int]:
    if len(exact(xml, "Continue Watching")) != 1:
        raise RuntimeFailure("Continue Watching is unavailable after process restart")
    root = ET.fromstring(xml)
    parents = {child: parent for parent in root.iter() for child in parent}
    matches: list[tuple[ET.Element, int]] = []
    for node in root.iter("node"):
        if (node.get("package") != PACKAGE or node.get("enabled", "true") != "true"
                or node.get("visible-to-user", "true") != "true"):
            continue
        text = "\n".join(filter(None, (node.get("text", ""), node.get("content-desc", ""))))
        if FIXTURE_NAME not in text:
            continue
        candidate = node
        while candidate.get("clickable") != "true" and candidate in parents:
            candidate = parents[candidate]
        combined = "\n".join(value for child in candidate.iter("node")
                             for value in (child.get("text", ""), child.get("content-desc", "")))
        position = re.search(r"Local player · (\d+:[0-5]\d(?::[0-5]\d)?) of (\d+:[0-5]\d(?::[0-5]\d)?)", combined)
        if (candidate.get("clickable") == "true" and candidate.get("enabled", "true") == "true"
                and candidate.get("visible-to-user", "true") == "true" and position):
            elapsed = parse_time(position.group(1))
            duration = parse_time(position.group(2))
            if elapsed is not None and duration is not None and 89 <= duration <= 91:
                if not any(existing is candidate for existing, _ in matches):
                    matches.append((candidate, elapsed))
    if len(matches) != 1:
        raise RuntimeFailure("the unique saved fixture and its persisted position are unavailable")
    return matches[0]


def history_swipe(xml: str) -> tuple[int, int, int, int]:
    containers = [node for node in nodes(xml) if node.get("scrollable") == "true"]
    if len(containers) != 1:
        raise RuntimeFailure("a unique visible home scroll container is required")
    container = containers[0]
    x, y = center(container)
    bounds = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", container.get("bounds", ""))
    assert bounds is not None  # center already validated these bounds.
    _, top, _, bottom = map(int, bounds.groups())
    offset = (bottom - top) // 5
    if offset < 20:
        raise RuntimeFailure("home scroll container is too small for a safe swipe")
    return x, y + offset, x, y - offset


class Runner:
    def __init__(self, serial: str, apk: Path, fixture: Path, output: Path,
                 observer_apk: Path = DEFAULT_APK) -> None:
        if not apk.is_file() or not fixture.is_file() or fixture.name != FIXTURE_NAME:
            raise ValueError("normal APK and prepared sync-fixture.mp4 are required")
        self.adb = Adb(serial, f"lifecycle-{os.getpid()}-{time.time_ns()}")
        self.observer = NativeUiObserver(self.adb, observer_apk)
        self.apk, self.fixture, self.output = apk, fixture, output
        self.cleanup_authorized = False
        self.evidence_started = False
        self.phase = "prepare"
        self.last_xml = ""
        self.last_window = ""
        self.last_observation: dict[str, object] | None = None
        self.observation_timeouts: list[dict[str, object]] = []
        self.samples: list[dict[str, object]] = []
        self.preparation_recoveries: list[dict[str, object]] = []
        self.recording: LifecycleRecording | None = None
        self.recordings: list[dict[str, object]] = []

    def prepare(self) -> dict[str, object]:
        if self.output.exists() and any(self.output.iterdir()):
            raise RuntimeFailure("lifecycle evidence directory must start empty")
        self.output.mkdir(parents=True, exist_ok=True)
        self.evidence_started = True
        if self.adb.run("get-state").stdout.decode().strip() != "device":
            raise RuntimeFailure("selected Android emulator is not ready")
        if self.adb.run("shell", "getprop", "ro.kernel.qemu").stdout.decode().strip() != "1":
            raise RuntimeFailure("lifecycle acceptance requires a dedicated emulator")
        if self.adb.run("shell", "test", "-e", self.adb.remote_root, check=False).returncode == 0:
            raise RuntimeFailure("remote evidence directory already exists")
        self.adb.run("shell", "mkdir", self.adb.remote_root)
        self.adb.remote_root_created = True
        self.cleanup_authorized = True
        installed = self.adb.run("shell", "pm", "path", PACKAGE, check=False).stdout.decode().strip()
        if installed:
            if self.adb.run("uninstall", PACKAGE, timeout=60).stdout.decode().strip() != "Success":
                raise RuntimeFailure("could not remove the previous test application")
        installed = self.adb.run("install", "-t", str(self.apk), timeout=120).stdout.decode()
        if not install_output_succeeded(installed):
            raise RuntimeFailure("normal APK installation failed")
        observer = self.observer.install()
        return {
            "nativeUiObserver": observer,
            "runtime": {
                "emulator": True,
                "physicalDevice": False,
                "model": self.adb.run("shell", "getprop", "ro.product.model").stdout.decode().strip(),
                "api": self.adb.run("shell", "getprop", "ro.build.version.sdk").stdout.decode().strip(),
                "abi": self.adb.run("shell", "getprop", "ro.product.cpu.abi").stdout.decode().strip(),
            },
            "application": parse_package_metadata(self.adb.run("shell", "dumpsys", "package", PACKAGE).stdout.decode()),
            "apkSha256": hashlib.sha256(self.apk.read_bytes()).hexdigest(),
            "fixtureSha256": hashlib.sha256(self.fixture.read_bytes()).hexdigest(),
            "normalLibMainEntrypoint": True,
        }

    def pid(self) -> str:
        value = self.adb.run("shell", "pidof", PACKAGE, check=False).stdout.decode().strip()
        if value and not re.fullmatch(r"\d+", value):
            raise RuntimeFailure("expected exactly one app process")
        return value

    def observe(self) -> str:
        xml, window = self.observer.observe()
        self.last_xml = xml
        self.last_window = window
        if self.recover_preparation_anr(xml, window):
            raise RuntimeFailure("initial emulator ANR closed; awaiting fresh application UI")
        focused_component(window)
        return xml

    def recover_preparation_anr(self, xml: str, window: str) -> bool:
        if self.phase != "01-fixture-review":
            return False
        for package, selector in (
            (LAUNCHER_PACKAGE, select_pixel_launcher_anr_close),
            (SETUP_PACKAGE, select_google_sdk_setup_anr_close),
        ):
            try:
                selector(xml, window)
                break
            except UnsafeDialog:
                continue
        else:
            return False
        if len(self.preparation_recoveries) >= MAX_PREPARATION_ANR_RECOVERIES:
            raise PreparationRecoveryFailure("initial emulator ANR recovery limit reached")
        if (re.fullmatch(r"emulator-[0-9]+", self.adb.serial) is None
                or self.adb.run("shell", "getprop", "ro.kernel.qemu").stdout.decode().strip() != "1"):
            raise PreparationRecoveryFailure("initial ANR recovery is emulator-only")
        attempt = len(self.preparation_recoveries) + 1
        prefix = self.output / f"01-preparation-anr-{attempt}"
        prefix.with_suffix(".xml").write_text(xml, encoding="utf-8")
        prefix.with_suffix(".window.txt").write_text(window, encoding="utf-8")
        png = self.adb.screenshot()
        prefix.with_suffix(".png").write_bytes(png)
        try:
            width, height = image_size(png)
        except UnsafeDialog as error:
            raise PreparationRecoveryFailure("initial ANR screenshot dimensions are invalid") from error
        fresh_xml, fresh_window = self.observer.observe()
        self.last_xml, self.last_window = fresh_xml, fresh_window
        prefix.with_suffix(".fresh.xml").write_text(fresh_xml, encoding="utf-8")
        prefix.with_suffix(".fresh.window.txt").write_text(fresh_window, encoding="utf-8")
        try:
            target = selector(fresh_xml, fresh_window)
        except UnsafeDialog as error:
            raise RuntimeFailure("initial ANR changed before recovery; no tap sent") from error
        if target.bounds[2] > width or target.bounds[3] > height:
            raise PreparationRecoveryFailure("initial ANR close lies outside the screen")
        row: dict[str, object] = {
            "phase": self.phase, "package": package, "attempt": attempt,
            "status": "attempted", "evidencePrefix": prefix.name,
        }
        self.preparation_recoveries.append(row)
        x, y = target.center
        try:
            self.adb.run("shell", "input", "tap", str(x), str(y))
        except (RuntimeFailure, subprocess.TimeoutExpired) as error:
            row["status"] = "uncertain"
            raise PreparationRecoveryFailure("initial ANR close was not confirmed; refusing another tap") from error
        row["status"] = "closed"
        return True

    def tap(self, node: ET.Element) -> None:
        x, y = center(node)
        self.adb.run("shell", "input", "tap", str(x), str(y))

    def wait(self, phase: str, check: Callable[[str], T], timeout: float = 45) -> tuple[str, T]:
        self.phase = phase
        deadline = time.monotonic() + timeout
        last_error = "waiting for production UI"
        observation_timeouts = 0
        while time.monotonic() < deadline:
            try:
                xml = self.observe()
            except (PreparationRecoveryFailure, ObserverIntegrityFailure):
                raise
            except subprocess.TimeoutExpired as error:
                # A transient read timeout is not a playback result. Retry a
                # fresh hierarchy within this phase's original polling budget;
                # never re-use last_xml or repeat a tap performed by check().
                observation_timeouts += 1
                operation = timed_out_observation(error)
                self.observation_timeouts.append({
                    "phase": phase,
                    "operation": operation,
                    "attempt": observation_timeouts,
                    "timeoutSeconds": error.timeout,
                    "observedAtMonotonic": time.monotonic(),
                })
                last_error = f"{operation} timed out"
                if observation_timeouts >= MAX_OBSERVATION_TIMEOUTS:
                    raise RuntimeFailure(
                        f"{phase}: {last_error} ({observation_timeouts} attempts)"
                    ) from error
                time.sleep(0.3)
                continue
            except RuntimeFailure as error:
                last_error = str(error)
                time.sleep(0.3)
                continue
            try:
                self.last_observation = {
                    "phase": phase,
                    "observedAtMonotonic": time.monotonic(),
                }
                result = check(xml)
                self.output.joinpath(f"{phase}.xml").write_text(xml, encoding="utf-8")
                return xml, result
            except RuntimeFailure as error:
                last_error = str(error)
                time.sleep(0.3)
        raise RuntimeFailure(f"{phase}: {last_error}")

    def sample(
        self,
        phase: str,
        *,
        playing: bool,
        screenshot: bool = True,
    ) -> tuple[str, Playback]:
        def check(xml: str) -> Playback:
            state = playback(xml)
            if state.playing != playing:
                raise RuntimeFailure("native player has the wrong play/pause state")
            return state
        xml, state = self.wait(phase, check)
        self.samples.append({"phase": phase, "observedAtMonotonic": time.monotonic(), **asdict(state)})
        if screenshot:
            self.output.joinpath(f"{phase}.png").write_bytes(self.adb.screenshot())
        return xml, state

    def launch_main(self) -> None:
        result = self.adb.run("shell", "am", "start", "-W", "-n", ACTIVITY,
                              "-a", "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER",
                              timeout=35).stdout.decode()
        if not launch_output_succeeded(result):
            raise RuntimeFailure("Android did not launch the normal MainActivity")

    def wait_history(self) -> tuple[str, tuple[ET.Element, int]]:
        swipes = 0
        def find(xml: str) -> tuple[ET.Element, int]:
            nonlocal swipes
            try:
                return history_card(xml)
            except RuntimeFailure:
                if swipes < 4:
                    coordinates = history_swipe(xml)
                    self.adb.run("shell", "input", "swipe", *(str(value) for value in coordinates), "400")
                    swipes += 1
                raise
        return self.wait("10-persisted-history", find)

    def load_fixture(self) -> None:
        result = self.adb.run("shell", "am", "start", "-W", "-n", ACTIVITY,
                              "-a", "android.intent.action.SEND", "-t", "text/plain",
                              "--es", "android.intent.extra.TEXT", FIXTURE_URL, timeout=35).stdout.decode()
        if not launch_output_succeeded(result):
            raise RuntimeFailure("could not deliver the fixture share")
        onboarded = False
        def review(xml: str) -> None:
            nonlocal onboarded
            if not onboarded and exact(xml, "Close the distance.\nKeep the movie night."):
                self.tap(button(xml, "Continue"))
                onboarded = True
                raise RuntimeFailure("finishing first-run onboarding")
            require_review(xml, FIXTURE_NAME)
        xml, _ = self.wait("01-fixture-review", review, timeout=65)
        self.output.joinpath("01-fixture-review.png").write_bytes(self.adb.screenshot())
        self.tap(button(xml, "Open video"))

    def go_home(
        self,
        *,
        pre_home_phase: str | None = None,
        playing: bool | None = None,
    ) -> tuple[float, Playback | None]:
        if (pre_home_phase is None) != (playing is None):
            raise ValueError("pre-HOME phase and expected playback state must be provided together")
        pre_home = None
        if pre_home_phase is not None:
            # A screenshot can take several seconds to transfer on a hosted AVD.
            # Refresh the accessible timeline after prior evidence capture, then
            # send HOME without another screenshot between the two operations.
            _, pre_home = self.sample(
                pre_home_phase,
                playing=playing,
                screenshot=False,
            )
        self.adb.run("shell", "input", "keyevent", "KEYCODE_HOME")
        started = time.monotonic()
        time.sleep(8)
        window = self.adb.run("shell", "dumpsys", "window", "displays").stdout.decode()
        focus = re.findall(r"mCurrentFocus=([^\r\n]+)", window)
        if len(focus) != 1 or PACKAGE in focus[0] or "launcher" not in focus[0].lower():
            raise RuntimeFailure("HOME did not put an Android launcher in the foreground")
        self.output.joinpath(f"{self.phase}-home.png").write_bytes(self.adb.screenshot())
        return time.monotonic() - started, pre_home

    def run(self) -> dict[str, object]:
        report = self.prepare()
        self.start_recording()
        self.load_fixture()
        xml, loaded = self.sample("02-loaded-paused", playing=False)
        self.tap(button(xml, "Play", "Play together"))
        _, initial = self.sample("03-playing", playing=True)
        time.sleep(4)
        _, advanced = self.sample("04-advanced", playing=True)
        first_advance = require_playing_advance(initial, advanced)
        self.finish_recording()
        self.start_recording()
        before_home_pid = self.pid()
        if not before_home_pid:
            raise RuntimeFailure("playing process is absent")
        background_seconds, pre_home = self.go_home(
            pre_home_phase="04-pre-home-playing",
            playing=True,
        )
        assert pre_home is not None
        if self.pid() != before_home_pid:
            raise RuntimeFailure("HOME destroyed the process before foreground-resume testing")
        self.launch_main()
        _, foreground = self.sample("05-foreground-paused", playing=False)
        require_background_pause(pre_home, foreground, background_seconds)
        time.sleep(4)
        xml, stable = self.sample("06-no-autoplay", playing=False)
        require_paused_stability(foreground, stable)
        self.tap(button(xml, "Play", "Play together"))
        _, replay = self.sample("07-explicit-replay", playing=True)
        time.sleep(4)
        xml, replay_advanced = self.sample("08-replay-advanced", playing=True)
        replay_advance = require_playing_advance(replay, replay_advanced)
        self.tap(button(xml, "Pause", "Pause together"))
        _, saved = self.sample("09-saved-paused", playing=False)
        if saved.position_seconds < 8:
            raise RuntimeFailure("saved progress is too small to establish nonzero resume")
        self.go_home()
        old_pid = self.pid()
        if old_pid != before_home_pid:
            raise RuntimeFailure("the app unexpectedly restarted before the process-death stage")
        self.adb.run("shell", "am", "force-stop", PACKAGE)
        if self.pid():
            raise RuntimeFailure("process restart precondition failed: old process remains")
        self.launch_main()
        xml, (card, history_position) = self.wait_history()
        new_pid = self.pid()
        if not new_pid or new_pid == old_pid:
            raise RuntimeFailure("Continue Watching was not observed in a new process")
        if abs(history_position - saved.position_seconds) > 1:
            raise RuntimeFailure("persisted history does not match the last paused position")
        self.output.joinpath("10-persisted-history.png").write_bytes(self.adb.screenshot())
        self.tap(card)
        _, restored = self.sample("11-resumed-paused", playing=False)
        require_restored_position(saved, restored)
        time.sleep(4)
        _, restored_stable = self.sample("12-restored-no-autoplay", playing=False)
        require_paused_stability(restored, restored_stable)
        self.finish_recording()
        report.update({
            "completed": True,
            "initialPlayAdvanceSeconds": first_advance,
            "homeHoldSeconds": background_seconds,
            "preHomePositionSeconds": pre_home.position_seconds,
            "homePositionAdvanceSeconds": foreground.position_seconds - pre_home.position_seconds,
            "explicitReplayAdvanceSeconds": replay_advance,
            "pausedAfterForeground": True,
            "noAutoplayAfterForeground": True,
            "oldPid": int(old_pid), "newPid": int(new_pid),
            "oldProcessAbsentBeforeRestart": True,
            "sameMediaAfterRestart": FIXTURE_NAME,
            "savedPositionSeconds": saved.position_seconds,
            "historyPositionSeconds": history_position,
            "restoredPositionSeconds": restored.position_seconds,
            "noAutoplayAfterRestart": True,
            "samples": self.samples,
            "observationTimeouts": self.observation_timeouts,
            "preparationAnrRecoveries": self.preparation_recoveries,
            "nativeUiObservations": self.observer.observations,
            "recordings": self.recordings,
            "recordingBoundary": "Original native segments; measured inter-stage gaps are not continuous footage",
        })
        return report

    def start_recording(self) -> None:
        size = recording_size(self.adb.run("shell", "wm", "size").stdout.decode("ascii", errors="replace"))
        self.recording = LifecycleRecording(self.adb, self.output, len(self.recordings) + 1, size)
        self.recordings.append(self.recording.metadata)
        self.recording.start()
        if len(self.recordings) > 1:
            self.recording.metadata["gapAfterPreviousStopSeconds"] = (
                float(self.recording.metadata["startedAtMonotonic"])
                - float(self.recordings[-2]["stopRequestedAtMonotonic"]))

    def finish_recording(self) -> None:
        if self.recording is not None:
            try:
                self.recording.finish()
            finally:
                self.recording = None

    def cleanup(self) -> None:
        try:
            self.finish_recording()
        finally:
            if self.evidence_started:
                self.output.joinpath("recordings.json").write_text(json.dumps(self.recordings, indent=2), encoding="utf-8")
            try:
                self.observer.cleanup()
            finally:
                if self.cleanup_authorized:
                    self.adb.run("shell", "am", "force-stop", PACKAGE, check=False)
                    self.adb.cleanup()
                    self.cleanup_authorized = False


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--observer-apk", type=Path, default=DEFAULT_APK)
    parser.add_argument("--output", type=Path, default=Path("build/android-lifecycle-artifacts"))
    args = parser.parse_args(argv)
    runner = Runner(args.serial, args.apk, args.fixture, args.output, args.observer_apk)
    def timed_out(_signum: int, _frame: object) -> None:
        raise RuntimeFailure("native lifecycle acceptance exceeded its external time bound")
    signal.signal(signal.SIGTERM, timed_out)
    status = 0
    report: dict[str, object] = {}
    try:
        report = runner.run()
    except (RuntimeFailure, OSError, subprocess.TimeoutExpired) as error:
        status = 1
        message = str(error) if isinstance(error, RuntimeFailure) else type(error).__name__
        if runner.evidence_started:
            report = {
                "completed": False, "phase": runner.phase, "error": message, "samples": runner.samples,
                "observationTimeouts": runner.observation_timeouts,
                "lastCompletedUiObservation": runner.last_observation,
                "preparationAnrRecoveries": runner.preparation_recoveries,
                "nativeUiObservations": runner.observer.observations,
                "nativeUiObserverInstallation": runner.observer.installation,
                "recordings": runner.recordings,
            }
            args.output.joinpath("failure.xml").write_text(runner.last_xml, encoding="utf-8")
            args.output.joinpath("failure-window.txt").write_text(runner.last_window, encoding="utf-8")
            try:
                args.output.joinpath("failure.png").write_bytes(runner.adb.screenshot())
            except (RuntimeFailure, OSError, subprocess.TimeoutExpired):
                pass
        print(f"ANDROID_LIFECYCLE_RUNTIME_FAIL: {runner.phase}: {message}")
    finally:
        try:
            runner.cleanup()
        except (RuntimeFailure, OSError, subprocess.TimeoutExpired) as error:
            status = 1
            message = str(error) if isinstance(error, RuntimeFailure) else type(error).__name__
            report.update({"completed": False, "cleanupError": message})
            print(f"ANDROID_LIFECYCLE_RUNTIME_FAIL: cleanup: {message}")
    if runner.evidence_started:
        report["recordings"] = runner.recordings
        report["nativeUiObserverRemoved"] = not runner.observer.owns_package
        args.output.joinpath("result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    if status == 0:
        print("ANDROID_LIFECYCLE_RUNTIME_PASS")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
