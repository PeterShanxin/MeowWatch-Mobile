#!/usr/bin/env python3
"""Record the real MainApp purchase journey on one clean Android emulator."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
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

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "billing_runtime"))
sys.path.insert(0, str(ROOT / "tools" / "hosting_purchase"))
from native_dialog import (  # noqa: E402
    Adb, DialogOrchestrator, NativeRecording, PACKAGE, STAGES,
    UnsafeDialog, image_size, select_target,
)
from run_hosting_purchase import parse_stage_marker, stop_owned_process  # noqa: E402

RUNTIME = "Android MainApp; one native player and independent headless TLS peer in one process"
REQUIRED = {
    "clean_production_services_and_free_customer",
    "one_free_host_consumed_via_ui_and_real_tls_peer",
    "next_host_opens_production_paywall",
    "native_cancel_through_production_paywall",
    "native_failure_through_production_paywall",
    "native_success_through_production_paywall",
    "sdk_restore_via_settings_retains_entitlement_for_same_customer",
    "sdk_restore_after_customer_info_cache_invalidation",
    "glass_aurora_selected_persisted_and_paid_room_usable",
    "movie_night_premium_reaction_sent_via_ui_and_received_by_real_tls_peer",
    "premium_theme_selected_via_ui_and_persisted",
    "two_distinct_paid_hosts_via_ui_with_real_tls_peer",
}
RECORDING_SEGMENT_SECONDS = 70.0
MAX_RECORDING_DURATION_SHORTFALL_SECONDS = 3.0
MAX_RECORDING_GAP_SECONDS = 15.0
MIN_RECORDING_COVERAGE_RATIO = 0.90


def ffprobe_duration(path: Path, ffprobe: str) -> float:
    result = subprocess.run(
        [
            ffprobe,
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            str(path),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=20,
        check=False,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or "no ffprobe diagnostic"
        raise RuntimeError(f"ffprobe rejected {path.name}: {detail}")
    try:
        duration = float(result.stdout.strip())
    except ValueError as error:
        raise RuntimeError(f"ffprobe returned no duration for {path.name}") from error
    if not math.isfinite(duration) or duration <= 0:
        raise RuntimeError(f"ffprobe returned an invalid duration for {path.name}: {duration}")
    return duration


def validate_recording_coverage(
    segments: list[dict[str, object]],
    journey_started: float,
    journey_finished: float,
) -> dict[str, float]:
    if not segments:
        raise RuntimeError("Native journey recording has no segments")
    if not math.isfinite(journey_started) or not math.isfinite(journey_finished):
        raise RuntimeError("Native journey recording has invalid monotonic bounds")
    if journey_finished <= journey_started:
        raise RuntimeError("Native journey recording has no positive journey interval")

    previous_end: float | None = None
    covered = 0.0
    largest_gap = 0.0
    for index, segment in enumerate(segments, start=1):
        try:
            started = float(segment["coverageStartedMonotonicSeconds"])
            ended = float(segment["coverageEndedMonotonicSeconds"])
            video_duration = float(segment["videoDurationSeconds"])
        except (KeyError, TypeError, ValueError) as error:
            raise RuntimeError(f"Recording segment {index} has invalid timing evidence") from error
        if not all(math.isfinite(value) for value in (started, ended, video_duration)):
            raise RuntimeError(f"Recording segment {index} has non-finite timing evidence")
        if ended <= started or video_duration <= 0:
            raise RuntimeError(f"Recording segment {index} has no positive coverage")
        elapsed = ended - started
        if segment.get("endedBeforeRequestedStop") is True:
            raise RuntimeError(
                f"Recording segment {index} exited before the requested stop after "
                f"{video_duration:.3f}s"
            )
        if video_duration + MAX_RECORDING_DURATION_SHORTFALL_SECONDS < elapsed:
            raise RuntimeError(
                f"Recording segment {index} video covers only {video_duration:.3f}s of "
                f"{elapsed:.3f}s monotonic recording time"
            )
        if previous_end is not None:
            gap = started - previous_end
            if gap < 0:
                raise RuntimeError(f"Recording segment {index} overlaps or is out of order")
            largest_gap = max(largest_gap, gap)
            segment["gapFromPreviousSeconds"] = round(gap, 3)
            if gap > MAX_RECORDING_GAP_SECONDS:
                raise RuntimeError(
                    f"Recording gap before segment {index} is {gap:.3f}s; "
                    f"limit is {MAX_RECORDING_GAP_SECONDS:.3f}s"
                )
        else:
            segment["gapFromPreviousSeconds"] = 0.0
        interval_start = max(started, journey_started)
        interval_end = min(ended, journey_finished)
        covered += max(0.0, interval_end - interval_start)
        previous_end = ended

    first_started = float(segments[0]["coverageStartedMonotonicSeconds"])
    last_ended = float(segments[-1]["coverageEndedMonotonicSeconds"])
    if first_started > journey_started + MAX_RECORDING_DURATION_SHORTFALL_SECONDS:
        raise RuntimeError("Native journey recording is missing its initial coverage")
    if last_ended + MAX_RECORDING_DURATION_SHORTFALL_SECONDS < journey_finished:
        raise RuntimeError("Native journey recording is missing its final coverage")

    journey_duration = journey_finished - journey_started
    coverage_ratio = min(1.0, covered / journey_duration)
    if coverage_ratio < MIN_RECORDING_COVERAGE_RATIO:
        raise RuntimeError(
            f"Native journey recording covers only {coverage_ratio:.1%} of "
            f"{journey_duration:.3f}s; minimum is {MIN_RECORDING_COVERAGE_RATIO:.1%}"
        )
    return {
        "journeyDurationSeconds": round(journey_duration, 3),
        "coveredSeconds": round(covered, 3),
        "coverageRatio": round(coverage_ratio, 6),
        "largestGapSeconds": round(largest_gap, 3),
    }
SCREENSHOTS = {
    "free-home", "free-host-playing", "quota-paywall", "purchase-cancel",
    "purchase-failure", "purchase-unlocked-room", "plus-restored",
    "glass-aurora-applied", "movie-night-reaction-sent",
    "plus-theme-applied", "plus-host-one-playing", "plus-host-two-playing",
}


def display_override(output: str) -> str | None:
    matches = re.findall(r"(?m)^Override (?:size|density): ([0-9x]+)\s*$", output)
    if len(matches) > 1:
        raise RuntimeError("Ambiguous Android display override")
    return matches[0] if matches else None


class PortraitRecording(NativeRecording):
    """The submission screenshot has odd width; the encoder needs even pixels."""

    def start(self) -> None:
        command = (
            f"screenrecord --size 720x1560 --bit-rate 2000000 --time-limit 90 {self.remote} & "
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
            raise RuntimeError("Could not identify owned portrait recorder") from error


class RecordedDialogs(DialogOrchestrator):
    """Use the shared native guards while the whole journey is being recorded.

    Unlike the standalone billing probe, do not launch a second concurrent
    screen recorder for each dialog on the same Android encoder.
    """

    def perform(self, stage: str) -> None:
        expected = STAGES[len(self.completed)] if len(self.completed) < len(STAGES) else None
        if stage != expected:
            raise UnsafeDialog(f"Unexpected native stage {stage!r}; expected {expected!r}")
        deadline = time.monotonic() + self.stage_timeout
        last_error = "No native dialog observed"
        while time.monotonic() < deadline:
            try:
                xml, window = self.adb.observe()
                if self._recover_pixel_launcher_anr(stage, xml, window):
                    continue
                select_target(xml, window, stage)
                png = self.adb.screenshot()
                width, height = image_size(png)
                xml, window = self.adb.observe()
                target = select_target(xml, window, stage)
                if target.bounds[2] > width or target.bounds[3] > height:
                    raise UnsafeDialog("Native target is outside the observed screen")
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


class JourneyRecording:
    """Rotate bounded, owned native recordings and retain their timing gaps."""

    def __init__(self, adb: Adb, artifacts: Path, ffprobe: str):
        self.adb = adb
        self.artifacts = artifacts
        self.ffprobe = ffprobe
        self.stop = threading.Event()
        self.ready = threading.Event()
        self.errors: list[str] = []
        self.segments: list[dict[str, object]] = []
        self.journey_started_monotonic: float | None = None
        self.journey_finished_monotonic: float | None = None
        self.coverage_summary: dict[str, float] | None = None
        self.thread = threading.Thread(target=self._run, daemon=True)

    def _run(self) -> None:
        try:
            while not self.stop.is_set():
                name = f"journey-{len(self.segments) + 1:03}"
                recording = PortraitRecording(self.adb, self.artifacts / f"{name}.mp4", name)
                try:
                    recording.start()
                    coverage_started = time.monotonic()
                    started_at = datetime.now(timezone.utc).isoformat()
                    self.ready.set()
                    stop_requested = self.stop.wait(RECORDING_SEGMENT_SECONDS)
                    coverage_ended = time.monotonic()
                    coverage_ended_at = datetime.now(timezone.utc).isoformat()
                    ended_before_requested_stop = (
                        not stop_requested
                        and recording.process is not None
                        and recording.process.poll() is not None
                    )
                finally:
                    recording.finish()
                video_duration = ffprobe_duration(recording.output, self.ffprobe)
                segment = {
                    "file": f"{name}.mp4",
                    "startedAtUtc": started_at,
                    "coverageEndedAtUtc": coverage_ended_at,
                    "finalizedAtUtc": datetime.now(timezone.utc).isoformat(),
                    "coverageStartedMonotonicSeconds": coverage_started,
                    "coverageEndedMonotonicSeconds": coverage_ended,
                    "monotonicCoverageSeconds": round(coverage_ended - coverage_started, 3),
                    "videoDurationSeconds": round(video_duration, 3),
                    "endedBeforeRequestedStop": ended_before_requested_stop,
                }
                self.segments.append(segment)
                elapsed = coverage_ended - coverage_started
                if ended_before_requested_stop:
                    raise RuntimeError(
                        f"Recording segment {len(self.segments)} exited before the "
                        f"requested stop after {video_duration:.3f}s"
                    )
                if video_duration + MAX_RECORDING_DURATION_SHORTFALL_SECONDS < elapsed:
                    raise RuntimeError(
                        f"Recording segment {len(self.segments)} video covers only "
                        f"{video_duration:.3f}s of {elapsed:.3f}s monotonic recording time"
                    )
        except Exception as error:
            self.errors.append(f"{type(error).__name__}: {error}")
            self.ready.set()

    def start(self) -> None:
        self.thread.start()
        if not self.ready.wait(20) or self.errors:
            raise RuntimeError(f"Journey recorder did not start: {self.errors}")
        self.journey_started_monotonic = time.monotonic()

    def finish(self) -> None:
        if self.journey_finished_monotonic is None:
            self.journey_finished_monotonic = time.monotonic()
        self.stop.set()
        if self.thread.ident is not None:
            self.thread.join(timeout=65)
        if self.thread.is_alive():
            raise RuntimeError("Owned recorder did not finalize in time")
        if self.errors or not self.segments:
            raise RuntimeError(f"Incomplete native journey recording: {self.errors}")
        if self.journey_started_monotonic is None:
            raise RuntimeError("Native journey recording never became ready")
        self.coverage_summary = validate_recording_coverage(
            self.segments,
            self.journey_started_monotonic,
            self.journey_finished_monotonic,
        )


def validate_evidence(report: object, artifacts: Path, actions: list[dict[str, object]]) -> dict:
    evidence = report.get("purchaseJourney") if isinstance(report, dict) else None
    if not isinstance(evidence, dict) or evidence.get("result") != "passed":
        raise RuntimeError("No passing production purchase journey")
    if evidence.get("runtime") != RUNTIME:
        raise RuntimeError("Missing explicit native/headless runtime boundary")
    verified = evidence.get("verified")
    if not isinstance(verified, list) or not all(isinstance(item, str) for item in verified):
        raise RuntimeError("Invalid verification list")
    if REQUIRED - set(verified):
        raise RuntimeError(f"Missing production UI evidence: {sorted(REQUIRED - set(verified))}")
    if [action.get("stage") for action in actions] != list(STAGES):
        raise RuntimeError("Native cancel/failure/success sequence incomplete")
    if evidence.get("finalPlus") is not True or evidence.get("remainingFreeHosts") != 0:
        raise RuntimeError("Incorrect final entitlement or quota")
    if evidence.get("theme") != "cinemaNoir":
        raise RuntimeError("Paid appearance not applied")
    if not re.fullmatch(r"[0-9a-f]{64}", str(evidence.get("customerHash", ""))):
        raise RuntimeError("Customer evidence must be hashed")
    if evidence.get("cancelErrorCode") != "1":
        raise RuntimeError("Cancellation must report RevenueCat purchaseCancelledError")
    if evidence.get("failureErrorCode") != "42":
        raise RuntimeError("Failure must report RevenueCat testStoreSimulatedPurchaseError")
    if evidence.get("restoreKeptSameCustomer") is not True:
        raise RuntimeError("Settings restore must retain Plus for the same SDK customer")
    if evidence.get("glassAuroraPersisted") is not True:
        raise RuntimeError("Glass Aurora was not persisted through production UI")
    if evidence.get("glassAuroraRoomUsable") is not True:
        raise RuntimeError("Glass Aurora was not retained in a usable paid room")
    if evidence.get("movieNightReaction") != "🎬":
        raise RuntimeError("Movie night reaction was not sent through the production picker")
    if evidence.get("movieNightReactionPeerReceived") is not True:
        raise RuntimeError("Headless TLS peer did not receive the premium reaction")
    if evidence.get("movieNightReactionSenderMatched") is not True:
        raise RuntimeError("Premium reaction did not carry the app's server username")
    if not isinstance(evidence.get("localizedPrice"), str) or not evidence["localizedPrice"].strip():
        raise RuntimeError("Actual catalog price missing")
    screenshots = evidence.get("screenshots")
    if not isinstance(screenshots, list) or not all(isinstance(item, str) for item in screenshots):
        raise RuntimeError("Invalid screenshot list")
    if set(screenshots) != SCREENSHOTS or len(screenshots) != len(SCREENSHOTS):
        raise RuntimeError("Incomplete or duplicate production screenshots")
    for name in SCREENSHOTS:
        path = artifacts / f"{name}.png"
        if not path.is_file() or path.stat().st_size <= 4096:
            raise RuntimeError(f"Missing screenshot: {name}")
        width, height = image_size(path.read_bytes())
        if (width, height) != (1179, 2556):
            raise RuntimeError(f"Native screenshot must be 1179x2556: {name} is {width}x{height}")
    sessions = evidence.get("sessions")
    if not isinstance(sessions, list) or len(sessions) != 3:
        raise RuntimeError("Need one free and two paid real sessions")
    ids = []
    for index, session in enumerate(sessions):
        if not isinstance(session, dict):
            raise RuntimeError("Invalid session observation")
        session_id = session.get("id")
        if not isinstance(session_id, str) or not session_id or session_id in ids:
            raise RuntimeError("Hosted sessions must have distinct real identities")
        ids.append(session_id)
        if session.get("usedFreeHost") is not (index == 0) or session.get("plus") is not (index > 0):
            raise RuntimeError("Incorrect free/Plus accounting")
        if session.get("peerCompletedTlsHello") is not True or session.get("peerObservedPlaying") is not True:
            raise RuntimeError("Missing actual secure peer play observation")
        position = session.get("nativePositionMs")
        if isinstance(position, bool) or not isinstance(position, (int, float)) or position <= 500:
            raise RuntimeError("Native playback did not advance")
        if session.get("remainingFreeHosts") != 0 or not session.get("server"):
            raise RuntimeError("Missing session quota/server observation")
    first_paid = sessions[1]
    if first_paid.get("theme") != "glassAurora":
        raise RuntimeError("First paid room did not retain Glass Aurora")
    if first_paid.get("premiumReaction") != "🎬":
        raise RuntimeError("First paid room did not send the Movie night reaction")
    if first_paid.get("peerReceivedPremiumReaction") is not True:
        raise RuntimeError("First paid room lacks the real TLS peer reaction receipt")
    if first_paid.get("peerReactionSenderMatched") is not True:
        raise RuntimeError("First paid room reaction sender does not match the app")
    return evidence


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--flutter", default="flutter")
    parser.add_argument("--ffprobe", default="ffprobe")
    parser.add_argument("--timeout", type=int, default=840)
    args = parser.parse_args()
    apk = args.apk.resolve()
    if not apk.is_file() or apk.suffix.lower() != ".apk":
        parser.error("--apk must identify a prebuilt integration APK")
    if not 120 <= args.timeout <= 1200:
        parser.error("--timeout must be 120 through 1200 seconds")
    adb_path, flutter, ffprobe = (
        shutil.which(args.adb),
        shutil.which(args.flutter),
        shutil.which(args.ffprobe),
    )
    if not adb_path or not flutter or not ffprobe:
        parser.error("adb, flutter and ffprobe must be available")
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
    artifacts = ROOT / "build" / "production-purchase-artifacts" / run_id
    artifacts.mkdir(parents=True, exist_ok=False)
    adb = Adb(adb_path, args.serial, run_id)
    dialogs = RecordedDialogs(adb, artifacts)
    recorder = JourneyRecording(adb, artifacts, ffprobe)
    summary = {
        "passed": False, "serial": args.serial, "runId": run_id,
        "runtimeBoundary": RUNTIME, "physicalDeviceEvidence": False,
        "recordingBoundary": "Raw native segments; rotation and transfer gaps are not continuous footage",
    }
    process = None
    original_display: dict[str, str | None] = {}
    events: queue.Queue[str | None] = queue.Queue()
    try:
        if not adb.verified_emulator():
            raise RuntimeError("Clean-install runner accepts only an explicitly verified emulator")
        if adb.run("get-state").decode().strip() != "device":
            raise RuntimeError("Selected emulator is unavailable")
        summary["model"] = adb.run("shell", "getprop", "ro.product.model").decode().strip()
        summary["androidApi"] = adb.run("shell", "getprop", "ro.build.version.sdk").decode().strip()
        for setting in ("size", "density"):
            output = adb.run("shell", "wm", setting).decode().replace("\r", "")
            original_display[setting] = display_override(output)
            (artifacts / f"original-wm-{setting}.txt").write_text(output, encoding="utf-8")
        adb.run("shell", "wm", "size", "1179x2556")
        adb.run("shell", "wm", "density", "480")
        for _ in range(10):
            if image_size(adb.screenshot()) == (1179, 2556):
                break
            time.sleep(0.5)
        else:
            raise RuntimeError("Native emulator screenshot did not adopt submission dimensions")
        summary["nativeScreenshotPixels"] = [1179, 2556]
        summary["requestedRecordingPixels"] = [720, 1560]
        with apk.open("rb") as binary:
            summary["apkSha256"] = hashlib.file_digest(binary, "sha256").hexdigest()
        adb.run("install", "-r", "-t", str(apk), timeout=120)
        if adb.run("shell", "pm", "clear", PACKAGE).decode().strip() != "Success":
            raise RuntimeError("Could not reset the selected emulator's app")
        summary["cleanInstall"] = True
        recorder.start()
        environment = os.environ.copy()
        environment["BILLING_RUNTIME_RUN_ID"] = run_id
        options = ({"creationflags": subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW}
                   if os.name == "nt" else {"start_new_session": True})
        process = subprocess.Popen([
            flutter, "drive", "--no-pub", "-d", args.serial,
            "--driver=tools/production_purchase_runtime/driver.dart",
            "--target=integration_test/purchase_journey_test.dart",
            f"--use-application-binary={apk}", "--timeout=780",
        ], cwd=ROOT, env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, encoding="utf-8", errors="replace", **options)

        def read_log() -> None:
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

        reader = threading.Thread(target=read_log, daemon=True)
        reader.start()
        deadline = time.monotonic() + args.timeout
        while time.monotonic() < deadline:
            if recorder.errors:
                raise RuntimeError(f"Native recording failed: {recorder.errors}")
            try:
                stage = events.get(timeout=0.5)
            except queue.Empty:
                continue
            if stage is None:
                break
            dialogs.perform(stage)
        else:
            raise TimeoutError("Production purchase journey exceeded its deadline")
        summary["driveExitCode"] = process.wait(timeout=20)
        reader.join(timeout=5)
        if summary["driveExitCode"] != 0:
            raise RuntimeError("Flutter production purchase journey failed")
        report = json.loads((artifacts / "result.json").read_text(encoding="utf-8"))
        evidence = validate_evidence(report, artifacts, dialogs.completed)
        summary["verified"] = evidence["verified"]
        summary["passed"] = True
    except (Exception, KeyboardInterrupt) as error:
        summary["error"] = f"{type(error).__name__}: {error}"
        dialogs.diagnostics("run-failure")
    finally:
        for name, cleanup in [
            ("process", lambda: stop_owned_process(process) if process else None),
            ("recording", recorder.finish),
            ("remote", lambda: adb.cleanup() if not recorder.thread.is_alive() else None),
        ]:
            try:
                cleanup()
            except Exception as error:
                summary[f"{name}CleanupError"] = str(error)
                summary["passed"] = False
        for setting, value in original_display.items():
            try:
                adb.run("shell", "wm", setting, value or "reset")
            except Exception as error:
                summary[f"{setting}RestoreError"] = str(error)
                summary["passed"] = False
        summary["nativeActions"] = dialogs.completed
        summary["recordingSegments"] = recorder.segments
        summary["recordingCoverage"] = recorder.coverage_summary
        (artifacts / "run.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(f"Production purchase evidence: {artifacts}", flush=True)
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
