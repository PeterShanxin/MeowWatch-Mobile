"""Prove that a paced native fixture cannot serve the decoder-failure seek bytes."""

from __future__ import annotations

import json
import math
import os
from pathlib import Path
import re
import signal
import subprocess
import time

from tools.android_install.runner import RuntimeFailure
from tools.android_multi_device.fixture_server import process_identity


SEEK_MS = 85000
PACE_BYTES_PER_SECOND = 160 * 1024


def prepare(fixture: Path, output: Path) -> dict:
    size = fixture.stat().st_size
    cap = size * 90 // 100
    completed = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_packets",
         "-show_entries", "packet=pts_time,pos,flags", "-of", "json", str(fixture)],
        capture_output=True, text=True, check=True, timeout=30,
    )
    packets = json.loads(completed.stdout)["packets"]
    before = [item for item in packets if "K" in item.get("flags", "")
              and float(item["pts_time"]) <= SEEK_MS / 1000]
    if not before:
        raise RuntimeFailure("fixture has no preceding video keyframe for late seek")
    keyframe = max(before, key=lambda item: float(item["pts_time"]))
    keyframe_ms = round(float(keyframe["pts_time"]) * 1000)
    keyframe_offset = int(keyframe["pos"])
    if (not 75000 <= keyframe_ms <= SEEK_MS or not cap < keyframe_offset < size):
        raise RuntimeFailure("actual fixture keyframe is not beyond the byte cap")
    proof = {"seekMs": SEEK_MS, "keyframeMs": keyframe_ms,
             "keyframeOffset": keyframe_offset, "maxBodyOffset": cap,
             "bodyBytesPerSecond": PACE_BYTES_PER_SECOND, "fixtureSize": size}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(proof, indent=2) + "\n", encoding="utf-8")
    return proof


def validate_spans(log: Path, proof: dict, offline_proof_at: float) -> dict:
    lines = log.read_text(encoding="utf-8").splitlines()
    observed_at = time.monotonic()
    if (type(offline_proof_at) not in (int, float)
            or not math.isfinite(offline_proof_at)
            or not 0 < offline_proof_at <= observed_at):
        raise RuntimeFailure("offline proof has no valid host monotonic boundary")
    if (proof.get("seekMs") != SEEK_MS
            or proof.get("bodyBytesPerSecond") != PACE_BYTES_PER_SECOND
            or type(proof.get("fixtureSize")) is not int
            or type(proof.get("maxBodyOffset")) is not int
            or proof["maxBodyOffset"] != proof["fixtureSize"] * 90 // 100
            or type(proof.get("keyframeOffset")) is not int
            or not proof["maxBodyOffset"] < proof["keyframeOffset"] < proof["fixtureSize"]):
        raise RuntimeFailure("actual fixture packet proof does not match the native seek and cap")
    spans = []
    ready = []
    responses = {}
    waits = []
    cap = proof["maxBodyOffset"]
    previous_clock_by_port = {}
    for line in lines:
        row = json.loads(line)
        if row.get("event") == "request_log_limit":
            raise RuntimeFailure("fixture byte receipts exceeded their log budget")
        if row.get("outcome") == "body_cap_timeout":
            raise RuntimeFailure("fixture timed out at its artificial byte cap")
        event = row.get("event")
        if event in {"body_response", "body_span", "body_cap_wait"}:
            clock = row.get("at_monotonic")
            port = row.get("client_port")
            if (type(clock) not in (int, float) or not math.isfinite(clock)
                    or not 0 < clock <= observed_at
                    or type(port) is not int or port <= 0
                    or clock < previous_clock_by_port.get(port, 0)):
                raise RuntimeFailure("fixture body receipt has a missing or misordered host monotonic timestamp")
            previous_clock_by_port[port] = clock
        if event == "body_cap_wait":
            if (row.get("asset") != "sync-fixture.mp4"
                    or type(row.get("next_offset")) is not int
                    or row["next_offset"] < cap):
                raise RuntimeFailure("fixture cap wait receipt is invalid")
            if clock <= offline_proof_at:
                raise RuntimeFailure("fixture reached its artificial byte cap before offline proof")
            waits.append(row)
        if row.get("event") == "ready":
            ready.append(row)
        if row.get("event") == "body_response" and row.get("asset") == "sync-fixture.mp4":
            if (row.get("status") not in (200, 206)
                    or type(row.get("first")) is not int
                    or type(row.get("last")) is not int
                    or row["first"] > row["last"]):
                raise RuntimeFailure("fixture native HTTP range receipt is invalid")
            responses[row["client_port"]] = row
        if row.get("event") != "body_span" or row.get("asset") != "sync-fixture.mp4":
            continue
        first, last = row.get("first"), row.get("last")
        if type(first) is not int or type(last) is not int or not 0 <= first <= last < cap:
            raise RuntimeFailure("fixture sent an invalid or uncapped body interval")
        spans.append(row)
    if not spans:
        raise RuntimeFailure("no actual media-body byte receipt was recorded")
    if (len(ready) != 1 or ready[0].get("max_body_offset") != cap
            or ready[0].get("body_bytes_per_second") != proof["bodyBytesPerSecond"]):
        raise RuntimeFailure("fixture server did not run with the proved byte cap and pace")
    ports = {row["client_port"] for row in spans}
    if len(ports) < 2:
        raise RuntimeFailure("two native media requests need distinct byte receipts")
    if ports - responses.keys() or any(
            row["first"] < responses[row["client_port"]]["first"]
            or row["last"] > responses[row["client_port"]]["last"]
            or row["at_monotonic"] < responses[row["client_port"]]["at_monotonic"]
            for row in spans):
        raise RuntimeFailure("fixture bytes lack a matching HTTP range receipt")
    if any(row["client_port"] not in responses
           or row["at_monotonic"] < responses[row["client_port"]]["at_monotonic"]
           for row in waits):
        raise RuntimeFailure("fixture cap wait lacks a preceding HTTP range receipt")
    return {"spanCount": len(spans), "requestPorts": len(ports),
            "highestServedOffset": max(row["last"] for row in spans),
            "offlineProofAtMonotonic": offline_proof_at,
            "postProofCapWaitCount": len(waits),
            **proof}


