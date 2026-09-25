#!/usr/bin/env python3
"""Observe one ordinary Android guest in a disposable public Syncplay room."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import signal
import time

from tools.android_install.runner import ACTIVITY, RuntimeFailure, launch_output_succeeded
from tools.android_lifecycle_runtime.run import Playback, button, labels, parse_time, require_playing_advance
from tools.incoming_media_runtime.run import exact, nodes
from tools.normal_apk_rehearsal.run import (
    Device, onboard, present, timeline_tap, unique_text_field, visible_chat_receipt,
)


SAMPLE_URL = "https://media.w3.org/2010/05/bunny/movie.mp4"
SAMPLE_TITLE = "movie.mp4"
MAX_SECONDS = 20 * 60
ROOM_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{2,35}", re.ASCII)
STAGES = frozenset({
    "READY", "DESKTOP_READY", "CLOUD_PLAY", "SAW_CLOUD_PLAY",
    "CLOUD_PAUSE", "SAW_CLOUD_PAUSE", "CLOUD_SEEK", "SAW_CLOUD_SEEK",
    "READY_DESKTOP_PLAY", "DESKTOP_PLAY", "SAW_DESKTOP_PLAY",
    "DESKTOP_PAUSE", "SAW_DESKTOP_PAUSE", "DESKTOP_SEEK",
    "SAW_DESKTOP_SEEK",
})


def validate_room(room: str) -> str:
    if ROOM_PATTERN.fullmatch(room) is None:
        raise ValueError("room must be 3-36 ASCII letters, digits, dots, underscores or hyphens")
    return room


def message(room: str, stage: str) -> str:
    if stage not in STAGES:
        raise ValueError("unknown rehearsal stage")
    token = hashlib.sha256(validate_room(room).encode("ascii")).hexdigest()[:8]
    return f"MWG-{token}-{stage}"


def sample_player(xml: str, playing: bool | None = None) -> Playback:
    if SAMPLE_TITLE not in labels(xml):
        raise RuntimeFailure("ordinary player does not show the selected Big Buck Bunny file")
    if len([node for node in nodes(xml) if node.get("class", "").endswith("SeekBar")]) != 1:
        raise RuntimeFailure("ordinary player has no unique native timeline")
    times = sorted({seconds for value in labels(xml)
                    if (seconds := parse_time(value)) is not None})
    if len(times) != 2 or not 540 <= times[1] <= 660 or times[0] >= times[1]:
        raise RuntimeFailure("Big Buck Bunny elapsed and 9–11 minute duration are not visible")
    play = exact(xml, "Play", clickable=True) + exact(xml, "Play together", clickable=True)
    pause = exact(xml, "Pause", clickable=True) + exact(xml, "Pause together", clickable=True)
    if len(play) + len(pause) != 1:
        raise RuntimeFailure("player has no unique Play or Pause action")
    state = Playback(times[0], times[1], bool(pause))
    if playing is not None and state.playing != playing:
        raise RuntimeFailure("visible player state differs from expected peer action")
    return state


def receipt(xml: str, expected: str) -> bool:
    # The peer's stage strings are never sent by this guest; match a complete
    # visible message, not composer text, a substring or an old room's token.
    return visible_chat_receipt(xml, expected)


def invite_review(xml: str, room: str) -> bool:
    if not exact(xml, "Room invitation received") or not exact(xml, "Join this room", clickable=True):
        raise RuntimeFailure("external room invite confirmation is not visible")
    values = labels(xml)
    if not any(f"Room: {room}" in value or f"Room {room}, server" in value for value in values):
        raise RuntimeFailure("invite confirmation has a different room")
    if not any("syncplay.pl:8995" in value or "server syncplay.pl, port 8995" in value for value in values):
        raise RuntimeFailure("invite confirmation has a different public server")
    return True


def sample_link_ready(xml: str) -> bool:
    if unique_text_field(xml).get("text") != SAMPLE_URL:
        raise RuntimeFailure("visible media field does not contain the exact public Big Buck Bunny URL")
    button(xml, "Use this link")
    return True


class Guest:
    def __init__(self, device: Device, room: str):
        self.device = device
        self.room = room
        self.deadline = time.monotonic() + MAX_SECONDS

    def capture(self, phase: str, check, timeout: int = 45):
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise RuntimeFailure("20-minute external peer rehearsal deadline exceeded")
        return self.device.capture(phase, check, timeout=max(1, min(timeout, int(remaining))))

    def send(self, stage: str, phase: str) -> None:
        self.device.tap("Chat")
        self.capture(f"{phase}-composer", present("Send message"))
        self.device.enter(message(self.room, stage))
        self.device.tap("Send message")
        self.capture(f"{phase}-sent", lambda xml: receipt(xml, message(self.room, stage)))

    def receive(self, stage: str, phase: str, timeout: int = 90) -> None:
        self.capture(f"{phase}-received", lambda xml: receipt(xml, message(self.room, stage)), timeout)
        self.device.tap("Close chat")

    def await_peer(self, stage: str, phase: str, timeout: int = 90) -> None:
        self.device.tap("Chat")
        self.receive(stage, phase, timeout)

    def player(self, phase: str, playing: bool | None = None) -> Playback:
        return self.capture(phase, lambda xml: sample_player(xml, playing))


def run(guest: Guest, report: dict[str, object]) -> None:
    device, room = guest.device, guest.room
    report["device"] = device.prepare()
    onboard(device, "guest")
    # A normal external VIEW invitation exercises the visible room/server
    # confirmation, then the same ordinary join action as a pasted code.
    url = shlex.quote(f"meowwatch://join?room={room}&server=syncplay.pl&port=8995")
    launch = device.adb.run("shell", "am", "start", "-W", "-n", ACTIVITY,
                            "-a", "android.intent.action.VIEW", "-d", url, timeout=35)
    if not launch_output_succeeded(launch.stdout.decode(errors="replace")):
        raise RuntimeFailure("ordinary external room invite did not open")
    guest.capture("04-invite-confirmation", lambda xml: invite_review(xml, room))
    device.tap("Join this room")
    guest.capture("05-joined-room", present("Together in this room"), 90)

    device.tap("Video")
    guest.capture("06-media-choice", present("Direct video link"))
    device.enter(SAMPLE_URL)
    device.back()
    guest.capture("06-bunny-link-ready", sample_link_ready)
    device.tap("Use this link")
    guest.player("07-bunny-loaded", False)
    guest.send("READY", "08-ready")
    guest.receive("DESKTOP_READY", "09-desktop-ready")

    device.tap_playback(False)
    first = guest.player("10-cloud-playing", True)
    time.sleep(3)
    require_playing_advance(first, guest.player("11-cloud-advanced", True))
    guest.send("CLOUD_PLAY", "12-cloud-play")
    guest.receive("SAW_CLOUD_PLAY", "13-desktop-saw-play")

    device.tap_playback(True)
    paused = guest.player("14-cloud-paused", False)
    time.sleep(2)
    stable = guest.player("15-cloud-pause-stable", False)
    if abs(stable.position_seconds - paused.position_seconds) > 1:
        raise RuntimeFailure("cloud pause did not keep the actual timeline stable")
    guest.send("CLOUD_PAUSE", "16-cloud-pause")
    guest.receive("SAW_CLOUD_PAUSE", "17-desktop-saw-pause")

    # Seek to about three minutes; the peer independently confirms its view.
    x, y = timeline_tap(device.observe(), .30)
    device.adb.run("shell", "input", "tap", str(x), str(y))
    sought = guest.player("18-cloud-sought", False)
    if not 150 <= sought.position_seconds <= 220:
        raise RuntimeFailure("cloud seek did not reach about three minutes")
    guest.send("CLOUD_SEEK", "19-cloud-seek")
    guest.receive("SAW_CLOUD_SEEK", "20-desktop-saw-seek")

    guest.send("READY_DESKTOP_PLAY", "21-ready-for-desktop")
    guest.receive("DESKTOP_PLAY", "22-desktop-play-command", 90)
    started = guest.player("23-cloud-follows-desktop-play", True)
    time.sleep(3)
    require_playing_advance(started, guest.player("24-cloud-follows-desktop-advance", True))
    guest.send("SAW_DESKTOP_PLAY", "25-cloud-saw-desktop-play")
    device.tap("Close chat")

    guest.await_peer("DESKTOP_PAUSE", "26-desktop-pause-command", 90)
    stopped = guest.player("27-cloud-follows-desktop-pause", False)
    time.sleep(2)
    stable = guest.player("28-desktop-pause-stable", False)
    if abs(stable.position_seconds - stopped.position_seconds) > 1:
        raise RuntimeFailure("desktop pause did not hold the cloud timeline")
    guest.send("SAW_DESKTOP_PAUSE", "29-cloud-saw-desktop-pause")
    device.tap("Close chat")

    guest.await_peer("DESKTOP_SEEK", "30-desktop-seek-command", 90)
    sought = guest.player("31-cloud-follows-desktop-seek", False)
    if not 270 <= sought.position_seconds <= 330:
        raise RuntimeFailure("desktop seek did not reach about five minutes on cloud timeline")
    guest.send("SAW_DESKTOP_SEEK", "32-cloud-saw-desktop-seek")
    device.tap("Close chat")
    report["completed"] = True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--room", required=True)
    parser.add_argument("--print-token", action="store_true")
    parser.add_argument("--serial")
    parser.add_argument("--apk", type=Path)
    parser.add_argument("--observer-apk", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        room = validate_room(args.room)
    except ValueError as error:
        parser.error(str(error))
    if args.print_token:
        print(message(room, "READY").removesuffix("READY"))
        return 0
    if not all((args.serial, args.apk, args.observer_apk, args.output)):
        parser.error("serial, APK, native observer APK and output are required")
    if args.output.exists() or not args.apk.is_file() or not args.observer_apk.is_file():
        parser.error("fresh output and both built APK files are required")
    args.output.mkdir(parents=True)
    device = Device(args.serial, args.apk, args.observer_apk, args.output / "phone")
    guest = Guest(device, room)
    report: dict[str, object] = {
        "completed": False, "normalLibMainEntrypoint": True, "integrationTarget": False,
        "sourceHead": os.environ.get("GITHUB_SHA"),
        "githubRunId": os.environ.get("GITHUB_RUN_ID"),
        "room": room, "server": "syncplay.pl:8995", "sampleUrl": SAMPLE_URL,
        "handshakePrefix": message(room, "READY").removesuffix("READY"),
        "apkSha256": hashlib.sha256(args.apk.read_bytes()).hexdigest(),
        "deadlineSeconds": MAX_SECONDS,
    }
    def expired(_signum, _frame):
        raise RuntimeFailure("20-minute external peer rehearsal deadline exceeded")
    signal.signal(signal.SIGALRM, expired)
    signal.alarm(MAX_SECONDS)
    try:
        run(guest, report)
        return 0
    except Exception as error:
        report["failure"] = f"{type(error).__name__}: {error}"
        if device.output.exists():
            device.diagnostics()
        return 1
    finally:
        signal.alarm(0)
        report["phases"] = device.phases
        report["nativeUiObservations"] = device.observer.observations
        (args.output / "result.json").write_text(json.dumps(report, indent=2, default=str) + "\n", encoding="utf-8")
        if device.installed:
            device.cleanup()


if __name__ == "__main__":
    raise SystemExit(main())
