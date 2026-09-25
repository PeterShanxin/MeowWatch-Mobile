#!/usr/bin/env python3
"""Verify real normal-APK playback across HOME and a separate app process."""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import hashlib
import json
import math
import os
from pathlib import Path
import queue
import re
import signal
import struct
import subprocess
import threading
import time
from typing import Callable, Sequence, TypeVar
import xml.etree.ElementTree as ET

from tools.android_install.runner import (
    ACTIVITY, Adb, PACKAGE, RuntimeFailure, focused_component,
    install_output_succeeded, launch_output_succeeded, parse_package_metadata,
    validate_mp4,
)
from tools.incoming_media_runtime.run import center, exact, nodes, require_review
from tools.billing_runtime.native_dialog import (
    LAUNCHER_PACKAGE, SETUP_PACKAGE, UnsafeDialog, image_size,
    select_google_sdk_setup_anr_close, select_pixel_launcher_anr_close,
)
from tools.android_native_ui.observer import DEFAULT_APK, NativeUiObserver, ObserverIntegrityFailure, remaining_timeout


FIXTURE_NAME = "sync-fixture.mp4"
FIXTURE_URL = "http://10.0.2.2:18765/sync-fixture.mp4"
MAX_OBSERVATION_TIMEOUTS = 3
MAX_PREPARATION_ANR_RECOVERIES = 2
POST_ROLL_SECONDS = 8
MAX_RECORDING_BYTES = 64 * 1024 * 1024
MAX_CODEC_EVIDENCE_BYTES = 256 * 1024
MAX_FILE_QUERY_BYTES = 512
MAX_LIVE_READ_SUMMARIES = 128
OWNED_RECORDING_PATH = re.compile(r"/sdcard/meowwatch-install-[A-Za-z0-9_-]+/lifecycle-\d+\.mp4")
T = TypeVar("T")


class PreparationRecoveryFailure(RuntimeFailure):
    """Preparation recovery must stop rather than repeat an uncertain action."""


