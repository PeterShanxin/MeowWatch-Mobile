#!/usr/bin/env python3
"""Verify Android fullscreen through real InsetsState, UI and normal playback."""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import json
from pathlib import Path
import re
import signal
import subprocess
import time
import xml.etree.ElementTree as ET

from tools.android_install.runner import PACKAGE, RuntimeFailure, focused_component, verify_build_mode
from tools.android_lifecycle_runtime.run import (
    LifecycleRecording, Playback, Runner as LifecycleRunner, button,
    playback, require_paused_stability, require_playing_advance,
)
from tools.android_native_ui.observer import DEFAULT_APK, ObserverIntegrityFailure
from tools.billing_runtime.native_dialog import image_size
from tools.incoming_media_runtime.run import exact, nodes


@dataclass(frozen=True)
class Display:
    width: int
    height: int
    rotation: int
    smallest_width_dp: int
    app_orientation: str
    status_bar_visible: bool
    navigation_bar_visible: bool


def display_state(window: str) -> Display:
    """Read current Display 0 source visibility, never requested hide flags."""
    focused_component(window)
    displays = re.findall(r"(?m)^\s*Display: mDisplayId=(\d+)\b", window)
    if displays != ["0"]:
        raise RuntimeFailure("one current Android display is required")
    sections = re.findall(r"(?ms)^\s*WindowInsetsStateController\s*\n(.*?)(?=^\s*Control map:)", window)
    if len(sections) != 1:
        raise RuntimeFailure("current WindowInsetsStateController is missing or ambiguous")
    inset = sections[0]
    frame = re.findall(r"mDisplayFrame=Rect\(0, 0 - (\d+), (\d+)\)", inset)
    current = re.findall(r"\bcur=(\d+)x(\d+)\b", window)
    rotation = re.findall(r"(?m)^\s*mRotation=(?:ROTATION_)?(0|1|2|3|90|180|270)\b", window)
    smallest = re.search(r"(?m)^\s*overrideConfig=\{[^\n]*\bsw(\d+)dp\b", window)
    orientation = re.findall(r"(?m)^\s*mCurrentAppOrientation=(\S+)\s*$", window)
    if len(frame) != 1 or current != frame or len(rotation) != 1 or smallest is None or len(orientation) != 1:
        raise RuntimeFailure("display frame, current geometry and orientation must agree")
    width, height = map(int, frame[0])
    if not 200 <= min(width, height) <= max(width, height) <= 10000:
        raise RuntimeFailure("unsupported physical display bounds")
    bars = {}
    for kind in ("statusBars", "navigationBars"):
        values = re.findall(rf"(?m)^\s*InsetsSource\s+[^\n]*\btype={kind}\b[^\n]*\bvisible=(true|false)\b", inset)
        if len(values) != 1:
            raise RuntimeFailure(f"current {kind} visibility is missing or ambiguous")
        bars[kind] = values[0] == "true"
    raw_rotation = int(rotation[0])
    return Display(width, height, raw_rotation // 90 if raw_rotation > 3 else raw_rotation,
                   int(smallest[1]), orientation[0], bars["statusBars"], bars["navigationBars"])


def require_transition(before: Display, after: Display, form_factor: str, *, fullscreen: bool) -> None:
    if after.status_bar_visible != (not fullscreen) or after.navigation_bar_visible != (not fullscreen):
        raise RuntimeFailure("actual Android status/navigation bar visibility is wrong")
    if form_factor == "phone":
        if before.smallest_width_dp >= 600 or after.smallest_width_dp >= 600:
            raise RuntimeFailure("phone gate requires an actual phone dp configuration")
        if fullscreen:
            if before.width >= before.height or after.width <= after.height:
                raise RuntimeFailure("phone must actually rotate from portrait to landscape")
            if (after.width, after.height) != (before.height, before.width) or after.rotation == before.rotation:
                raise RuntimeFailure("phone display geometry and actual rotation did not change together")
        elif (after.width, after.height, after.rotation) != (before.width, before.height, before.rotation):
            raise RuntimeFailure("phone did not restore its original display orientation")
    elif form_factor == "tablet":
        if before.smallest_width_dp < 600 or after.smallest_width_dp < 600:
            raise RuntimeFailure("tablet gate requires an actual tablet dp configuration")
        if (after.width, after.height, after.rotation) != (before.width, before.height, before.rotation):
            raise RuntimeFailure("fullscreen changed the tablet's original display orientation")
    else:
        raise RuntimeFailure("unknown form factor")
    if not fullscreen and after.app_orientation != before.app_orientation:
        raise RuntimeFailure("normal player did not restore its original Android orientation policy")


