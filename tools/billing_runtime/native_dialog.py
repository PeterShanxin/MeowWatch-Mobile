"""Strict native RevenueCat Test Store dialog control using only adb/stdlib."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import queue
import re
import subprocess
import threading
import time
import xml.etree.ElementTree as ET


PACKAGE = "com.meowwatch.meowwatch_mobile"
PRODUCT = "meowwatch_plus_monthly"
STAGES = ("cancel", "failure", "success")
LAUNCHER_PACKAGE = "com.google.android.apps.nexuslauncher"
SETUP_PACKAGE = "com.google.android.googlesdksetup"
MAX_SYSTEM_ANR_RECOVERIES = 2
# The first variants are from the native SDK's SimulatedStoreBillingWrapper;
# the latter full labels are documented in RevenueCat's Test Store guide.
BUTTONS = {
    "cancel": ("android:id/button3", {"cancel"}),
    "failure": ("android:id/button2", {"test failed purchase", "failed purchase"}),
    "success": ("android:id/button1", {"test valid purchase", "successful purchase"}),
}


class UnsafeDialog(RuntimeError):
    """The currently observed window cannot safely receive a purchase tap."""


@dataclass(frozen=True)
class Target:
    label: str
    bounds: tuple[int, int, int, int]

    @property
    def center(self) -> tuple[int, int]:
        left, top, right, bottom = self.bounds
        return ((left + right) // 2, (top + bottom) // 2)


def focused_on_app(window_dump: str, package: str = PACKAGE) -> bool:
    focuses = re.findall(r"mCurrentFocus=([^\r\n]+)", window_dump)
    return len(focuses) == 1 and re.search(
        rf"\b{re.escape(package)}/[^\s}}]+", focuses[0]
    ) is not None


def _select_system_anr_close(
    xml: str,
    window_dump: str,
    *,
    anr_package: str,
    anr_title: str,
    expected_underlying_package: str,
) -> Target:
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+", expected_underlying_package):
        raise UnsafeDialog("An exact underlying Android package is required")
    focuses = re.findall(r"mCurrentFocus=([^\r\n]+)", window_dump)
    focused_apps = re.findall(r"mFocusedApp=([^\r\n]+)", window_dump)
    if len(focuses) != 1 or re.search(
        rf"\bApplication Not Responding: {re.escape(anr_package)}(?:\s|}})",
        focuses[0],
    ) is None:
        raise UnsafeDialog(f"The focused window is not the allowed {anr_package} ANR")
    if len(focused_apps) != 1 or re.search(
        rf"\b{re.escape(expected_underlying_package)}/[^\s}}]+", focused_apps[0]
    ) is None:
        raise UnsafeDialog("System ANR is not obscuring the expected activity")
    try:
        root = ET.fromstring(xml)
    except ET.ParseError as error:
        raise UnsafeDialog("Invalid accessibility XML") from error
    nodes = [
        node
        for node in root.iter("node")
        if node.get("package") == "android"
        and node.get("visible-to-user", "true") == "true"
        and node.get("enabled") == "true"
    ]
    titles = [
        node
        for node in nodes
        if node.get("resource-id") == "android:id/alertTitle"
        and node.get("class") == "android.widget.TextView"
        and node.get("text") == anr_title
    ]
    close_buttons = [
        node
        for node in nodes
        if node.get("resource-id") == "android:id/aerr_close"
        and node.get("class") == "android.widget.Button"
        and node.get("clickable") == "true"
        and node.get("text") == "Close app"
    ]
    if len(titles) != 1 or len(close_buttons) != 1:
        raise UnsafeDialog("Missing unique allowed system ANR title/close action")
    node = close_buttons[0]
    bounds = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds", ""))
    if not bounds:
        raise UnsafeDialog("Invalid system ANR close bounds")
    left, top, right, bottom = map(int, bounds.groups())
    if left >= right or top >= bottom:
        raise UnsafeDialog("Empty system ANR close bounds")
    return Target(node.get("text", ""), (left, top, right, bottom))


def select_pixel_launcher_anr_close(
    xml: str, window_dump: str, *, expected_underlying_package: str = PACKAGE,
) -> Target:
    """Select only the Pixel Launcher ANR over the caller's exact activity."""
    return _select_system_anr_close(
        xml,
        window_dump,
        anr_package=LAUNCHER_PACKAGE,
        anr_title="Pixel Launcher isn't responding",
        expected_underlying_package=expected_underlying_package,
    )


