#!/usr/bin/env python3
"""Prove normal Android cold/warm share intake reaches explicit user review."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import time
from typing import Sequence
import xml.etree.ElementTree as ET

from tools.android_install.runner import (
    ACTIVITY,
    Adb,
    PACKAGE,
    RuntimeFailure,
    focused_component,
    launch_output_succeeded,
    parse_package_metadata,
)


@dataclass(frozen=True)
class Case:
    name: str
    action: str
    cold: bool
    invite: bool = False

    @property
    def filename(self) -> str:
        return f"meowwatch-{self.name}.mp4"

    @property
    def room(self) -> str:
        return f"meowwatch-{self.name}"


CASES = (
    Case("cold-send", "SEND", True),
    Case("warm-send", "SEND", False),
    Case("warm-view", "VIEW", False),
    Case("cold-view", "VIEW", True),
    Case("cold-invite", "VIEW", True, True),
    Case("warm-invite", "VIEW", False, True),
    Case("shared-invite", "SEND", False, True),
)


def launch_arguments(case: Case) -> list[str]:
    if case not in CASES:
        raise ValueError("only fixed non-sensitive rehearsal fixtures are supported")
    # Deliberately not real video: this gate must stop at review, before Open.
    url = f"https://example.invalid/{case.filename}"
    if case.invite:
        # adb shell joins argv into shell text; quote the query's ampersands.
        url = shlex.quote(f"meowwatch://join?room={case.room}&server=syncplay.pl&port=8995")
    common = ["shell", "am", "start", "-W", "-n", ACTIVITY]
    if case.action == "SEND":
        return common + [
            "-a", "android.intent.action.SEND", "-t", "text/plain",
            "--es", "android.intent.extra.TEXT", url,
        ]
    return common + ["-a", "android.intent.action.VIEW", "-d", url]


def nodes(xml: str) -> list[ET.Element]:
    try:
        root = ET.fromstring(xml)
    except ET.ParseError as error:
        raise RuntimeFailure("invalid native UI hierarchy") from error
    return [node for node in root.iter("node")
            if node.get("package") == PACKAGE
            and node.get("enabled", "true") == "true"
            and node.get("visible-to-user", "true") == "true"]


def exact(xml: str, label: str, *, clickable: bool = False) -> list[ET.Element]:
    return [node for node in nodes(xml)
            if label in {node.get("text", ""), node.get("content-desc", "")}
            and (not clickable or node.get("clickable") == "true")]


def require_review(xml: str, filename: str) -> None:
    expected = (
        ("Open shared video?", False),
        (filename, False),
        ("Cancel", True),
        ("Open video", True),
    )
    if any(len(exact(xml, label, clickable=clickable)) != 1
           for label, clickable in expected):
        raise RuntimeFailure("the unique expected shared-video review is missing")


def require_case_review(xml: str, case: Case) -> None:
    if not case.invite:
        require_review(xml, case.filename)
        return
    if len(exact(xml, "Room invitation received")) != 1 or len(
        exact(xml, "Join this room", clickable=True)
    ) != 1:
        raise RuntimeFailure("the unique expected room-invitation review is missing")
    labels = [value for node in nodes(xml)
              for value in (node.get("text", ""), node.get("content-desc", ""))]
    room_visible = any(f"Room: {case.room}" in label or f"Room {case.room}, server" in label
                       for label in labels)
    server_visible = any("Server: syncplay.pl:8995" in label or "server syncplay.pl, port 8995" in label
                         for label in labels)
    if not room_visible or not server_visible or exact(xml, "Open shared video?"):
        raise RuntimeFailure("the invitation room/server review is incomplete or duplicated by media intake")


def center(node: ET.Element) -> tuple[int, int]:
    match = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds", ""))
    if match is None:
        raise RuntimeFailure("native button bounds are unavailable")
    left, top, right, bottom = map(int, match.groups())
    if right <= left or bottom <= top:
        raise RuntimeFailure("native button is not visible")
    return (left + right) // 2, (top + bottom) // 2


class Runner:
    def __init__(self, serial: str, output: Path) -> None:
        self.adb = Adb(serial, f"incoming-{os.getpid()}-{time.time_ns()}")
        self.output = output
        self.cleanup_authorized = False

    def prepare(self) -> dict[str, object]:
        if self.output.exists() and any(self.output.iterdir()):
            raise RuntimeFailure("evidence directory must start empty")
        self.output.mkdir(parents=True, exist_ok=True)
        if self.adb.run("get-state").stdout.decode().strip() != "device":
            raise RuntimeFailure("selected Android emulator is not ready")
        if self.adb.run("shell", "getprop", "ro.kernel.qemu").stdout.decode().strip() != "1":
            raise RuntimeFailure("this rehearsal requires a dedicated Android emulator")
        installed = self.adb.run("shell", "pm", "path", PACKAGE).stdout.decode().strip()
        if not installed.startswith("package:"):
            raise RuntimeFailure("install the normal application APK before this rehearsal")
        if self.adb.run("shell", "test", "-e", self.adb.remote_root, check=False).returncode == 0:
            raise RuntimeFailure("task-owned remote evidence directory already exists")
        self.adb.run("shell", "mkdir", self.adb.remote_root)
        self.adb.remote_root_created = True
        self.cleanup_authorized = True
        package = self.adb.run("shell", "dumpsys", "package", PACKAGE).stdout.decode()
        return {
            "package": parse_package_metadata(package),
            "runtime": {
                "kind": "Android emulator",
                "model": self.adb.run("shell", "getprop", "ro.product.model").stdout.decode().strip(),
                "api": self.adb.run("shell", "getprop", "ro.build.version.sdk").stdout.decode().strip(),
                "abi": self.adb.run("shell", "getprop", "ro.product.cpu.abi").stdout.decode().strip(),
            },
        }

    def pid(self) -> str:
        value = self.adb.run("shell", "pidof", PACKAGE, check=False).stdout.decode().strip()
        if value and re.fullmatch(r"\d+", value) is None:
            raise RuntimeFailure("expected exactly one application process")
        return value

    def cold_stop(self) -> None:
        self.adb.run("shell", "am", "force-stop", PACKAGE)
        deadline = time.monotonic() + 10
        while self.pid():
            if time.monotonic() >= deadline:
                raise RuntimeFailure("cold-start precondition failed: app process still exists")
            time.sleep(0.2)

    def tap(self, node: ET.Element) -> None:
        x, y = center(node)
        self.adb.run("shell", "input", "tap", str(x), str(y))

    def wait_review(self, case: Case) -> str:
        deadline = time.monotonic() + 65
        completed_onboarding = False
        while time.monotonic() < deadline:
            try:
                xml, window = self.adb.observe()
                focused_component(window)
                if not completed_onboarding:
                    title = exact(xml, "Close the distance.\nKeep the movie night.")
                    proceed = exact(xml, "Continue", clickable=True)
                    if len(title) == 1 and len(proceed) == 1:
                        self.tap(proceed[0])
                        completed_onboarding = True
                        continue
                require_case_review(xml, case)
                return xml
            except RuntimeFailure:
                time.sleep(0.4)
        raise RuntimeFailure(f"{case.name}: review was never shown")

    def run_case(self, case: Case) -> dict[str, object]:
        if case.cold:
            self.cold_stop()
        previous_pid = self.pid()
        if case.cold and previous_pid:
            raise RuntimeFailure("a cold launch cannot reuse an existing process")
        if not case.cold and not previous_pid:
            raise RuntimeFailure("warm launch lost its running application")
        launched = self.adb.run(*launch_arguments(case), timeout=35).stdout.decode()
        if not launch_output_succeeded(launched):
            raise RuntimeFailure(f"{case.name}: Android did not launch the normal activity")
        xml = self.wait_review(case)
        live_pid = self.pid()
        if not live_pid or (not case.cold and live_pid != previous_pid):
            raise RuntimeFailure("warm intent did not remain in the original process")
        self.output.joinpath(f"{case.name}.xml").write_text(xml, encoding="utf-8")
        self.output.joinpath(f"{case.name}.png").write_bytes(self.adb.screenshot())
        # Holding the dialog distinguishes a real confirmation gate from a transient label.
        time.sleep(1)
        held, window = self.adb.observe()
        focused_component(window)
        require_case_review(held, case)
        if case.invite:
            self.adb.run("shell", "input", "keyevent", "KEYCODE_BACK")
        else:
            self.tap(exact(held, "Cancel", clickable=True)[0])
        time.sleep(0.8)
        for _ in range(2):
            after, window = self.adb.observe()
            focused_component(window)
            if exact(after, "Open shared video?") or exact(after, "Room invitation received"):
                raise RuntimeFailure("dismissal replayed an incoming review")
            time.sleep(0.4)
        return {
            "case": case.name,
            "coldProcessAbsentBeforeLaunch": not previous_pid if case.cold else None,
            "sameProcessForWarmDelivery": live_pid == previous_pid if not case.cold else None,
            "reviewShown": True,
            "reviewRemainedUntilChoice": True,
            "cancelDidNotReplay": True,
            "openActionInvoked": False,
            "joinActionInvoked": False,
        }

    def run(self) -> dict[str, object]:
        report = self.prepare()
        report["cases"] = [self.run_case(case) for case in CASES]
        report["completed"] = True
        return report

    def cleanup(self) -> None:
        if self.cleanup_authorized:
            self.adb.run("shell", "am", "force-stop", PACKAGE, check=False)
            self.adb.cleanup()


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--output", type=Path, default=Path("build/incoming-media-runtime-artifacts"))
    parser.add_argument("--apk", type=Path, help="Optional installed APK path for provenance hash; does not install it")
    args = parser.parse_args(argv)
    runner = Runner(args.serial, args.output)
    try:
        report = runner.run()
        if args.apk is not None:
            report["suppliedApkSha256"] = hashlib.sha256(args.apk.read_bytes()).hexdigest()
        args.output.joinpath("result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        print("INCOMING_MEDIA_NATIVE_REVIEW_PASS")
        return 0
    except (RuntimeFailure, OSError, subprocess.TimeoutExpired) as error:
        message = str(error) if isinstance(error, RuntimeFailure) else type(error).__name__
        if runner.cleanup_authorized:
            args.output.joinpath("result.json").write_text(
                json.dumps({"completed": False, "error": message}, indent=2), encoding="utf-8"
            )
            try:
                args.output.joinpath("failure.png").write_bytes(runner.adb.screenshot())
            except (RuntimeFailure, OSError, subprocess.TimeoutExpired):
                pass
        print(f"INCOMING_MEDIA_NATIVE_REVIEW_FAIL: {message}")
        return 1
    finally:
        runner.cleanup()


if __name__ == "__main__":
    raise SystemExit(main())
