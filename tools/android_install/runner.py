#!/usr/bin/env python3
"""Install and launch the normal MeowWatch Android application entrypoint."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import shutil
import subprocess
import threading
import time
from typing import Any, Sequence
import xml.etree.ElementTree as ET


PACKAGE = "com.meowwatch.meowwatch_mobile"
ACTIVITY = f"{PACKAGE}/.MainActivity"
SETUP_PACKAGE = "com.google.android.googlesdksetup"
ARTIFACT_ROOT = Path("build/android-install-artifacts")
_SERIAL = re.compile(r"^emulator-[0-9]+$")
_PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
_CONTENT_URI = re.compile(r"content://[^\s'\"<>]+", re.IGNORECASE)
_SENSITIVE_LOG = re.compile(
    r"(?i)\b(token|password|secret|private[_-]?key|authorization|api[_-]?key)"
    r"(?:['\"])?\s*[:=]\s*[^\s,;]+"
)
_FATAL_LOG = re.compile(
    r"FATAL EXCEPTION|Fatal signal|AndroidRuntime|Unhandled Exception|Process .* has died",
    re.IGNORECASE,
)
_BUILD_MODES = ("debug", "release")


class RuntimeFailure(RuntimeError):
    """The native install or first-launch proof did not satisfy the gate."""


def redact_log(value: str) -> str:
    value = _CONTENT_URI.sub("[REDACTED_CONTENT_URI]", value)
    return _SENSITIVE_LOG.sub(r"\1=[REDACTED]", value)


def install_command(serial: str, apk: Path) -> list[str]:
    if not _SERIAL.fullmatch(serial):
        raise ValueError("serial must explicitly name an Android emulator")
    return ["adb", "-s", serial, "install", "-t", str(apk)]


def install_output_succeeded(output: str) -> bool:
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    return bool(lines) and lines[-1] == "Success"


def launch_output_succeeded(output: str) -> bool:
    status_ok = re.search(r"(?m)^Status:\s+ok\s*$", output) is not None
    component = re.search(
        rf"\b{re.escape(PACKAGE)}/(?:\.MainActivity|{re.escape(PACKAGE)}\.MainActivity)\b",
        output,
    )
    return status_ok and component is not None


def launch_output_timed_out(output: str) -> bool:
    """AM's draw wait can expire while the requested activity is still starting."""
    statuses = re.findall(r"(?m)^Status:[ \t]*([^\r\n]+)", output)
    activities = re.findall(r"(?m)^Activity:[ \t]*([^\r\n]+)", output)
    return (
        [value.strip() for value in statuses] == ["timeout"]
        and len(activities) == 1
        and activities[0].strip() in {
            ACTIVITY, f"{PACKAGE}/{PACKAGE}.MainActivity",
        }
        and re.search(r"(?im)^Error\b", output) is None
    )