def select_google_sdk_setup_anr_close(
    xml: str, window_dump: str, *, expected_underlying_package: str = PACKAGE,
) -> Target:
    """Select only Google SDK setup's ANR over the caller's exact activity."""
    return _select_system_anr_close(
        xml,
        window_dump,
        anr_package=SETUP_PACKAGE,
        anr_title=f"{SETUP_PACKAGE} isn't responding",
        expected_underlying_package=expected_underlying_package,
    )


def select_target(xml: str, window_dump: str, stage: str) -> Target:
    """Match complete native labels/IDs and product within the focused app."""
    if stage not in STAGES:
        raise UnsafeDialog("Unknown purchase stage")
    if not focused_on_app(window_dump):
        raise UnsafeDialog("The focused window is not the MeowWatch application")
    try:
        root = ET.fromstring(xml)
    except ET.ParseError as error:
        raise UnsafeDialog("Invalid accessibility XML") from error
    nodes = [
        node for node in root.iter("node")
        if node.get("package") == PACKAGE
        and node.get("visible-to-user", "true") == "true"
        and node.get("enabled") == "true"
    ]
    titles = [
        node for node in nodes
        if node.get("resource-id") == "android:id/alertTitle"
        and node.get("text") == "Test Store Purchase"
        and node.get("class") == "android.widget.TextView"
    ]
    messages = [
        node for node in nodes
        if node.get("resource-id") == "android:id/message"
        and re.search(rf"(?m)^Product: {re.escape(PRODUCT)}\s*$", node.get("text", ""))
        and "RevenueCat" in node.get("text", "")
        and "test purchase" in node.get("text", "").lower()
    ]
    if len(titles) != 1 or len(messages) != 1:
        raise UnsafeDialog("Missing unique native Test Store title/product message")

    targets: dict[str, Target] = {}
    for outcome, (resource_id, labels) in BUTTONS.items():
        matches = [
            node for node in nodes
            if node.get("class") == "android.widget.Button"
            and node.get("clickable") == "true"
            and node.get("resource-id") == resource_id
            and node.get("text", "").strip().casefold() in labels
        ]
        if len(matches) != 1:
            raise UnsafeDialog(f"Missing or ambiguous native {outcome} button")
        node = matches[0]
        bounds = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds", ""))
        if not bounds:
            raise UnsafeDialog("Invalid native button bounds")
        left, top, right, bottom = map(int, bounds.groups())
        if left >= right or top >= bottom:
            raise UnsafeDialog("Empty native button bounds")
        targets[outcome] = Target(node.get("text", ""), (left, top, right, bottom))
    return targets[stage]


def image_size(png: bytes) -> tuple[int, int]:
    if len(png) < 24 or png[:8] != b"\x89PNG\r\n\x1a\n" or png[12:16] != b"IHDR":
        raise UnsafeDialog("adb did not return a PNG screenshot")
    return int.from_bytes(png[16:20], "big"), int.from_bytes(png[20:24], "big")


class Adb:
    def __init__(self, executable: str, serial: str, run_id: str):
        if not serial or not re.fullmatch(r"[A-Za-z0-9_.:-]+", serial):
            raise ValueError("An explicit adb device serial is required")
        if not re.fullmatch(r"[A-Za-z0-9_-]+", run_id):
            raise ValueError("Invalid run ID")
        self.prefix = [executable, "-s", serial]
        self.serial = serial
        self.remote_prefix = f"/sdcard/meowwatch-billing-{run_id}-"
        self.remote_files: list[str] = []
        self.observations = 0

    def run(self, *args: str, timeout: float = 15) -> bytes:
        result = subprocess.run(
            self.prefix + list(args), capture_output=True, timeout=timeout, check=False,
        )
        if result.returncode:
            raise RuntimeError(
                f"adb {args[0] if args else ''} failed ({result.returncode}): "
                f"{result.stderr.decode('utf-8', errors='replace').strip()}"
            )
        return result.stdout

    def observe(self) -> tuple[str, str]:
        self.observations += 1
        remote = f"{self.remote_prefix}ui-{self.observations}.xml"
        self.remote_files.append(remote)
        # A unique path per observation prevents a failed dump from replaying
        # yesterday's successful XML, even if uiautomator exits with status 0.
        self.run("shell", "uiautomator", "dump", "--compressed", remote)
        xml = self.run("exec-out", "cat", remote).decode("utf-8", errors="strict")
        # Android 35's windows section lists visible windows and IME targets,
        # but not mCurrentFocus. DisplayContent owns the authoritative focus.
        window = self.run("shell", "dumpsys", "window", "displays").decode("utf-8", errors="replace")
        return xml, window

    def screenshot(self) -> bytes:
        png = self.run("exec-out", "screencap", "-p")
        image_size(png)
        return png

    def verified_emulator(self) -> bool:
        """Require both an emulator adb serial and Android's qemu property."""
        if re.fullmatch(r"emulator-\d+", self.serial) is None:
            return False
        return self.run("shell", "getprop", "ro.kernel.qemu").decode(
            "ascii", errors="strict"
        ).strip() == "1"

    def cleanup(self) -> None:
        for remote in self.remote_files:
            if not remote.startswith(self.remote_prefix):
                raise RuntimeError("Refusing to remove a non-owned remote file")
            self.run("shell", "rm", "-f", remote)


