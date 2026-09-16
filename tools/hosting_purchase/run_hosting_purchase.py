#!/usr/bin/env python3
"""Drive the real hosted-session quota and RevenueCat Test Store funnel."""

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


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "billing_runtime"))

from native_dialog import Adb, DialogOrchestrator, STAGES  # noqa: E402


REQUIRED_VERIFIED = {
    "real_sdk_catalog_initial_free_customer",
    "room_creation_and_solo_play_do_not_consume",
    "peer_join_without_play_does_not_consume",
    "actual_peer_and_native_play_consume_one_host",
    "real_socket_reconnect_does_not_consume_again",
    "same_process_service_reopen_reuses_durable_room_and_quota",
    "next_host_denied_with_needs_plus_and_room_preserved",
    "native_cancel_preserves_room_and_quota",
    "native_failure_preserves_room_and_quota",
    "real_purchase_activates_plus_and_unlocks_next_host",
    "real_restore_preserves_entitlement_and_quota",
    "plus_allows_distinct_real_host_1",
    "plus_allows_distinct_real_host_2",
}
REQUIRED_OBSERVATIONS = {
    "solo-play-does-not-consume",
    "first-real-together-session",
    "reconnect-keeps-free-session",
    "disk-reopen-keeps-free-session",
    "next-host-requires-plus",
    "plus-host-1-playing",
    "plus-host-2-playing",
}
STAGE_PATTERN = re.compile(r"\bRC_SMOKE_STAGE (cancel|failure|success)\s*$")


