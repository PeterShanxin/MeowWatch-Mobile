#!/usr/bin/env python3
"""Prove Test Store Plus survives an Android process relaunch for one SDK customer."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
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
import uuid

from native_dialog import Adb, DialogOrchestrator, PACKAGE, STAGES
from run_billing_smoke import stop_owned_process


ROOT = Path(__file__).resolve().parents[2]
TARGET = "integration_test/billing_smoke_test.dart"
DRIVER = "test_driver/billing_smoke_driver.dart"
ARTIFACT_ROOT = ROOT / "build" / "billing-relaunch-artifacts"
RESULT_ROOT = ROOT / "build" / "billing-runtime-artifacts"
HASH = re.compile(r"^[0-9a-f]{64}$")
BASE_REQUIRED = {"sdk", "offering", "monthly", "customer_info"}
MATRIX_REQUIRED = BASE_REQUIRED | {
    "restore_without_plus",
    "native_cancel",
    "native_failure",
    "purchase_activates_plus",
    "server_refresh_keeps_plus",
    "restore_with_plus",
}
RELAUNCH_REQUIRED = BASE_REQUIRED | {
    "same_customer_plus_after_process_relaunch",
    "restore_cache_invalidated",
    "restore_relaunch",
}


def _reject_raw_customer_identity(value: object) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            normalized = str(key).replace("_", "").lower()
            if normalized in {"originalappuserid", "appuserid", "customerid"}:
                raise RuntimeError(f"Raw RevenueCat customer identity is forbidden: {key}")
            _reject_raw_customer_identity(child)
    elif isinstance(value, list):
        for child in value:
            _reject_raw_customer_identity(child)


def sha256_file(path: Path) -> str:
    with path.open("rb") as binary:
        return hashlib.file_digest(binary, "sha256").hexdigest()


def drive_command(
    flutter: str,
    serial: str,
    apk: Path,
    host_port: int,
) -> list[str]:
    if re.fullmatch(r"emulator-\d+", serial) is None:
        raise ValueError("serial must explicitly name an Android emulator")
    if not 1024 <= host_port <= 65535:
        raise ValueError("host VM service port is invalid")
    return [
        flutter,
        "drive",
        "--no-pub",
        "-d",
        serial,
        f"--driver={DRIVER}",
        f"--target={TARGET}",
        f"--use-application-binary={apk}",
        "--keep-app-running",
        "--timeout=600",
        f"--host-vmservice-port={host_port}",
    ]


def relaunch_build_command(
    flutter: str,
    customer_hash: str,
    test_store_key: str,
) -> list[str]:
    if HASH.fullmatch(customer_hash) is None:
        raise ValueError("expected customer hash must be lowercase SHA-256")
    if not test_store_key.startswith("test_"):
        raise ValueError("only a RevenueCat Test Store public SDK key is allowed")
    return [
        flutter,
        "build",
        "apk",
        "--debug",
        "--no-pub",
        f"--target={TARGET}",
        "--dart-define=REVENUECAT_TEST_MODE=relaunch",
        f"--dart-define=REVENUECAT_EXPECT_CUSTOMER_HASH={customer_hash}",
        f"--dart-define=REVENUECAT_API_KEY={test_store_key}",
    ]


def validate_evidence(
    report: object,
    mode: str,
    expected_customer_hash: str | None = None,
) -> dict[str, object]:
    if mode not in {"matrix", "relaunch"}:
        raise ValueError("relaunch journey mode must be matrix or relaunch")
    _reject_raw_customer_identity(report)
    evidence = report.get("revenueCatTestStore") if isinstance(report, dict) else None
    if not isinstance(evidence, dict) or evidence.get("mode") != mode:
        raise RuntimeError(f"Missing {mode} RevenueCat integration evidence")
    customer_hash = evidence.get("customerHash")
    if not isinstance(customer_hash, str) or HASH.fullmatch(customer_hash) is None:
        raise RuntimeError("RevenueCat customer evidence must be a SHA-256 hash")
    if expected_customer_hash is not None and customer_hash != expected_customer_hash:
        raise RuntimeError("Relaunch used a different RevenueCat SDK customer")
    verified = evidence.get("verified")
    if not isinstance(verified, list) or not all(isinstance(item, str) for item in verified):
        raise RuntimeError("RevenueCat verification list is invalid")
    required = MATRIX_REQUIRED if mode == "matrix" else RELAUNCH_REQUIRED
    if required - set(verified):
        raise RuntimeError(f"Missing {mode} verification: {sorted(required - set(verified))}")
    if evidence.get("finalPlus") is not True:
        raise RuntimeError(f"{mode} evidence did not finish with active Plus")
    if mode == "matrix":
        if evidence.get("initialPlus") is not False:
            raise RuntimeError("Purchase matrix did not start with a fresh non-Plus customer")
        if evidence.get("cancelErrorCode") != "1":
            raise RuntimeError("Matrix cancellation was not the RevenueCat cancellation code")
        if evidence.get("failureErrorCode") != "42":
            raise RuntimeError("Matrix failure was not the Test Store simulated error")
    elif evidence.get("initialPlus") is not True:
        raise RuntimeError("Relaunch did not load active Plus from the real SDK")
    return evidence


def _pids(adb: Adb) -> list[int]:
    result = subprocess.run(
        adb.prefix + ["shell", "pidof", PACKAGE],
        capture_output=True,
        timeout=15,
        check=False,
    )
    output = result.stdout.decode("ascii", errors="strict").strip()
    if result.returncode not in (0, 1):
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"adb pidof failed ({result.returncode}): {detail}")
    if not output:
        return []
    parts = output.split()
    if not all(part.isdigit() for part in parts):
        raise RuntimeError("adb pidof returned a non-numeric process identity")
    return [int(part) for part in parts]


def single_pid(adb: Adb) -> int:
    pids = _pids(adb)
    if len(pids) != 1:
        raise RuntimeError(f"Expected one MeowWatch process, observed {len(pids)}")
    return pids[0]


def force_stop_and_wait(adb: Adb, expected_pid: int) -> None:
    if expected_pid <= 0:
        raise ValueError("expected PID must be positive")
    adb.run("shell", "am", "force-stop", PACKAGE)
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        pids = _pids(adb)
        if not pids:
            return
        if expected_pid not in pids:
            raise RuntimeError("App process identity changed before force-stop completed")
        time.sleep(0.25)
    raise RuntimeError("Expected app process survived force-stop")


def require_installed(adb: Adb) -> None:
    output = adb.run("shell", "pm", "path", PACKAGE).decode("utf-8", errors="strict").strip()
    if not output.startswith("package:"):
        raise RuntimeError("Billing test package is not installed; app data cannot be retained")


def _process_options() -> dict[str, object]:
    if os.name == "nt":
        return {
            "creationflags": subprocess.CREATE_NEW_PROCESS_GROUP
            | subprocess.CREATE_NO_WINDOW
        }
    return {"start_new_session": True}


def run_drive(
    *,
    flutter: str,
    adb: Adb,
    apk: Path,
    mode: str,
    run_id: str,
    artifacts: Path,
    orchestrator: DialogOrchestrator | None,
    host_port: int,
    timeout: float = 660,
) -> dict[str, object]:
    result_directory = RESULT_ROOT / run_id
    environment = os.environ.copy()
    environment["BILLING_RUNTIME_RUN_ID"] = run_id
    process = subprocess.Popen(
        drive_command(flutter, adb.serial, apk, host_port),
        cwd=ROOT,
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        **_process_options(),
    )
    events: queue.Queue[str | None] = queue.Queue()
    read_errors: list[BaseException] = []

    def read_output() -> None:
        try:
            assert process.stdout is not None
            with (artifacts / f"{mode}-flutter-drive.log").open(
                "w", encoding="utf-8"
            ) as log:
                for line in process.stdout:
                    log.write(line)
                    log.flush()
                    print(line, end="", flush=True)
                    match = re.search(
                        r"\bRC_SMOKE_STAGE (cancel|failure|success)\s*$", line
                    )
                    if match:
                        events.put(match.group(1))
        except BaseException as error:
            read_errors.append(error)
        finally:
            events.put(None)

    reader = threading.Thread(target=read_output, daemon=True)
    reader.start()
    deadline = time.monotonic() + timeout
    try:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(f"{mode} flutter drive exceeded {timeout:g} seconds")
            try:
                stage = events.get(timeout=min(0.5, remaining))
            except queue.Empty:
                continue
            if stage is None:
                break
            if mode != "matrix" or orchestrator is None:
                raise RuntimeError("Native purchase marker appeared during relaunch")
            orchestrator.perform(stage)
        return_code = process.wait(timeout=20)
        reader.join(timeout=10)
        if reader.is_alive() or read_errors:
            raise RuntimeError(f"Could not capture complete {mode} flutter output")
        if return_code != 0:
            raise RuntimeError(f"{mode} flutter drive failed with exit code {return_code}")
        result_path = result_directory / "result.json"
        report = json.loads(result_path.read_text(encoding="utf-8"))
        (artifacts / f"{mode}-result.json").write_text(
            json.dumps(report, indent=2) + "\n", encoding="utf-8"
        )
        return validate_evidence(report, mode)
    finally:
        if process.poll() is None:
            stop_owned_process(process)
        reader.join(timeout=10)


def build_relaunch(
    flutter: str,
    customer_hash: str,
    test_store_key: str,
    artifacts: Path,
) -> Path:
    command = relaunch_build_command(flutter, customer_hash, test_store_key)
    with (artifacts / "relaunch-build.log").open("w", encoding="utf-8") as log:
        result = subprocess.run(
            command,
            cwd=ROOT,
            stdout=log,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=360,
            check=False,
        )
    if result.returncode != 0:
        raise RuntimeError(f"Relaunch APK build failed with exit code {result.returncode}")
    apk = ROOT / "build" / "app" / "outputs" / "flutter-apk" / "app-debug.apk"
    if not apk.is_file():
        raise RuntimeError("Relaunch build produced no debug APK")
    return apk


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--matrix-apk", required=True, type=Path)
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--flutter", default="flutter")
    args = parser.parse_args()
    matrix_apk = args.matrix_apk.resolve()
    if not matrix_apk.is_file() or matrix_apk.suffix.lower() != ".apk":
        parser.error("--matrix-apk must identify the prebuilt matrix APK")
    adb_path = shutil.which(args.adb)
    flutter = shutil.which(args.flutter)
    if not adb_path or not flutter:
        parser.error("adb and flutter must be installed or supplied by path")
    test_store_key = os.environ.get("REVENUECAT_TEST_STORE_KEY", "").strip()
    if not test_store_key.startswith("test_"):
        parser.error("REVENUECAT_TEST_STORE_KEY must be a Test Store public SDK key")

    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
    artifacts = ARTIFACT_ROOT / run_id
    artifacts.mkdir(parents=True, exist_ok=False)
    adb = Adb(adb_path, args.serial, run_id)
    native_artifacts = artifacts / "matrix-native"
    native_artifacts.mkdir()
    orchestrator = DialogOrchestrator(adb, native_artifacts)
    summary: dict[str, object] = {
        "passed": False,
        "serial": args.serial,
        "runId": run_id,
        "physicalDeviceEvidence": False,
        "runnerRequestedUninstall": False,
        "runnerRequestedAppDataClear": False,
        "recoveryBoundary": (
            "Same persisted RevenueCat SDK customer across an Android process "
            "force-stop and replacement debug APK install"
        ),
    }
    safe_emulator = False
    try:
        if not adb.verified_emulator():
            raise RuntimeError("Relaunch runner requires an explicitly verified emulator")
        safe_emulator = True
        if adb.run("get-state").decode("ascii", errors="strict").strip() != "device":
            raise RuntimeError("Selected Android emulator is unavailable")
        summary["runtime"] = {
            "model": adb.run("shell", "getprop", "ro.product.model")
            .decode()
            .strip(),
            "apiLevel": adb.run("shell", "getprop", "ro.build.version.sdk")
            .decode()
            .strip(),
        }
        matrix_hash = sha256_file(matrix_apk)
        matrix = run_drive(
            flutter=flutter,
            adb=adb,
            apk=matrix_apk,
            mode="matrix",
            run_id=f"{run_id}-matrix",
            artifacts=artifacts,
            orchestrator=orchestrator,
            host_port=39701,
        )
        if [step.get("stage") for step in orchestrator.completed] != list(STAGES):
            raise RuntimeError("Matrix did not complete all guarded native Test Store dialogs")
        customer_hash = str(matrix["customerHash"])
        old_pid = single_pid(adb)
        require_installed(adb)
        force_stop_and_wait(adb, old_pid)
        require_installed(adb)
        if _pids(adb):
            raise RuntimeError("Old app process still exists after force-stop")

        relaunch_apk = build_relaunch(flutter, customer_hash, test_store_key, artifacts)
        relaunch_hash = sha256_file(relaunch_apk)
        if relaunch_hash == matrix_hash:
            raise RuntimeError("Relaunch build did not produce a distinct mode-bound APK")
        relaunch = run_drive(
            flutter=flutter,
            adb=adb,
            apk=relaunch_apk,
            mode="relaunch",
            run_id=f"{run_id}-relaunch",
            artifacts=artifacts,
            orchestrator=None,
            host_port=39702,
        )
        validate_evidence(
            {"revenueCatTestStore": relaunch},
            "relaunch",
            expected_customer_hash=customer_hash,
        )
        new_pid = single_pid(adb)
        if new_pid == old_pid:
            raise RuntimeError("Android reused the old PID; distinct process proof is unavailable")
        summary.update(
            {
                "matrix": {
                    "apkSha256": matrix_hash,
                    "pid": old_pid,
                    "customerHash": customer_hash,
                },
                "processTransition": {
                    "oldPidGoneBeforeRelaunch": True,
                    "newPidDifferent": True,
                },
                "relaunch": {
                    "apkSha256": relaunch_hash,
                    "pid": new_pid,
                    "customerHash": str(relaunch["customerHash"]),
                    "initialPlus": relaunch["initialPlus"],
                    "finalPlus": relaunch["finalPlus"],
                },
                "nativeActions": orchestrator.completed,
                "passed": True,
            }
        )
    except (Exception, KeyboardInterrupt) as error:
        summary["error"] = f"{type(error).__name__}: {error}"
        if safe_emulator:
            orchestrator.diagnostics("relaunch-failure")
    finally:
        try:
            if safe_emulator:
                running = _pids(adb)
                if len(running) == 1:
                    force_stop_and_wait(adb, running[0])
                elif running:
                    summary["processCleanupError"] = (
                        f"Refusing ambiguous cleanup of {len(running)} app processes"
                    )
                    summary["passed"] = False
        except Exception as error:
            summary["processCleanupError"] = str(error)
            summary["passed"] = False
        try:
            adb.cleanup()
        except Exception as error:
            summary["remoteCleanupError"] = str(error)
            summary["passed"] = False
        (artifacts / "run.json").write_text(
            json.dumps(summary, indent=2) + "\n", encoding="utf-8"
        )
    print(f"Billing relaunch evidence: {artifacts}", flush=True)
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