class NativeRecording:
    """Own a bounded Android screenrecord child, identified by PID and path."""

    def __init__(self, adb: Adb, output: Path, stage: str):
        self.adb = adb
        self.output = output
        self.remote = f"{adb.remote_prefix}{stage}.mp4"
        adb.remote_files.append(self.remote)
        self.process: subprocess.Popen[str] | None = None
        self.pid: str | None = None
        self.lines: list[str] = []

    def start(self) -> None:
        # All interpolated values are internally generated/validated paths.
        command = (
            f"screenrecord --bit-rate 2000000 --time-limit 90 {self.remote} & "
            "record_pid=$!; printf 'RC_RECORDER_PID=%s\\n' \"$record_pid\"; wait \"$record_pid\""
        )
        self.process = subprocess.Popen(
            self.adb.prefix + ["shell", command], stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace",
        )
        pids: queue.Queue[str] = queue.Queue()

        def read_output() -> None:
            assert self.process and self.process.stdout
            for line in self.process.stdout:
                self.lines.append(line)
                match = re.fullmatch(r"RC_RECORDER_PID=(\d+)\s*", line)
                if match:
                    pids.put(match.group(1))

        threading.Thread(target=read_output, daemon=True).start()
        try:
            self.pid = pids.get(timeout=10)
        except queue.Empty as error:
            raise RuntimeError("Could not identify the task-owned screen recorder") from error

    def finish(self) -> None:
        if not self.process:
            return
        try:
            if self.process.poll() is None:
                if not self.pid:
                    raise RuntimeError("Recorder PID missing; refusing broad termination")
                command_line = self.adb.run("exec-out", "cat", f"/proc/{self.pid}/cmdline")
                arguments = command_line.decode("utf-8", errors="strict").split("\x00")
                if arguments[0].rsplit("/", 1)[-1] != "screenrecord" or self.remote not in arguments:
                    raise RuntimeError("Recorder ownership changed; refusing to signal PID")
                self.adb.run("shell", "kill", "-2", self.pid)
            self.process.wait(timeout=15)
            self.adb.run("pull", self.remote, str(self.output), timeout=30)
            data = self.output.read_bytes()
            if len(data) < 1024 or b"ftyp" not in data[:64] or b"moov" not in data:
                raise RuntimeError("Native recording is missing or lacks finalized MP4 metadata")
        finally:
            self.output.with_suffix(".log").write_text("".join(self.lines), encoding="utf-8")
            if self.process.poll() is None:
                # This terminates only our host adb client. An unverified remote
                # PID is never signalled; screenrecord has a 90-second cap.
                self.process.terminate()
                self.process.wait(timeout=5)