def bounds(node: ET.Element) -> tuple[int, int, int, int]:
    match = re.fullmatch(r"\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]", node.get("bounds", ""))
    if match is None:
        raise RuntimeFailure("native UI node bounds are missing")
    return tuple(map(int, match.groups()))


def require_visible_bounds(xml: str, state: Display, *, fullscreen: bool, controls: bool) -> None:
    visible = nodes(xml)
    for node in visible:
        left, top, right, bottom = bounds(node)
        if not (0 <= left <= right <= state.width and 0 <= top <= bottom <= state.height):
            raise RuntimeFailure("visible native UI extends outside the current physical display")
        if node.get("clickable") == "true" and (right <= left or bottom <= top):
            raise RuntimeFailure("visible native action has no usable bounds")
    if fullscreen:
        video = exact(xml, "Video")
        if len(video) != 1 or bounds(video[0]) != (0, 0, state.width, state.height):
            raise RuntimeFailure("fullscreen video surface does not occupy the uncropped display")
        exit_controls = exact(xml, "Exit full screen", clickable=True)
        if bool(exit_controls) != controls or len(exit_controls) > 1:
            raise RuntimeFailure("fullscreen controls have the wrong visible state")
        if controls:
            for label in ("Choose video", "Choose playback screen"):
                if len(exact(xml, label, clickable=True)) != 1:
                    raise RuntimeFailure(f"fullscreen action is not visible: {label}")
        elif any(exact(xml, label, clickable=True) for label in ("Play", "Pause", "Play together", "Pause together")):
            raise RuntimeFailure("transport controls remain visible after hiding the overlay")


