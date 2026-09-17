#!/usr/bin/env python3
"""Read-only cold-boot admission policy for two task-owned Android emulators.

These resource limits are this acceptance runner's policy, not Android ANR
guarantees. No dialog is dismissed, process stopped, or device setting changed.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import re
import shlex
import subprocess
import time
from typing import Callable


BUDGET_SECONDS = 240
WINDOW_SECONDS = 5
REQUIRED_WINDOWS = 3
POLICY = {
    "scope": "test-runner resource policy; not an Android responsiveness guarantee",
    "budgetSeconds": BUDGET_SECONDS,
    "minimumWindowSeconds": WINDOW_SECONDS,
    "consecutiveWindows": REQUIRED_WINDOWS,
    "minimumCpuIdlePercent": 20,
    "maximumCpuSomeStallPercent": 20,
    "maximumMemoryFullStallPercent": 1,
    "psiClock": "device /proc/uptime; total microseconds delta, not avg10 or CPU full",
}
METRICS = {
    "uptime_before": "cat /proc/uptime",
    "stat": "cat /proc/stat",
    "psi_cpu": "cat /proc/pressure/cpu",
    "psi_memory": "cat /proc/pressure/memory",
    "meminfo": "cat /proc/meminfo",
    "uptime_after": "cat /proc/uptime",
}
STATE = {
    "qemu": "getprop ro.kernel.qemu",
    "debuggable": "getprop ro.debuggable",
    "boot": "getprop sys.boot_completed",
    "bootanim": "getprop init.svc.bootanim",
    "provisioned": "settings get global device_provisioned",
    "setup": "settings get secure user_setup_complete",
    "home": "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME",
    "window": "dumpsys window displays",
    "anr": "logcat -b events -d -v epoch am_anr:I '*:S'",
    "size": "wm size",
    "density": "wm density",
}
COMPONENT = re.compile(r"([A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+)/(\.?[A-Za-z0-9_.$]+)")


class MeasurementError(RuntimeError):
    pass


def section_script(commands: dict[str, str]) -> str:
    return "\n".join(
        f"printf 'MW_READY_BEGIN {name}\\n'; {command}; "
        f"mw_status=$?; printf '\\nMW_READY_END {name} %s\\n' \"$mw_status\""
        for name, command in commands.items()
    )


def parse_sections(raw: str, expected: dict[str, str]) -> dict[str, dict]:
    sections = {}
    pattern = re.compile(r"(?m)^MW_READY_BEGIN (\w+)\r?\n(.*?)^MW_READY_END \1 (\d+)\r?$", re.S)
    for match in pattern.finditer(raw):
        name = match[1]
        if name in sections or name not in expected:
            raise MeasurementError("duplicate or unexpected measurement section")
        sections[name] = {"exitCode": int(match[3]), "stdout": match[2].replace("\r\n", "\n").strip()}
    if sections.keys() != expected.keys():
        raise MeasurementError("missing measurement section")
    return sections


def require_output(sections: dict, name: str) -> str:
    value = sections[name]
    if value["exitCode"] != 0:
        raise MeasurementError(f"{name} could not be read (exit {value['exitCode']})")
    return value["stdout"]


def uptime(raw: str) -> float:
    if re.fullmatch(r"\d+(?:\.\d+)? \d+(?:\.\d+)?", raw) is None:
        raise MeasurementError("invalid device elapsed clock")
    value = float(raw.split()[0])
    if not math.isfinite(value) or value <= 0:
        raise MeasurementError("invalid device elapsed clock")
    return value


def psi_total(raw: str, kind: str) -> int:
    values = re.findall(rf"(?m)^{kind} avg10=\d+(?:\.\d+)? avg60=\d+(?:\.\d+)? "
                        rf"avg300=\d+(?:\.\d+)? total=(\d+)$", raw)
    if len(values) != 1:
        raise MeasurementError(f"missing or invalid PSI {kind} measurement")
    return int(values[0])


def parse_metrics(sections: dict) -> dict:
    before = uptime(require_output(sections, "uptime_before"))
    after = uptime(require_output(sections, "uptime_after"))
    if after < before:
        raise MeasurementError("device clock moved backwards while sampling")
    rows = re.findall(r"(?m)^cpu\s+((?:\d+\s+){7,}\d+)\s*$", require_output(sections, "stat"))
    if len(rows) != 1:
        raise MeasurementError("missing or invalid aggregate CPU counters")
    counters = [int(value) for value in rows[0].split()]
    # guest and guest_nice are already included in user and nice.
    total = sum(counters[:8])
    ram = re.findall(r"(?m)^MemTotal:\s+(\d+) kB$", require_output(sections, "meminfo"))
    if len(ram) != 1 or int(ram[0]) <= 0:
        raise MeasurementError("guest MemTotal is unavailable")
    return {
        "elapsedBeforeSeconds": before, "elapsedAfterSeconds": after,
        "cpuTotalTicks": total, "cpuIdleTicks": counters[3],
        "cpuSomeStallMicroseconds": psi_total(require_output(sections, "psi_cpu"), "some"),
        "memoryFullStallMicroseconds": psi_total(require_output(sections, "psi_memory"), "full"),
        "guestVisibleMemoryKiB": int(ram[0]),
    }


def component(raw: str) -> str | None:
    matches = COMPONENT.findall(raw)
    if len(matches) != 1:
        return None
    package, activity = matches[0]
    return f"{package}/{package + activity if activity.startswith('.') else activity}"


def physical_value(raw: str, name: str) -> str:
    pattern = r"Physical size: (\d+x\d+)" if name == "size" else r"Physical density: (\d+)"
    values = re.findall(rf"(?m)^{pattern}$", raw)
    if len(values) != 1 or any(int(value) <= 0 for value in values[0].split("x")):
        raise MeasurementError(f"physical {name} is unavailable")
    return values[0]


def parse_state(sections: dict) -> dict:
    values = {name: require_output(sections, name) for name in STATE}
    if values["qemu"] != "1":
        raise MeasurementError("device is not a verified emulator")
    window = values["window"]
    focus_lines = re.findall(r"(?m)^\s*mCurrentFocus=(.*)$", window)
    app_lines = re.findall(r"(?m)^\s*mFocusedApp=(.*)$", window)
    if len(focus_lines) != 1 or len(app_lines) != 1:
        raise MeasurementError("focused window/application measurement is ambiguous")
    home = component(values["home"])
    focus, app = component(focus_lines[0]), component(app_lines[0])
    reasons = []
    if any(values[name] != value for name, value in {
        "boot": "1", "bootanim": "stopped", "provisioned": "1", "setup": "1",
    }.items()):
        reasons.append("boot or provisioning is incomplete")
    if (not home or any(name in home.lower() for name in ("googlesdksetup", "fallbackhome"))
            or focus != home or app != home):
        reasons.append("resolved Home does not own both focused window and application")
    if re.search(r"Application Not Responding|AppErrorDialog|AppNotRespondingDialog|PermissionDialog", window, re.I):
        reasons.append("system dialog is present")
    events = []
    for line in values["anr"].splitlines():
        if not line.strip() or line.startswith("--------- beginning of"):
            continue
        if re.search(r"\bam_anr\s*:", line) is None or re.match(r"\s*\d+\.\d+\s", line) is None:
            raise MeasurementError("ANR event measurement is not a complete filtered event log")
        events.append(line.strip())
    return {
        "ready": not reasons, "reasons": reasons,
        "resolvedHome": home, "focusedWindow": focus, "focusedApplication": app,
        "anrEvents": events, "physicalSize": physical_value(values["size"], "size"),
        "physicalDensity": int(physical_value(values["density"], "density")),
        "reportedSize": values["size"], "reportedDensity": values["density"],
        "debuggable": values["debuggable"] == "1",
    }


class DeviceSampler:
    def __init__(self, adb: str, deadline: float, *, clock: Callable = time.monotonic,
                 execute: Callable = subprocess.run):
        self.adb, self.deadline, self.clock, self.execute = adb, deadline, clock, execute

    def read(self, serial: str, commands: dict, *, privileged: bool = False) -> dict:
        remaining = self.deadline - self.clock()
        if remaining <= 0:
            raise MeasurementError("readiness deadline reached")
        script = section_script(commands)
        if privileged:
            script = "su 0 sh -c " + shlex.quote(script)
        try:
            result = self.execute([self.adb, "-s", serial, "shell", script],
                                  capture_output=True, timeout=min(15, remaining), check=False)
        except subprocess.TimeoutExpired as error:
            return {"exitCode": None, "error": "TimeoutExpired",
                    "stdout": (error.stdout or b"").decode("utf-8", errors="replace"),
                    "stderr": (error.stderr or b"").decode("utf-8", errors="replace")}
        return {"exitCode": result.returncode, "stdout": result.stdout.decode("utf-8", errors="replace"),
                "stderr": result.stderr.decode("utf-8", errors="replace")}

    def capture(self, serial: str) -> dict:
        sample = {"serial": serial, "startedAtMonotonic": self.clock(), "raw": {}}
        try:
            state_raw = sample["raw"]["state"] = self.read(serial, STATE)
            if state_raw["exitCode"] != 0:
                raise MeasurementError(f"state command failed: {state_raw.get('error', state_raw['exitCode'])}")
            state_sections = parse_sections(state_raw["stdout"], STATE)
            sample["state"] = parse_state(state_sections)
            metrics_raw = sample["raw"]["shellMetrics"] = self.read(serial, METRICS)
            if metrics_raw["exitCode"] != 0:
                raise MeasurementError("metrics command failed")
            metrics = parse_sections(metrics_raw["stdout"], METRICS)
            denied = [name for name in ("psi_cpu", "psi_memory") if metrics[name]["exitCode"] != 0]
            source = "adb shell (unprivileged)"
            if denied:
                combined_error = metrics_raw["stderr"] + "\n".join(metrics[name]["stdout"] for name in denied)
                if not sample["state"]["debuggable"] or "Permission denied" not in combined_error:
                    raise MeasurementError("PSI unavailable; read-only privileged fallback is not eligible")
                elevated = sample["raw"]["suMetrics"] = self.read(serial, METRICS, privileged=True)
                if elevated["exitCode"] != 0:
                    raise MeasurementError("read-only su 0 PSI measurement is unavailable")
                metrics = parse_sections(elevated["stdout"], METRICS)
                source = "adb shell su 0; verified debuggable emulator; read-only proc files"
            sample["metrics"] = parse_metrics(metrics)
            sample["measurementAccess"] = source
            # Admission uses a fresh UI/ANR read after the resource measurement;
            # an ANR during a slow metrics call must not be missed at release.
            final_state = sample["raw"]["stateAfterMetrics"] = self.read(serial, STATE)
            if final_state["exitCode"] != 0:
                raise MeasurementError("post-measurement state command failed")
            sample["state"] = parse_state(parse_sections(final_state["stdout"], STATE))
        except (MeasurementError, OSError, subprocess.TimeoutExpired) as error:
            sample["error"] = str(error) if isinstance(error, MeasurementError) else type(error).__name__
        sample["completedAtMonotonic"] = self.clock()
        return sample


def evaluate_window(previous: dict, current: dict) -> dict:
    if previous.get("error") or current.get("error"):
        raise MeasurementError("window has missing critical measurements")
    first, last = previous["metrics"], current["metrics"]
    # Use the smallest possible device interval, conservatively accounting for
    # the time spent reading counters instead of comparing host and guest clocks.
    elapsed = last["elapsedBeforeSeconds"] - first["elapsedAfterSeconds"]
    total = last["cpuTotalTicks"] - first["cpuTotalTicks"]
    idle = last["cpuIdleTicks"] - first["cpuIdleTicks"]
    cpu_stall = last["cpuSomeStallMicroseconds"] - first["cpuSomeStallMicroseconds"]
    memory_stall = last["memoryFullStallMicroseconds"] - first["memoryFullStallMicroseconds"]
    if elapsed <= 0 or total <= 0 or min(idle, cpu_stall, memory_stall) < 0 or idle > total:
        raise MeasurementError("device counters reset or did not advance")
    measured = {"deviceWindowSeconds": elapsed, "cpuIdlePercent": 100 * idle / total,
                "cpuSomeStallPercent": 100 * cpu_stall / (elapsed * 1_000_000),
                "memoryFullStallPercent": 100 * memory_stall / (elapsed * 1_000_000)}
    reasons = list(dict.fromkeys(previous["state"]["reasons"] + current["state"]["reasons"]))
    previous_anrs, current_anrs = set(previous["state"]["anrEvents"]), set(current["state"]["anrEvents"])
    if not previous_anrs.issubset(current_anrs):
        raise MeasurementError("ANR event history disappeared; continuous observation is unverified")
    new_anrs = sorted(current_anrs - previous_anrs)
    if new_anrs:
        reasons.append("new ANR event during preparation")
    if elapsed < WINDOW_SECONDS:
        reasons.append("device observation window is shorter than five seconds")
    if measured["cpuIdlePercent"] < POLICY["minimumCpuIdlePercent"]:
        reasons.append("CPU idle is below resource policy")
    if measured["cpuSomeStallPercent"] > POLICY["maximumCpuSomeStallPercent"]:
        reasons.append("CPU pressure exceeds resource policy")
    if measured["memoryFullStallPercent"] > POLICY["maximumMemoryFullStallPercent"]:
        reasons.append("memory full pressure exceeds resource policy")
    return {"ready": not reasons, "reasons": reasons, "measured": measured, "newAnrEvents": new_anrs}


def run_gate(serials: list[str], output: Path, capture: Callable, *, clock: Callable = time.monotonic,
             sleep: Callable = time.sleep, deadline: float, provenance: dict) -> dict:
    if output.exists() and any(output.iterdir()):
        raise MeasurementError("readiness output must be empty; previous evidence is preserved")
    output.mkdir(parents=True, exist_ok=True)
    report = {"status": "waiting", "policy": POLICY, "provenance": provenance,
              "startedUtc": datetime.now(timezone.utc).isoformat(), "sampleCount": 0,
              "consecutiveWindows": 0, "lastReasons": {}}
    previous = None
    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            while clock() < deadline:
                samples = dict(zip(serials, pool.map(capture, serials)))
                record = {"sampleIndex": report["sampleCount"], "devices": samples, "windows": {}}
                failures = {serial: [sample["error"]] for serial, sample in samples.items() if sample.get("error")}
                if not failures and previous is not None:
                    for serial in serials:
                        try:
                            record["windows"][serial] = evaluate_window(previous[serial], samples[serial])
                        except MeasurementError as error:
                            failures[serial] = [str(error)]
                    if not failures:
                        report["lastReasons"] = {serial: window["reasons"] for serial, window in record["windows"].items()}
                        all_ready = all(window["ready"] for window in record["windows"].values())
                        report["consecutiveWindows"] = report["consecutiveWindows"] + 1 if all_ready else 0
                record["consecutiveWindows"] = report["consecutiveWindows"]
                (output / f"sample-{report['sampleCount']:03}.json").write_text(
                    json.dumps(record, indent=2) + "\n", encoding="utf-8")
                report["sampleCount"] += 1
                report["lastDevices"] = {serial: {key: value for key, value in sample.items() if key != "raw"}
                                         for serial, sample in samples.items()}
                if failures:
                    report["lastReasons"] = failures
                    raise MeasurementError("critical device measurement failed")
                if clock() >= deadline:
                    break
                if report["consecutiveWindows"] == REQUIRED_WINDOWS:
                    report.update(status="ready", reason="both devices passed three consecutive resource windows")
                    return report
                previous = samples
                sleep(min(WINDOW_SECONDS, max(0, deadline - clock())))
        raise MeasurementError("both devices did not become ready within the 240-second budget")
    except MeasurementError as error:
        report.update(status="failed", reason=str(error))
        return report
    finally:
        report["completedUtc"] = datetime.now(timezone.utc).isoformat()
        (output / "result.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


def memory_provenance(requested: int, log: Path) -> dict:
    values = re.findall(r"Increasing RAM size to (\d+)MB", log.read_text(encoding="utf-8", errors="replace"))
    return {"requestedMemoryMiB": requested,
            "emulatorReportedIncreasedMemoryMiB": int(values[-1]) if values else None,
            "memoryBoundary": "guest MemTotal is recorded separately; requested RAM is not an actual-RAM claim"}


def check_physical_geometry(sample: dict, role: str) -> dict:
    expected = {"phone": ("720x1600", 280), "tablet": ("1280x800", 160)}[role]
    state = sample.get("state")
    if state and (state["physicalSize"], state["physicalDensity"]) != expected:
        sample["error"] = f"{role} physical display does not match the fixed dual-player CI geometry"
    if state and ("Override" in state["reportedSize"] or "Override" in state["reportedDensity"]):
        sample["error"] = f"{role} uses a display override instead of the configured physical display"
    return sample


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--phone", required=True)
    parser.add_argument("--tablet", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--phone-log", type=Path, required=True)
    parser.add_argument("--tablet-log", type=Path, required=True)
    parser.add_argument("--requested-memory-mib", type=int, default=3072)
    args = parser.parse_args(argv)
    if (args.phone == args.tablet or any(re.fullmatch(r"emulator-\d+", value) is None for value in (args.phone, args.tablet))
            or args.requested_memory_mib <= 0):
        parser.error("two distinct emulator serials and positive requested memory are required")
    deadline = time.monotonic() + BUDGET_SECONDS
    try:
        provenance = {"phone": memory_provenance(args.requested_memory_mib, args.phone_log),
                      "tablet": memory_provenance(args.requested_memory_mib, args.tablet_log),
                      "geometry": {"phone": "720x1600@280dpi", "tablet": "1280x800@160dpi",
                                   "boundary": "resource-limited two-native-player CI; not full-resolution layout acceptance"},
                      "boundary": "before native recording and application installation; no UI or device mutations"}
        sampler = DeviceSampler(args.adb, deadline)
        def capture(serial: str) -> dict:
            return check_physical_geometry(sampler.capture(serial), "phone" if serial == args.phone else "tablet")
        report = run_gate([args.phone, args.tablet], args.output, capture, deadline=deadline, provenance=provenance)
    except (MeasurementError, OSError) as error:
        print(f"DEVICE_READINESS_FAIL: {error}")
        return 1
    print(f"DEVICE_READINESS_{report['status'].upper()}: {report['reason']}")
    return 0 if report["status"] == "ready" else 1


if __name__ == "__main__":
    raise SystemExit(main())