class DialogOrchestrator:
    def __init__(self, adb: Adb, artifacts: Path, stage_timeout: float = 65):
        self.adb = adb
        self.artifacts = artifacts
        self.stage_timeout = stage_timeout
        self.completed: list[dict[str, object]] = []
        self.launcher_recoveries = 0
        self.setup_recoveries = 0

    def _recover_emulator_system_anr(self, stage: str, xml: str, window: str) -> bool:
        matches = (
            (
                "launcher",
                LAUNCHER_PACKAGE,
                select_pixel_launcher_anr_close,
                "launcher_recoveries",
            ),
            (
                "setup",
                SETUP_PACKAGE,
                select_google_sdk_setup_anr_close,
                "setup_recoveries",
            ),
        )
        selected = None
        for candidate in matches:
            try:
                candidate[2](xml, window)
            except UnsafeDialog:
                continue
            selected = candidate
            break
        if selected is None:
            return False
        kind, package, selector, counter_name = selected
        if self.launcher_recoveries + self.setup_recoveries >= MAX_SYSTEM_ANR_RECOVERIES:
            raise UnsafeDialog("System ANR recovery limit reached")
        if not self.adb.verified_emulator():
            raise UnsafeDialog("System ANR recovery is emulator-only")

        attempt = getattr(self, counter_name) + 1
        prefix = self.artifacts / f"{stage}-{kind}-recovery-{attempt}"
        png = self.adb.screenshot()
        width, height = image_size(png)
        # Reinspect after capture exactly as purchase taps do. A dialog that
        # changed during evidence collection never receives the recovery tap.
        fresh_xml, fresh_window = self.adb.observe()
        target = selector(fresh_xml, fresh_window)
        if target.bounds[2] > width or target.bounds[3] > height:
            raise UnsafeDialog("System ANR close action lies outside the observed screen")
        prefix.with_suffix(".xml").write_text(fresh_xml, encoding="utf-8")
        Path(f"{prefix}-window.txt").write_text(
            fresh_window, encoding="utf-8"
        )
        prefix.with_suffix(".png").write_bytes(png)
        x, y = target.center
        self.adb.run("shell", "input", "tap", str(x), str(y))
        setattr(self, counter_name, attempt)
        with (self.artifacts / f"{kind}-recovery.log").open(
            "a", encoding="utf-8"
        ) as log:
            log.write(
                f"stage={stage}\tattempt={attempt}\tserial={self.adb.serial}\t"
                f"package={package}\taction=close_app\n"
            )
        time.sleep(0.5)
        Path(f"{prefix}-after.png").write_bytes(self.adb.screenshot())
        return True

    def _recover_pixel_launcher_anr(self, stage: str, xml: str, window: str) -> bool:
        """Compatibility entry point for runtime subclasses using this guard."""
        return self._recover_emulator_system_anr(stage, xml, window)

    def diagnostics(self, name: str) -> None:
        errors = []
        try:
            xml, window = self.adb.observe()
            (self.artifacts / f"{name}.xml").write_text(xml, encoding="utf-8")
            (self.artifacts / f"{name}-window.txt").write_text(window, encoding="utf-8")
        except Exception as error:
            errors.append(str(error))
        try:
            (self.artifacts / f"{name}.png").write_bytes(self.adb.screenshot())
        except Exception as error:
            errors.append(str(error))
        if errors:
            (self.artifacts / f"{name}-diagnostic-errors.txt").write_text("\n".join(errors), encoding="utf-8")

    def perform(self, stage: str) -> None:
        expected = STAGES[len(self.completed)] if len(self.completed) < len(STAGES) else None
        if stage != expected:
            raise UnsafeDialog(f"Unexpected stage {stage!r}; expected {expected!r}")
        recording = NativeRecording(self.adb, self.artifacts / f"{stage}.mp4", stage)
        last_error = "No native dialog observed"
        deadline = time.monotonic() + self.stage_timeout
        try:
            recording.start()
            while time.monotonic() < deadline:
                try:
                    xml, window = self.adb.observe()
                    if self._recover_emulator_system_anr(stage, xml, window):
                        continue
                    select_target(xml, window, stage)
                    png = self.adb.screenshot()
                    width, height = image_size(png)
                    # Reinspect after screenshot/recording work; never tap bounds
                    # that preceded an expensive capture or stale log poll.
                    xml, window = self.adb.observe()
                    if self._recover_emulator_system_anr(stage, xml, window):
                        continue
                    target = select_target(xml, window, stage)
                    if target.bounds[2] > width or target.bounds[3] > height:
                        raise UnsafeDialog("Native button lies outside the observed screen")
                    break
                except (UnsafeDialog, RuntimeError, subprocess.TimeoutExpired) as error:
                    last_error = str(error)
                    time.sleep(0.5)
            else:
                raise UnsafeDialog(f"Timed out observing safe {stage} dialog: {last_error}")

            (self.artifacts / f"{stage}-before.xml").write_text(xml, encoding="utf-8")
            (self.artifacts / f"{stage}-window.txt").write_text(window, encoding="utf-8")
            (self.artifacts / f"{stage}-before.png").write_bytes(png)
            x, y = target.center
            self.adb.run("shell", "input", "tap", str(x), str(y))
            self.completed.append({"stage": stage, "label": target.label, "bounds": target.bounds})
            time.sleep(0.8)
            (self.artifacts / f"{stage}-after.png").write_bytes(self.adb.screenshot())
        except Exception:
            self.diagnostics(f"{stage}-failure")
            raise
        finally:
            recording.finish()