def recording_size(state: Display) -> tuple[int, int]:
    maximum = (960, 432) if state.width > state.height else (432, 960)
    ratio = min(maximum[0] / state.width, maximum[1] / state.height, 1)
    return max(2, int(state.width * ratio) // 2 * 2), max(2, int(state.height * ratio) // 2 * 2)


def require_same_paused_player(before: Playback, after: Playback, before_pid: str, after_pid: str) -> None:
    if not before_pid or before_pid != after_pid:
        raise RuntimeFailure("fullscreen transition replaced the normal app process")
    if before.duration_seconds != after.duration_seconds:
        raise RuntimeFailure("fullscreen transition changed the loaded media duration")
    require_paused_stability(before, after)


def immersive_confirmation_button(xml: str, window: str) -> ET.Element:
    """Recognize only the retained API 35 first-use Android fullscreen tip."""
    focuses = re.findall(r"mCurrentFocus=([^\r\n]+)", window)
    apps = re.findall(r"mFocusedApp=([^\r\n]+)", window)
    activity = rf"{re.escape(PACKAGE)}/(?:\.MainActivity|{re.escape(PACKAGE)}\.MainActivity)"
    if (len(focuses) != 1 or re.fullmatch(
            r"Window\{[0-9a-f]+ u0 ImmersiveModeConfirmation\}", focuses[0].strip()) is None
            or len(apps) != 1 or re.fullmatch(
                rf"ActivityRecord\{{[0-9a-f]+ u0 {activity} t\d+\}}", apps[0].strip()) is None):
        raise RuntimeFailure("fullscreen tip must be the sole focused system window over MeowWatch MainActivity")
    geometry = re.findall(r"\bcur=(\d+)x(\d+)\b", window)
    if len(geometry) != 1:
        raise RuntimeFailure("fullscreen tip display geometry is ambiguous")
    width, height = map(int, geometry[0])
    try:
        root = ET.fromstring(xml)
    except ET.ParseError as error:
        raise RuntimeFailure("fullscreen tip XML is invalid") from error
    tree = list(root.iter("node"))
    if root.tag != "hierarchy" or not tree or any(item.get("package") != "android" for item in tree):
        raise RuntimeFailure("fullscreen tip must contain only native Android system nodes")
    selected = {}
    for identifier, label, class_name, clickable in (
        ("immersive_cling_title", "Viewing full screen", "android.widget.TextView", "false"),
        ("immersive_cling_description", "To exit, swipe down from the top of your screen", "android.widget.TextView", "false"),
        ("ok", "Got it", "android.widget.Button", "true"),
    ):
        matches = [item for item in tree if item.get("resource-id") == f"android:id/{identifier}"]
        if len(matches) != 1:
            raise RuntimeFailure("fullscreen tip labels or action are missing or ambiguous")
        item = matches[0]
        if (item.get("text") != label or item.get("class") != class_name
                or item.get("enabled") != "true" or item.get("clickable") != clickable
                or item.get("visible-to-user", "true") != "true"):
            raise RuntimeFailure("fullscreen tip labels or action do not match the native confirmation")
        left, top, right, bottom = bounds(item)
        if not (0 <= left < right <= width <= 10000 and 0 <= top < bottom <= height <= 10000):
            raise RuntimeFailure("fullscreen tip action or labels lie outside the current display")
        selected[identifier] = item
    actions = [item for item in tree if item.get("clickable") == "true"
               and item.get("visible-to-user", "true") == "true"]
    if actions != [selected["ok"]]:
        raise RuntimeFailure("fullscreen tip has an unexpected native action")
    return selected["ok"]


class Runner(LifecycleRunner):
    """Reuse normal installation/share/native-observer and recorder contracts."""

    def __init__(self, serial: str, avd_name: str, form_factor: str,
                 apk: Path, fixture: Path, output: Path, observer_apk: Path = DEFAULT_APK):
        super().__init__(serial, apk, fixture, output, observer_apk)
        self.avd_name, self.form_factor = avd_name, form_factor
        self.states: list[dict] = []
        self.logcat: subprocess.Popen | None = None
        self.log_file = None
        self.fullscreen_entry_pid = ""
        self.immersive_confirmations: list[dict] = []

    def require_owned_avd(self) -> None:
        if (re.fullmatch(r"emulator-[0-9]+", self.adb.serial) is None
                or self.form_factor not in {"phone", "tablet"}
                or re.fullmatch(rf"meowwatch_fullscreen_{self.form_factor}_[A-Za-z0-9_]+", self.avd_name) is None):
            raise RuntimeFailure("an explicit task-owned fullscreen AVD is required")
        name = [line.strip() for line in self.adb.run("emu", "avd", "name").stdout.decode().splitlines()
                if line.strip() and line.strip() != "OK"]
        if name != [self.avd_name]:
            raise RuntimeFailure("selected AVD does not belong to this fullscreen gate")
        if (self.adb.run("shell", "getprop", "ro.kernel.qemu").stdout.strip() != b"1"
                or self.adb.run("shell", "getprop", "ro.build.version.sdk").stdout.strip() != b"35"):
            raise RuntimeFailure("fullscreen gate requires a dedicated API 35 emulator")

    def require_entry_pid(self) -> None:
        if not self.fullscreen_entry_pid or self.pid() != self.fullscreen_entry_pid:
            raise ObserverIntegrityFailure("fullscreen tip handling changed or lost the normal app process")

    def acknowledge_immersive_confirmation(self, xml: str, window: str) -> None:
        if self.phase != "07-entered-fullscreen" or self.immersive_confirmations:
            raise ObserverIntegrityFailure("fullscreen tip acknowledgement is allowed once at first entry only")
        self.require_owned_avd()
        self.require_entry_pid()
        prefix = self.output / "07-immersive-confirmation"
        prefix.with_suffix(".xml").write_text(xml, encoding="utf-8")
        prefix.with_suffix(".window.txt").write_text(window, encoding="utf-8")
        immersive_confirmation_button(xml, window)
        png = self.adb.screenshot()
        prefix.with_suffix(".png").write_bytes(png)
        dimensions = image_size(png)
        # UIAutomator is used only for this idle Android system dialog. The
        # resumed app must still pass the standalone fresh native observer.
        fresh_xml, fresh_window = self.adb.observe()
        self.last_xml, self.last_window = fresh_xml, fresh_window
        prefix.with_suffix(".fresh.xml").write_text(fresh_xml, encoding="utf-8")
        prefix.with_suffix(".fresh.window.txt").write_text(fresh_window, encoding="utf-8")
        target = immersive_confirmation_button(fresh_xml, fresh_window)
        current = re.findall(r"\bcur=(\d+)x(\d+)\b", fresh_window)
        if dimensions != tuple(map(int, current[0])):
            raise RuntimeFailure("fullscreen tip display changed between screenshot and fresh confirmation")
        self.require_entry_pid()
        receipt = {"phase": self.phase, "attempt": 1, "status": "tap-sent",
                   "pid": int(self.fullscreen_entry_pid), "evidencePrefix": prefix.name,
                   "observedAtMonotonic": time.monotonic()}
        self.immersive_confirmations.append(receipt)
        try:
            self.tap(target)
        except (RuntimeFailure, subprocess.TimeoutExpired) as error:
            receipt["status"] = "uncertain"
            raise ObserverIntegrityFailure("fullscreen tip tap was not confirmed; refusing another tap") from error
        self.require_entry_pid()

    def observe(self) -> str:
        if self.phase == "07-entered-fullscreen":
            self.require_entry_pid()
            window = self.adb.run("shell", "dumpsys", "window", "displays", timeout=10).stdout.decode()
            focuses = re.findall(r"mCurrentFocus=([^\r\n]+)", window)
            if any("ImmersiveModeConfirmation" in value for value in focuses) and not self.immersive_confirmations:
                xml, window = self.adb.observe()
                self.last_xml, self.last_window = xml, window
                self.acknowledge_immersive_confirmation(xml, window)
        xml = super().observe()
        if self.phase == "07-entered-fullscreen":
            self.require_entry_pid()
            if self.immersive_confirmations:
                self.immersive_confirmations[0]["status"] = "acknowledged"
        return xml

    def evidence(self, phase: str, state: Display, xml: str) -> None:
        self.output.joinpath(f"{phase}.window.txt").write_text(self.last_window, encoding="utf-8")
        self.output.joinpath(f"{phase}.xml").write_text(xml, encoding="utf-8")
        detailed = self.adb.run("shell", "dumpsys", "window", "windows", timeout=10).stdout
        self.output.joinpath(f"{phase}.windows.txt").write_bytes(detailed)
        png = self.adb.screenshot()
        self.output.joinpath(f"{phase}.png").write_bytes(png)
        if image_size(png) != (state.width, state.height):
            raise RuntimeFailure("original screenshot dimensions disagree with the current native display")
        fresh_window = self.adb.run("shell", "dumpsys", "window", "displays", timeout=10).stdout.decode()
        self.output.joinpath(f"{phase}.after-screenshot.window.txt").write_text(fresh_window, encoding="utf-8")
        if display_state(fresh_window) != state:
            raise RuntimeFailure("system bars/orientation changed across the accepted native screenshot")
        self.states.append({"phase": phase, "observedAtMonotonic": time.monotonic(),
                            "pid": self.pid(), **asdict(state)})

    def system_sample(self, phase: str, baseline: Display, *, fullscreen: bool,
                      controls: bool = True, playing: bool | None = None) -> tuple[str, Display, Playback | None]:
        def check(xml: str):
            state = display_state(self.last_window)
            require_transition(baseline, state, self.form_factor, fullscreen=fullscreen)
            require_visible_bounds(xml, state, fullscreen=fullscreen, controls=controls)
            player = playback(xml) if playing is not None else None
            if player is not None and player.playing != playing:
                raise RuntimeFailure("fullscreen has the wrong native playback state")
            return state, player
        xml, (state, player) = self.wait(phase, check, timeout=35)
        self.evidence(phase, state, xml)
        return xml, state, player

    def start_recording(self) -> None:
        if self.recording is not None:
            raise RuntimeFailure("stop the owned recorder before starting another orientation segment")
        window = self.adb.run("shell", "dumpsys", "window", "displays", timeout=10).stdout.decode()
        state = display_state(window)
        recording = LifecycleRecording(self.adb, self.output, len(self.recordings) + 1, recording_size(state))
        self.recording = recording
        self.recordings.append(recording.metadata)
        recording.metadata["displayAtStart"] = asdict(state)
        recording.start()
        if len(self.recordings) > 1:
            recording.metadata["gapAfterPreviousStopSeconds"] = (
                float(recording.metadata["startedAtMonotonic"])
                - float(self.recordings[-2]["stopRequestedAtMonotonic"]))
        if display_state(self.adb.run("shell", "dumpsys", "window", "displays", timeout=10).stdout.decode()) != state:
            raise RuntimeFailure("native display changed while the new recording segment was starting")

    def stop_for_rotation(self, phase: str) -> None:
        self.finish_recording(required_phase=phase)
        if self.adb.run("shell", "pidof", "screenrecord", check=False).stdout.strip():
            raise RuntimeFailure("a recorder is still running before orientation is allowed to change")

    def center_tap(self, state: Display) -> None:
        self.adb.run("shell", "input", "tap", str(state.width // 2), str(state.height // 2))

    def pause_after_fullscreen_advance(self, full: Display, before: Playback) -> int:
        def advanced(xml: str) -> Playback:
            require_visible_bounds(xml, full, fullscreen=True, controls=True)
            state = playback(xml)
            if not state.playing or state.position_seconds - before.position_seconds < 2:
                raise RuntimeFailure("explicit fullscreen Play has not advanced the native timeline by two seconds")
            return state
        shown_xml, shown_playing = self.wait("09-controls-shown-and-native-advanced", advanced, timeout=10)
        # Pause only from the fresh hierarchy that proves actual advancement.
        # Avoid a screenshot between observing and tapping this transient UI.
        self.tap(button(shown_xml, "Pause", "Pause together"))
        return shown_playing.position_seconds - before.position_seconds

    def run(self) -> dict:
        self.require_owned_avd()
        report = self.prepare()
        package = self.adb.run("shell", "dumpsys", "package", PACKAGE).stdout.decode()
        report["application"]["debuggable"] = verify_build_mode(package, "release")
        self.log_file = self.output.joinpath("logcat.txt").open("wb")
        self.logcat = subprocess.Popen(self.adb.prefix + ["logcat", "-v", "threadtime", "-T", "1"],
                                       stdout=self.log_file, stderr=subprocess.STDOUT, start_new_session=True)
        self.load_fixture()
        xml, loaded = self.sample("02-loaded-paused", playing=False)
        baseline = display_state(self.last_window)
        require_transition(baseline, baseline, self.form_factor, fullscreen=False)
        if self.form_factor == "phone" and baseline.width >= baseline.height:
            raise RuntimeFailure("the phone profile must start in its natural portrait orientation")
        require_visible_bounds(xml, baseline, fullscreen=False, controls=True)
        self.evidence("02-loaded-paused", baseline, xml)
        app_pid = self.pid()
        if not app_pid:
            raise RuntimeFailure("normal player process is absent")
        self.start_recording()
        self.tap(button(xml, "Play", "Play together"))
        _, playing = self.sample("03-normal-playing", playing=True)
        time.sleep(3)
        xml, advanced = self.sample("04-normal-advanced", playing=True)
        normal_advance = require_playing_advance(playing, advanced)
        self.tap(button(xml, "Pause", "Pause together"))
        xml, _, paused = self.system_sample("05-before-fullscreen", baseline, fullscreen=False, playing=False)
        assert paused is not None
        self.stop_for_rotation("05-before-fullscreen")
        # The entry command is sent only after the original recorder is gone.
        xml, _ = self.sample("06-fresh-entry-control", playing=False, screenshot=False)
        self.fullscreen_entry_pid = app_pid
        self.require_entry_pid()
        self.tap(button(xml, "Enter full screen"))
        xml, full, entered = self.system_sample("07-entered-fullscreen", baseline, fullscreen=True, playing=False)
        assert entered is not None
        require_same_paused_player(paused, entered, app_pid, self.pid())
        self.start_recording()

        # Observe the production idle auto-hide, then show the actual controls
        # with one native surface tap. A bounded hidden-state wait cannot
        # distinguish a tap-hide result from the three-second auto-hide timer.
        self.tap(button(xml, "Play", "Play together"))
        self.system_sample("08-controls-auto-hidden", baseline, fullscreen=True, controls=False)
        self.center_tap(full)
        fullscreen_advance = self.pause_after_fullscreen_advance(full, entered)
        xml, _, full_paused = self.system_sample("10-fullscreen-paused", baseline, fullscreen=True, playing=False)
        assert full_paused is not None
        time.sleep(2)
        _, _, stable = self.system_sample("11-fullscreen-still-paused", baseline, fullscreen=True, playing=False)
        assert stable is not None
        require_paused_stability(full_paused, stable)
        self.stop_for_rotation("11-fullscreen-still-paused")
        _, before_back = self.sample("12-before-system-back", playing=False, screenshot=False)
        self.adb.run("shell", "input", "keyevent", "KEYCODE_BACK")
        xml, restored, after_back = self.system_sample("13-back-exits-fullscreen", baseline, fullscreen=False, playing=False)
        assert after_back is not None
        if len(exact(xml, "Enter full screen", clickable=True)) != 1 or exact(xml, "Exit full screen"):
            raise RuntimeFailure("first system Back did not return to the normal player")
        require_same_paused_player(before_back, after_back, app_pid, self.pid())
        self.start_recording()
        self.evidence("14-normal-player-restored", restored, xml)
        self.adb.run("shell", "input", "keyevent", "KEYCODE_BACK")
        def home(xml: str) -> Display:
            if len(exact(xml, "Start a room", clickable=True)) != 1 or exact(xml, "Enter full screen"):
                raise RuntimeFailure("second system Back did not leave the normal player")
            state = display_state(self.last_window)
            require_transition(baseline, state, self.form_factor, fullscreen=False)
            require_visible_bounds(xml, state, fullscreen=False, controls=True)
            return state
        home_xml, home_state = self.wait("15-normal-return-home", home, timeout=30)
        self.evidence("15-normal-return-home", home_state, home_xml)
        if self.pid() != app_pid:
            raise RuntimeFailure("normal Back navigation replaced the app process")
        self.finish_recording(required_phase="15-normal-return-home")
        if self.logcat.poll() is not None:
            raise RuntimeFailure("raw logcat capture exited during fullscreen acceptance")
        if len(self.recordings) != 3 or any(row["status"] != "verified" for row in self.recordings):
            raise RuntimeFailure("all three native orientation segments must be intact")
        report.update({
            "completed": True, "formFactor": self.form_factor, "avdName": self.avd_name,
            "sameAppPid": int(app_pid), "normalNativeAdvanceSeconds": normal_advance,
            "fullscreenNativeAdvanceSeconds": fullscreen_advance,
            "sameMediaAndPausedPositionAfterFirstBack": True,
            "systemBarsHiddenByActualInsetsSources": True,
            "systemBarsAndOrientationRestored": True,
            "secondBackReturnsHome": True, "controlsAutoHiddenDuringPlayback": True,
            "controlsShownByNativeTap": True,
            "nativeVisibleBoundsWithinPhysicalDisplay": True,
            "states": self.states, "samples": self.samples,
            "immersiveConfirmations": self.immersive_confirmations,
            "nativeUiObservations": self.observer.observations,
            "recordings": self.recordings,
            "boundary": "Dedicated API 35 emulator, normal release lib/main.dart; no physical device proof. "
                        "Rotation gaps are explicit, not continuous footage. PNGs remain uncropped. "
                        "Bounds checks do not replace visual review of original screenshots.",
        })
        return report

    def cleanup(self) -> None:
        try:
            if self.logcat is not None:
                if self.logcat.poll() is None:
                    self.logcat.terminate()
                    self.logcat.wait(timeout=10)
                if self.log_file is not None:
                    self.log_file.close()
        finally:
            if self.cleanup_authorized or self.observer.owns_package:
                self.require_owned_avd()
            super().cleanup()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--avd-name", required=True)
    parser.add_argument("--form-factor", choices=("phone", "tablet"), required=True)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--observer-apk", type=Path, default=DEFAULT_APK)
    parser.add_argument("--output", type=Path, default=Path("build/android-fullscreen-artifacts"))
    args = parser.parse_args()
    runner = Runner(args.serial, args.avd_name, args.form_factor, args.apk, args.fixture, args.output, args.observer_apk)
    def timeout(signum: int, _frame: object) -> None:
        raise RuntimeFailure(f"fullscreen gate interrupted by signal {signum}")
    signal.signal(signal.SIGTERM, timeout)
    signal.signal(signal.SIGINT, timeout)
    report = {}
    status = 0
    try:
        report = runner.run()
    except Exception as error:
        status = 1
        report = {"completed": False, "phase": runner.phase, "error": f"{type(error).__name__}: {error}",
                  "states": runner.states, "samples": runner.samples,
                  "immersiveConfirmations": runner.immersive_confirmations,
                  "nativeUiObservations": runner.observer.observations,
                  "observationTimeouts": runner.observation_timeouts}
        if runner.evidence_started:
            runner.output.joinpath("failure.xml").write_text(runner.last_xml, encoding="utf-8")
            runner.output.joinpath("failure.window.txt").write_text(runner.last_window, encoding="utf-8")
            try:
                runner.output.joinpath("failure.png").write_bytes(runner.adb.screenshot())
            except Exception as capture_error:
                report["failureScreenshotError"] = str(capture_error)
    finally:
        try:
            runner.cleanup()
        except Exception as error:
            status = 1
            report.update({"completed": False, "cleanupError": f"{type(error).__name__}: {error}"})
        if runner.evidence_started:
            report.update({"recordings": runner.recordings, "nativeUiObserverRemoved": not runner.observer.owns_package})
            runner.output.joinpath("result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("ANDROID_FULLSCREEN_RUNTIME_PASS" if status == 0 else "ANDROID_FULLSCREEN_RUNTIME_FAIL")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
