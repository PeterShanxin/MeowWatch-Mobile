#!/usr/bin/env python3
"""Run the Nearby platform integration target in three retained app processes."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from typing import Any, Sequence


PACKAGE = "com.meowwatch.meowwatch_mobile"
DRIVER = "test_driver/nearby_platform_driver.dart"
TARGET = "integration_test/nearby_platform_smoke_test.dart"
ARTIFACT_ROOT = Path("build/nearby-runtime-artifacts")
_SERIAL = re.compile(r"^emulator-[0-9]+$")
_FORBIDDEN_EVIDENCE_KEYS = {
    "secret",
    "token",
    "tokenid",
    "privatekey",
    "privatekeypem",
    "certificatepem",
}


def drive_command(serial: str, apk: Path, stage: int) -> list[str]:
    if not _SERIAL.fullmatch(serial):
        raise ValueError("serial must explicitly name an Android emulator")
    if stage not in (1, 2, 3):
        raise ValueError("stage must be 1, 2 or 3")
    return [
        "flutter",
        "drive",
        "--no-pub",
        f"--driver={DRIVER}",
        f"--target={TARGET}",
        f"--use-application-binary={apk}",
        "--keep-app-running",
        f"--host-vmservice-port={39400 + stage}",
        "-d",
        serial,
    ]


def validate_result(value: Any, stage: int) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError("driver result must be an object")
    nearby = value.get("nearbyRuntime")
    if not isinstance(nearby, dict):
        raise ValueError("driver result has no nearbyRuntime object")
    if nearby.get("stage") != stage or nearby.get("completed") is not True:
        raise ValueError("driver result stage is incomplete or mismatched")
    _reject_sensitive_evidence(nearby)
    return nearby


def _reject_sensitive_evidence(value: Any) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            normalized = str(key).replace("_", "").lower()
            if normalized in _FORBIDDEN_EVIDENCE_KEYS:
                raise ValueError(f"sensitive evidence key is forbidden: {key}")
            _reject_sensitive_evidence(child)
    elif isinstance(value, list):
        for child in value:
            _reject_sensitive_evidence(child)
    elif isinstance(value, str) and "BEGIN PRIVATE KEY" in value:
        raise ValueError("private key material is forbidden in evidence")


class Runner:
    def __init__(self, serial: str, apk: Path) -> None:
        if not _SERIAL.fullmatch(serial):
            raise ValueError("--serial must explicitly name an Android emulator")
        if not apk.is_file():
            raise ValueError(f"APK does not exist: {apk}")
        self.serial = serial
        self.apk = apk.resolve()
        self.stage_rows: list[dict[str, Any]] = []

    def adb(self, *arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["adb", "-s", self.serial, *arguments],
            check=check,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )

    def prepare(self) -> None:
        for tool in ("adb", "flutter"):
            if shutil.which(tool) is None:
                raise RuntimeError(f"required tool is unavailable: {tool}")
        if self.adb("get-state").stdout.strip() != "device":
            raise RuntimeError("selected emulator is unavailable")
        if self.adb("shell", "getprop", "ro.kernel.qemu").stdout.strip() != "1":
            raise RuntimeError("selected serial is not an Android emulator")
        if ARTIFACT_ROOT.exists() and any(ARTIFACT_ROOT.iterdir()):
            raise RuntimeError(f"artifact directory must start empty: {ARTIFACT_ROOT}")
        ARTIFACT_ROOT.mkdir(parents=True, exist_ok=True)
        self.adb("install", "-t", "-r", str(self.apk))
        self.adb("shell", "am", "force-stop", PACKAGE)
        cleared = self.adb("shell", "pm", "clear", PACKAGE).stdout.strip()
        if cleared != "Success":
            raise RuntimeError(f"pm clear failed: {cleared}")
        self._require_installed()

    def run_stage(self, stage: int) -> None:
        stage_dir = ARTIFACT_ROOT / f"stage-{stage}"
        stage_dir.mkdir(parents=True, exist_ok=True)
        log_path = stage_dir / "flutter-drive.log"
        environment = os.environ.copy()
        environment["NEARBY_RUNTIME_STAGE"] = str(stage)
        command = drive_command(self.serial, self.apk, stage)
        with log_path.open("w", encoding="utf-8", newline="\n") as log:
            process = subprocess.Popen(
                command,
                env=environment,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                errors="replace",
            )
            assert process.stdout is not None
            for line in process.stdout:
                sys.stdout.write(line)
                log.write(line)
            exit_code = process.wait()
        self._require_installed()
        result_path = stage_dir / "result.json"
        if exit_code != 0:
            pid = self._running_pid()
            if pid is not None:
                self._force_stop(pid)
            raise RuntimeError(f"flutter drive stage {stage} failed: {exit_code}")
        pid = self._single_pid()
        if not result_path.is_file():
            self._force_stop(pid)
            raise RuntimeError(f"stage {stage} result.json is missing")
        result = json.loads(result_path.read_text(encoding="utf-8"))
        validate_result(result, stage)
        self._force_stop(pid)
        self._require_installed()
        self.stage_rows.append(
            {
                "stage": stage,
                "pid": pid,
                "flutterDriveExit": exit_code,
                "processStarted": True,
                "processStopped": True,
                "packageRetained": True,
            }
        )

    def _single_pid(self) -> int:
        output = self.adb("shell", "pidof", PACKAGE, check=False).stdout.strip()
        parts = output.split()
        if len(parts) != 1 or not parts[0].isdigit():
            raise RuntimeError(f"expected one running app process, observed: {output!r}")
        return int(parts[0])

    def _running_pid(self) -> int | None:
        output = self.adb("shell", "pidof", PACKAGE, check=False).stdout.strip()
        parts = output.split()
        if not parts:
            return None
        if len(parts) != 1 or not parts[0].isdigit():
            raise RuntimeError(f"expected at most one app process, observed: {output!r}")
        return int(parts[0])

    def _force_stop(self, pid: int) -> None:
        self.adb("shell", "am", "force-stop", PACKAGE)
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            output = self.adb("shell", "pidof", PACKAGE, check=False).stdout.strip()
            if not output:
                return
            if str(pid) not in output.split():
                raise RuntimeError("app process changed before force-stop completed")
            time.sleep(0.25)
        raise RuntimeError(f"app process {pid} survived force-stop")

    def _require_installed(self) -> None:
        output = self.adb("shell", "pm", "path", PACKAGE).stdout.strip()
        if not output.startswith("package:"):
            raise RuntimeError("test package is not installed; app data continuity is lost")

    def write_summary(self) -> None:
        properties = {
            "apiLevel": self.adb("shell", "getprop", "ro.build.version.sdk").stdout.strip(),
            "abi": self.adb("shell", "getprop", "ro.product.cpu.abi").stdout.strip(),
            "model": self.adb("shell", "getprop", "ro.product.model").stdout.strip(),
            "emulator": True,
        }
        summary = {
            "runtime": properties,
            "package": PACKAGE,
            "sameInstallAcrossStages": len(self.stage_rows) == 3,
            "processRuns": self.stage_rows,
            "evidenceBoundary": {
                "physicalDevice": False,
                "windowsDesktopDiscovered": False,
                "crossDevicePairingPerformed": False,
                "rawSecretsLogged": False,
                "privateAddressesLogged": False,
            },
        }
        _reject_sensitive_evidence(summary)
        (ARTIFACT_ROOT / "runner-summary.json").write_text(
            json.dumps(summary, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )


def parse_args(arguments: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--serial", required=True)
    parser.add_argument("--apk", required=True, type=Path)
    return parser.parse_args(arguments)


def main(arguments: Sequence[str] | None = None) -> int:
    args = parse_args(arguments)
    runner = Runner(args.serial, args.apk)
    prepared = False
    try:
        runner.prepare()
        prepared = True
        for stage in (1, 2, 3):
            runner.run_stage(stage)
        return 0
    finally:
        if prepared:
            runner.adb("shell", "am", "force-stop", PACKAGE, check=False)
            runner.write_summary()


if __name__ == "__main__":
    raise SystemExit(main())
