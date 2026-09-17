#!/usr/bin/env python3
"""One exact system-package recovery before the read-only admission gate."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import re
import shlex
import subprocess
import time

from tools.android_multi_device.device_readiness import (
    MeasurementError, component, parse_sections, require_output, section_script,
)

SETUP_PACKAGE = "com.google.android.googlesdksetup"
LAUNCHER_PACKAGE = "com.google.android.apps.nexuslauncher"
LAUNCHER_HOME = f"{LAUNCHER_PACKAGE}/{LAUNCHER_PACKAGE}.NexusLauncherActivity"
APP_PACKAGE = "com.meowwatch.meowwatch_mobile"
BUDGET_SECONDS = 90
QUERIES = {
    "qemu": "getprop ro.kernel.qemu",
    "debuggable": "getprop ro.debuggable",
    "boot": "getprop sys.boot_completed",
    "provisioned": "settings get global device_provisioned",
    "setup": "settings get secure user_setup_complete",
    "packages": f"pm list packages --user 0 {APP_PACKAGE}",
    "home": "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME",
    "window": "dumpsys window displays",
    "anr": "logcat -b events -d -v epoch am_anr:I '*:S'",
}
ANR_WINDOW = re.compile(r"Window\{([0-9a-f]+) u0 Application Not Responding: ([A-Za-z0-9_.]+)\}")
ANR_EVENT = re.compile(r"^\s*\d+\.\d+\s+\d+\s+\d+\s+I\s+am_anr\s*:\s*\[0,([1-9]\d*),([A-Za-z0-9_.]+),-?\d+,.+\]$")
LAUNCHER_QUERIES = {
    "launcher_system_package": f"pm list packages -s -U --user 0 {LAUNCHER_PACKAGE}",
    "launcher_processes": "ps -A -o PID,UID,NAME",
    "launcher_api": "getprop ro.build.version.sdk",
    "launcher_abi": "getprop ro.product.cpu.abi",
}


def launcher_identity(raw: str | None) -> dict:
    if raw is None:
        raise MeasurementError("system Launcher identity evidence is missing")
    sections = parse_sections(raw, LAUNCHER_QUERIES)
    if (require_output(sections, "launcher_api") != "35"
            or require_output(sections, "launcher_abi") != "x86_64"):
        raise MeasurementError("Launcher recovery requires the API 35 x86_64 runtime")
    package = require_output(sections, "launcher_system_package")
    match = re.fullmatch(r"package:" + re.escape(LAUNCHER_PACKAGE) + r" uid:([1-9]\d*)", package)
    if match is None or not 10000 <= int(match[1]) < 100000:
        raise MeasurementError("NexusLauncher is not an unambiguous user-0 system app")
    uid = int(match[1])
    rows = require_output(sections, "launcher_processes").splitlines()
    if not rows or rows[0].split() != ["PID", "UID", "NAME"]:
        raise MeasurementError("Launcher process identity measurement is malformed")
    processes = []
    for row in rows[1:]:
        fields = row.split()
        if len(fields) != 3 or not fields[0].isdigit() or not fields[1].isdigit():
            raise MeasurementError("Launcher process identity measurement is malformed")
        if fields[2] == LAUNCHER_PACKAGE:
            processes.append((int(fields[0]), int(fields[1])))
    if len(processes) > 1 or any(pid <= 0 or process_uid != uid for pid, process_uid in processes):
        raise MeasurementError("Launcher PID/UID ownership is ambiguous")
    return {"uid": uid, "pid": processes[0][0] if processes else None}


def inspect_state(raw: str, expected_avd: str, avd_raw: str, *, retiring_window=None,
                  retiring_package=SETUP_PACKAGE, launcher_raw=None) -> dict:
    if avd_raw.splitlines() != [expected_avd, "OK"]:
        raise MeasurementError("serial does not identify this task's expected AVD")
    sections = parse_sections(raw, QUERIES)
    values = {name: require_output(sections, name) for name in QUERIES}
    if values["qemu"] != "1" or values["debuggable"] != "1":
        raise MeasurementError("SDK preparation requires a verified debuggable emulator")
    packages = values["packages"].splitlines()
    if any(re.fullmatch(r"package:[A-Za-z0-9_.]+", line) is None for line in packages):
        raise MeasurementError("installed-package evidence is malformed")
    if f"package:{APP_PACKAGE}" in packages:
        raise MeasurementError("MeowWatch is already installed; SDK preparation is forbidden")
    focus = re.findall(r"(?m)^\s*mCurrentFocus=(.*)$", values["window"])
    focused_app = re.findall(r"(?m)^\s*mFocusedApp=(.*)$", values["window"])
    if len(focus) != 1 or len(focused_app) != 1:
        raise MeasurementError("focused window/application is ambiguous")
    home = component(values["home"])
    events = []
    for line in values["anr"].splitlines():
        if not line.strip() or line.startswith("--------- beginning of"):
            continue
        match = ANR_EVENT.match(line)
        if match is None:
            raise MeasurementError("ANR event evidence is malformed or is not for user 0")
        events.append({"pid": int(match[1]), "package": match[2], "raw": line.strip()})
    windows = set(ANR_WINDOW.findall(values["window"]))
    if len(windows) > 1:
        raise MeasurementError("multiple ANR windows make SDK recovery ambiguous")
    if any(package not in (SETUP_PACKAGE, LAUNCHER_PACKAGE) for _, package in windows):
        raise MeasurementError("another package has a current ANR window; no system recovery is permitted")
    # Unknown dialog formats cannot qualify through a loose package substring.
    if re.search(r"Application Not Responding|Application Error:|AppNotRespondingDialog|AppErrorDialog|PermissionDialog",
                 ANR_WINDOW.sub("", values["window"]), re.I):
        raise MeasurementError("unrecognized system error dialog; no SDK recovery is permitted")
    focused_anr = ANR_WINDOW.fullmatch(focus[0].strip())
    eligible = bool(focused_anr and windows == {(focused_anr[1], focused_anr[2])})
    if retiring_window is not None and windows and windows != {(retiring_window, retiring_package)}:
        raise MeasurementError("SDK ANR window changed after recovery; no further mutation is permitted")
    if retiring_window is None and windows and not eligible:
        raise MeasurementError("SDK ANR window does not uniquely own current focus")
    recovery_package = focused_anr[2] if eligible else None
    target = retiring_package if retiring_window is not None else recovery_package
    identity = None
    if eligible or retiring_window is not None:
        if home is None or any(name in home.lower() for name in ("googlesdksetup", "fallbackhome")):
            raise MeasurementError("Home does not resolve to an unambiguous launcher")
        if any(values[name] != "1" for name in ("boot", "provisioned", "setup")):
            raise MeasurementError("boot and provisioning must complete before SDK recovery")
        matching_events = [event for event in events if event["package"] == target]
        if not matching_events:
            raise MeasurementError("focused system ANR does not have a matching am_anr event")
        if retiring_window is None and component(focused_app[0]) != home:
            raise MeasurementError("completed SDK setup has not handed focus ownership to Home")
        if target == LAUNCHER_PACKAGE:
            if platform.system() != "Linux" or platform.machine() != "x86_64":
                raise MeasurementError("Launcher recovery is limited to Linux x86_64 emulator runners")
            if home != LAUNCHER_HOME:
                raise MeasurementError("NexusLauncher does not own the exact resolved Home component")
            identity = launcher_identity(launcher_raw)
            if retiring_window is None and identity["pid"] != matching_events[-1]["pid"]:
                raise MeasurementError("current Launcher PID does not match its latest ANR event")
    return {"eligible": eligible, "resolvedHome": home, "focusedWindow": focus[0].strip(),
            "focusedApplication": focused_app[0].strip(), "anrEvents": events,
            "anrWindow": next(iter(windows))[0] if windows else None,
            "sdkAnrWindow": next(iter(windows))[0] if windows and target == SETUP_PACKAGE else None,
            "recoveryPackage": recovery_package, "launcherIdentity": identity,
            "homeFocused": home is not None and component(focus[0]) == home and component(focused_app[0]) == home,
            "bootCompleted": values["boot"], "provisioned": values["provisioned"],
            "userSetupComplete": values["setup"], "appInstalled": False, "verifiedAvd": expected_avd}


class Preparation:
    def __init__(self, adb, output, deadline, *, execute=subprocess.run, clock=time.monotonic, sleep=time.sleep):
        self.adb, self.output, self.deadline = adb, output, deadline
        self.execute, self.clock, self.sleep = execute, clock, sleep

    def command(self, serial, arguments, *, binary=False, deadline=None):
        effective_deadline = min(self.deadline, deadline if deadline is not None else self.deadline)
        remaining = effective_deadline - self.clock()
        if remaining <= 0:
            raise MeasurementError("SDK preparation or observation deadline exceeded")
        command = [self.adb, "-s", serial, *arguments]
        try:
            result = self.execute(command, capture_output=True, timeout=min(15, remaining), check=False)
            record = {"arguments": arguments, "exitCode": result.returncode,
                      "stderr": result.stderr.decode("utf-8", errors="replace")}
            if not binary:
                record["stdout"] = result.stdout.decode("utf-8", errors="replace").replace("\r\n", "\n").strip()
            if self.clock() >= effective_deadline:
                record.update(processExitCode=result.returncode, exitCode=None, error="DeadlineExceeded")
            return record, result.stdout
        except subprocess.TimeoutExpired as error:
            return {"arguments": arguments, "exitCode": None, "error": "TimeoutExpired",
                    "stderr": (error.stderr or b"").decode("utf-8", errors="replace"),
                    "stdout": None if binary else (error.stdout or b"").decode("utf-8", errors="replace")}, error.stdout or b""

    def snapshot(self, serial, avd, name, *, retiring_window=None, retiring_package=SETUP_PACKAGE, deadline=None):
        folder = self.output / serial
        folder.mkdir(exist_ok=True)
        record = {"name": name, "utc": datetime.now(timezone.utc).isoformat(), "commands": {}}
        try:
            for key, args in (("avd", ["emu", "avd", "name"]), ("state", ["shell", section_script(QUERIES)])):
                record["commands"][key], _ = self.command(serial, args, deadline=deadline)
                if record["commands"][key]["exitCode"] != 0:
                    raise MeasurementError(f"{key} command failed; no recovery is permitted")
            launcher_raw = None
            raw = record["commands"]["state"]["stdout"]
            if (retiring_window is not None and retiring_package == LAUNCHER_PACKAGE
                    or f"Application Not Responding: {LAUNCHER_PACKAGE}" in raw):
                record["commands"]["launcher"], _ = self.command(
                    serial, ["shell", section_script(LAUNCHER_QUERIES)], deadline=deadline)
                if record["commands"]["launcher"]["exitCode"] != 0:
                    raise MeasurementError("Launcher identity command failed; no recovery is permitted")
                launcher_raw = record["commands"]["launcher"]["stdout"]
            screenshot, pixels = self.command(serial, ["exec-out", "screencap", "-p"], binary=True, deadline=deadline)
            record["commands"]["screenshot"] = screenshot
            # Preserve original bytes even when screenshot validation fails.
            image_path = folder / f"{name}.png"
            image_path.write_bytes(pixels)
            screenshot.update(path=image_path.name, sha256=hashlib.sha256(pixels).hexdigest(), bytes=len(pixels))
            if (screenshot["exitCode"] != 0 or len(pixels) < 45
                    or not pixels.startswith(b"\x89PNG\r\n\x1a\n") or pixels[12:16] != b"IHDR"
                    or not pixels.endswith(b"\x00\x00\x00\x00IEND\xaeB\x60\x82")):
                raise MeasurementError("original PNG could not be retained; no recovery is permitted")
            record["state"] = inspect_state(record["commands"]["state"]["stdout"], avd,
                                             record["commands"]["avd"]["stdout"], retiring_window=retiring_window,
                                             retiring_package=retiring_package, launcher_raw=launcher_raw)
            return record["state"]
        finally:
            (folder / f"{name}.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")

    def mutate(self, serial, name, arguments, *, deadline=None):
        # Exclusive creation precedes the command: an uncertain attempt is never retried.
        path = self.output / serial / f"{name}.json"
        with path.open("x", encoding="utf-8") as stream:
            json.dump({"arguments": arguments, "attempted": True}, stream)
        result, _ = self.command(serial, arguments, deadline=deadline)
        path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        if result["exitCode"] != 0 or re.search(r"(?im)^\s*(?:Error|Exception)[: ]", result.get("stdout", "")):
            raise MeasurementError(f"{name} failed; no retry is permitted")

    def recover(self, serial, avd, before):
        # Recheck after saving the screenshot so a changed dialog cannot inherit authorization.
        confirmed = self.snapshot(serial, avd, "confirmed-before-recovery")
        if confirmed != before:
            raise MeasurementError("SDK recovery preconditions changed; no mutation is permitted")
        package = before["recoveryPackage"]
        if package not in (SETUP_PACKAGE, LAUNCHER_PACKAGE):
            raise MeasurementError("system recovery has no exact permitted package")
        self.mutate(serial, "force-stop-attempt", ["shell", f"am force-stop --user 0 {package}"])
        limit = min(self.deadline, self.clock() + 30)

        def observe(name):
            after = self.snapshot(serial, avd, name, retiring_window=before["anrWindow"],
                                  retiring_package=package, deadline=limit)
            if after["anrEvents"] != before["anrEvents"] or after["resolvedHome"] != before["resolvedHome"]:
                raise MeasurementError("ANR events or Home changed after recovery; no further mutation is permitted")
            if package == LAUNCHER_PACKAGE and after["launcherIdentity"]["uid"] != before["launcherIdentity"]["uid"]:
                raise MeasurementError("system Launcher UID changed after recovery")
            return after

        # Android dismisses ANR dialogs asynchronously. Observe only the original
        # window retiring; never give a different dialog the same authorization.
        stopped = observe("after-force-stop")
        index = 0
        while stopped["anrWindow"] is not None and self.clock() < limit:
            self.sleep(min(1, max(0, limit - self.clock())))
            stopped = observe(f"after-force-stop-settle-{index:02}")
            index += 1
        if stopped["anrWindow"] is not None or self.clock() >= limit:
            raise MeasurementError("SDK ANR window did not retire after the single force-stop")
        self.mutate(serial, "home-attempt", ["shell", "am start -W --user 0 -a android.intent.action.MAIN "
                                             "-c android.intent.category.HOME -n " + shlex.quote(before["resolvedHome"])],
                    deadline=limit)
        index = 0
        while self.clock() < limit:
            after = observe(f"after-home-{index:02}")
            if after["homeFocused"] and after["anrWindow"] is None:
                if (package == LAUNCHER_PACKAGE
                        and after["launcherIdentity"]["pid"] in (None, before["launcherIdentity"]["pid"])):
                    raise MeasurementError("Home focus has no verified new system Launcher process")
                return {"status": "recovered-once", "package": package, "before": before, "after": after}
            index += 1
            self.sleep(min(1, max(0, limit - self.clock())))
        raise MeasurementError("Home did not regain focus after the single SDK recovery")


def prepare(adb, devices, output, *, execute=subprocess.run, clock=time.monotonic, sleep=time.sleep):
    output.mkdir(parents=True, exist_ok=False)
    runner = Preparation(adb, output, clock() + BUDGET_SECONDS, execute=execute, clock=clock, sleep=sleep)
    report = {"status": "failed", "budgetSeconds": BUDGET_SECONDS, "devices": {},
              "boundary": "SDK emulator preparation only, before MeowWatch installation; fresh read-only admission remains required"}
    try:
        # Check both devices before mutating either one.
        snapshots = {serial: runner.snapshot(serial, avd, "before") for serial, avd in devices.items()}
        for serial, avd in devices.items():
            before = snapshots[serial]
            if before["eligible"]:
                report["devices"][serial] = runner.recover(serial, avd, before)
            else:
                report["devices"][serial] = {"status": "not-needed", "reason": "no current eligible system ANR; no mutation", "before": before}
        report["status"] = "prepared"
    except (MeasurementError, OSError) as error:
        report["reason"] = str(error)
    finally:
        report["completedUtc"] = datetime.now(timezone.utc).isoformat()
        (output / "result.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", required=True)
    parser.add_argument("--phone", required=True)
    parser.add_argument("--tablet", required=True)
    parser.add_argument("--phone-avd", required=True)
    parser.add_argument("--tablet-avd", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    if (args.phone == args.tablet or args.phone_avd == args.tablet_avd
            or any(re.fullmatch(r"emulator-\d+", value) is None for value in (args.phone, args.tablet))
            or any(re.fullmatch(r"meowwatch_(?:phone|tablet)_[A-Za-z0-9_]+", value) is None for value in (args.phone_avd, args.tablet_avd))):
        parser.error("distinct task-created emulator serials and MeowWatch AVD names are required")
    try:
        report = prepare(args.adb, {args.phone: args.phone_avd, args.tablet: args.tablet_avd}, args.output)
    except OSError as error:
        print(f"SDK_SETUP_PREPARATION_FAILED: {error}")
        return 1
    print(f"SDK_SETUP_PREPARATION_{report['status'].upper()}: {report.get('reason', 'read-only admission is still required')}")
    return 0 if report["status"] == "prepared" else 1


if __name__ == "__main__":
    raise SystemExit(main())
