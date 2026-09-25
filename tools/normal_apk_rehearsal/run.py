#!/usr/bin/env python3
"""Rehearse one ordinary APK on independent API 35 phone/tablet emulators."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time
from typing import Callable
import xml.etree.ElementTree as ET

from tools.android_install.runner import (
    ACTIVITY, PACKAGE, Adb, RuntimeFailure, focused_component,
    install_output_succeeded, launch_output_succeeded, parse_package_metadata,
    verify_build_mode,
)
from tools.android_native_ui.observer import NativeUiObserver, ObserverIntegrityFailure
from tools.android_lifecycle_runtime.run import (
    FIXTURE_NAME, FIXTURE_URL, Playback, button, history_card, history_swipe,
    labels, parse_time, playback, require_playing_advance,
)
from tools.incoming_media_runtime.run import center, exact, nodes
from tools.billing_runtime.native_dialog import select_target, UnsafeDialog


ROOM_LABEL = re.compile(r"^QR invite to ([A-Za-z0-9][A-Za-z0-9._-]{2,127})(?:\nqr code)?$")
CODE_SUFFIX = re.compile(r"(?:@[A-Za-z0-9.\[\]:-]+)?")
PHASE_TIMEOUT = 65


def visible_code(xml: str) -> str:
    """Read the displayed share code, never app state or the clipboard."""
    labels = [value for node in nodes(xml) for value in
              (node.get("text", ""), node.get("content-desc", "")) if value]
    rooms = [match.group(1) for value in labels if (match := ROOM_LABEL.fullmatch(value))]
    if len(rooms) != 1:
        raise RuntimeFailure("invite sheet has no unique visible room identity")
    room = rooms[0]
    codes = [value for value in labels if value != room and
             value.startswith(room) and CODE_SUFFIX.fullmatch(value[len(room):])]
    if len(codes) != 1:
        # The bare share code may match the QR room identity exactly.
        codes = [value for value in labels if value == room]
    if len(codes) != 1:
        raise RuntimeFailure("invite sheet has no unique visible share code")
    return codes[0]


def unique_text_field(xml: str) -> ET.Element:
    fields = [node for node in nodes(xml) if node.get("class", "").endswith("EditText")
              and node.get("bounds")]
    if len(fields) != 1:
        raise RuntimeFailure("expected one visible text field")
    return fields[0]


def focused_text_field(xml: str) -> bool:
    if unique_text_field(xml).get("focused") != "true":
        raise RuntimeFailure("visible text field has not received focus")
    return True


def entered_text_field(xml: str, value: str) -> bool:
    if unique_text_field(xml).get("text") != value:
        raise RuntimeFailure("visible text field differs from entered value")
    return True


def join_sheet_ready(xml: str) -> bool:
    if len(exact(xml, "Join their movie night")) != 1:
        raise RuntimeFailure("expected the visible guest join sheet")
    unique_text_field(xml)
    button(xml, "Join room")
    return True


def media_link_ready(xml: str) -> bool:
    if len(exact(xml, "Choose what to watch")) != 1:
        raise RuntimeFailure("media choice sheet is not visible")
    if unique_text_field(xml).get("text") != FIXTURE_URL:
        raise RuntimeFailure("the controlled direct video URL is not in the field")
    button(xml, "Use this link")
    return True


def unique_seekbar(xml: str) -> ET.Element:
    bars = [node for node in nodes(xml) if node.get("class", "").endswith("SeekBar")]
    if len(bars) != 1:
        raise RuntimeFailure("expected one visible player timeline")
    return bars[0]


def timeline_tap(xml: str, fraction: float) -> tuple[int, int]:
    bar = unique_seekbar(xml)
    times = [(parse_time(node.get("text") or node.get("content-desc", "")), node)
             for node in nodes(xml)
             if not node.get("class", "").endswith("SeekBar")]
    times = [(seconds, node) for seconds, node in times if seconds is not None]
    if len(times) != 2 or times[0][0] == times[1][0]:
        raise RuntimeFailure("expected visible elapsed and duration labels below timeline")
    elapsed, duration = sorted(times, key=lambda item: item[0])
    bounds = []
    for node in (bar, elapsed[1], duration[1]):
        match = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds", ""))
        if match is None:
            raise RuntimeFailure("timeline bounds unavailable")
        bounds.append(tuple(map(int, match.groups())))
    thumb, elapsed_label, duration_label = bounds
    thumb_left, thumb_top, thumb_right, thumb_bottom = thumb
    _, elapsed_top, elapsed_right, _ = elapsed_label
    duration_left, duration_top, _, _ = duration_label
    thumb_x = (thumb_left + thumb_right) // 2
    if (duration_left - elapsed_right < 100 or
            not elapsed_right <= thumb_x <= duration_left or
            not thumb_top < thumb_bottom <= min(elapsed_top, duration_top) + 4 or
            abs(elapsed_top - duration_top) > 8):
        raise RuntimeFailure("visible timeline labels do not flank the slider")
    x = round(elapsed_right + (duration_left - elapsed_right) * fraction)
    return x, (thumb_top + thumb_bottom) // 2


def rehearsed_playback(xml: str, *, direct_fixture_submitted: bool) -> Playback:
    if any(FIXTURE_NAME in value for value in labels(xml)):
        return playback(xml)
    # The tablet's two-column landscape player omits the media title. Its
    # immediately preceding visible sheet must have submitted the exact URL;
    # the native room player must still expose the controlled 90-second timeline.
    if not direct_fixture_submitted or len(exact(xml, "Together in this room")) != 1:
        raise RuntimeFailure("the loaded playback source is not the controlled fixture")
    unique_seekbar(xml)
    times = sorted({value for label in labels(xml) if (value := parse_time(label)) is not None})
    if len(times) != 2 or not 89 <= times[1] <= 91 or times[0] >= times[1]:
        raise RuntimeFailure("native landscape player lacks the controlled 90-second timeline")
    play = [node for label in ("Play", "Play together") for node in exact(xml, label, clickable=True)]
    pause = [node for label in ("Pause", "Pause together") for node in exact(xml, label, clickable=True)]
    if len(play) + len(pause) != 1:
        raise RuntimeFailure("native landscape player lacks a unique Play or Pause action")
    return Playback(times[0], times[1], bool(pause))


class Device:
    def __init__(self, serial: str, apk: Path, observer_apk: Path, output: Path):
        self.adb = Adb(serial, f"rehearsal-{serial.replace('-', '')}-{time.time_ns()}")
        self.observer = NativeUiObserver(self.adb, observer_apk)
        self.apk = apk
        self.output = output
        self.phase = "prepare"
        self.last_xml = ""
        self.last_window = ""
        self.phases: list[dict[str, object]] = []
        self.installed = False
        self.direct_fixture_submitted = False

    def prepare(self) -> dict[str, object]:
        self.output.mkdir(parents=True, exist_ok=False)
        if self.adb.run("get-state").stdout.strip() != b"device":
            raise RuntimeFailure("rehearsal emulator is not ready")
        if self.adb.run("shell", "getprop", "ro.kernel.qemu").stdout.strip() != b"1":
            raise RuntimeFailure("rehearsal requires a verified emulator")
        if self.adb.run("shell", "pm", "path", PACKAGE, check=False).stdout.strip():
            raise RuntimeFailure("fresh emulator already contains the application")
        result = self.adb.run("install", "--no-incremental", "-t", str(self.apk), timeout=120)
        if not install_output_succeeded(result.stdout.decode()):
            raise RuntimeFailure("ordinary APK install did not report success")
        self.installed = True
        self.adb.prepare_storage(output=self.output)
        observer = self.observer.install()
        dump = self.adb.run("shell", "dumpsys", "package", PACKAGE).stdout.decode(errors="replace")
        verify_build_mode(dump, "debug")
        launch = self.adb.run("shell", "am", "start", "-W", "-n", ACTIVITY,
                              "-a", "android.intent.action.MAIN",
                              "-c", "android.intent.category.LAUNCHER", timeout=35)
        if not launch_output_succeeded(launch.stdout.decode(errors="replace")):
            raise RuntimeFailure("ordinary MainActivity did not launch")
        return {"serial": self.adb.serial, "model": self.adb.run("shell", "getprop", "ro.product.model").stdout.decode().strip(),
                "api": self.adb.run("shell", "getprop", "ro.build.version.sdk").stdout.decode().strip(),
                "abi": self.adb.run("shell", "getprop", "ro.product.cpu.abi").stdout.decode().strip(),
                "package": parse_package_metadata(dump), "observer": observer}

    def observe(self) -> str:
        xml, window = self.observer.observe()
        focused_component(window)
        self.last_xml, self.last_window = xml, window
        return xml

    def wait(self, phase: str, check: Callable[[str], object], timeout: int = PHASE_TIMEOUT) -> tuple[str, object]:
        self.phase = phase
        deadline = time.monotonic() + timeout
        last = "expected visible UI unavailable"
        while time.monotonic() < deadline:
            try:
                xml = self.observe()
                result = check(xml)
                return xml, result
            except (ObserverIntegrityFailure, subprocess.TimeoutExpired):
                raise
            except RuntimeFailure as error:
                last = str(error)
                time.sleep(0.5)
        raise RuntimeFailure(f"{phase}: {last}")

    def capture(self, phase: str, check: Callable[[str], object], timeout: int = PHASE_TIMEOUT) -> object:
        xml, value = self.wait(phase, check, timeout)
        prefix = self.output / phase
        prefix.with_suffix(".xml").write_text(xml, encoding="utf-8")
        prefix.with_suffix(".window.txt").write_text(self.last_window, encoding="utf-8")
        prefix.with_suffix(".png").write_bytes(self.adb.screenshot())
        self.phases.append({"phase": phase, "observedAtUtc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                            "pid": self.observer.observations[-1].get("applicationPid"),
                            "xmlSha256": hashlib.sha256(xml.encode()).hexdigest()})
        return value

    def tap(self, label: str) -> None:
        xml = self.observe()  # Fresh bounds immediately before every action.
        self.tap_node(button(xml, label))

    def tap_purchase_button(self) -> None:
        choices = [node for node in nodes(self.observe())
                   if node.get("clickable") == "true" and
                   any(value.startswith("Continue · ") for value in
                       (node.get("text", ""), node.get("content-desc", "")))]
        if len(choices) != 1:
            raise RuntimeFailure("paywall has no unique enabled purchase action")
        self.tap_node(choices[0])

    def tap_playback(self, playing: bool) -> None:
        self.tap_node(button(self.observe(), *(('Pause', 'Pause together') if playing
                                               else ('Play', 'Play together'))))

    def tap_home_action(self, label: str) -> None:
        for _ in range(5):
            xml = self.observe()
            try:
                self.tap_node(button(xml, label))
                return
            except RuntimeFailure:
                x1, y1, x2, y2 = history_swipe(xml)
                self.adb.run("shell", "input", "swipe", str(x2), str(y2), str(x1), str(y1), "400")
        raise RuntimeFailure(f"home action {label!r} is not visible")

    def resume_local_history(self) -> int:
        for _ in range(5):
            xml = self.observe()
            try:
                card, position = history_card(xml)
                self.tap_node(card)
                return position
            except RuntimeFailure:
                x1, y1, x2, y2 = history_swipe(xml)
                self.adb.run("shell", "input", "swipe", str(x1), str(y1), str(x2), str(y2), "400")
        raise RuntimeFailure("saved local fixture is not visible in Continue Watching")

    def capture_history(self, phase: str, context: str) -> None:
        for _ in range(5):
            xml = self.observe()
            try:
                history_context(xml, context)
                self.capture(phase, lambda fresh: history_context(fresh, context))
                return
            except RuntimeFailure:
                pass
            x1, y1, x2, y2 = history_swipe(xml)
            self.adb.run("shell", "input", "swipe", str(x1), str(y1), str(x2), str(y2), "400")
        raise RuntimeFailure(f"Continue Watching does not show {context}")

    def tap_node(self, node: ET.Element) -> None:
        x, y = center(node)
        self.adb.run("shell", "input", "tap", str(x), str(y))

    def back(self) -> None:
        self.adb.run("shell", "input", "keyevent", "KEYCODE_BACK")

    def enter(self, value: str) -> None:
        if not re.fullmatch(r"[A-Za-z0-9:/._@-]+", value):
            raise RuntimeFailure("unsafe text-entry value")
        phase = self.phase
        field = unique_text_field(self.observe())
        if field.get("focused") != "true":
            self.tap_node(field)
        self.wait(f"{phase}-field-focused", focused_text_field, timeout=20)
        self.adb.run("shell", "input", "text", value)
        self.wait(f"{phase}-field-entered",
                  lambda xml: entered_text_field(xml, value), timeout=10)

    def player(self, phase: str, playing: bool):
        def check(xml: str):
            state = rehearsed_playback(xml, direct_fixture_submitted=self.direct_fixture_submitted)
            if state.playing != playing:
                raise RuntimeFailure("visible player play state differs")
            return state
        return self.capture(phase, check)

    def seek(self, fraction: float) -> None:
        xml = self.observe()
        rehearsed_playback(xml, direct_fixture_submitted=self.direct_fixture_submitted)
        x, y = timeline_tap(xml, fraction)
        self.adb.run("shell", "input", "tap", str(x), str(y))

    def diagnostics(self) -> None:
        prefix = self.output / f"failure-{self.phase}"
        prefix.with_suffix(".error.txt").write_text("Rehearsal stopped at this phase.\n", encoding="utf-8")
        if self.last_xml:
            prefix.with_suffix(".xml").write_text(self.last_xml, encoding="utf-8")
            prefix.with_suffix(".window.txt").write_text(self.last_window, encoding="utf-8")
        try:
            prefix.with_suffix(".png").write_bytes(self.adb.screenshot())
        except Exception as error:
            prefix.with_suffix(".screenshot-error.txt").write_text(str(error), encoding="utf-8")

    def cleanup(self) -> None:
        self.observer.cleanup()


def present(label: str) -> Callable[[str], bool]:
    def check(xml: str) -> bool:
        if not exact(xml, label):
            raise RuntimeFailure(f"{label!r} is not visible")
        return True
    return check


def visible_chat_receipt(xml: str, message: str) -> bool:
    for node in nodes(xml):
        if node.get("class", "").endswith("EditText"):
            continue
        for value in (node.get("text", ""), node.get("content-desc", "")):
            sender, separator, body = value.partition("\n")
            if value == message or (separator and sender.strip() and body == message):
                return True
    raise RuntimeFailure(f"complete received chat message {message!r} is not visible")


def history_context(xml: str, context: str) -> bool:
    values = [value for node in nodes(xml) for value in
              (node.get("text", ""), node.get("content-desc", "")) if value]
    if "Continue Watching" not in values or not any(FIXTURE_NAME in value for value in values):
        raise RuntimeFailure("controlled fixture is absent from visible watch history")
    if not any(value.startswith(context + " · ") for value in values):
        raise RuntimeFailure(f"visible watch history has no {context} position")
    return True


def onboard(device: Device, role: str) -> None:
    device.capture(f"01-{role}-first-launch", present("Continue"))
    device.tap("New here? Take the 30-second guide")
    device.capture(f"02-{role}-guide", present("Step 1 of 3"))
    device.tap("Next")
    device.capture(f"02-{role}-guide-step-2", present("Step 2 of 3"))
    device.tap("Next")
    device.capture(f"02-{role}-guide-step-3", present("Step 3 of 3"))
    device.tap("Got it")
    device.tap("Continue")
    device.capture(f"03-{role}-home", present("Start a room"))


def load_link(device: Device, role: str) -> None:
    device.direct_fixture_submitted = False
    device.tap("Video")
    device.capture(f"07-{role}-media-choice", present("Direct video link"))
    device.enter(FIXTURE_URL)
    device.back()  # Dismiss the keyboard so the visible submit action is reachable.
    device.capture(f"07-{role}-link-ready", media_link_ready)
    device.tap("Use this link")
    # Only the tablet landscape layout omits the media title; phone and Local
    # playback retain the stricter filename-visible proof in playback().
    device.direct_fixture_submitted = role == "tablet"
    device.player(f"08-{role}-loaded", False)


def chat(device: Device, recipient: Device, message: str, phase: str) -> None:
    device.tap("Chat")
    device.capture(f"{phase}-composer", present("Send message"))
    device.enter(message)
    device.tap("Send message")
    recipient.capture(f"{phase}-received",
                      lambda xml: visible_chat_receipt(xml, message))
    device.tap("Close chat")


def native_purchase(device: Device) -> None:
    deadline = time.monotonic() + 65
    last = "native Test Store dialog unavailable"
    while time.monotonic() < deadline:
        xml, window = device.adb.observe(deadline=deadline)
        try:
            target = select_target(xml, window, "success")
            device.phase = "21-native-test-store-success"
            prefix = device.output / device.phase
            prefix.with_suffix(".xml").write_text(xml, encoding="utf-8")
            prefix.with_suffix(".window.txt").write_text(window, encoding="utf-8")
            prefix.with_suffix(".png").write_bytes(device.adb.screenshot())
            # Native dialog may change during capture; reselect from a fresh tree.
            xml, window = device.adb.observe(deadline=deadline)
            target = select_target(xml, window, "success")
            device.adb.run("shell", "input", "tap", *map(str, target.center))
            device.phases.append({"phase": device.phase, "nativeButton": target.label})
            return
        except UnsafeDialog as error:
            last = str(error)
            time.sleep(0.5)
    raise RuntimeFailure(last)


def run(phone: Device, tablet: Device, fixture: Path, report: dict[str, object]) -> dict[str, object]:
    if phone.adb.serial == tablet.adb.serial or phone.apk.resolve() != tablet.apk.resolve():
        raise RuntimeFailure("two independent devices must use the same APK")
    report["devices"] = {}
    report["devices"]["phone"] = phone.prepare()
    report["devices"]["tablet"] = tablet.prepare()
    onboard(phone, "phone")
    onboard(tablet, "tablet")
    phone.tap_home_action("Start a room")
    phone.capture("04-first-host", present("Invite to room"))
    phone.tap("Invite to room")
    code = phone.capture("05-visible-invite-code", visible_code)
    assert isinstance(code, str)
    phone.back()
    tablet.tap("Join a room")
    tablet.capture("04-guest-join-sheet", join_sheet_ready)
    tablet.enter(code)
    tablet.tap("Join room")
    phone.capture("06-peer-present-phone", present("Together in this room"))
    tablet.capture("06-peer-present-tablet", present("Together in this room"))
    load_link(phone, "phone")
    load_link(tablet, "tablet")
    phone.tap_playback(False)
    first = phone.player("09-host-playing", True)
    guest_first = tablet.player("09-guest-follows-play", True)
    time.sleep(3)
    advanced = phone.player("10-host-advanced", True)
    require_playing_advance(first, advanced)
    guest_advanced = tablet.player("10-guest-advanced", True)
    require_playing_advance(guest_first, guest_advanced)
    tablet.tap_playback(True)
    phone.player("11-host-follows-guest-pause", False)
    tablet.seek(.60)
    guest_seek = tablet.player("12-guest-seek", False)
    sought = phone.player("12-host-follows-guest-seek", False)
    if (not 45 <= sought.position_seconds <= 65 or
            abs(sought.position_seconds - guest_seek.position_seconds) > 3):
        raise RuntimeFailure("guest seek did not reach host native timeline")
    tablet.tap_playback(False)
    phone.player("13-host-follows-guest-play", True)
    phone.tap_playback(True)
    tablet.player("14-guest-follows-host-pause", False)
    phone.seek(.35)
    host_seek = phone.player("15-host-seek", False)
    guest_sought = tablet.player("15-guest-follows-host-seek", False)
    if (not 25 <= guest_sought.position_seconds <= 40 or
            abs(host_seek.position_seconds - guest_sought.position_seconds) > 3):
        raise RuntimeFailure("host seek did not reach guest native timeline")
    phone.tap_playback(False)
    tablet.player("16-guest-follows-host-replay", True)
    phone.tap_playback(True)
    tablet.player("17-guest-follows-host-final-pause", False)
    chat(phone, tablet, "HelloFromPhone", "14-phone-chat")
    chat(tablet, phone, "HelloFromTablet", "15-tablet-chat")
    phone.tap("Send a reaction")
    phone.capture("16-reaction-picker", present("Send a reaction"))
    # The reaction is visible for three seconds; begin the guest's ordinary
    # native UI wait before the sender presses the visible emoji button.
    with ThreadPoolExecutor(max_workers=1) as executor:
        received = executor.submit(tablet.capture, "16-guest-reaction", any_reaction)
        phone.tap("❤️")
        received.result(timeout=PHASE_TIMEOUT + 10)
    phone.tap("Enter full screen")
    phone.capture("17-phone-fullscreen", present("Exit full screen"))
    phone.back()
    phone.capture("18-phone-after-back", present("Enter full screen"))
    tablet.tap("Leave room")
    room = code.split("@", 1)[0]
    tablet.capture_history("19-guest-history", f"Room {room}")
    phone.tap("Leave room")
    phone.capture_history("19-host-history", f"Room {room}")
    phone.tap_home_action("Start a room")
    phone.capture("20-free-limit-paywall", present("Free includes one hosted session per local day."))
    phone.tap_purchase_button()
    native_purchase(phone)
    phone.capture("23-second-distinct-host", present("Invite to room"))
    phone.tap("Invite to room")
    second_code = phone.capture("23-second-visible-invite-code", visible_code)
    if second_code == code:
        raise RuntimeFailure("Plus host reused the first room code")
    phone.back()
    phone.tap("Leave room")
    phone.capture("24-home-after-plus-host", present("Start a room"))
    phone.tap("Profile and settings")
    phone.capture("25-settings-plus", present("Plus is active · unlimited hosting"))
    phone.tap("Restore purchases")
    phone.capture("26-settings-restore", present("Restored. MeowWatch Plus is active."))
    phone.back()
    phone.tap("Local Player Mode\nWatch on this device without starting a room.")
    phone.capture("27-local-player", present("Back to home"))
    load_link(phone, "local")
    phone.tap_playback(False)
    local_first = phone.player("28-local-playing", True)
    time.sleep(3)
    local_after = phone.player("29-local-advanced", True)
    require_playing_advance(local_first, local_after)
    phone.tap_playback(True)
    phone.tap("Back to home")
    phone.capture_history("30-local-history", "Local player")
    history_position = phone.resume_local_history()
    resumed = phone.player("32-local-resumed-paused", False)
    if history_position < 2 or abs(resumed.position_seconds - history_position) > 1:
        raise RuntimeFailure("Local Continue Watching did not restore the saved position")
    report["localResumePositionSeconds"] = resumed.position_seconds
    report["firstInviteCode"] = code
    report["secondInviteCode"] = second_code
    report["completed"] = True
    return report


def any_reaction(xml: str) -> bool:
    if not any("reacted" in value for node in nodes(xml) for value in
               (node.get("text", ""), node.get("content-desc", ""))):
        raise RuntimeFailure("peer reaction not visible")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phone", required=True)
    parser.add_argument("--tablet", required=True)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--observer-apk", type=Path, required=True)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists() or not all(path.is_file() for path in
                                        (args.apk, args.observer_apk, args.fixture)):
        parser.error("empty output path and built APK/observer/prepared fixture required")
    args.output.mkdir(parents=True)
    devices = [Device(args.phone, args.apk, args.observer_apk, args.output / "phone"),
               Device(args.tablet, args.apk, args.observer_apk, args.output / "tablet")]
    report: dict[str, object] = {
        "completed": False, "normalLibMainEntrypoint": True, "integrationTarget": False,
        "apkSha256": hashlib.sha256(args.apk.read_bytes()).hexdigest(),
        "fixtureSha256": hashlib.sha256(args.fixture.read_bytes()).hexdigest(),
        "fixtureUrl": FIXTURE_URL,
        "serials": {"phone": args.phone, "tablet": args.tablet},
    }
    try:
        run(*devices, args.fixture, report)
        return 0
    except Exception as error:
        report["failure"] = f"{type(error).__name__}: {error}"
        for device in devices:
            if device.output.exists():
                device.diagnostics()
        return 1
    finally:
        report["phases"] = {"phone": devices[0].phases, "tablet": devices[1].phases}
        report["nativeUiObservations"] = {
            "phone": devices[0].observer.observations,
            "tablet": devices[1].observer.observations,
        }
        (args.output / "result.json").write_text(json.dumps(report, indent=2, default=str) + "\n", encoding="utf-8")
        for device in devices:
            if device.installed:
                device.cleanup()


if __name__ == "__main__":
    raise SystemExit(main())
