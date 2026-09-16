#!/usr/bin/env python3
"""Run real SAF selection and retained-access checks in two app processes."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import queue
import re
import shutil
import subprocess
import sys
import threading
import time
from typing import Any, Sequence

from tools.local_file_runtime.picker import Adb, DocumentsUiSelector


PACKAGE = "com.meowwatch.meowwatch_mobile"
DRIVER = "test_driver/local_file_relaunch_driver.dart"
TARGET = "integration_test/local_file_relaunch_test.dart"
ARTIFACT_ROOT = Path("build/local-file-runtime-artifacts")
FIXTURE_NAME = "meowwatch-saf-fixture.mp4"
REMOTE_FIXTURE = f"/sdcard/Download/{FIXTURE_NAME}"
_SERIAL = re.compile(r"^emulator-[0-9]+$")
_CONTENT_URI = re.compile(r"content://[^\s'\"<>]+", re.IGNORECASE)
_FORBIDDEN_KEYS = {
    "uri",
    "url",
    "path",
    "token",
    "tokenid",
    "secret",
    "password",
    "authorization",
    "apikey",
}
_DRIVE_TIMEOUT_SECONDS = 330


def drive_command(serial: str, apk: Path, stage: int) -> list[str]:
    if not _SERIAL.fullmatch(serial):
        raise ValueError("serial must explicitly name an Android emulator")
    if stage not in (1, 2):
        raise ValueError("stage must be 1 or 2")
    return [
        "flutter",
        "drive",
        "--no-pub",
        f"--driver={DRIVER}",
        f"--target={TARGET}",
        f"--use-application-binary={apk}",
        "--keep-app-running",
        "--timeout=300",
        f"--host-vmservice-port={39500 + stage}",
        "-d",
        serial,
    ]


def redact_log(line: str) -> str:
    redacted = _CONTENT_URI.sub("[REDACTED_CONTENT_URI]", line)
    return re.sub(
        r"(?i)\b(token|password|secret|private[_-]?key|authorization|api[_-]?key)"
        r"(?:['\"])?\s*[:=]\s*[^\s,;]+",
        r"\1=[REDACTED]",
        redacted,
    )


def _reject_sensitive(value: Any) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            normalized = str(key).replace("_", "").lower()
            if normalized in _FORBIDDEN_KEYS:
                raise ValueError(f"sensitive evidence key is forbidden: {key}")
            _reject_sensitive(child)
    elif isinstance(value, list):
        for child in value:
            _reject_sensitive(child)
    elif isinstance(value, str) and _CONTENT_URI.search(value):
        raise ValueError("content URI is forbidden in runtime evidence")


def validate_result(value: Any, stage: int) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError("driver result must be an object")
    runtime = value.get("localFileRuntime")
    if not isinstance(runtime, dict):
        raise ValueError("driver result has no localFileRuntime object")
    if runtime.get("stage") != stage or runtime.get("completed") is not True:
        raise ValueError("driver result stage is incomplete or mismatched")
    _reject_sensitive(value)
    return runtime


def wait_for_owned_process(
    process: subprocess.Popen[str],
    log: Any,
    timeout: float = _DRIVE_TIMEOUT_SECONDS,
) -> int:
    """Stream output while bounding the runner-owned flutter process."""
    read_errors: list[BaseException] = []

    def stream_output() -> None:
        try:
            assert process.stdout is not None
            for raw in process.stdout:
                line = redact_log(raw)
                sys.stdout.write(line)
                log.write(line)
                log.flush()
        except BaseException as error:
            read_errors.append(error)

    reader = threading.Thread(target=stream_output, daemon=True)
    reader.start()
    try:
        exit_code = process.wait(timeout=timeout)
    except subprocess.TimeoutExpired as error:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=10)
        raise RuntimeError(
            f"flutter drive exceeded the {timeout:g}-second wall timeout"
        ) from error
    finally:
        reader.join(timeout=10)
        if process.stdout is not None:
            process.stdout.close()
        reader.join(timeout=1)
    if reader.is_alive():
        raise RuntimeError("flutter drive output reader did not finish")
    if read_errors:
        raise RuntimeError("could not capture flutter drive output") from read_errors[0]
    return exit_code


class NativeRecording:
    def __init__(self, adb: Adb, stage: int) -> None:
        self.adb = adb
        self.stage = stage
        self.remote = f"{adb.remote_prefix}stage-{stage}.mp4"
        self.output = ARTIFACT_ROOT / "native" / f"stage-{stage}.mp4"
        self.process: subprocess.Popen[str] | None = None
        self.pid: str | None = None
        self.lines: list[str] = []

    def start(self) -> None:
        self.output.parent.mkdir(parents=True, exist_ok=True)
        self.adb.remote_files.append(self.remote)
        command = (
            f"screenrecord --bit-rate 2500000 --time-limit 180 {self.remote} & "
            "record_pid=$!; printf 'SAF_RECORDER_PID=%s\\n' \"$record_pid\"; "
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
            assert self.process and self.process.stdout
            for line in self.process.stdout:
                self.lines.append(redact_log(line))
                match = re.fullmatch(r"SAF_RECORDER_PID=(\d+)\s*", line)
                if match:
                    observed.put(match.group(1))

        threading.Thread(target=read_output, daemon=True).start()
        try:
            self.pid = observed.get(timeout=10)
        except queue.Empty as error:
            raise RuntimeError("could not identify the task-owned screen recorder") from error

    def finish(self) -> None:
        if not self.process:
            return
        try:
            if self.process.poll() is None:
                if not self.pid:
                    raise RuntimeError("recorder PID missing")
                command_line = self.adb.run("exec-out", "cat", f"/proc/{self.pid}/cmdline").stdout
                arguments = command_line.decode("utf-8", errors="strict").split("\x00")
                if arguments[0].rsplit("/", 1)[-1] != "screenrecord" or self.remote not in arguments:
                    raise RuntimeError("screen recorder ownership changed")
                self.adb.run("shell", "kill", "-2", self.pid)
            self.process.wait(timeout=20)
            self.adb.run("pull", self.remote, str(self.output), timeout=40)
            data = self.output.read_bytes()
            if len(data) < 4096 or b"ftyp" not in data[:64] or b"moov" not in data:
                raise RuntimeError("native screen recording is incomplete")
        finally:
            self.output.with_suffix(".log").write_text("".join(self.lines), encoding="utf-8")
            if self.process.poll() is None:
                self.process.terminate()
                self.process.wait(timeout=5)


class Runner:
    def __init__(self, serial: str, apk: Path, fixture: Path) -> None:
        if not _SERIAL.fullmatch(serial):
            raise ValueError("--serial must explicitly name an Android emulator")
        if not apk.is_file():
            raise ValueError(f"APK does not exist: {apk}")
        if not fixture.is_file():
            raise ValueError(f"fixture does not exist: {fixture}")
        self.serial = serial
        self.apk = apk.resolve()
        self.fixture = fixture.resolve()
        self.adb = Adb(serial, f"runtime-{os.getpid()}")
        self.rows: list[dict[str, Any]] = []

    def prepare(self) -> None:
        for tool in ("adb", "flutter"):
            if shutil.which(tool) is None:
                raise RuntimeError(f"required tool is unavailable: {tool}")
        if self.adb.run("get-state").stdout.decode().strip() != "device":
            raise RuntimeError("selected emulator is unavailable")
        if self.adb.run("shell", "getprop", "ro.kernel.qemu").stdout.decode().strip() != "1":
            raise RuntimeError("selected serial is not an Android emulator")
        if ARTIFACT_ROOT.exists() and any(ARTIFACT_ROOT.iterdir()):
            raise RuntimeError(f"artifact directory must start empty: {ARTIFACT_ROOT}")
        (ARTIFACT_ROOT / "native").mkdir(parents=True, exist_ok=True)
        self.adb.run("install", "-t", "-r", str(self.apk), timeout=120)
        self.adb.run("shell", "am", "force-stop", PACKAGE)
        if self.adb.run("shell", "pm", "clear", PACKAGE).stdout.decode().strip() != "Success":
            raise RuntimeError("pm clear failed")
        self.adb.run("shell", "mkdir", "-p", "/sdcard/Download")
        self.adb.run("shell", "rm", "-f", REMOTE_FIXTURE)
        self.adb.run("push", str(self.fixture), REMOTE_FIXTURE, timeout=120)
        self.adb.run(
            "shell",
            "am",
            "broadcast",
            "-a",
            "android.intent.action.MEDIA_SCANNER_SCAN_FILE",
            "-d",
            f"file://{REMOTE_FIXTURE}",
            check=False,
        )
        self._require_installed()

    def run_stage(self, stage: int) -> None:
        stage_dir = ARTIFACT_ROOT / f"stage-{stage}"
        stage_dir.mkdir(parents=True, exist_ok=True)
        recording = NativeRecording(self.adb, stage)
        selector: DocumentsUiSelector | None = None
        picker_error: list[BaseException] = []
        picker_thread: threading.Thread | None = None
        picker_stop = threading.Event()
        if stage == 1:
            selector = DocumentsUiSelector(
                self.adb,
                ARTIFACT_ROOT / "native",
                FIXTURE_NAME,
                stop_event=picker_stop,
            )

            def select_fixture() -> None:
                try:
                    assert selector is not None
                    selector.select()
                except BaseException as error:
                    picker_error.append(error)

            picker_thread = threading.Thread(target=select_fixture, daemon=True)

        environment = os.environ.copy()
        environment["LOCAL_FILE_RUNTIME_STAGE"] = str(stage)
        command = drive_command(self.serial, self.apk, stage)
        exit_code = -1
        try:
            recording.start()
            if picker_thread:
                picker_thread.start()
            with (stage_dir / "flutter-drive.log").open("w", encoding="utf-8", newline="\n") as log:
                process = subprocess.Popen(
                    command,
                    env=environment,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    errors="replace",
                )
                exit_code = wait_for_owned_process(process, log)
            if picker_thread:
                picker_thread.join(timeout=5)
                if picker_thread.is_alive():
                    raise RuntimeError("DocumentsUI selector did not finish")
                if picker_error:
                    raise RuntimeError(str(picker_error[0]))
                if not selector or not selector.selected:
                    raise RuntimeError("DocumentsUI fixture selection was not recorded")
            self._require_installed()
            if exit_code != 0:
                raise RuntimeError(f"flutter drive stage {stage} failed: {exit_code}")
            pid = self._single_pid()
            result_path = stage_dir / "result.json"
            if not result_path.is_file():
                raise RuntimeError(f"stage {stage} result.json is missing")
            validate_result(json.loads(result_path.read_text(encoding="utf-8")), stage)
            (ARTIFACT_ROOT / "native" / f"stage-{stage}-final.png").write_bytes(
                self.adb.screenshot()
            )
        except BaseException:
            try:
                (ARTIFACT_ROOT / "native" / f"stage-{stage}-failure.png").write_bytes(
                    self.adb.screenshot()
                )
            except BaseException:
                pass
            raise
        finally:
            picker_stop.set()
            if picker_thread and picker_thread.is_alive():
                picker_thread.join(timeout=25)
            recording.finish()
        self._force_stop(pid)
        self._require_installed()
        self.rows.append(
            {
                "stage": stage,
                "pid": pid,
                "flutterDriveExit": exit_code,
                "processStopped": True,
                "packageRetained": True,
                "documentsUiFixtureSelected": stage != 1 or bool(selector and selector.selected),
            }
        )

    def _single_pid(self) -> int:
        output = self.adb.run("shell", "pidof", PACKAGE, check=False).stdout.decode().strip()
        parts = output.split()
        if len(parts) != 1 or not parts[0].isdigit():
            raise RuntimeError(f"expected one running app process, observed {len(parts)}")
        return int(parts[0])

    def _force_stop(self, pid: int) -> None:
        self.adb.run("shell", "am", "force-stop", PACKAGE)
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            output = self.adb.run("shell", "pidof", PACKAGE, check=False).stdout.decode().strip()
            if not output:
                return
            if str(pid) not in output.split():
                raise RuntimeError("app process changed before force-stop completed")
            time.sleep(0.25)
        raise RuntimeError("owned app process survived force-stop")

    def _require_installed(self) -> None:
        output = self.adb.run("shell", "pm", "path", PACKAGE).stdout.decode().strip()
        if not output.startswith("package:"):
            raise RuntimeError("test package is not installed; retained data is lost")

    def summary(self) -> None:
        payload = {
            "runtime": {
                "apiLevel": self.adb.run("shell", "getprop", "ro.build.version.sdk").stdout.decode().strip(),
                "abi": self.adb.run("shell", "getprop", "ro.product.cpu.abi").stdout.decode().strip(),
                "model": self.adb.run("shell", "getprop", "ro.product.model").stdout.decode().strip(),
                "emulator": True,
            },
            "package": PACKAGE,
            "fixtureName": FIXTURE_NAME,
            "replacementInstallRetainedAppData": len(self.rows) == 2,
            "uninstallBetweenStages": False,
            "processRuns": self.rows,
            "evidenceBoundary": {
                "physicalDevice": False,
                "actualDocumentsUi": True,
                "actualContentUriValueReported": False,
                "fixtureBytesAreReviewedCc0Media": True,
            },
        }
        _reject_sensitive(payload)
        (ARTIFACT_ROOT / "runner-summary.json").write_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )

    def cleanup(self) -> None:
        self.adb.run("shell", "am", "force-stop", PACKAGE, check=False)
        self.adb.run("shell", "rm", "-f", REMOTE_FIXTURE, check=False)
        self.adb.cleanup()


def parse_args(arguments: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--serial", required=True)
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--fixture", required=True, type=Path)
    return parser.parse_args(arguments)


def main(arguments: Sequence[str] | None = None) -> int:
    args = parse_args(arguments)
    runner = Runner(args.serial, args.apk, args.fixture)
    prepared = False
    try:
        runner.prepare()
        prepared = True
        for stage in (1, 2):
            runner.run_stage(stage)
        runner.summary()
        return 0
    finally:
        if prepared:
            runner.cleanup()


if __name__ == "__main__":
    raise SystemExit(main())