def stop_owned_process(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    if os.name == "nt":
        try:
            process.send_signal(signal.CTRL_BREAK_EVENT)
            process.wait(timeout=10)
            return
        except (OSError, subprocess.TimeoutExpired):
            subprocess.run(
                ["taskkill", "/PID", str(process.pid), "/T", "/F"],
                capture_output=True,
                check=False,
                timeout=10,
            )
    else:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
    process.wait(timeout=10)


def parse_stage_marker(line: str) -> str | None:
    match = STAGE_PATTERN.search(line)
    return match.group(1) if match else None


def validate_evidence(
    report: object,
    artifacts: Path,
    native_actions: list[dict[str, object]],
) -> dict[str, object]:
    if not isinstance(report, dict):
        raise RuntimeError("Integration result must be a JSON object")
    evidence = report.get("hostingPurchase")
    if not isinstance(evidence, dict):
        raise RuntimeError("Integration result lacks hostingPurchase evidence")
    if evidence.get("mode") != "hosting_purchase" or evidence.get("result") != "passed":
        raise RuntimeError("Hosting purchase funnel did not report a passing real run")
    runtime = evidence.get("runtime")
    if runtime != "Android; two native video targets and two TLS clients in one process":
        raise RuntimeError("Runtime boundary is missing or ambiguous")

    verified = evidence.get("verified")
    if not isinstance(verified, list) or not all(isinstance(item, str) for item in verified):
        raise RuntimeError("Verified evidence must be a list of strings")
    missing = REQUIRED_VERIFIED - set(verified)
    if missing:
        raise RuntimeError(f"Missing hosting verification evidence: {sorted(missing)}")

    actions = [action.get("stage") for action in native_actions]
    if actions != list(STAGES):
        raise RuntimeError("Native Test Store cancel/failure/success sequence is incomplete")
    if evidence.get("finalPlus") is not True or evidence.get("remainingFreeHosts") != 0:
        raise RuntimeError("Final Plus entitlement or free-host quota is incorrect")
    if not re.fullmatch(r"[0-9a-f]{64}", str(evidence.get("customerHash", ""))):
        raise RuntimeError("RevenueCat customer identity must be represented by a SHA-256 hash")
    if not isinstance(evidence.get("localizedPrice"), str) or not evidence["localizedPrice"].strip():
        raise RuntimeError("Real Test Store catalog price is missing")

    observations = evidence.get("observations")
    if not isinstance(observations, list) or not all(isinstance(item, dict) for item in observations):
        raise RuntimeError("Hosting observations must be a list of objects")
    observed_stages = {item.get("stage") for item in observations}
    missing_observations = REQUIRED_OBSERVATIONS - observed_stages
    if missing_observations:
        raise RuntimeError(f"Missing runtime observations: {sorted(missing_observations)}")

    screenshots = evidence.get("screenshots")
    if not isinstance(screenshots, list) or set(screenshots) != REQUIRED_OBSERVATIONS:
        raise RuntimeError("Flutter runtime screenshots do not cover every required stage")
    for name in screenshots:
        if not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", name):
            raise RuntimeError("Invalid screenshot name in integration evidence")
        screenshot = artifacts / f"{name}.png"
        if not screenshot.is_file() or screenshot.stat().st_size <= 4096:
            raise RuntimeError(f"Missing non-empty runtime screenshot: {name}")

    return evidence


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--serial", required=True, help="Exact adb device serial")
    result.add_argument("--apk", required=True, type=Path, help="Prebuilt integration APK")
    result.add_argument("--adb", default="adb")
    result.add_argument("--flutter", default="flutter")
    result.add_argument("--timeout", type=int, default=900, help="Host timeout in seconds")
    return result


def main() -> int:
    args = parser().parse_args()
    apk = args.apk.resolve()
    if not apk.is_file() or apk.suffix.lower() != ".apk":
        raise SystemExit("--apk must point to an existing APK; this runner never builds one")
    if args.timeout < 60:
        raise SystemExit("--timeout must be at least 60 seconds")
    adb_path = shutil.which(args.adb)
    flutter_path = shutil.which(args.flutter)
    if not adb_path or not flutter_path:
        raise SystemExit("Both adb and flutter must be installed or supplied by absolute path")

    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
    artifacts = ROOT / "build" / "hosting-purchase-artifacts" / run_id
    artifacts.mkdir(parents=True, exist_ok=False)
    adb = Adb(adb_path, args.serial, run_id)
    orchestrator = DialogOrchestrator(adb, artifacts)
    with apk.open("rb") as binary:
        apk_hash = hashlib.file_digest(binary, "sha256").hexdigest()
    summary: dict[str, object] = {
        "serial": args.serial,
        "runtimeBoundary": "one Android emulator; host and guest TLS clients share one app process",
        "physicalDeviceEvidence": False,
        "apk": str(apk),
        "apkSha256": apk_hash,
        "runId": run_id,
        "passed": False,
    }
    process: subprocess.Popen[str] | None = None
    events: queue.Queue[str | None] = queue.Queue()
    failure: str | None = None
    try:
        if adb.run("get-state").decode().strip() != "device":
            raise RuntimeError("The specified adb device is not online/authorized")
        command = [
            flutter_path,
            "drive",
            "--no-pub",
            "-d",
            args.serial,
            "--driver=test_driver/hosting_purchase_driver.dart",
            "--target=integration_test/hosting_purchase_test.dart",
            f"--use-application-binary={apk}",
            "--timeout=780",
        ]
        environment = os.environ.copy()
        environment["BILLING_RUNTIME_RUN_ID"] = run_id
        options: dict[str, object] = {}
        if os.name == "nt":
            options["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW
        else:
            options["start_new_session"] = True
        process = subprocess.Popen(
            command,
            cwd=ROOT,
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            **options,
        )

        def read_drive_log() -> None:
            assert process and process.stdout
            with (artifacts / "flutter-drive.log").open("w", encoding="utf-8") as log:
                for line in process.stdout:
                    log.write(line)
                    log.flush()
                    print(line, end="", flush=True)
                    stage = parse_stage_marker(line)
                    if stage:
                        events.put(stage)
                events.put(None)

        reader = threading.Thread(target=read_drive_log, daemon=True)
        reader.start()
        deadline = time.monotonic() + args.timeout
        while True:
            if time.monotonic() >= deadline:
                raise TimeoutError("Timed out waiting for the hosting purchase funnel")
            try:
                stage = events.get(timeout=0.5)
            except queue.Empty:
                continue
            if stage is None:
                break
            orchestrator.perform(stage)
        return_code = process.wait(timeout=20)
        reader.join(timeout=5)
        summary["driveExitCode"] = return_code
        if return_code != 0:
            raise RuntimeError(f"flutter drive failed with exit code {return_code}")
        report = json.loads((artifacts / "result.json").read_text(encoding="utf-8"))
        evidence = validate_evidence(report, artifacts, orchestrator.completed)
        summary["verified"] = evidence["verified"]
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
    print(f"Hosting purchase evidence: {artifacts}", flush=True)
    if failure:
        print(failure, file=sys.stderr)
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