def recording_size(display: str) -> tuple[int, int]:
    sizes = re.findall(r"(?m)^(Physical|Override) size: (\d+)x(\d+)\s*$", display)
    if not sizes or len({kind for kind, _, _ in sizes}) != len(sizes):
        raise RuntimeFailure("native recording requires unambiguous Android display dimensions")
    selected = next((row for row in sizes if row[0] == "Override"), sizes[0])
    width, height = int(selected[1]), int(selected[2])
    if not 200 <= width <= 10000 or not 200 <= height <= 10000:
        raise RuntimeFailure("native recording display dimensions are outside supported bounds")
    scale = min(432 / width, 960 / height, 1)
    return max(2, int(width * scale) // 2 * 2), max(2, int(height * scale) // 2 * 2)


def validate_recording_duration(duration: float, elapsed: float, exited_early: bool) -> None:
    if (not math.isfinite(duration) or not math.isfinite(elapsed) or duration <= 0
            or elapsed <= 0 or duration > 181 or elapsed > 180 or exited_early
            or duration + 3 < elapsed):
        raise RuntimeFailure("native recording ended early or does not cover its measured segment")


def recording_media_ready(data: bytes) -> bool:
    """Require a complete H.264 picture NAL in the live MP4's media payload."""
    offset = 0
    while offset + 8 <= len(data):
        size = int.from_bytes(data[offset:offset + 4], "big")
        kind = data[offset + 4:offset + 8]
        header = 16 if size == 1 else 8
        if offset + header > len(data):
            return False
        if size == 1:
            size = int.from_bytes(data[offset + 8:offset + 16], "big")
        if kind == b"mdat":
            # MediaMuxer leaves the mdat length unset until finalization.
            offset += header
            while offset + 5 <= len(data):
                length = int.from_bytes(data[offset:offset + 4], "big")
                if length <= 0 or offset + 4 + length > len(data):
                    return False
                if data[offset + 4] & 0x1f in (1, 5):
                    return True
                offset += 4 + length
            return False
        if size < header:
            return False
        offset += size
    return False


def recording_device_elapsed(data: bytes) -> float:
    if re.fullmatch(rb"[0-9]+(?:\.[0-9]+)? [0-9]+(?:\.[0-9]+)?\s*", data) is None:
        raise RuntimeFailure("native recording device elapsed clock is unavailable")
    value = float(data.split()[0])
    if not math.isfinite(value) or value <= 0:
        raise RuntimeFailure("native recording device elapsed clock is invalid")
    return value


def recording_frame_clock(data: bytes, presentation_times: list[float]) -> list[float]:
    """Read Android 15 screenrecord's original Winscope v2 elapsed timestamps."""
    magic = b"#VV1NSC0PET1ME2#"
    found = []
    offset = 0
    while offset + 8 <= len(data):
        size = int.from_bytes(data[offset:offset + 4], "big")
        kind = data[offset + 4:offset + 8]
        header = 16 if size == 1 else 8
        if size == 1:
            size = int.from_bytes(data[offset + 8:offset + 16], "big")
        elif size == 0:
            size = len(data) - offset
        if size < header or offset + size > len(data):
            raise RuntimeFailure("native recording has an invalid MP4 box")
        if kind == b"mdat":
            payload = data[offset + header:offset + size]
            location = payload.find(magic)
            while location >= 0:
                found.append(payload[location + len(magic):])
                location = payload.find(magic, location + len(magic))
        offset += size
    if offset != len(data) or len(found) != 1 or len(found[0]) < 16:
        raise RuntimeFailure("native recording requires unique Winscope v2 frame-clock metadata")
    version, _realtime_offset, count = struct.unpack_from("<IqI", found[0])
    if version != 2 or not 1 <= count <= 20000 or count != len(presentation_times) or len(found[0]) < 16 + count * 8:
        raise RuntimeFailure("native recording frame-clock version or count is invalid")
    elapsed_ns = struct.unpack_from(f"<{count}Q", found[0], 16)
    elapsed = [value / 1e9 for value in elapsed_ns]
    if (any(value <= 0 for value in elapsed_ns)
            or any(b < a for a, b in zip(elapsed_ns, elapsed_ns[1:]))
            or any(not math.isfinite(value) or value < 0 for value in presentation_times)):
        raise RuntimeFailure("native recording frame clock does not match its actual video PTS")

    # screenrecord gives the same microsecond PTS to the MP4 writer and Winscope.
    # Android 15 MPEG4Writer rounds to 90 kHz ticks and may reuse the previous
    # duration when doing so changes one timestamp by less than 100 us. Replay
    # that exact integer conversion; ffprobe prints pts_time to six decimals.
    timescale = 90000
    previous_us = previous_duration_ticks = pts_ticks = 0
    for raw_ns, pts in zip(elapsed_ns, presentation_times):
        relative_ns = raw_ns - elapsed_ns[0]
        if relative_ns % 1000:
            raise RuntimeFailure("native recording frame clock does not match its actual video PTS")
        timestamp_us = relative_ns // 1000
        duration_ticks = ((timestamp_us * timescale + 500000) // 1000000
                          - (previous_us * timescale + 500000) // 1000000)
        if duration_ticks < 0:
            raise RuntimeFailure("native recording frame clock does not match its actual video PTS")
        if previous_duration_ticks and duration_ticks != previous_duration_ticks:
            numerator = (previous_duration_ticks - duration_ticks) * 1000000 + timescale // 2
            adjustment_us = (numerator // timescale if numerator >= 0
                             else -((-numerator) // timescale))
            if -100 < adjustment_us < 100:
                duration_ticks = previous_duration_ticks
                timestamp_us += adjustment_us
        pts_ticks += duration_ticks
        if abs(pts_ticks / timescale - (pts - presentation_times[0])) > 0.00000051:
            raise RuntimeFailure("native recording frame clock does not match its actual video PTS")
        previous_us, previous_duration_ticks = timestamp_us, duration_ticks
    return elapsed


def require_recorded_observation(elapsed: list[float], required: float, stopped: float) -> None:
    if (not math.isfinite(required) or not math.isfinite(stopped) or required <= 0
            or not elapsed or elapsed[0] > required or elapsed[-1] < required
            or required > stopped):
        raise RuntimeFailure("native recording does not cover its final required device observation")


class RecordingPictures:
    """Incrementally count complete picture NALs without rereading the MP4."""
    def __init__(self) -> None:
        self.buffer = b""
        self.read_bytes = 0
        self.consumed_bytes = 0
        self.in_media = False
        self.picture_ends: list[int] = []

    def feed(self, chunk: bytes) -> None:
        self.read_bytes += len(chunk)
        if self.read_bytes > MAX_RECORDING_BYTES:
            raise RuntimeFailure("native recording progress exceeds its byte bound")
        self.buffer += chunk
        while True:
            if not self.in_media:
                if len(self.buffer) < 8:
                    return
                size = int.from_bytes(self.buffer[:4], "big")
                header = 16 if size == 1 else 8
                if len(self.buffer) < header:
                    return
                if self.buffer[4:8] == b"mdat":
                    consumed = header
                    self.in_media = True
                else:
                    if size == 1:
                        size = int.from_bytes(self.buffer[8:16], "big")
                    if not header <= size <= 1024 * 1024:
                        raise RuntimeFailure("native recording progress has an invalid MP4 header")
                    if len(self.buffer) < size:
                        return
                    consumed = size
            else:
                if len(self.buffer) < 4:
                    return
                size = int.from_bytes(self.buffer[:4], "big")
                if not 1 <= size <= 8 * 1024 * 1024:
                    raise RuntimeFailure("native recording progress has an invalid NAL length")
                if len(self.buffer) < 4 + size:
                    return
                consumed = 4 + size
                if self.buffer[4] & 0x1f in (1, 5):
                    self.picture_ends.append(self.consumed_bytes + consumed)
                    if len(self.picture_ends) > 20000:
                        raise RuntimeFailure("native recording progress exceeds its picture bound")
            self.consumed_bytes += consumed
            self.buffer = self.buffer[consumed:]


class LifecycleRecording:
    """One original, bounded screenrecord segment with verified process ownership."""

    def __init__(self, adb: Adb, output: Path, index: int, size: tuple[int, int]):
        self.adb, self.size = adb, size
        self.output = output / "native" / f"lifecycle-{index:02}.mp4"
        self.remote = f"{adb.remote_prefix}lifecycle-{index:02}.mp4"
        self.process: subprocess.Popen[str] | None = None
        self.reader: threading.Thread | None = None
        self.pid: str | None = None
        self.lines: list[str] = []
        self.finished = False
        self.codec_log_since: str | None = None
        self.metadata: dict[str, object] = {"file": str(self.output.relative_to(output)).replace("\\", "/"),
                                            "status": "not-started", "width": size[0], "height": size[1],
                                            "timeLimitSeconds": 180, "bitRate": 2000000}

    def require_owned_path(self) -> None:
        if (OWNED_RECORDING_PATH.fullmatch(self.remote) is None
                or self.remote != self.adb.remote_prefix + self.output.name):
            raise RuntimeFailure("native recording file query requires the exact owned output path")

    def device_file_receipt(self) -> dict[str, object]:
        """Observe the finalized owned file; defer query failures until after decode."""
        self.require_owned_path()
        receipt: dict[str, object] = {"status": "failed", "queries": {},
                                      "timeoutSecondsPerQuery": 3,
                                      "maxFileBytes": MAX_RECORDING_BYTES,
                                      "maxOutputBytesPerQuery": MAX_FILE_QUERY_BYTES}
        self.metadata["deviceFileReceipt"] = receipt
        for name, arguments in (("size", ("exec-out", "stat", "-c", "%s", self.remote)),
                                ("sha256", ("exec-out", "sha256sum", self.remote))):
            query: dict[str, object] = {"startedAtMonotonic": time.monotonic()}
            receipt["queries"][name] = query
            try:
                result = self.adb.run(*arguments, timeout=3, check=False)
                stdout, stderr = result.stdout or b"", result.stderr or b""
                query.update({"exitCode": result.returncode,
                              "stdoutBytes": len(stdout), "stderrBytes": len(stderr),
                              "stdoutPrefix": stdout[:MAX_FILE_QUERY_BYTES].decode("ascii", errors="replace"),
                              "stderrPrefix": stderr[:MAX_FILE_QUERY_BYTES].decode("ascii", errors="replace")})
                if (result.returncode != 0 or stderr.strip()
                        or len(stdout) > MAX_FILE_QUERY_BYTES or len(stderr) > MAX_FILE_QUERY_BYTES):
                    raise RuntimeFailure("device recording file query did not return one bounded result")
                if name == "size":
                    if re.fullmatch(rb"[0-9]+\s*", stdout) is None or not 0 < int(stdout) <= MAX_RECORDING_BYTES:
                        raise RuntimeFailure("finalized device recording size is invalid or exceeds its byte bound")
                    receipt["bytes"] = int(stdout)
                else:
                    match = re.fullmatch(rb"([0-9a-f]{64})  " + re.escape(self.remote.encode("ascii")) + rb"\r?\n?", stdout)
                    if match is None:
                        raise RuntimeFailure("device recording digest does not identify the exact owned file")
                    receipt["sha256"] = match[1].decode("ascii")
            except (RuntimeFailure, OSError, subprocess.TimeoutExpired) as error:
                query.update({"status": "failed", "error": str(error) if isinstance(error, RuntimeFailure) else type(error).__name__})
                receipt["error"] = query["error"]
                return receipt
            finally:
                query["finishedAtMonotonic"] = time.monotonic()
            query["status"] = "verified"
        receipt["status"] = "verified"
        return receipt

    @staticmethod
    def live_read_summary(section: dict, summary: dict) -> None:
        summaries = section.setdefault("readSummaries", [])
        if len(summaries) >= MAX_LIVE_READ_SUMMARIES:
            summaries.pop(0)
            section["droppedEarlierReadSummaries"] = section.get("droppedEarlierReadSummaries", 0) + 1
        summaries.append(summary)

    def codec_evidence(self, name: str, arguments: tuple[str, ...]) -> bytes | None:
        """Bound auxiliary diagnostics; never replace recording acceptance failures."""
        evidence: dict[str, object] = {"timeoutSeconds": 3, "byteLimitPerStream": MAX_CODEC_EVIDENCE_BYTES}
        self.metadata.setdefault("codecEvidence", {})[name] = evidence
        try:
            result = self.adb.run(*arguments, timeout=3, check=False)
            stdout, stderr = result.stdout or b"", result.stderr or b""
            evidence.update({"status": "collected" if result.returncode == 0 else "failed",
                             "exitCode": result.returncode})
        except subprocess.TimeoutExpired as error:
            stdout, stderr = error.stdout or b"", error.stderr or b""
            evidence["status"] = "timeout"
        except (OSError, RuntimeFailure) as error:
            stdout, stderr = b"", b""
            evidence.update({"status": "failed", "errorType": type(error).__name__})
        for label, data in (("stdout", stdout), ("stderr", stderr)):
            if isinstance(data, str):
                data = data.encode("utf-8", errors="replace")
            path = self.output.with_suffix(f".{name}.{label}.txt")
            path.write_bytes(data[:MAX_CODEC_EVIDENCE_BYTES])
            evidence[label] = {"file": path.name, "bytes": len(data),
                               "truncated": len(data) > MAX_CODEC_EVIDENCE_BYTES}
        return stdout if evidence["status"] == "collected" else None

    def start(self, *, startup_action: Callable[[float], None] | None = None,
              finite_transition: bool = False) -> None:
        if self.process is not None or self.finished:
            raise RuntimeFailure("native recording cannot be started or its startup action repeated")
        if finite_transition and startup_action is None:
            raise RuntimeFailure("finite native transition requires one owned startup action")
        self.require_owned_path()
        if (re.fullmatch(r"emulator-[0-9]+", self.adb.serial) is None
                or self.adb.run("shell", "getprop", "ro.kernel.qemu").stdout.strip() != b"1"):
            raise RuntimeFailure("native recording requires an owned path and verified emulator")
        if self.adb.run("shell", "pidof", "screenrecord", check=False).stdout.strip():
            raise RuntimeFailure("refusing to replace an existing Android screen recorder")
        self.output.parent.mkdir(parents=True, exist_ok=True)
        self.adb.remote_files.append(self.remote)
        baseline = self.codec_evidence("codec-log-clock", ("exec-out", "date", "+%m-%d %H:%M:%S.000"))
        if baseline is not None and re.fullmatch(rb"[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.000\s*", baseline):
            self.codec_log_since = baseline.decode("ascii").strip()
        else:
            self.metadata["codecLogSkipped"] = "device log-clock baseline unavailable or invalid"
        width, height = self.size
        command = (f"screenrecord --verbose --size {width}x{height} --bit-rate 2000000 --time-limit 180 {self.remote} & "
                   "record_pid=$!; printf 'LIFECYCLE_RECORDER_PID=%s\\n' \"$record_pid\"; wait \"$record_pid\"")
        self.metadata["launchRequestedAtMonotonic"] = time.monotonic()
        self.process = subprocess.Popen(self.adb.prefix + ["shell", command], stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
        observed: queue.Queue[str] = queue.Queue()

        def read_output() -> None:
            assert self.process and self.process.stdout
            for line in self.process.stdout:
                self.lines.append(line)
                match = re.fullmatch(r"LIFECYCLE_RECORDER_PID=(\d+)\s*", line)
                if match:
                    observed.put(match[1])

        self.reader = threading.Thread(target=read_output, daemon=True)
        self.reader.start()
        try:
            self.pid = observed.get(timeout=10)
            self.metadata.update({"pid": int(self.pid), "pidObservedAtMonotonic": time.monotonic()})
            deadline = float(self.metadata["launchRequestedAtMonotonic"]) + 20
            readiness = {"deadlineAtMonotonic": deadline, "probeAttempts": 0,
                         "timeoutCount": 0, "timeouts": []}
            self.metadata["readinessProbe"] = readiness
            if startup_action is not None:
                action: dict[str, object] = {"status": "not-sent", "deadlineAtMonotonic": deadline}
                self.metadata["startupAction"] = action
                remaining = deadline - time.monotonic()
                if remaining <= 0 or self.process.poll() is not None:
                    raise RuntimeFailure("owned recorder is unavailable before its startup action")
                raw = self.adb.run("exec-out", "cat", f"/proc/{self.pid}/cmdline",
                                   timeout=min(3, remaining)).stdout
                expected = ["--verbose", "--size", f"{width}x{height}", "--bit-rate", "2000000",
                            "--time-limit", "180", self.remote, ""]
                command = raw.decode("utf-8", errors="replace").split("\x00")
                if (len(raw) > 4096 or command[0].rsplit("/", 1)[-1] != "screenrecord"
                        or command[1:] != expected):
                    raise RuntimeFailure("native recorder ownership changed before startup action; no action sent")
                action["ownershipVerifiedAtMonotonic"] = time.monotonic()
                if float(action["ownershipVerifiedAtMonotonic"]) >= deadline or self.process.poll() is not None:
                    raise RuntimeFailure("owned recorder is unavailable before its startup action")
                action["triggerDeviceElapsedSeconds"] = recording_device_elapsed(self.adb.run(
                    "exec-out", "cat", "/proc/uptime",
                    timeout=min(3, deadline - float(action["ownershipVerifiedAtMonotonic"]))
                ).stdout)
                action["triggerClockSource"] = "Android /proc/uptime immediately before callback dispatch"
                action_started = time.monotonic()
                if action_started >= deadline or self.process.poll() is not None:
                    raise RuntimeFailure("owned recorder is unavailable at startup action dispatch")
                action.update({"status": "sent", "startedAtMonotonic": action_started,
                               "ownedRecorderPid": int(self.pid), "beforeMediaReadiness": True})
                try:
                    # The callback receives the original launch deadline. It is
                    # an existing native operation, never a readiness retry.
                    startup_action(deadline)
                except Exception as error:
                    action.update({"status": "uncertain", "errorType": type(error).__name__})
                    raise RuntimeFailure("native recording startup action failed; refusing to repeat it") from error
                finally:
                    action["finishedAtMonotonic"] = time.monotonic()
                action["status"] = "completed"
                if finite_transition:
                    accepted_at = time.monotonic()
                    if accepted_at >= deadline or self.process.poll() is not None:
                        raise RuntimeFailure("finite native transition exceeded its original launch deadline")
                    self.metadata.update({"status": "recording", "startedAtMonotonic": accepted_at,
                                          "finiteTransition": True,
                                          "readiness": "owned recorder and completed action; finalized frames required",
                                          "measurementStart": "pre-dispatch device trigger clock; no live-picture claim"})
                    return
                self.metadata["measurementStart"] = "live picture and device clock after the startup action"

            def record_readiness_timeout(operation: str, error: subprocess.TimeoutExpired) -> None:
                occurred = time.monotonic()
                timeout = error.timeout
                readiness["timeoutCount"] = int(readiness["timeoutCount"]) + 1
                readiness["timeouts"].append({
                    "operation": operation,
                    "probeAttempt": readiness["probeAttempts"],
                    "timeoutSeconds": float(timeout) if timeout is not None else None,
                    "occurredAtMonotonic": occurred,
                })

            while True:
                probe_started = time.monotonic()
                remaining = deadline - probe_started
                if remaining <= 0:
                    break
                if self.process.poll() is not None:
                    raise RuntimeFailure("native lifecycle recorder exited before media was ready")
                readiness["probeAttempts"] = int(readiness["probeAttempts"]) + 1
                try:
                    prefix = self.adb.run("exec-out", "head", "-c", "1048576", self.remote,
                                          timeout=min(3, remaining), check=False)
                except subprocess.TimeoutExpired as error:
                    record_readiness_timeout("media-prefix", error)
                    continue
                if len(prefix.stdout) > 1048576:
                    raise RuntimeFailure("native recording readiness prefix exceeds its read bound")
                self.live_read_summary(readiness, {
                    "startedAtMonotonic": probe_started, "finishedAtMonotonic": time.monotonic(),
                    "exitCode": prefix.returncode, "offset": 0, "bytes": len(prefix.stdout),
                    "sha256": hashlib.sha256(prefix.stdout).hexdigest(),
                })
                if prefix.returncode == 0 and recording_media_ready(prefix.stdout):
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        break
                    try:
                        clock = self.adb.run("exec-out", "cat", "/proc/uptime", timeout=min(3, remaining))
                    except subprocess.TimeoutExpired as error:
                        record_readiness_timeout("device-clock", error)
                        continue
                    device_elapsed = recording_device_elapsed(clock.stdout)
                    accepted_at = time.monotonic()
                    if accepted_at > deadline:
                        break
                    if self.process.poll() is not None:
                        raise RuntimeFailure("native lifecycle recorder exited before media was ready")
                    self.metadata.update({"status": "recording", "startedAtMonotonic": accepted_at,
                                          "mediaReadyAtDeviceElapsedSeconds": device_elapsed,
                                          "readiness": "complete H.264 picture NAL in native MP4 mdat"})
                    self.codec_evidence("codec-state", ("shell", "dumpsys", "media.codec"))
                    return
                time.sleep(0.2)
            raise RuntimeFailure(
                "native lifecycle recorder did not establish picture and device clock before the readiness deadline")
        except queue.Empty:
            self.metadata["status"] = "failed"
            raise RuntimeFailure("could not identify the owned lifecycle recorder") from None
        except (RuntimeFailure, OSError, subprocess.TimeoutExpired) as error:
            self.metadata.update({"status": "failed", "error": str(error)})
            raise

    def observe_startup_result(self, phase: str, *, deadline: float | None = None) -> None:
        if (self.metadata.get("startupAction", {}).get("status") != "completed"
                or self.metadata["status"] != "recording"
                or ("mediaReadyAtDeviceElapsedSeconds" not in self.metadata
                    and not self.metadata.get("finiteTransition"))):
            raise RuntimeFailure("recording startup result requires a completed action and active owned segment")
        if "firstPostActionObservation" in self.metadata:
            raise RuntimeFailure("the first recording startup observation cannot be replaced")
        if deadline is not None and time.monotonic() >= deadline:
            raise RuntimeFailure("first post-action observation exceeded the original launch deadline")
        elapsed = recording_device_elapsed(self.adb.run(
            "exec-out", "cat", "/proc/uptime",
            timeout=remaining_timeout(deadline, 3)).stdout)
        observed_at = time.monotonic()
        if deadline is not None and observed_at >= deadline:
            raise RuntimeFailure("first post-action observation exceeded the original launch deadline")
        self.metadata["firstPostActionObservation"] = {
            "phase": phase, "deviceElapsedSeconds": elapsed, "observedAtMonotonic": observed_at,
            "source": "Android /proc/uptime after actual native observation and original screenshot",
        }

    def post_roll(self, phase: str) -> None:
        self.require_owned_path()
        # Winscope timestamps are written only when screenrecord stops. Live
        # NAL progress is a drain hint; the finalized timestamps decide coverage.
        required = recording_device_elapsed(
            self.adb.run("exec-out", "cat", "/proc/uptime", timeout=3).stdout)
        self.metadata.update({"requiredThroughDeviceElapsedSeconds": required,
                              "requiredThroughPhase": phase,
                              "requiredThroughSource": "Android /proc/uptime after final native observation and screenshot"})
        deadline = time.monotonic() + POST_ROLL_SECONDS
        progress = RecordingPictures()
        prefix_digest = hashlib.sha256()
        observations: list[dict[str, object]] = []
        self.metadata["postRoll"] = {"limitSeconds": POST_ROLL_SECONDS,
                                     "startedAtMonotonic": deadline - POST_ROLL_SECONDS,
                                     "observations": observations}
        size = self.adb.run("shell", "stat", "-c", "%s", self.remote, timeout=2).stdout.strip()
        if re.fullmatch(rb"[0-9]+", size) is None or not 0 < int(size) <= MAX_RECORDING_BYTES:
            raise RuntimeFailure("native recording post-roll cannot establish its original file size")
        initial_bytes = int(size)
        self.metadata["postRoll"]["initialBytes"] = initial_bytes
        while time.monotonic() < deadline:
            if self.process is None or self.process.poll() is not None:
                raise RuntimeFailure("native recording exited during post-roll")
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            # The path was generated and verified by start(); the integer byte
            # cursor avoids repeatedly transferring already observed footage.
            command = f"tail -c +{progress.read_bytes + 1} {self.remote} | head -c 1048576"
            read_started = time.monotonic()
            offset = progress.read_bytes
            try:
                chunk = self.adb.run("exec-out", "sh", "-c", command, timeout=min(2, remaining)).stdout
            except subprocess.TimeoutExpired as error:
                # Retry this read-only byte range inside the original budget.
                # Partial timed-out output is not a verified contiguous prefix.
                self.live_read_summary(self.metadata["postRoll"], {
                    "startedAtMonotonic": read_started, "finishedAtMonotonic": time.monotonic(),
                    "offset": offset, "status": "timeout", "acceptedBytes": 0,
                    "discardedBytes": len(error.stdout or b""),
                })
                continue
            if time.monotonic() > deadline:
                raise RuntimeFailure("native recording post-roll read exceeded its original deadline")
            if len(chunk) > 1048576:
                raise RuntimeFailure("native recording post-roll chunk exceeds its read bound")
            progress.feed(chunk)
            prefix_digest.update(chunk)
            self.live_read_summary(self.metadata["postRoll"], {
                "startedAtMonotonic": read_started, "finishedAtMonotonic": time.monotonic(),
                "offset": offset, "bytes": len(chunk), "sha256": hashlib.sha256(chunk).hexdigest(),
                "prefixBytes": progress.read_bytes, "prefixSha256": prefix_digest.hexdigest(),
                "lastCompletePictureEnd": progress.picture_ends[-1] if progress.picture_ends else None,
            })
            observations.append({"hostMonotonic": time.monotonic(), "bytesRead": progress.read_bytes,
                                 "completePictureNals": len(progress.picture_ends)})
            remaining = deadline - time.monotonic()
            if remaining > 0 and len(chunk) < 1048576:
                time.sleep(min(1, remaining))
        advanced = sum(end > initial_bytes for end in progress.picture_ends)
        self.metadata["postRoll"]["newCompletePictureNals"] = advanced
        self.metadata["postRoll"]["finishedAtMonotonic"] = time.monotonic()
        if not advanced:
            raise RuntimeFailure("native recording produced no new complete picture during bounded post-roll")

    def finish(self, *, required_phase: str | None = None) -> None:
        if self.finished or self.process is None:
            return
        self.finished = True
        post_roll_error: Exception | None = None
        finite_transition = self.metadata.get("finiteTransition") is True
        if required_phase is not None and not finite_transition:
            try:
                self.post_roll(required_phase)
            except (RuntimeFailure, OSError, subprocess.TimeoutExpired) as error:
                post_roll_error = error
                self.metadata["postRollError"] = str(error) if isinstance(error, RuntimeFailure) else type(error).__name__
        stopped = time.monotonic()
        self.metadata["stopRequestedAtMonotonic"] = stopped
        exited_early = self.process.poll() is not None
        self.metadata["exitedBeforeStopRequest"] = exited_early
        try:
            self.require_owned_path()
            clock_error: Exception | None = None
            if not exited_early:
                if self.pid is None:
                    raise RuntimeFailure("native lifecycle recorder PID is missing")
                command = self.adb.run("exec-out", "cat", f"/proc/{self.pid}/cmdline").stdout.decode(
                    "utf-8", errors="replace").split("\x00")
                if command[0].rsplit("/", 1)[-1] != "screenrecord" or self.remote not in command:
                    raise RuntimeFailure("native lifecycle recorder ownership changed; no signal sent")
                try:
                    self.metadata["stopRequestedAtDeviceElapsedSeconds"] = recording_device_elapsed(
                        self.adb.run("exec-out", "cat", "/proc/uptime", timeout=3).stdout)
                except (RuntimeFailure, OSError, subprocess.TimeoutExpired) as error:
                    clock_error = error
                self.adb.run("shell", "kill", "-2", self.pid)
            exit_code = self.process.wait(timeout=20)
            self.metadata["exitCode"] = exit_code
            self.metadata["recorderExitedAtMonotonic"] = time.monotonic()
            if self.reader:
                self.reader.join(timeout=5)
                if self.reader.is_alive():
                    raise RuntimeFailure("native lifecycle recorder output did not close")
            device_receipt = self.device_file_receipt()
            self.metadata["pullStartedAtMonotonic"] = time.monotonic()
            self.adb.run("pull", self.remote, str(self.output), timeout=40)
            if not 0 < self.output.stat().st_size <= MAX_RECORDING_BYTES:
                raise RuntimeFailure("pulled native recording exceeds its file byte bound")
            data = self.output.read_bytes()
            self.metadata.update({"pulledAtMonotonic": time.monotonic(),
                                  "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)})
            self.metadata["deviceFileMatchesPulledFile"] = (
                device_receipt["status"] == "verified" and device_receipt["bytes"] == len(data)
                and device_receipt["sha256"] == self.metadata["sha256"])
            validate_mp4(data)
            if exit_code != 0:
                raise RuntimeFailure("native lifecycle recorder did not exit successfully")
            if exited_early:
                raise RuntimeFailure("native recording ended early or does not cover its measured segment")
            if clock_error is not None:
                raise RuntimeFailure("native recording device elapsed clock is unavailable") from clock_error
            probe = subprocess.run(["ffprobe", "-v", "error", "-show_entries",
                                    "stream=codec_type,width,height,duration:frame=media_type,pts_time",
                                    "-show_frames", "-of", "json", str(self.output)],
                                   capture_output=True, check=False, timeout=15)
            if probe.returncode:
                raise RuntimeFailure("native lifecycle recording could not be decoded by ffprobe")
            try:
                metadata = json.loads(probe.stdout)
                streams = metadata["streams"]
                videos = [stream for stream in streams if stream["codec_type"] == "video"]
                if (len(videos) != 1 or any(stream["codec_type"] not in ("video", "data") for stream in streams)
                        or (videos[0]["width"], videos[0]["height"]) != self.size):
                    raise ValueError()
                duration = float(videos[0]["duration"])
            except (ValueError, TypeError, KeyError):
                raise RuntimeFailure("native lifecycle recording dimensions or duration are invalid") from None
            if finite_transition:
                action = self.metadata.get("startupAction")
                if (not isinstance(action, dict) or action.get("status") != "completed"
                        or "triggerDeviceElapsedSeconds" not in action):
                    raise RuntimeFailure("finite native transition has no completed owned action")
                elapsed = (float(self.metadata["stopRequestedAtDeviceElapsedSeconds"])
                           - float(action["triggerDeviceElapsedSeconds"]))
                if not math.isfinite(duration) or not 0 < duration <= 181 or not 0 < elapsed <= 180:
                    raise RuntimeFailure("finite native transition has invalid video duration or device capture window")
                self.metadata.update({"videoDurationSeconds": duration, "deviceCaptureWindowSeconds": elapsed,
                                      "measurementClock": "Android /proc/uptime elapsed seconds",
                                      "hostSegmentSeconds": stopped - float(self.metadata["startedAtMonotonic"])})
            else:
                if "mediaReadyAtDeviceElapsedSeconds" not in self.metadata:
                    raise RuntimeFailure("native lifecycle recording never reached media readiness")
                elapsed = (float(self.metadata["stopRequestedAtDeviceElapsedSeconds"])
                           - float(self.metadata["mediaReadyAtDeviceElapsedSeconds"]))
                self.metadata.update({"videoDurationSeconds": duration, "measuredSegmentSeconds": elapsed,
                                      "measurementClock": "Android /proc/uptime elapsed seconds",
                                      "hostSegmentSeconds": stopped - float(self.metadata["startedAtMonotonic"])})
            frame_clock_error: Exception | None = None
            try:
                pts = [float(frame["pts_time"]) for frame in metadata["frames"] if frame["media_type"] == "video"]
                frame_clock = recording_frame_clock(data, pts)
                self.metadata.update({"frameClockSource": "Android screenrecord Winscope v2 elapsedRealtime nanoseconds",
                                      "frameCount": len(frame_clock),
                                      "firstFrameDeviceElapsedSeconds": frame_clock[0],
                                      "lastFrameDeviceElapsedSeconds": frame_clock[-1]})
                self.output.with_suffix(".frame-clock.json").write_text(json.dumps({
                    "deviceElapsedSeconds": frame_clock, "videoPresentationSeconds": pts,
                }, indent=2), encoding="utf-8")
            except (RuntimeFailure, KeyError, TypeError, ValueError) as error:
                frame_clock_error = error
                self.metadata["frameClockError"] = str(error) if isinstance(error, RuntimeFailure) else type(error).__name__
            if not finite_transition:
                validate_recording_duration(duration, elapsed, exited_early)
            decoded = subprocess.run(["ffmpeg", "-v", "error", "-xerror", "-i", str(self.output),
                                      "-map", "0:v:0", "-enc_time_base:v", "demux", "-fps_mode", "passthrough",
                                      "-f", "null", "-"], capture_output=True, check=False, timeout=60)
            self.metadata["decodeExitCode"] = decoded.returncode
            decode_failed = decoded.returncode != 0 or bool(decoded.stderr.strip())
            if decode_failed:
                self.metadata["firstDecodeError"] = {
                    "stage": "ffmpeg", "exitCode": decoded.returncode,
                    "stderrBytes": len(decoded.stderr), "stderrSha256": hashlib.sha256(decoded.stderr).hexdigest(),
                    "stderrPrefix": decoded.stderr[:4096].decode("utf-8", errors="replace"),
                }
            try:
                self.output.with_suffix(".decode.log").write_bytes(decoded.stderr)
            except OSError as error:
                self.metadata["decodeLogWriteError"] = type(error).__name__
                if not decode_failed:
                    raise
            if decode_failed:
                raise RuntimeFailure("native lifecycle recording could not be decoded completely")
            if frame_clock_error is not None:
                raise RuntimeFailure("native recording frame-clock evidence is unavailable or invalid") from frame_clock_error
            if finite_transition:
                action = self.metadata["startupAction"]
                observation = self.metadata.get("firstPostActionObservation")
                if required_phase is not None:
                    raise RuntimeFailure("finite native transition cannot claim live post-roll coverage")
                if (observation is None or observation.get("phase") != "15-normal-return-home"
                        or float(observation["observedAtMonotonic"]) <= float(action["finishedAtMonotonic"])
                        or float(observation["observedAtMonotonic"]) >=
                        float(self.metadata["readinessProbe"]["deadlineAtMonotonic"])):
                    raise RuntimeFailure("finite native transition is missing its fresh Home observation")
                trigger = float(action["triggerDeviceElapsedSeconds"])
                observed = float(observation["deviceElapsedSeconds"])
                stopped_device = float(self.metadata["stopRequestedAtDeviceElapsedSeconds"])
                if (not trigger < observed <= stopped_device or len(frame_clock) < 2
                        or frame_clock[0] >= frame_clock[-1]
                        or not any(trigger < frame <= stopped_device for frame in frame_clock)):
                    raise RuntimeFailure("finite native transition lacks two frames and a post-trigger picture before owned stop")
                observation["capturedWhileRecorderOwned"] = True
                observation["coveredByFrameClock"] = frame_clock[0] <= observed <= frame_clock[-1]
                self.metadata["transitionVisualReview"] = {
                    "status": "pending", "required": True,
                    "reason": "inspect original first and last video frames against retained player and Home PNGs",
                    "continuousCoverageAfterLastFrame": False,
                    "firstFrameDeviceElapsedSeconds": frame_clock[0],
                    "lastFrameDeviceElapsedSeconds": frame_clock[-1],
                }
            if "startupAction" in self.metadata:
                trigger = float(self.metadata["startupAction"]["triggerDeviceElapsedSeconds"])
                self.metadata["startupAction"].update({
                    "firstFrameAfterTriggerSeconds": frame_clock[0] - trigger,
                    "triggerTimeWithinFrameClock": frame_clock[0] <= trigger <= frame_clock[-1],
                })
                observation = self.metadata.get("firstPostActionObservation")
                if observation is None:
                    raise RuntimeFailure("native recording is missing its first post-action observation")
                if not finite_transition:
                    observation["coveredByFrameClock"] = False
                    require_recorded_observation(frame_clock, float(observation["deviceElapsedSeconds"]),
                                                 float(self.metadata["stopRequestedAtDeviceElapsedSeconds"]))
                    observation["coveredByFrameClock"] = True
            if required_phase is not None and not finite_transition:
                required = self.metadata.get("requiredThroughDeviceElapsedSeconds")
                if required is None:
                    raise RuntimeFailure("native recording final required device clock is unavailable")
                require_recorded_observation(frame_clock, float(required),
                                             float(self.metadata["stopRequestedAtDeviceElapsedSeconds"]))
            if post_roll_error is not None:
                raise RuntimeFailure("native recording bounded post-roll failed") from post_roll_error
            if device_receipt["status"] != "verified":
                raise RuntimeFailure("native recording finalized device file receipt is unavailable or invalid")
            if not self.metadata["deviceFileMatchesPulledFile"]:
                raise RuntimeFailure("native recording device bytes or digest differ from the pulled original")
            self.metadata["status"] = "verified"
        except (RuntimeFailure, OSError, subprocess.TimeoutExpired) as error:
            self.metadata["status"] = "failed"
            self.metadata["error"] = str(error) if isinstance(error, RuntimeFailure) else type(error).__name__
            raise
        finally:
            log_write_error: OSError | None = None
            try:
                self.output.parent.mkdir(parents=True, exist_ok=True)
                self.output.with_suffix(".screenrecord.log").write_text("".join(self.lines), encoding="utf-8")
            except OSError as error:
                self.metadata["screenrecordLogWriteError"] = type(error).__name__
                if self.metadata["status"] != "failed":
                    log_write_error = error
                    self.metadata.update({"status": "failed", "error": "native recorder output log could not be retained"})
            if self.process.poll() is None:
                # This is our local ADB subprocess, not an unverified Android PID.
                self.process.terminate()
                self.process.wait(timeout=5)
            if self.process.stdout:
                self.process.stdout.close()
            if self.codec_log_since is not None and self.pid is not None:
                self.metadata["codecLogRecorderPid"] = int(self.pid)
                self.metadata["codecLogSinceDeviceTime"] = self.codec_log_since
                try:
                    self.codec_evidence("codec-log", (
                        "exec-out", "logcat", "-d", "-b", "main", "-b", "system", "-v", "threadtime",
                        "-T", self.codec_log_since, "--pid", self.pid,
                        "CCodec:D", "Codec2Client:D", "ACodec:D", "OMXClient:D", "MediaCodec:D",
                        "C2SoftAvcEnc:D", "CCodecBufferChannel:D", "MPEG4Writer:D", "screenrecord:D", "*:S",
                    ))
                except (OSError, RuntimeFailure, subprocess.TimeoutExpired) as error:
                    self.metadata["codecLogCollectionError"] = type(error).__name__
            if log_write_error is not None:
                raise RuntimeFailure("native recorder output log could not be retained") from log_write_error


@dataclass(frozen=True)
class Playback:
    position_seconds: int
    duration_seconds: int
    playing: bool


def labels(xml: str) -> list[str]:
    return [value for node in nodes(xml)
            for value in (node.get("text", ""), node.get("content-desc", "")) if value]


def parse_time(value: str) -> int | None:
    if re.fullmatch(r"\d+:[0-5]\d(?::[0-5]\d)?", value) is None:
        return None
    total = 0
    for part in value.split(":"):
        total = total * 60 + int(part)
    return total


def button(xml: str, *alternatives: str) -> ET.Element:
    matches = [node for label in alternatives for node in exact(xml, label, clickable=True)]
    if len(matches) != 1:
        raise RuntimeFailure("expected one enabled playback action")
    return matches[0]


def playback(xml: str, *, expected_duration_seconds: int = 90, allow_ended: bool = False) -> Playback:
    values = labels(xml)
    if not any(FIXTURE_NAME in value for value in values):
        raise RuntimeFailure("the loaded playback source is not the controlled fixture")
    if not any(node.get("class", "").endswith("SeekBar") for node in nodes(xml)):
        raise RuntimeFailure("the actual player timeline is unavailable")
    parsed_times = [parsed for value in values if (parsed := parse_time(value)) is not None]
    times = sorted(set(parsed_times))
    # Diagnostic setup may rewind a completed fixture. Measured playback keeps
    # the strict default; EOF requires both actual elapsed and duration labels.
    ended = allow_ended and len(parsed_times) == 2 and len(times) == 1
    if ended:
        times.append(times[0])
    if (expected_duration_seconds <= 0 or len(times) != 2
            or not expected_duration_seconds - 1 <= times[1] <= expected_duration_seconds + 1
            or (times[0] >= times[1] and not ended)):
        raise RuntimeFailure(f"unique actual elapsed and {expected_duration_seconds}-second duration labels are required")
    play = [node for label in ("Play", "Play together") for node in exact(xml, label, clickable=True)]
    pause = [node for label in ("Pause", "Pause together") for node in exact(xml, label, clickable=True)]
    if len(play) + len(pause) != 1:
        raise RuntimeFailure("player must expose exactly one enabled Play or Pause action")
    return Playback(times[0], times[1], bool(pause))


def require_playing_advance(before: Playback, after: Playback) -> int:
    advance = after.position_seconds - before.position_seconds
    if not before.playing or not after.playing or advance < 2:
        raise RuntimeFailure("native playback did not advance by at least two displayed seconds")
    return advance


def require_paused_stability(before: Playback, after: Playback) -> None:
    if before.playing or after.playing or abs(after.position_seconds - before.position_seconds) > 1:
        raise RuntimeFailure("paused playback advanced or resumed without an explicit Play action")


def require_background_pause(before: Playback, after: Playback, home_seconds: float) -> None:
    advance = after.position_seconds - before.position_seconds
    if not before.playing or after.playing or home_seconds < 8 or not -1 <= advance <= 4:
        raise RuntimeFailure("HOME did not pause native playback within the visible-time tolerance")


def require_restored_position(saved: Playback, restored: Playback) -> None:
    if restored.playing or abs(saved.position_seconds - restored.position_seconds) > 1:
        raise RuntimeFailure("new-process Continue Watching did not restore the paused saved position")


def timed_out_observation(error: subprocess.TimeoutExpired) -> str:
    """Describe only recognized read operations, never raw command payloads."""
    command = error.cmd
    if not isinstance(command, (list, tuple)):
        return "Android UI observation"
    arguments = list(command[3:]) if len(command) > 3 and command[1] == "-s" else []
    if arguments[:3] == ["shell", "uiautomator", "dump"]:
        return "UIAutomator hierarchy dump"
    if arguments[:3] == ["shell", "am", "instrument"]:
        return "native accessibility snapshot"
    if arguments[:2] == ["exec-out", "cat"]:
        return "UI hierarchy transfer"
    if arguments[:4] == ["shell", "dumpsys", "window", "displays"]:
        return "foreground window query"
    return "Android UI observation"


def history_card(xml: str) -> tuple[ET.Element, int]:
    if len(exact(xml, "Continue Watching")) != 1:
        raise RuntimeFailure("Continue Watching is unavailable after process restart")
    root = ET.fromstring(xml)
    parents = {child: parent for parent in root.iter() for child in parent}
    matches: list[tuple[ET.Element, int]] = []
    for node in root.iter("node"):
        if (node.get("package") != PACKAGE or node.get("enabled", "true") != "true"
                or node.get("visible-to-user", "true") != "true"):
            continue
        text = "\n".join(filter(None, (node.get("text", ""), node.get("content-desc", ""))))
        if FIXTURE_NAME not in text:
            continue
        candidate = node
        while candidate.get("clickable") != "true" and candidate in parents:
            candidate = parents[candidate]
        combined = "\n".join(value for child in candidate.iter("node")
                             for value in (child.get("text", ""), child.get("content-desc", "")))
        position = re.search(r"Local player · (\d+:[0-5]\d(?::[0-5]\d)?) of (\d+:[0-5]\d(?::[0-5]\d)?)", combined)
        if (candidate.get("clickable") == "true" and candidate.get("enabled", "true") == "true"
                and candidate.get("visible-to-user", "true") == "true" and position):
            elapsed = parse_time(position.group(1))
            duration = parse_time(position.group(2))
            if elapsed is not None and duration is not None and 89 <= duration <= 91:
                if not any(existing is candidate for existing, _ in matches):
                    matches.append((candidate, elapsed))
    if len(matches) != 1:
        raise RuntimeFailure("the unique saved fixture and its persisted position are unavailable")
    return matches[0]


def history_swipe(xml: str) -> tuple[int, int, int, int]:
    containers = [node for node in nodes(xml) if node.get("scrollable") == "true"]
    if len(containers) != 1:
        raise RuntimeFailure("a unique visible home scroll container is required")
    container = containers[0]
    x, y = center(container)
    bounds = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", container.get("bounds", ""))
    assert bounds is not None  # center already validated these bounds.
    _, top, _, bottom = map(int, bounds.groups())
    offset = (bottom - top) // 5
    if offset < 20:
        raise RuntimeFailure("home scroll container is too small for a safe swipe")
    return x, y + offset, x, y - offset


class Runner:
    def __init__(self, serial: str, apk: Path, fixture: Path, output: Path,
                 observer_apk: Path = DEFAULT_APK, *, expected_duration_seconds: int = 90) -> None:
        if not apk.is_file() or not fixture.is_file() or fixture.name != FIXTURE_NAME:
            raise ValueError("normal APK and prepared sync-fixture.mp4 are required")
        self.adb = Adb(serial, f"lifecycle-{os.getpid()}-{time.time_ns()}")
        self.observer = NativeUiObserver(self.adb, observer_apk)
        self.apk, self.fixture, self.output = apk, fixture, output
        self.expected_duration_seconds = expected_duration_seconds
        self.cleanup_authorized = False
        self.evidence_started = False
        self.phase = "prepare"
        self.last_xml = ""
        self.last_window = ""
        self.last_observation: dict[str, object] | None = None
        self.observation_timeouts: list[dict[str, object]] = []
        self.samples: list[dict[str, object]] = []
        self.home_timings: list[dict[str, object]] = []
        self.preparation_recoveries: list[dict[str, object]] = []
        self.recording: LifecycleRecording | None = None
        self.recordings: list[dict[str, object]] = []

    def prepare(self) -> dict[str, object]:
        if self.output.exists() and any(self.output.iterdir()):
            raise RuntimeFailure("lifecycle evidence directory must start empty")
        self.output.mkdir(parents=True, exist_ok=True)
        self.evidence_started = True
        if self.adb.run("get-state").stdout.decode().strip() != "device":
            raise RuntimeFailure("selected Android emulator is not ready")
        if self.adb.run("shell", "getprop", "ro.kernel.qemu").stdout.decode().strip() != "1":
            raise RuntimeFailure("lifecycle acceptance requires a dedicated emulator")
        self.adb.prepare_storage(output=self.output)
        self.cleanup_authorized = True
        installed = self.adb.run("shell", "pm", "path", PACKAGE, check=False).stdout.decode().strip()
        if installed:
            if self.adb.run("uninstall", PACKAGE, timeout=60).stdout.decode().strip() != "Success":
                raise RuntimeFailure("could not remove the previous test application")
        installed = self.adb.run("install", "-t", str(self.apk), timeout=120).stdout.decode()
        if not install_output_succeeded(installed):
            raise RuntimeFailure("normal APK installation failed")
        observer = self.observer.install()
        return {
            "nativeUiObserver": observer,
            "runtime": {
                "emulator": True,
                "physicalDevice": False,
                "model": self.adb.run("shell", "getprop", "ro.product.model").stdout.decode().strip(),
                "api": self.adb.run("shell", "getprop", "ro.build.version.sdk").stdout.decode().strip(),
                "abi": self.adb.run("shell", "getprop", "ro.product.cpu.abi").stdout.decode().strip(),
            },
            "application": parse_package_metadata(self.adb.run("shell", "dumpsys", "package", PACKAGE).stdout.decode()),
            "apkSha256": hashlib.sha256(self.apk.read_bytes()).hexdigest(),
            "fixtureSha256": hashlib.sha256(self.fixture.read_bytes()).hexdigest(),
            "normalLibMainEntrypoint": True,
        }

    def pid(self, *, deadline: float | None = None) -> str:
        self.require_observation_deadline(deadline)
        value = self.adb.run("shell", "pidof", PACKAGE, check=False,
                             timeout=25 if deadline is None else min(25, deadline - time.monotonic())).stdout.decode().strip()
        self.require_observation_deadline(deadline)
        if value and not re.fullmatch(r"\d+", value):
            raise RuntimeFailure("expected exactly one app process")
        return value

    def observe(self, *, deadline: float | None = None) -> str:
        xml, window = self.observer.observe(deadline=deadline)
        self.require_observation_deadline(deadline)
        self.last_xml = xml
        self.last_window = window
        if self.recover_preparation_anr(xml, window, deadline=deadline):
            raise RuntimeFailure("initial emulator ANR closed; awaiting fresh application UI")
        focused_component(window)
        self.require_observation_deadline(deadline)
        return xml

    @staticmethod
    def require_observation_deadline(deadline: float | None) -> None:
        if deadline is not None and time.monotonic() >= deadline:
            raise ObserverIntegrityFailure("native observation exceeded the caller deadline")

    def recover_preparation_anr(self, xml: str, window: str, *, deadline: float | None = None) -> bool:
        if self.phase != "01-fixture-review":
            return False
        for package, selector in (
            (LAUNCHER_PACKAGE, select_pixel_launcher_anr_close),
            (SETUP_PACKAGE, select_google_sdk_setup_anr_close),
        ):
            try:
                selector(xml, window)
                break
            except UnsafeDialog:
                continue
        else:
            return False
        if len(self.preparation_recoveries) >= MAX_PREPARATION_ANR_RECOVERIES:
            raise PreparationRecoveryFailure("initial emulator ANR recovery limit reached")
        self.require_observation_deadline(deadline)
        if (re.fullmatch(r"emulator-[0-9]+", self.adb.serial) is None
                or self.adb.run("shell", "getprop", "ro.kernel.qemu",
                                timeout=remaining_timeout(deadline, 25)).stdout.decode().strip() != "1"):
            raise PreparationRecoveryFailure("initial ANR recovery is emulator-only")
        self.require_observation_deadline(deadline)
        attempt = len(self.preparation_recoveries) + 1
        prefix = self.output / f"01-preparation-anr-{attempt}"
        prefix.with_suffix(".xml").write_text(xml, encoding="utf-8")
        prefix.with_suffix(".window.txt").write_text(window, encoding="utf-8")
        png = self.adb.screenshot(timeout=remaining_timeout(deadline, 25))
        self.require_observation_deadline(deadline)
        prefix.with_suffix(".png").write_bytes(png)
        try:
            width, height = image_size(png)
        except UnsafeDialog as error:
            raise PreparationRecoveryFailure("initial ANR screenshot dimensions are invalid") from error
        self.require_observation_deadline(deadline)
        fresh_xml, fresh_window = self.observer.observe(deadline=deadline)
        self.require_observation_deadline(deadline)
        self.last_xml, self.last_window = fresh_xml, fresh_window
        prefix.with_suffix(".fresh.xml").write_text(fresh_xml, encoding="utf-8")
        prefix.with_suffix(".fresh.window.txt").write_text(fresh_window, encoding="utf-8")
        try:
            target = selector(fresh_xml, fresh_window)
        except UnsafeDialog as error:
            raise RuntimeFailure("initial ANR changed before recovery; no tap sent") from error
        if target.bounds[2] > width or target.bounds[3] > height:
            raise PreparationRecoveryFailure("initial ANR close lies outside the screen")
        row: dict[str, object] = {
            "phase": self.phase, "package": package, "attempt": attempt,
            "status": "attempted", "evidencePrefix": prefix.name,
        }
        self.preparation_recoveries.append(row)
        x, y = target.center
        try:
            self.require_observation_deadline(deadline)
            self.adb.run("shell", "input", "tap", str(x), str(y),
                         timeout=25 if deadline is None else min(25, deadline - time.monotonic()))
        except (RuntimeFailure, subprocess.TimeoutExpired) as error:
            row["status"] = "uncertain"
            raise PreparationRecoveryFailure("initial ANR close was not confirmed; refusing another tap") from error
        row["status"] = "closed"
        return True

    def tap(self, node: ET.Element, *, deadline: float | None = None) -> None:
        x, y = center(node)
        self.require_observation_deadline(deadline)
        self.adb.run("shell", "input", "tap", str(x), str(y),
                     timeout=25 if deadline is None else min(25, deadline - time.monotonic()))
        self.require_observation_deadline(deadline)

    def wait(self, phase: str, check: Callable[[str], T], timeout: float = 45) -> tuple[str, T]:
        self.phase = phase
        deadline = time.monotonic() + timeout
        last_error = "waiting for production UI"
        observation_timeouts = 0
        while time.monotonic() < deadline:
            try:
                xml = self.observe(deadline=deadline)
                self.require_observation_deadline(deadline)
            except (PreparationRecoveryFailure, ObserverIntegrityFailure):
                raise
            except subprocess.TimeoutExpired as error:
                # A transient read timeout is not a playback result. Retry a
                # fresh hierarchy within this phase's original polling budget;
                # never re-use last_xml or repeat a tap performed by check().
                observation_timeouts += 1
                operation = timed_out_observation(error)
                self.observation_timeouts.append({
                    "phase": phase,
                    "operation": operation,
                    "attempt": observation_timeouts,
                    "timeoutSeconds": error.timeout,
                    "observedAtMonotonic": time.monotonic(),
                })
                last_error = f"{operation} timed out"
                if observation_timeouts >= MAX_OBSERVATION_TIMEOUTS:
                    raise RuntimeFailure(
                        f"{phase}: {last_error} ({observation_timeouts} attempts)"
                    ) from error
                time.sleep(0.3)
                continue
            except RuntimeFailure as error:
                last_error = str(error)
                time.sleep(0.3)
                continue
            try:
                self.last_observation = {
                    "phase": phase,
                    "observedAtMonotonic": time.monotonic(),
                }
                result = check(xml)
                self.require_observation_deadline(deadline)
                self.output.joinpath(f"{phase}.xml").write_text(xml, encoding="utf-8")
                return xml, result
            except RuntimeFailure as error:
                last_error = str(error)
                time.sleep(0.3)
        raise RuntimeFailure(f"{phase}: {last_error}")

    def sample(
        self,
        phase: str,
        *,
        playing: bool,
        screenshot: bool = True,
    ) -> tuple[str, Playback]:
        def check(xml: str) -> Playback:
            state = playback(xml, expected_duration_seconds=self.expected_duration_seconds)
            if state.playing != playing:
                raise RuntimeFailure("native player has the wrong play/pause state")
            return state
        observation_count_before = len(self.observer.observations)
        xml, state = self.wait(phase, check)
        sample: dict[str, object] = {"phase": phase, "observedAtMonotonic": time.monotonic(),
                                     **asdict(state)}
        observations = self.observer.observations
        if len(observations) > observation_count_before:
            capture = observations[-1]
            required_capture_fields = (
                "startedAtMonotonic", "completedAtMonotonic",
                "captureStartedAtElapsedRealtimeMs", "captureCompletedAtElapsedRealtimeMs",
            )
            if (capture.get("status") == "success"
                    and capture.get("xmlSha256") == hashlib.sha256(xml.encode()).hexdigest()
                    and all(field in capture for field in required_capture_fields)):
                sample["nativeUiCapture"] = {
                    "observationIndex": len(observations) - 1,
                    "requestedAtMonotonic": capture["startedAtMonotonic"],
                    "returnedAtMonotonic": capture["completedAtMonotonic"],
                    "startedAtDeviceElapsedRealtimeMs": capture["captureStartedAtElapsedRealtimeMs"],
                    "completedAtDeviceElapsedRealtimeMs": capture["captureCompletedAtElapsedRealtimeMs"],
                }
        if phase in ("04-pre-home-playing", "05-foreground-paused") and "nativeUiCapture" not in sample:
            raise ObserverIntegrityFailure("HOME playback sample has no matching fresh native UI capture")
        self.samples.append(sample)
        if screenshot:
            self.output.joinpath(f"{phase}.png").write_bytes(self.adb.screenshot())
        return xml, state

    def launch_main(self) -> None:
        result = self.adb.run("shell", "am", "start", "-W", "-n", ACTIVITY,
                              "-a", "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER",
                              timeout=35).stdout.decode()
        if not launch_output_succeeded(result):
            raise RuntimeFailure("Android did not launch the normal MainActivity")

    def wait_history(self) -> tuple[str, tuple[ET.Element, int]]:
        swipes = 0
        def find(xml: str) -> tuple[ET.Element, int]:
            nonlocal swipes
            try:
                return history_card(xml)
            except RuntimeFailure:
                if swipes < 4:
                    coordinates = history_swipe(xml)
                    self.adb.run("shell", "input", "swipe", *(str(value) for value in coordinates), "400")
                    swipes += 1
                raise
        return self.wait("10-persisted-history", find)

    def load_fixture(self) -> None:
        result = self.adb.run("shell", "am", "start", "-W", "-n", ACTIVITY,
                              "-a", "android.intent.action.SEND", "-t", "text/plain",
                              "--es", "android.intent.extra.TEXT", FIXTURE_URL, timeout=35).stdout.decode()
        if not launch_output_succeeded(result):
            raise RuntimeFailure("could not deliver the fixture share")
        onboarded = False
        def review(xml: str) -> None:
            nonlocal onboarded
            if not onboarded and exact(xml, "Close the distance.\nKeep the movie night."):
                self.tap(button(xml, "Continue"))
                onboarded = True
                raise RuntimeFailure("finishing first-run onboarding")
            require_review(xml, FIXTURE_NAME)
        xml, _ = self.wait("01-fixture-review", review, timeout=65)
        self.output.joinpath("01-fixture-review.png").write_bytes(self.adb.screenshot())
        self.tap(button(xml, "Open video"))

    def go_home(
        self,
        *,
        pre_home_phase: str | None = None,
        playing: bool | None = None,
    ) -> tuple[float, Playback | None]:
        if (pre_home_phase is None) != (playing is None):
            raise ValueError("pre-HOME phase and expected playback state must be provided together")
        pre_home = None
        if pre_home_phase is not None:
            # A screenshot can take several seconds to transfer on a hosted AVD.
            # Refresh the accessible timeline after prior evidence capture, then
            # send HOME without another screenshot between the two operations.
            _, pre_home = self.sample(
                pre_home_phase,
                playing=playing,
                screenshot=False,
            )
        timing: dict[str, object] | None = None
        if pre_home is not None:
            timing = {"phase": pre_home_phase, "status": "incomplete",
                      "preHomeSampleIndex": len(self.samples) - 1,
                      "deviceClockSource": "Android /proc/uptime elapsedRealtime seconds"}
            self.home_timings.append(timing)
            # Keep both added clock reads and HOME inside the original 25-second
            # ADB action bound; a slow probe must not enlarge the control window.
            deadline = time.monotonic() + 25
            before_clock: dict[str, object] = {}
            timing["beforeHomeClock"] = before_clock
            self.device_clock_observation(deadline, before_clock)
            home_timeout = self.home_timing_timeout(deadline, 25)
            timing["keyeventRequestedAtMonotonic"] = time.monotonic()
        try:
            self.adb.run("shell", "input", "keyevent", "KEYCODE_HOME",
                         timeout=home_timeout if timing is not None else 25)
            if timing is not None:
                timing["keyeventStatus"] = "completed"
        finally:
            if timing is not None:
                timing["keyeventReturnedAtMonotonic"] = time.monotonic()
        if timing is not None:
            after_clock: dict[str, object] = {}
            timing["afterHomeClock"] = after_clock
            self.device_clock_observation(deadline, after_clock)
            timing["status"] = "measured"
        started = time.monotonic()
        time.sleep(8)
        window = self.adb.run("shell", "dumpsys", "window", "displays").stdout.decode()
        focus = re.findall(r"mCurrentFocus=([^\r\n]+)", window)
        if len(focus) != 1 or PACKAGE in focus[0] or "launcher" not in focus[0].lower():
            raise RuntimeFailure("HOME did not put an Android launcher in the foreground")
        self.output.joinpath(f"{self.phase}-home.png").write_bytes(self.adb.screenshot())
        return time.monotonic() - started, pre_home

    @staticmethod
    def home_timing_timeout(deadline: float, cap: float) -> float:
        remaining = min(cap, deadline - time.monotonic())
        if remaining <= 0:
            raise RuntimeFailure("HOME timing exceeded its original ADB control bound")
        return remaining

    def device_clock_observation(self, deadline: float, evidence: dict[str, object]) -> None:
        evidence["requestedAtMonotonic"] = time.monotonic()
        try:
            data = self.adb.run(
                "exec-out", "cat", "/proc/uptime", timeout=self.home_timing_timeout(deadline, 3)).stdout
            try:
                value = recording_device_elapsed(data)
            except RuntimeFailure as error:
                raise RuntimeFailure("HOME device elapsed clock is invalid") from error
        finally:
            evidence["finishedAtMonotonic"] = time.monotonic()
        evidence["returnedAtMonotonic"] = evidence["finishedAtMonotonic"]
        evidence["deviceElapsedSeconds"] = value

    def run(self) -> dict[str, object]:
        report = self.prepare()
        self.start_recording()
        self.load_fixture()
        xml, loaded = self.sample("02-loaded-paused", playing=False)
        self.tap(button(xml, "Play", "Play together"))
        _, initial = self.sample("03-playing", playing=True)
        time.sleep(4)
        _, advanced = self.sample("04-advanced", playing=True)
        first_advance = require_playing_advance(initial, advanced)
        self.finish_recording(required_phase=self.phase)
        self.start_recording()
        before_home_pid = self.pid()
        if not before_home_pid:
            raise RuntimeFailure("playing process is absent")
        background_seconds, pre_home = self.go_home(
            pre_home_phase="04-pre-home-playing",
            playing=True,
        )
        assert pre_home is not None
        if self.pid() != before_home_pid:
            raise RuntimeFailure("HOME destroyed the process before foreground-resume testing")
        self.launch_main()
        _, foreground = self.sample("05-foreground-paused", playing=False)
        require_background_pause(pre_home, foreground, background_seconds)
        time.sleep(4)
        xml, stable = self.sample("06-no-autoplay", playing=False)
        require_paused_stability(foreground, stable)
        self.tap(button(xml, "Play", "Play together"))
        _, replay = self.sample("07-explicit-replay", playing=True)
        time.sleep(4)
        xml, replay_advanced = self.sample("08-replay-advanced", playing=True)
        replay_advance = require_playing_advance(replay, replay_advanced)
        self.tap(button(xml, "Pause", "Pause together"))
        _, saved = self.sample("09-saved-paused", playing=False)
        if saved.position_seconds < 8:
            raise RuntimeFailure("saved progress is too small to establish nonzero resume")
        self.go_home()
        old_pid = self.pid()
        if old_pid != before_home_pid:
            raise RuntimeFailure("the app unexpectedly restarted before the process-death stage")
        self.adb.run("shell", "am", "force-stop", PACKAGE)
        if self.pid():
            raise RuntimeFailure("process restart precondition failed: old process remains")
        self.launch_main()
        xml, (card, history_position) = self.wait_history()
        new_pid = self.pid()
        if not new_pid or new_pid == old_pid:
            raise RuntimeFailure("Continue Watching was not observed in a new process")
        if abs(history_position - saved.position_seconds) > 1:
            raise RuntimeFailure("persisted history does not match the last paused position")
        self.output.joinpath("10-persisted-history.png").write_bytes(self.adb.screenshot())
        self.tap(card)
        _, restored = self.sample("11-resumed-paused", playing=False)
        require_restored_position(saved, restored)
        time.sleep(4)
        xml, restored_stable = self.sample("12-restored-no-autoplay", playing=False)
        require_paused_stability(restored, restored_stable)
        # Prove manual continuation only after the independent no-autoplay
        # checks pass. A playing tail also avoids requiring VFR static repeats.
        self.tap(button(xml, "Play", "Play together"))
        _, resumed_playing = self.sample("13-restored-explicit-play", playing=True)
        time.sleep(4)
        _, resumed_advanced = self.sample("14-restored-play-advanced", playing=True)
        resumed_advance = require_playing_advance(resumed_playing, resumed_advanced)
        if self.pid() != new_pid:
            raise RuntimeFailure("the restored application process changed during explicit playback")
        self.finish_recording(required_phase=self.phase)
        report.update({
            "completed": True,
            "initialPlayAdvanceSeconds": first_advance,
            "homeHoldSeconds": background_seconds,
            "preHomePositionSeconds": pre_home.position_seconds,
            "homePositionAdvanceSeconds": foreground.position_seconds - pre_home.position_seconds,
            "explicitReplayAdvanceSeconds": replay_advance,
            "pausedAfterForeground": True,
            "noAutoplayAfterForeground": True,
            "oldPid": int(old_pid), "newPid": int(new_pid),
            "oldProcessAbsentBeforeRestart": True,
            "sameMediaAfterRestart": FIXTURE_NAME,
            "savedPositionSeconds": saved.position_seconds,
            "historyPositionSeconds": history_position,
            "restoredPositionSeconds": restored.position_seconds,
            "noAutoplayAfterRestart": True,
            "explicitReplayAfterRestartAdvanceSeconds": resumed_advance,
            "samples": self.samples,
            "homeTimings": self.home_timings,
            "observationTimeouts": self.observation_timeouts,
            "preparationAnrRecoveries": self.preparation_recoveries,
            "nativeUiObservations": self.observer.observations,
            "recordings": self.recordings,
            "recordingBoundary": "Original native segments; measured inter-stage gaps are not continuous footage",
        })
        return report

    def start_recording(self) -> None:
        size = recording_size(self.adb.run("shell", "wm", "size").stdout.decode("ascii", errors="replace"))
        self.recording = LifecycleRecording(self.adb, self.output, len(self.recordings) + 1, size)
        self.recordings.append(self.recording.metadata)
        self.recording.start()
        if len(self.recordings) > 1:
            self.recording.metadata["gapAfterPreviousStopSeconds"] = (
                float(self.recording.metadata["startedAtMonotonic"])
                - float(self.recordings[-2]["stopRequestedAtMonotonic"]))

    def finish_recording(self, *, required_phase: str | None = None) -> None:
        if self.recording is not None:
            try:
                self.recording.finish(required_phase=required_phase)
            finally:
                self.recording = None

    def cleanup(self) -> None:
        try:
            self.finish_recording()
        finally:
            if self.evidence_started:
                self.output.joinpath("recordings.json").write_text(json.dumps(self.recordings, indent=2), encoding="utf-8")
            try:
                self.observer.cleanup()
            finally:
                if self.cleanup_authorized:
                    self.adb.run("shell", "am", "force-stop", PACKAGE, check=False)
                if self.cleanup_authorized or self.adb.remote_root_created:
                    self.adb.cleanup()
                    self.cleanup_authorized = False


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--observer-apk", type=Path, default=DEFAULT_APK)
    parser.add_argument("--output", type=Path, default=Path("build/android-lifecycle-artifacts"))
    args = parser.parse_args(argv)
    runner = Runner(args.serial, args.apk, args.fixture, args.output, args.observer_apk)
    def timed_out(_signum: int, _frame: object) -> None:
        raise RuntimeFailure("native lifecycle acceptance exceeded its external time bound")
    signal.signal(signal.SIGTERM, timed_out)
    status = 0
    report: dict[str, object] = {}
    try:
        report = runner.run()
    except (RuntimeFailure, OSError, subprocess.TimeoutExpired) as error:
        status = 1
        message = str(error) if isinstance(error, RuntimeFailure) else type(error).__name__
        if runner.evidence_started:
            report = {
                "completed": False, "phase": runner.phase, "error": message, "samples": runner.samples,
                "homeTimings": runner.home_timings,
                "observationTimeouts": runner.observation_timeouts,
                "lastCompletedUiObservation": runner.last_observation,
                "preparationAnrRecoveries": runner.preparation_recoveries,
                "nativeUiObservations": runner.observer.observations,
                "nativeUiObserverInstallation": runner.observer.installation,
                "recordings": runner.recordings,
            }
            args.output.joinpath("failure.xml").write_text(runner.last_xml, encoding="utf-8")
            args.output.joinpath("failure-window.txt").write_text(runner.last_window, encoding="utf-8")
            try:
                args.output.joinpath("failure.png").write_bytes(runner.adb.screenshot())
            except (RuntimeFailure, OSError, subprocess.TimeoutExpired):
                pass
        print(f"ANDROID_LIFECYCLE_RUNTIME_FAIL: {runner.phase}: {message}")
    finally:
        try:
            runner.cleanup()
        except (RuntimeFailure, OSError, subprocess.TimeoutExpired) as error:
            status = 1
            message = str(error) if isinstance(error, RuntimeFailure) else type(error).__name__
            report.update({"completed": False, "cleanupError": message})
            print(f"ANDROID_LIFECYCLE_RUNTIME_FAIL: cleanup: {message}")
    if runner.evidence_started:
        report["recordings"] = runner.recordings
        report["nativeUiObserverRemoved"] = not runner.observer.owns_package
        args.output.joinpath("result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    if status == 0:
        print("ANDROID_LIFECYCLE_RUNTIME_PASS")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