def release_owned_server(state: Path, log: Path, proof: dict, *,
                         fixture_dir: Path = Path("build/android-network-fixture"),
                         timeout: float = 5) -> dict:
    """Release the proved cap by local signal after verifying the exact server PID."""
    fields = {}
    for line in state.read_text(encoding="utf-8").splitlines():
        match = re.fullmatch(r"(SERVER_PID|SERVER_PORT|SERVER_START_TICKS|MAX_BODY_OFFSET|BODY_BYTES_PER_SECOND)=([0-9]+)", line)
        if match:
            fields[match[1]] = int(match[2])
    if (set(fields) != {"SERVER_PID", "SERVER_PORT", "SERVER_START_TICKS",
                        "MAX_BODY_OFFSET", "BODY_BYTES_PER_SECOND"}
            or fields["SERVER_PORT"] != 18765
            or fields["MAX_BODY_OFFSET"] != proof["maxBodyOffset"]
            or fields["BODY_BYTES_PER_SECOND"] != proof["bodyBytesPerSecond"]):
        raise RuntimeFailure("task-owned fixture server receipt does not match the byte proof")
    pid = fields["SERVER_PID"]
    birth = str(fields["SERVER_START_TICKS"])
    fixture_dir = fixture_dir.resolve(strict=True)
    def owns_server() -> bool:
        return process_identity(pid, fixture_dir, 18765) == birth
    if not owns_server():
        raise RuntimeFailure("fixture server PID and birth token changed before cap release")
    if any(json.loads(line).get("event") == "body_cap_released"
           for line in log.read_text(encoding="utf-8").splitlines()):
        raise RuntimeFailure("fixture body cap was released before offline proof")
    os.kill(pid, signal.SIGUSR1)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not owns_server():
            raise RuntimeFailure("fixture server identity changed during cap release")
        releases = [row for line in log.read_text(encoding="utf-8").splitlines()
                    if (row := json.loads(line)).get("event") == "body_cap_released"]
        if releases:
            receipt = releases[0]
            if (len(releases) != 1 or receipt.get("pid") != pid
                    or receipt.get("max_body_offset") != proof["maxBodyOffset"]
                    or receipt.get("body_bytes_per_second") != proof["bodyBytesPerSecond"]
                    or not isinstance(receipt.get("at_utc"), str)):
                raise RuntimeFailure("fixture cap release acknowledgement is invalid")
            return receipt
        time.sleep(0.05)
    raise RuntimeFailure("fixture cap release was not acknowledged before radio restoration")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("fixture", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    print(json.dumps(prepare(args.fixture, args.output)))