def setup_anr_close(xml: str, window_dump: str) -> tuple[int, int] | None:
    """Recognize only the system's Google emulator setup ANR close action."""
    focuses = re.findall(r"mCurrentFocus=([^\r\n]+)", window_dump)
    if len(focuses) != 1 or re.search(
        rf"\bApplication Not Responding: {re.escape(SETUP_PACKAGE)}(?:\s|}})",
        focuses[0],
    ) is None:
        return None
    try:
        root = ET.fromstring(xml)
    except ET.ParseError as error:
        raise RuntimeFailure("Invalid setup ANR accessibility XML") from error
    nodes = [
        node for node in root.iter("node")
        if node.get("package") == "android"
        and node.get("enabled") == "true"
        and node.get("visible-to-user", "true") == "true"
    ]
    titles = [
        node for node in nodes
        if node.get("resource-id") == "android:id/alertTitle"
        and node.get("text") == f"{SETUP_PACKAGE} isn't responding"
    ]
    buttons = [
        node for node in nodes
        if node.get("resource-id") == "android:id/aerr_close"
        and node.get("text") == "Close app"
        and node.get("class") == "android.widget.Button"
        and node.get("clickable") == "true"
    ]
    if len(titles) != 1 or len(buttons) != 1:
        raise RuntimeFailure("Google emulator setup ANR is ambiguous")
    bounds = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", buttons[0].get("bounds", ""))
    if bounds is None:
        raise RuntimeFailure("Google emulator setup close bounds are missing")
    left, top, right, bottom = map(int, bounds.groups())
    if left >= right or top >= bottom:
        raise RuntimeFailure("Google emulator setup close bounds are empty")
    return ((left + right) // 2, (top + bottom) // 2)


def focused_component(window_dump: str) -> str:
    focuses = re.findall(r"mCurrentFocus=([^\r\n]+)", window_dump)
    if len(focuses) != 1:
        raise RuntimeFailure("Android did not report one focused window")
    match = re.search(rf"\b({re.escape(PACKAGE)}/[^\s}}]+)", focuses[0])
    if match is None:
        raise RuntimeFailure("MeowWatch is not the focused Android package")
    return match.group(1)


def verify_onboarding_semantics(xml: str) -> dict[str, bool]:
    """Require exact first-run Flutter semantics from the normal app UI."""
    try:
        root = ET.fromstring(xml)
    except ET.ParseError as error:
        raise RuntimeFailure("Invalid UIAutomator XML") from error
    nodes = [
        node
        for node in root.iter("node")
        if node.get("package") == PACKAGE
        and node.get("visible-to-user", "true") == "true"
        and node.get("enabled", "true") == "true"
    ]

    def exact(value: str) -> list[ET.Element]:
        return [
            node
            for node in nodes
            if value in {node.get("text", ""), node.get("content-desc", "")}
        ]

    title = exact("Close the distance.\nKeep the movie night.")
    privacy = exact("No account needed. Change your name anytime.")
    continue_buttons = [
        node
        for node in exact("Continue")
        if node.get("clickable") == "true"
    ]
    if len(title) != 1 or len(privacy) != 1 or len(continue_buttons) != 1:
        raise RuntimeFailure("Exact first-run onboarding semantics are missing or ambiguous")
    return {
        "heroTitle": True,
        "localPrivacyCopy": True,
        "enabledContinueAction": True,
    }


def parse_package_metadata(dump: str) -> dict[str, Any]:
    version_code = re.search(r"\bversionCode=(\d+)\b", dump)
    version_name = re.search(r"\bversionName=([^\s]+)", dump)
    target_sdk = re.search(r"\btargetSdk=(\d+)\b", dump)
    primary_abi = re.search(r"\bprimaryCpuAbi=([^\s]+)", dump)
    if version_code is None or version_name is None or target_sdk is None:
        raise RuntimeFailure("Installed package version metadata is incomplete")
    abi = None if primary_abi is None or primary_abi.group(1) == "null" else primary_abi.group(1)
    return {
        "versionCode": int(version_code.group(1)),
        "versionName": version_name.group(1),
        "targetSdk": int(target_sdk.group(1)),
        "primaryCpuAbi": abi,
    }


def verify_build_mode(dump: str, expected: str) -> bool:
    if expected not in _BUILD_MODES:
        raise ValueError(f"unsupported build mode: {expected}")
    flag_sets = re.findall(
        r"(?m)^\s*(?:pkgFlags|flags)=\[([^\]]*)\]\s*$", dump
    )
    if not flag_sets:
        raise RuntimeFailure("installed package debuggability metadata is missing")
    debuggable = any("DEBUGGABLE" in flags.split() for flags in flag_sets)
    if debuggable != (expected == "debug"):
        raise RuntimeFailure(
            f"installed package is not the expected {expected} build"
        )
    return debuggable


def artifact_boundary(build_mode: str) -> dict[str, Any]:
    if build_mode == "debug":
        return {
            "buildMode": "debug",
            "debuggable": True,
            "signing": "Android debug key",
            "playProductionSigned": False,
            "revenueCatBackend": "Test Store",
            "revenueCatSdkKeyKind": "public Test Store key",
        }
    if build_mode == "release":
        return {
            "buildMode": "release",
            "debuggable": False,
            "signing": "Android debug key",
            "playProductionSigned": False,
            "revenueCatBackend": "disabled",
            "revenueCatSdkKeyKind": "none",
        }
    raise ValueError(f"unsupported build mode: {build_mode}")


def validate_png(data: bytes) -> None:
    if len(data) < 4096 or not data.startswith(_PNG_SIGNATURE):
        raise RuntimeFailure("Native Android screenshot is missing or invalid")


def validate_mp4(data: bytes) -> None:
    if len(data) < 4096 or b"ftyp" not in data[:64] or b"moov" not in data:
        raise RuntimeFailure("Native Android recording is missing or invalid")


class Adb:
    def __init__(self, serial: str, run_id: str) -> None:
        if not _SERIAL.fullmatch(serial):
            raise ValueError("an explicit Android emulator serial is required")
        if not re.fullmatch(r"[A-Za-z0-9_-]+", run_id):
            raise ValueError("invalid run ID")
        self.serial = serial
        self.prefix = ["adb", "-s", serial]
        self.remote_root = f"/sdcard/meowwatch-install-{run_id}"
        self.remote_prefix = f"{self.remote_root}/"
        self.remote_root_created = False
        self.remote_files: list[str] = []
        self.observation = 0

    def run(
        self,
        *arguments: str,
        timeout: float = 25,
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
            raise RuntimeFailure(f"adb {command} failed with exit {result.returncode}")
        return result

    def screenshot(self) -> bytes:
        value = self.run("exec-out", "screencap", "-p").stdout
        validate_png(value)
        return value

    def observe(self) -> tuple[str, str]:
        self.observation += 1
        remote = f"{self.remote_prefix}ui-{self.observation}.xml"
        self.remote_files.append(remote)
        self.run(
            "shell", "uiautomator", "dump", "--compressed", remote, timeout=10
        )
        xml = self.run(
            "exec-out", "cat", remote, timeout=10
        ).stdout.decode("utf-8", errors="strict")
        window = self.run(
            "shell", "dumpsys", "window", "displays", timeout=10
        ).stdout.decode(
            "utf-8", errors="replace"
        )
        return xml, window

    def cleanup(self) -> None:
        for remote in self.remote_files:
            if not remote.startswith(self.remote_prefix):
                raise RuntimeFailure("refusing to remove a non-owned remote file")
            self.run("shell", "rm", "-f", remote, check=False)
        if self.remote_root_created:
            self.run("shell", "rmdir", self.remote_root, check=False)


class NativeRecording:
    def __init__(self, adb: Adb) -> None:
        self.adb = adb
        self.remote = f"{adb.remote_prefix}first-launch.mp4"
        self.output = ARTIFACT_ROOT / "first-launch.mp4"
        self.process: subprocess.Popen[str] | None = None
        self.pid: str | None = None
        self.lines: list[str] = []
        self.reader: threading.Thread | None = None

    def start(self) -> None:
        existing = self.adb.run(
            "shell", "pidof", "screenrecord", check=False
        ).stdout.decode().strip()
        if existing:
            raise RuntimeFailure("refusing to interfere with an existing Android screen recorder")
        self.adb.remote_files.append(self.remote)
        command = (
            f"screenrecord --bit-rate 3000000 --time-limit 90 {self.remote} & "
            "record_pid=$!; printf 'INSTALL_RECORDER_PID=%s\\n' \"$record_pid\"; "
            "wait \"$record_pid\""
        )
        self.process = subprocess.Popen(
            self.adb.prefix + ["shell", command],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        observed: queue.Queue[str] = queue.Queue()

        def read_output() -> None:
            assert self.process is not None and self.process.stdout is not None
            for line in self.process.stdout:
                self.lines.append(redact_log(line))
                match = re.fullmatch(r"INSTALL_RECORDER_PID=(\d+)\s*", line)
                if match:
                    observed.put(match.group(1))

        self.reader = threading.Thread(target=read_output, daemon=True)
        self.reader.start()
        try:
            self.pid = observed.get(timeout=10)
        except queue.Empty as error:
            raise RuntimeFailure("could not identify the task-owned screen recorder") from error

    def finish(self) -> None:
        if self.process is None:
            return
        try:
            if self.process.poll() is None:
                if self.pid is None:
                    raise RuntimeFailure("screen recorder PID is missing")
                command_line = self.adb.run(
                    "exec-out", "cat", f"/proc/{self.pid}/cmdline"
                ).stdout.decode("utf-8", errors="strict")
                arguments = command_line.split("\x00")
                if (
                    arguments[0].rsplit("/", 1)[-1] != "screenrecord"
                    or self.remote not in arguments
                ):
                    raise RuntimeFailure("screen recorder ownership changed")
                self.adb.run("shell", "kill", "-2", self.pid)
            self.process.wait(timeout=20)
            if self.reader is not None:
                self.reader.join(timeout=10)
                if self.reader.is_alive():
                    raise RuntimeFailure("screen recorder output reader did not finish")
            self.adb.run("pull", self.remote, str(self.output), timeout=40)
            validate_mp4(self.output.read_bytes())
        finally:
            (ARTIFACT_ROOT / "screenrecord.log").write_text(
                "".join(self.lines), encoding="utf-8"
            )
            if self.process.poll() is None:
                self.process.terminate()
                self.process.wait(timeout=5)
            if self.process.stdout is not None:
                self.process.stdout.close()


class Runner:
    def __init__(self, serial: str, apk: Path, build_mode: str) -> None:
        if not _SERIAL.fullmatch(serial):
            raise ValueError("--serial must explicitly name an Android emulator")
        if not apk.is_file():
            raise ValueError(f"APK does not exist: {apk}")
        if build_mode not in _BUILD_MODES:
            raise ValueError(f"unsupported build mode: {build_mode}")
        self.apk = apk.resolve()
        self.build_mode = build_mode
        self.adb = Adb(serial, f"runtime-{os.getpid()}")
        self.installed_pid: int | None = None
        self.cleanup_authorized = False

    def recover_setup_anr(self) -> bool:
        # This fixture owns a disposable emulator, never a user's phone. An
        # application ANR or any other system dialog must still fail the gate.
        if self.adb.run("shell", "getprop", "ro.kernel.qemu").stdout.decode().strip() != "1":
            raise RuntimeFailure("setup ANR recovery is emulator-only")
        xml, window = self.adb.observe()
        if setup_anr_close(xml, window) is None:
            return False
        (ARTIFACT_ROOT / "setup-anr.xml").write_text(xml, encoding="utf-8")
        (ARTIFACT_ROOT / "setup-anr-window.txt").write_text(window, encoding="utf-8")
        (ARTIFACT_ROOT / "setup-anr.png").write_bytes(self.adb.screenshot())
        fresh_xml, fresh_window = self.adb.observe()
        point = setup_anr_close(fresh_xml, fresh_window)
        if point is None:
            raise RuntimeFailure("setup ANR changed before the close action")
        self.adb.run("shell", "input", "tap", str(point[0]), str(point[1]))
        return True

    def launch(self) -> dict[str, Any]:
        recovered = False
        for attempt in (1, 2):
            try:
                result = self.adb.run(
                    "shell", "am", "start", "-W", "-n", ACTIVITY,
                    timeout=30, check=False,
                )
                output = (result.stdout + result.stderr).decode("utf-8", errors="replace")
                accepted = result.returncode == 0 and launch_output_succeeded(output)
                draw_wait_expired = result.returncode == 0 and launch_output_timed_out(output)
            except subprocess.TimeoutExpired:
                output = "ActivityManager launch exceeded its 30-second timeout.\n"
                accepted = False
                draw_wait_expired = False
            (ARTIFACT_ROOT / f"launch-{attempt}.txt").write_text(
                redact_log(output), encoding="utf-8",
            )
            if accepted:
                return {"attempts": attempt, "googleSetupAnrRecovered": recovered}
            if attempt == 1 and self.recover_setup_anr():
                recovered = True
                continue
            if draw_wait_expired:
                _, window = self.adb.observe()
                if focused_component(window) not in {
                    ACTIVITY, f"{PACKAGE}/{PACKAGE}.MainActivity",
                }:
                    raise RuntimeFailure("Timed-out launch did not focus MainActivity")
                # This is not a pass: run() must still observe exact onboarding,
                # a stable live process and clean app logs within its 55s budget.
                return {
                    "attempts": attempt,
                    "googleSetupAnrRecovered": recovered,
                    "activityManagerWaitTimedOut": True,
                }
            raise RuntimeFailure("ActivityManager did not confirm the normal MainActivity launch")
        raise AssertionError("launch attempts exhausted")

    def prepare(self) -> dict[str, Any]:
        if shutil.which("adb") is None:
            raise RuntimeFailure("required tool is unavailable: adb")
        if ARTIFACT_ROOT.exists() and any(ARTIFACT_ROOT.iterdir()):
            raise RuntimeFailure(f"artifact directory must start empty: {ARTIFACT_ROOT}")
        ARTIFACT_ROOT.mkdir(parents=True, exist_ok=True)
        state = self.adb.run("get-state").stdout.decode().strip()
        qemu = self.adb.run("shell", "getprop", "ro.kernel.qemu").stdout.decode().strip()
        if state != "device" or qemu != "1":
            raise RuntimeFailure("selected adb serial is not a ready Android emulator")
        self.cleanup_authorized = True
        remote_exists = self.adb.run(
            "shell", "test", "-e", self.adb.remote_root, check=False
        )
        if remote_exists.returncode == 0:
            raise RuntimeFailure("task-owned Android evidence directory already exists")
        self.adb.run("shell", "mkdir", self.adb.remote_root)
        self.adb.remote_root_created = True

        installed = self.adb.run(
            "shell", "pm", "path", PACKAGE, check=False
        ).stdout.decode().strip()
        if installed:
            uninstall = self.adb.run("uninstall", PACKAGE, timeout=60).stdout.decode().strip()
            if uninstall != "Success":
                raise RuntimeFailure("could not uninstall the pre-existing application")
        if self.adb.run(
            "shell", "pm", "path", PACKAGE, check=False
        ).stdout.decode().strip():
            raise RuntimeFailure("package remained installed before the clean-install check")

        install = subprocess.run(
            install_command(self.adb.serial, self.apk),
            capture_output=True,
            timeout=120,
            check=False,
        )
        if install.returncode != 0 or not install_output_succeeded(
            install.stdout.decode("utf-8", errors="replace")
        ):
            raise RuntimeFailure(f"adb install failed with exit {install.returncode}")
        package_path = self.adb.run(
            "shell", "pm", "path", PACKAGE
        ).stdout.decode().strip()
        if not package_path.startswith("package:"):
            raise RuntimeFailure("installed package path is unavailable")
        return {
            "preExistingPackageRemoved": bool(installed),
            "installSucceeded": True,
        }

    def run(self) -> None:
        recorder: NativeRecording | None = None
        recorder_finish_attempted = False
        semantics: dict[str, bool] | None = None
        focus = ""
        try:
            install_evidence = self.prepare()
            self.adb.run("logcat", "-c")
            recorder = NativeRecording(self.adb)
            recorder.start()
            launch_evidence = self.launch()
            deadline = time.monotonic() + 55
            last_error = "normal first-run UI was not observed"
            while time.monotonic() < deadline:
                try:
                    pid_text = self.adb.run(
                        "shell", "pidof", PACKAGE, check=False
                    ).stdout.decode().strip()
                    pids = pid_text.split()
                    if len(pids) != 1 or not pids[0].isdigit():
                        raise RuntimeFailure("expected one live MeowWatch process")
                    xml, window = self.adb.observe()
                    focus = focused_component(window)
                    semantics = verify_onboarding_semantics(xml)
                    self.installed_pid = int(pids[0])
                    break
                except RuntimeFailure as error:
                    last_error = str(error)
                    time.sleep(0.4)
            if self.installed_pid is None or semantics is None:
                raise RuntimeFailure(f"timed out waiting for first Flutter UI: {last_error}")

            package_dump = self.adb.run(
                "shell", "dumpsys", "package", PACKAGE
            ).stdout.decode("utf-8", errors="replace")
            if f"Package [{PACKAGE}]" not in package_dump:
                raise RuntimeFailure("dumpsys returned metadata for the wrong package")
            metadata = parse_package_metadata(package_dump)
            debuggable = verify_build_mode(package_dump, self.build_mode)
            device_abi = self.adb.run(
                "shell", "getprop", "ro.product.cpu.abi"
            ).stdout.decode().strip()
            if not device_abi:
                raise RuntimeFailure("Android did not report its runtime ABI")

            app_log = self.adb.run(
                "logcat",
                "-d",
                "--pid",
                str(self.installed_pid),
                "-v",
                "threadtime",
            ).stdout.decode("utf-8", errors="replace")
            flutter_frame_log = bool(
                re.search(
                    r"Flutter.*first frame|Displayed .*MainActivity",
                    app_log,
                    re.IGNORECASE,
                )
            )
            fatal_lines = [
                redact_log(line)
                for line in app_log.splitlines()
                if _FATAL_LOG.search(line)
            ]
            (ARTIFACT_ROOT / "logcat-fatals.txt").write_text(
                "\n".join(fatal_lines) + ("\n" if fatal_lines else ""),
                encoding="utf-8",
            )
            if fatal_lines:
                raise RuntimeFailure("fatal app-process logcat entries were observed")

            (ARTIFACT_ROOT / "first-launch.png").write_bytes(self.adb.screenshot())
            time.sleep(2)
            pid_text = self.adb.run(
                "shell", "pidof", PACKAGE, check=False
            ).stdout.decode().strip()
            if pid_text != str(self.installed_pid):
                raise RuntimeFailure("MeowWatch process did not remain stable after first launch")
            final_xml, final_window = self.adb.observe()
            focus = focused_component(final_window)
            semantics = verify_onboarding_semantics(final_xml)

            recorder_finish_attempted = True
            recorder.finish()
            summary = {
                "runtime": {
                    "androidApi": self.adb.run(
                        "shell", "getprop", "ro.build.version.sdk"
                    ).stdout.decode().strip(),
                    "actualAbi": device_abi,
                    "model": self.adb.run(
                        "shell", "getprop", "ro.product.model"
                    ).stdout.decode().strip(),
                    "emulator": True,
                    "physicalDevice": False,
                },
                "application": {
                    "package": PACKAGE,
                    "activity": ACTIVITY,
                    "pid": self.installed_pid,
                    "focusedComponent": focus,
                    "debuggable": debuggable,
                    **metadata,
                },
                "install": install_evidence,
                "launch": launch_evidence,
                "firstRun": {
                    "normalLibMainEntrypoint": True,
                    "uiautomatorOnboardingSemantics": semantics,
                    "flutterFirstFrameLogObserved": flutter_frame_log,
                    "nativeScreenshotCaptured": True,
                    "nativeRecordingCaptured": True,
                    "fatalAppLogLines": 0,
                },
                "artifactBoundary": artifact_boundary(self.build_mode),
                "apkSha256": hashlib.sha256(self.apk.read_bytes()).hexdigest(),
            }
            (ARTIFACT_ROOT / "summary.json").write_text(
                json.dumps(summary, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )
        except BaseException:
            try:
                (ARTIFACT_ROOT / "failure.png").write_bytes(self.adb.screenshot())
            except BaseException:
                pass
            try:
                diagnostic_log = self.adb.run(
                    "logcat", "-d", "-v", "threadtime", check=False
                ).stdout.decode("utf-8", errors="replace")
                diagnostic_fatals = [
                    redact_log(line)
                    for line in diagnostic_log.splitlines()
                    if _FATAL_LOG.search(line)
                ]
                (ARTIFACT_ROOT / "logcat-fatals.txt").write_text(
                    "\n".join(diagnostic_fatals)
                    + ("\n" if diagnostic_fatals else ""),
                    encoding="utf-8",
                )
            except BaseException:
                pass
            raise
        finally:
            try:
                if recorder is not None and not recorder_finish_attempted:
                    recorder.finish()
            finally:
                self.cleanup()

    def cleanup(self) -> None:
        if self.cleanup_authorized:
            self.adb.run("shell", "am", "force-stop", PACKAGE, check=False)
        self.adb.cleanup()


def parse_args(arguments: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--serial", required=True)
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--build-mode", required=True, choices=_BUILD_MODES)
    return parser.parse_args(arguments)


def main(arguments: Sequence[str] | None = None) -> int:
    args = parse_args(arguments)
    Runner(args.serial, args.apk, args.build_mode).run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
