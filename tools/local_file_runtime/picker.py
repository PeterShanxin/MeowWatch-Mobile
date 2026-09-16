"""Bounded UIAutomator control for Android's ACTION_OPEN_DOCUMENT surface."""

from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
import re
import subprocess
import threading
import time
import xml.etree.ElementTree as ET


APP_PACKAGE = "com.meowwatch.meowwatch_mobile"
DOCUMENTS_PACKAGES = {"com.google.android.documentsui", "com.android.documentsui"}
_BOUNDS = re.compile(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]")


class PickerNotReady(RuntimeError):
    """The expected safe picker control is not present in the current frame."""


@dataclass(frozen=True)
class PickerTarget:
    action: str
    bounds: tuple[int, int, int, int]

    @property
    def center(self) -> tuple[int, int]:
        left, top, right, bottom = self.bounds
        return ((left + right) // 2, (top + bottom) // 2)


def _focused_package(window_dump: str) -> str:
    focuses = re.findall(r"mCurrentFocus=([^\r\n]+)", window_dump)
    if len(focuses) != 1:
        raise PickerNotReady("Android did not report one focused window")
    for package in DOCUMENTS_PACKAGES:
        if re.search(rf"\b{re.escape(package)}/[^\s}}]+", focuses[0]):
            return package
    raise PickerNotReady("The system document picker is not focused")


def _bounds(node: ET.Element) -> tuple[int, int, int, int]:
    match = _BOUNDS.fullmatch(node.get("bounds", ""))
    if not match:
        raise PickerNotReady("Picker control has invalid bounds")
    bounds = tuple(map(int, match.groups()))
    if bounds[0] >= bounds[2] or bounds[1] >= bounds[3]:
        raise PickerNotReady("Picker control has empty bounds")
    return bounds


def select_picker_target(
    xml: str,
    window_dump: str,
    fixture_name: str,
    phase: str,
) -> PickerTarget:
    """Return only an exact fixture/search control in the focused DocumentsUI."""
    if phase not in {"initial", "search", "results"}:
        raise ValueError("unknown picker phase")
    package = _focused_package(window_dump)
    try:
        root = ET.fromstring(xml)
    except ET.ParseError as error:
        raise PickerNotReady("Invalid UIAutomator XML") from error
    nodes = [
        node
        for node in root.iter("node")
        if node.get("package") == package
        and node.get("visible-to-user", "true") == "true"
        and node.get("enabled", "true") == "true"
    ]
    files = [
        node
        for node in nodes
        if fixture_name in {node.get("text", ""), node.get("content-desc", "")}
        and node.get("class") not in {
            "android.widget.EditText", "android.widget.AutoCompleteTextView",
        }
        and node.get("resource-id") not in {
            "android:id/search_src_text", f"{package}:id/search_src_text",
        }
    ]
    if len(files) == 1:
        return PickerTarget("fixture", _bounds(files[0]))
    if len(files) > 1:
        raise PickerNotReady("Fixture selector is ambiguous")

    if phase == "initial":
        search = [
            node
            for node in nodes
            if node.get("content-desc", "").strip().casefold() == "search"
            and node.get("clickable") == "true"
        ]
        if len(search) == 1:
            return PickerTarget("search", _bounds(search[0]))
        raise PickerNotReady("Exact picker fixture and Search control are absent")

    if phase == "search":
        search_ids = {"android:id/search_src_text", f"{package}:id/search_src_text"}
        fields = [
            node
            for node in nodes
            if node.get("resource-id") in search_ids
            and node.get("class") in {
                "android.widget.EditText",
                "android.widget.AutoCompleteTextView",
            }
            and node.get("clickable", "true") == "true"
        ]
        if len(fields) == 1:
            return PickerTarget("query", _bounds(fields[0]))
        raise PickerNotReady("DocumentsUI search field is absent or ambiguous")

    raise PickerNotReady("Exact fixture is absent from DocumentsUI results")


def search_field_diagnostics(xml: str) -> list[dict[str, object]]:
    """Retain only search-control shape, never document names or URI values."""
    try:
        root = ET.fromstring(xml)
    except ET.ParseError:
        return []
    return [
        {
            "class": node.get("class", "")[:120],
            "clickable": node.get("clickable") == "true",
            "enabled": node.get("enabled", "true") == "true",
        }
        for node in root.iter("node")
        if node.get("package") in DOCUMENTS_PACKAGES
        and node.get("resource-id") in {
            "android:id/search_src_text",
            "com.android.documentsui:id/search_src_text",
            "com.google.android.documentsui:id/search_src_text",
        }
    ][:8]


def image_size(png: bytes) -> tuple[int, int]:
    if len(png) < 24 or png[:8] != b"\x89PNG\r\n\x1a\n" or png[12:16] != b"IHDR":
        raise RuntimeError("adb did not return a PNG screenshot")
    return int.from_bytes(png[16:20], "big"), int.from_bytes(png[20:24], "big")


class Adb:
    def __init__(self, serial: str, run_id: str) -> None:
        if not re.fullmatch(r"emulator-[0-9]+", serial):
            raise ValueError("an explicit Android emulator serial is required")
        if not re.fullmatch(r"[A-Za-z0-9_-]+", run_id):
            raise ValueError("invalid run ID")
        self.prefix = ["adb", "-s", serial]
        self.remote_prefix = f"/sdcard/meowwatch-saf-{run_id}-"
        self.remote_files: list[str] = []
        self.observation = 0

    def run(
        self,
        *arguments: str,
        timeout: float = 20,
        check: bool = True,
    ) -> subprocess.CompletedProcess[bytes]:
        result = subprocess.run(
            self.prefix + list(arguments),
            capture_output=True,
            timeout=timeout,
            check=False,
        )
        if check and result.returncode:
            command = arguments[0] if arguments else ""
            raise RuntimeError(f"adb {command} failed with exit {result.returncode}")
        return result

    def observe(self) -> tuple[str, str]:
        self.observation += 1
        remote = f"{self.remote_prefix}ui-{self.observation}.xml"
        self.remote_files.append(remote)
        self.run("shell", "uiautomator", "dump", "--compressed", remote)
        xml = self.run("exec-out", "cat", remote).stdout.decode("utf-8", errors="strict")
        window = self.run("shell", "dumpsys", "window", "displays").stdout.decode(
            "utf-8", errors="replace"
        )
        return xml, window

    def screenshot(self) -> bytes:
        png = self.run("exec-out", "screencap", "-p").stdout
        image_size(png)
        return png

    def wait_for_app_focus(self, timeout: float = 20) -> None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            window = self.run("shell", "dumpsys", "window", "displays").stdout.decode(
                "utf-8", errors="replace"
            )
            focuses = re.findall(r"mCurrentFocus=([^\r\n]+)", window)
            if len(focuses) == 1 and re.search(
                rf"\b{re.escape(APP_PACKAGE)}/[^\s}}]+", focuses[0]
            ):
                return
            time.sleep(0.25)
        raise RuntimeError("MeowWatch did not regain focus after document selection")

    def cleanup(self) -> None:
        for remote in self.remote_files:
            if not remote.startswith(self.remote_prefix):
                raise RuntimeError("refusing to remove a non-owned remote file")
            self.run("shell", "rm", "-f", remote, check=False)


class DocumentsUiSelector:
    def __init__(
        self,
        adb: Adb,
        artifacts: Path,
        fixture_name: str,
        timeout: float = 70,
        stop_event: threading.Event | None = None,
    ) -> None:
        self.adb = adb
        self.artifacts = artifacts
        self.fixture_name = fixture_name
        self.timeout = timeout
        self.stop_event = stop_event
        self.selected = False

    def select(self) -> None:
        self.artifacts.mkdir(parents=True, exist_ok=True)
        self.diagnostics: dict[str, object] = {
            "selected": False, "phase": "initial", "searchFields": [],
        }
        try:
            self._select()
        except BaseException as error:
            self.diagnostics["errorType"] = type(error).__name__
            raise
        finally:
            self.diagnostics["selected"] = self.selected
            (self.artifacts / "documentsui-selector.json").write_text(
                json.dumps(self.diagnostics, indent=2) + "\n", encoding="utf-8"
            )

    def _select(self) -> None:
        phase = "initial"
        deadline = time.monotonic() + self.timeout
        last_error = "DocumentsUI was not observed"
        while time.monotonic() < deadline:
            if self.stop_event is not None and self.stop_event.is_set():
                raise RuntimeError("DocumentsUI selection was cancelled")
            try:
                xml, window = self.adb.observe()
                self.diagnostics["phase"] = phase
                self.diagnostics["searchFields"] = search_field_diagnostics(xml)
                target = select_picker_target(xml, window, self.fixture_name, phase)
                png = self.adb.screenshot()
                width, height = image_size(png)
                # Expensive capture may change focus. Re-read before every tap.
                xml, window = self.adb.observe()
                target = select_picker_target(xml, window, self.fixture_name, phase)
                if target.bounds[2] > width or target.bounds[3] > height:
                    raise PickerNotReady("Picker control lies outside the screen")
                x, y = target.center
                if target.action == "fixture":
                    (self.artifacts / "documentsui-before.png").write_bytes(png)
                    self.adb.run("shell", "input", "tap", str(x), str(y))
                    self.adb.wait_for_app_focus()
                    (self.artifacts / "documentsui-after.png").write_bytes(
                        self.adb.screenshot()
                    )
                    self.selected = True
                    return
                self.adb.run("shell", "input", "tap", str(x), str(y))
                if target.action == "search":
                    phase = "search"
                elif target.action == "query":
                    self.adb.run("shell", "input", "text", self.fixture_name)
                    self.adb.run("shell", "input", "keyevent", "66")
                    phase = "results"
                time.sleep(0.4)
            except (PickerNotReady, RuntimeError, subprocess.TimeoutExpired) as error:
                last_error = str(error)
                time.sleep(0.35)
        raise RuntimeError(f"Timed out selecting the exact SAF fixture: {last_error}")
