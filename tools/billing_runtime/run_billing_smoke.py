#!/usr/bin/env python3
"""Drive an already-built Android billing test and observe native store dialogs."""

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
import signal
import subprocess
import sys
import threading
import time
import uuid

from native_dialog import Adb, DialogOrchestrator, STAGES


def stop_owned_process(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    if os.name == "nt":
        try:
            process.send_signal(signal.CTRL_BREAK_EVENT)
            process.wait(timeout=10)
            return
        except (OSError, subprocess.TimeoutExpired):
            # PID came directly from our Popen; stop only this owned process tree.
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                           capture_output=True, check=False, timeout=10)
    else:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
    process.wait(timeout=10)


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--serial", required=True, help="Exact adb device serial; no implicit device selection")
    result.add_argument("--apk", required=True, type=Path, help="Prebuilt debug integration-test APK")
    result.add_argument("--expect-mode", choices=("smoke", "matrix", "relaunch", "expired"), default="matrix")
    result.add_argument("--adb", default="adb")
    result.add_argument("--flutter", default="flutter")
    result.add_argument("--timeout", type=int, default=660, help="Host timeout in seconds")
    return result


def main() -> int:
    args = parser().parse_args()
    root = Path(__file__).resolve().parents[2]
    apk = args.apk.resolve()
    if not apk.is_file() or apk.suffix.lower() != ".apk":
        raise SystemExit("--apk must point to an existing APK; this runner never builds one")
    if args.timeout < 30:
        raise SystemExit("--timeout must be at least 30 seconds")
    adb_path = shutil.which(args.adb)
    flutter_path = shutil.which(args.flutter)
    if not adb_path or not flutter_path:
        raise SystemExit("Both adb and flutter must be installed or supplied by absolute path")

    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
    artifacts = root / "build" / "billing-runtime-artifacts" / run_id
    artifacts.mkdir(parents=True, exist_ok=False)
    adb = Adb(adb_path, args.serial, run_id)
    orchestrator = DialogOrchestrator(adb, artifacts)
    with apk.open("rb") as binary:
        apk_hash = hashlib.file_digest(binary, "sha256").hexdigest()
    summary: dict[str, object] = {
        "serial": args.serial, "expectedMode": args.expect_mode,
        "apk": str(apk), "apkSha256": apk_hash,
        "runId": run_id, "passed": False,
    }
    process: subprocess.Popen[str] | None = None
    events: queue.Queue[str | None] = queue.Queue()
    failure: str | None = None
    try:
        if adb.run("get-state").decode().strip() != "device":
            raise RuntimeError("The specified adb device is not online/authorized")
        command = [
            flutter_path, "drive", "--no-pub", "-d", args.serial,
            "--driver=test_driver/billing_smoke_driver.dart",
            "--target=integration_test/billing_smoke_test.dart",
            f"--use-application-binary={apk}", "--timeout=600",
        ]
        environment = os.environ.copy()
        environment["BILLING_RUNTIME_RUN_ID"] = run_id
        options: dict[str, object] = {}
        if os.name == "nt":
            options["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW
        else:
            options["start_new_session"] = True
        process = subprocess.Popen(
            command, cwd=root, env=environment, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace",
            **options,
        )

        def read_drive_log() -> None:
            assert process and process.stdout
            with (artifacts / "flutter-drive.log").open("w", encoding="utf-8") as log:
                for line in process.stdout:
                    log.write(line)
                    log.flush()
                    print(line, end="", flush=True)
                    match = re.search(r"\bRC_SMOKE_STAGE (cancel|failure|success)\s*$", line)
                    if match:
                        events.put(match.group(1))
                events.put(None)

        reader = threading.Thread(target=read_drive_log, daemon=True)
        reader.start()
        deadline = time.monotonic() + args.timeout
        while True:
            if time.monotonic() >= deadline:
                raise TimeoutError("Timed out waiting for flutter drive")
            try:
                stage = events.get(timeout=0.5)
            except queue.Empty:
                continue
            if stage is None:
                break
            if args.expect_mode != "matrix":
                raise RuntimeError("Purchase marker observed in a non-purchasing test mode")
            orchestrator.perform(stage)
        return_code = process.wait(timeout=15)
        summary["driveExitCode"] = return_code
        if return_code != 0:
            raise RuntimeError(f"flutter drive failed with exit code {return_code}")
        report = json.loads((artifacts / "result.json").read_text(encoding="utf-8"))
        evidence = report.get("revenueCatTestStore", {})
        if evidence.get("mode") != args.expect_mode:
            raise RuntimeError("Prebuilt APK test mode does not match --expect-mode")
        required = {"sdk", "offering", "monthly", "customer_info"}
        if args.expect_mode == "matrix":
            if [step["stage"] for step in orchestrator.completed] != list(STAGES):
                raise RuntimeError("Missing observed native purchase interactions")
            required |= {
                "restore_without_plus", "native_cancel", "native_failure",
                "purchase_activates_plus", "server_refresh_keeps_plus", "restore_with_plus",
            }
        elif args.expect_mode == "relaunch":
            required |= {"same_customer_plus_after_process_relaunch", "restore_relaunch"}
        elif args.expect_mode == "expired":
            required |= {"same_customer_entitlement_expired", "restore_expired"}
        if not required.issubset(set(evidence.get("verified", []))):
            raise RuntimeError("Integration report lacks required verification evidence")
        summary["passed"] = True
    except (Exception, KeyboardInterrupt) as error:
        failure = f"{type(error).__name__}: {error}"
        summary["error"] = failure
        orchestrator.diagnostics("run-failure")
    finally:
        if process:
            try:
                stop_owned_process(process)
            except Exception as error:
                summary["processCleanupError"] = str(error)
                summary["passed"] = False
        summary["nativeActions"] = orchestrator.completed
        try:
            adb.cleanup()
        except Exception as error:
            summary["remoteCleanupError"] = str(error)
            summary["passed"] = False
        (artifacts / "run.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(f"Billing runtime evidence: {artifacts}", flush=True)
    if failure:
        print(failure, file=sys.stderr)
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
