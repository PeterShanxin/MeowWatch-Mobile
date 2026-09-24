from copy import deepcopy
from fractions import Fraction
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from tools.android_multi_device.device_readiness import (
    DISPLAY_PROFILES, DeviceSampler, METRICS, STATE, MeasurementError, check_physical_geometry,
    evaluate_window, memory_provenance, parse_metrics, parse_sections, parse_state, run_gate,
)


HOME = "com.google.android.apps.nexuslauncher/.NexusLauncherActivity"
FULL_HOME = "com.google.android.apps.nexuslauncher/com.google.android.apps.nexuslauncher.NexusLauncherActivity"


def sections(values):
    return {name: {"exitCode": 0, "stdout": value} for name, value in values.items()}


def state():
    return sections({"qemu": "1", "debuggable": "1", "boot": "1", "bootanim": "stopped",
                     "provisioned": "1", "setup": "1", "home": HOME,
                     "window": f"  mCurrentFocus=Window{{abc u0 {FULL_HOME}}}\n  mFocusedApp=ActivityRecord{{abc u0 {HOME} t1}}",
                     "anr": "--------- beginning of events", "size": "Physical size: 720x1600",
                     "density": "Physical density: 280"})


def metrics(elapsed=10):
    return sections({"uptime_before": f"{elapsed}.00 10.00", "uptime_after": f"{elapsed}.00 10.00",
                     "stat": f"cpu  {elapsed*10} 0 0 {elapsed*90} 0 0 0 0 50 50\ncpu0 1 2 3 4 5 6 7 8 9 10",
                     "psi_cpu": f"some avg10=91.27 avg60=79.73 avg300=33.32 total={elapsed*1000}",
                     "psi_memory": f"some avg10=13.62 avg60=7.29 avg300=2.57 total=800000\nfull avg10=1.22 avg60=0.37 avg300=0.10 total={elapsed*100}",
                     "meminfo": "MemTotal:        3984200 kB\nMemFree: 200000 kB"})


def raw(values):
    return "\n".join(f"MW_READY_BEGIN {name}\n{item['stdout']}\nMW_READY_END {name} {item['exitCode']}"
                     for name, item in values.items())


def sample(elapsed=10):
    return {"state": parse_state(state()), "metrics": parse_metrics(metrics(elapsed)), "raw": {"fixture": True}}


class Clock:
    def __init__(self):
        self.value = 10.0

    def __call__(self):
        return self.value

    def sleep(self, seconds):
        self.value += seconds


class ReadinessTests(unittest.TestCase):
    def test_launcher_aligns_existing_skin_and_lcd_without_changing_other_hardware(self):
        launcher = Path(__file__).with_name("launch_two_avds.sh").read_text()
        program = launcher.split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0]
        for profile in ("standard", "recording"):
            with self.subTest(profile=profile), tempfile.TemporaryDirectory() as directory:
                paths = [Path(directory) / f"{role}.ini" for role in ("phone", "tablet")]
                for path in paths:
                    path.write_text("hw.lcd.width=1080\nhw.lcd.height=2400\nhw.lcd.density=420\n"
                                    "skin.name=pixel_6\nskin.path=/old/skins/pixel_6\nhw.ramSize=3072\n")
                process = subprocess.run([sys.executable, "-", *map(str, paths)], input=program,
                                         text=True, capture_output=True, timeout=10,
                                         env={**os.environ, "MEOWWATCH_CI_DISPLAY_PROFILE": profile})
                self.assertEqual(process.returncode, 0, process.stderr)
                for path, role in zip(paths, ("phone", "tablet")):
                    width, height, density = DISPLAY_PROFILES[profile][role]
                    geometry = f"{width}x{height}"
                    values = dict(line.split("=", 1) for line in path.read_text().splitlines())
                    self.assertEqual(values["skin.name"], geometry)
                    self.assertEqual(values["skin.path"], geometry)
                    self.assertEqual(f"{values['hw.lcd.width']}x{values['hw.lcd.height']}", geometry)
                    self.assertEqual(values["hw.lcd.density"], str(density))
                    self.assertEqual(values["hw.ramSize"], "3072")
                    base_width, base_height, base_density = DISPLAY_PROFILES["standard"][role]
                    self.assertEqual(Fraction(width, density), Fraction(base_width, base_density))
                    self.assertEqual(Fraction(height, density), Fraction(base_height, base_density))

    def test_recording_geometry_requires_actual_configured_size_and_density(self):
        self.assertIn("error", check_physical_geometry(sample(), "phone", "recording"))
        for role in ("phone", "tablet"):
            value = sample()
            width, height, density = DISPLAY_PROFILES["recording"][role]
            value["state"].update(physicalSize=f"{width}x{height}", physicalDensity=density,
                                  reportedSize=f"Physical size: {width}x{height}",
                                  reportedDensity=f"Physical density: {density}")
            self.assertNotIn("error", check_physical_geometry(deepcopy(value), role, "recording"))
            self.assertIn("error", check_physical_geometry(deepcopy(value), role))
            value["state"]["reportedSize"] += f"\nOverride size: {width}x{height}"
            self.assertIn("error", check_physical_geometry(value, role, "recording"))

    def test_cli_with_fake_adb_processes_records_ready_and_missing_su_failure(self):
        # Python accepts -s before its script name, so it can act as a real
        # subprocess transport for our two fake serial scripts on every host.
        # This verifies CLI/serialization/exit status, not Android readiness.
        module = Path(__file__).with_name("device_readiness.py").resolve()
        fake = '''import json, os, sys, time
from pathlib import Path
serial = Path(sys.argv[0]).name
command = sys.argv[-1]
with Path(serial + ".calls.jsonl").open("a") as stream:
    stream.write(json.dumps(sys.argv[1:]) + "\\n")
state = json.loads(STATE_JSON)
values = json.loads(METRICS_JSON)
if serial == "emulator-5556":
    state["size"]["stdout"] = "Physical size: 1280x800"
    state["density"]["stdout"] = "Physical density: 160"
if "MW_READY_BEGIN qemu" in command:
    values = state
else:
    elapsed = int(time.monotonic())
    values["uptime_before"]["stdout"] = values["uptime_after"]["stdout"] = f"{elapsed}.00 0.00"
    values["stat"]["stdout"] = f"cpu {elapsed*10} 0 0 {elapsed*90} 0 0 0 0"
    values["psi_cpu"]["stdout"] = f"some avg10=91.27 avg60=0 avg300=0 total={elapsed*1000}"
    values["psi_memory"]["stdout"] = f"some avg10=0 avg60=0 avg300=0 total=0\\nfull avg10=1.22 avg60=0 avg300=0 total={elapsed*100}"
    if command.startswith("su 0 sh -c "):
        if os.environ.get("FAKE_ADB_MODE") == "missing-su":
            print("su: not found", file=sys.stderr)
            sys.exit(127)
    else:
        values["psi_cpu"] = {"exitCode": 1, "stdout": ""}
        print("cat: /proc/pressure/cpu: Permission denied", file=sys.stderr)
for name, item in values.items():
    print(f"MW_READY_BEGIN {name}\\n{item['stdout']}\\nMW_READY_END {name} {item['exitCode']}")
'''.replace("STATE_JSON", repr(json.dumps(state()))).replace("METRICS_JSON", repr(json.dumps(metrics())))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for serial in ("emulator-5554", "emulator-5556"):
                (root / serial).write_text(fake)
            log = root / "emulator.log"
            log.write_text("Increasing RAM size to 4096MB\n")
            for mode, expected_exit in (("ready", 0), ("missing-su", 1)):
                output = root / mode
                process = subprocess.run(
                    [sys.executable, str(module), "--adb", sys.executable, "--phone", "emulator-5554",
                     "--tablet", "emulator-5556", "--output", str(output),
                     "--phone-log", str(log), "--tablet-log", str(log)],
                    cwd=root, env={**os.environ, "FAKE_ADB_MODE": mode},
                    capture_output=True, text=True, timeout=45)
                report = json.loads((output / "result.json").read_text())
                self.assertEqual(process.returncode, expected_exit,
                                 process.stdout + process.stderr + json.dumps(report))
                self.assertEqual(report["status"], "ready" if mode == "ready" else "failed")
                self.assertEqual(report["provenance"]["tablet"]["requestedMemoryMiB"], 3072)
                self.assertEqual(report["provenance"]["tablet"]["emulatorReportedIncreasedMemoryMiB"], 4096)
                samples = sorted(output.glob("sample-*.json"))
                final = json.loads(samples[-1].read_text())
                if mode == "ready":
                    self.assertGreaterEqual(len(samples), 4)
                    self.assertEqual(report["consecutiveWindows"], 3)
                    for device in final["devices"].values():
                        self.assertIn("su 0", device["measurementAccess"])
                        self.assertIn("Permission denied", device["raw"]["shellMetrics"]["stderr"])
                        self.assertIn("stateAfterMetrics", device["raw"])
                else:
                    self.assertEqual(len(samples), 1)
                    self.assertIn("critical", report["reason"])
                    self.assertIn("su: not found", final["devices"]["emulator-5554"]["raw"]["suMetrics"]["stderr"])

    def test_parses_cpu_idle_without_double_counting_guest_and_psi_total_not_average(self):
        result = parse_metrics(metrics())
        self.assertEqual(result["cpuTotalTicks"], 1000)
        self.assertEqual(result["cpuIdleTicks"], 900)
        window = evaluate_window(sample(10), sample(15))
        self.assertTrue(window["ready"])
        self.assertEqual(window["measured"]["cpuIdlePercent"], 90)
        self.assertEqual(window["measured"]["cpuSomeStallPercent"], 0.1)

    def test_readiness_thresholds_include_exact_boundaries(self):
        before, after = sample(10), sample(15)
        after["metrics"].update(cpuIdleTicks=before["metrics"]["cpuIdleTicks"] + 100,
                                cpuSomeStallMicroseconds=before["metrics"]["cpuSomeStallMicroseconds"] + 1_000_000,
                                memoryFullStallMicroseconds=before["metrics"]["memoryFullStallMicroseconds"] + 50_000)
        self.assertTrue(evaluate_window(before, after)["ready"])
        for key, delta in (("cpuIdleTicks", -1), ("cpuSomeStallMicroseconds", 1), ("memoryFullStallMicroseconds", 1)):
            bad = deepcopy(after)
            bad["metrics"][key] += delta
            self.assertFalse(evaluate_window(before, bad)["ready"])

    def test_ambiguous_missing_or_nonadvancing_measurements_fail(self):
        for name in METRICS:
            bad = metrics()
            bad[name]["stdout"] = ""
            with self.subTest(name=name), self.assertRaises(MeasurementError):
                parse_metrics(bad)
        for key in ("cpuTotalTicks", "cpuIdleTicks", "cpuSomeStallMicroseconds", "memoryFullStallMicroseconds"):
            bad = sample(15)
            bad["metrics"][key] = -1
            with self.subTest(key=key), self.assertRaises(MeasurementError):
                evaluate_window(sample(10), bad)
        self.assertFalse(evaluate_window(sample(10), sample(14))["ready"])

    def test_both_focus_owners_and_every_boot_condition_are_required(self):
        self.assertTrue(parse_state(state())["ready"])
        for name, value in (("boot", "0"), ("bootanim", "running"), ("provisioned", "0"), ("setup", "0"),
                            ("home", "com.android.settings/.FallbackHome"), ("home", "No activity found")):
            bad = state()
            bad[name]["stdout"] = value
            self.assertFalse(parse_state(bad)["ready"])
        for value in (f"mCurrentFocus=null\nmFocusedApp=ActivityRecord{{a {HOME}}}",
                      f"mCurrentFocus=Window{{a {HOME}}}\nmFocusedApp=ActivityRecord{{a com.google.android.googlesdksetup/.DefaultActivity}}",
                      f"mCurrentFocus=Window{{a {HOME}}}\nmFocusedApp=ActivityRecord{{a {HOME}}}\nApplication Not Responding"):
            bad = state()
            bad["window"]["stdout"] = value
            self.assertFalse(parse_state(bad)["ready"])
        bad["window"]["stdout"] = ""
        with self.assertRaises(MeasurementError):
            parse_state(bad)

    def test_new_anr_resets_window_without_discarding_history(self):
        before, after = sample(10), sample(15)
        event = "1789642875.200  580 3787 I am_anr : [0,3306,com.android.test,0,reason]"
        after["state"]["anrEvents"] = [event]
        self.assertEqual(evaluate_window(before, after)["newAnrEvents"], [event])
        self.assertFalse(evaluate_window(before, after)["ready"])
        before["state"]["anrEvents"] = [event]
        self.assertTrue(evaluate_window(before, after)["ready"])
        after["state"]["anrEvents"] = []
        with self.assertRaisesRegex(MeasurementError, "history disappeared"):
            evaluate_window(before, after)

    def test_state_after_metrics_cannot_release_a_newly_blocked_home(self):
        calls = []
        def execute(command, **kwargs):
            calls.append(command)
            if len(calls) == 2:
                value = metrics()
            else:
                value = state()
                if len(calls) == 3:
                    value["window"]["stdout"] = "mCurrentFocus=null\nmFocusedApp=null"
            return subprocess.CompletedProcess(command, 0, raw(value).encode(), b"")
        result = DeviceSampler("adb", 100, clock=lambda: 0, execute=execute).capture("emulator-5554")
        self.assertNotIn("error", result)
        self.assertFalse(result["state"]["ready"])
        self.assertIn("stateAfterMetrics", result["raw"])

    def test_missing_or_duplicate_output_sections_are_not_success(self):
        self.assertEqual(parse_sections(raw(metrics()), METRICS), metrics())
        self.assertEqual(parse_sections(raw(metrics()).replace("\n", "\r\n"), METRICS), metrics())
        for value in ("", raw(metrics()) + "\n" + raw(metrics()), "Permission denied"):
            with self.assertRaises(MeasurementError):
                parse_sections(value, METRICS)

    def test_privileged_psi_fallback_is_read_only_and_verified(self):
        calls = []
        denied = metrics()
        denied["psi_cpu"] = {"exitCode": 1, "stdout": ""}
        def execute(command, **kwargs):
            calls.append(command)
            if len(calls) in (1, 4):
                return subprocess.CompletedProcess(command, 0, raw(state()).encode(), b"")
            if len(calls) == 2:
                return subprocess.CompletedProcess(command, 0, raw(denied).encode(), b"cat: /proc/pressure/cpu: Permission denied")
            return subprocess.CompletedProcess(command, 0, raw(metrics()).encode(), b"")
        result = DeviceSampler("adb", 100, clock=lambda: 0, execute=execute).capture("emulator-5554")
        self.assertNotIn("error", result)
        self.assertIn("su 0", result["measurementAccess"])
        self.assertTrue(calls[2][-1].startswith("su 0 sh -c "))
        for command in calls:
            self.assertNotIn("force-stop", command[-1])
            self.assertNotIn("settings put", command[-1])
            self.assertNotIn("keyevent", command[-1])
        self.assertIn("shellMetrics", result["raw"])
        self.assertIn("suMetrics", result["raw"])

    def test_missing_su_unreadable_psi_or_non_emulator_cannot_pass(self):
        for case in ("su_missing", "missing_psi", "not_debuggable", "physical"):
            calls = []
            setup = state()
            if case == "not_debuggable": setup["debuggable"]["stdout"] = "0"
            if case == "physical": setup["qemu"]["stdout"] = "0"
            denied = metrics()
            denied["psi_cpu"] = {"exitCode": 1, "stdout": ""}
            def execute(command, **kwargs):
                calls.append(command)
                if len(calls) == 1:
                    return subprocess.CompletedProcess(command, 0, raw(setup).encode(), b"")
                if len(calls) == 2:
                    message = b"No such file" if case == "missing_psi" else b"Permission denied"
                    return subprocess.CompletedProcess(command, 0, raw(denied).encode(), message)
                return subprocess.CompletedProcess(command, 127, b"", b"su: not found")
            result = DeviceSampler("adb", 100, clock=lambda: 0, execute=execute).capture("emulator-5554")
            with self.subTest(case=case):
                self.assertIn("error", result)
                self.assertEqual(len(calls), 1 if case == "physical" else 3 if case == "su_missing" else 2)

    def test_subprocess_deadline_and_timeout_fail_with_evidence(self):
        timeouts = []
        def execute(command, **kwargs):
            timeouts.append(kwargs["timeout"])
            raise subprocess.TimeoutExpired(command, kwargs["timeout"])
        result = DeviceSampler("adb", 2, clock=lambda: 0, execute=execute).capture("emulator-5554")
        self.assertEqual(timeouts, [2])
        self.assertIn("TimeoutExpired", result["error"])
        self.assertEqual(result["raw"]["state"]["error"], "TimeoutExpired")

    def test_three_global_windows_required_and_one_bad_device_resets_both(self):
        clock = Clock()
        def capture(serial):
            value = sample(int(clock()))
            if serial == "tablet" and clock() == 20:
                value["state"]["reasons"] = ["system dialog"]
            return value
        with tempfile.TemporaryDirectory() as directory:
            report = run_gate(["phone", "tablet"], Path(directory), capture, clock=clock, sleep=clock.sleep,
                              deadline=100, provenance={})
            self.assertEqual(report["status"], "ready")
            self.assertEqual(clock(), 40)
            self.assertEqual(report["consecutiveWindows"], 3)
            self.assertEqual(len(list(Path(directory).glob("sample-*.json"))), 7)
            self.assertEqual(json.loads((Path(directory) / "result.json").read_text())["status"], "ready")

    def test_single_device_measurement_failure_and_deadline_are_global_failures(self):
        for missing in (True, False):
            clock = Clock()
            def capture(serial):
                if serial == "tablet" and missing: return {"error": "PSI unavailable", "raw": {"stderr": "Permission denied"}}
                value = sample(int(clock()))
                value["state"]["reasons"] = ["boot incomplete"]
                return value
            with tempfile.TemporaryDirectory() as directory:
                report = run_gate(["phone", "tablet"], Path(directory), capture, clock=clock, sleep=clock.sleep,
                                  deadline=30, provenance={})
                self.assertEqual(report["status"], "failed")
                self.assertLessEqual(clock(), 30)
                self.assertIn("critical" if missing else "budget", report["reason"])

    def test_deadline_cannot_be_passed_by_a_late_third_window(self):
        clock = Clock()
        def capture(serial):
            value = sample(int(clock()))
            if clock() == 25:
                clock.value = 31
            return value
        with tempfile.TemporaryDirectory() as directory:
            report = run_gate(["phone", "tablet"], Path(directory), capture, clock=clock, sleep=clock.sleep,
                              deadline=30, provenance={})
            self.assertEqual(report["status"], "failed")

    def test_previous_evidence_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            (output / "result.json").write_text("previous evidence")
            with self.assertRaises(MeasurementError):
                run_gate(["phone", "tablet"], output, lambda _: sample(), deadline=100, provenance={})
            self.assertEqual((output / "result.json").read_text(), "previous evidence")

    def test_ram_and_physical_geometry_provenance_do_not_claim_requested_ram(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "emulator.log"
            log.write_text("INFO | Increasing RAM size to 4096MB\n")
            ram = memory_provenance(3072, log)
            self.assertEqual(ram["requestedMemoryMiB"], 3072)
            self.assertEqual(ram["emulatorReportedIncreasedMemoryMiB"], 4096)
        self.assertNotIn("error", check_physical_geometry(sample(), "phone"))
        wrong = sample()
        wrong["state"]["reportedSize"] += "\nOverride size: 720x1600"
        self.assertIn("error", check_physical_geometry(wrong, "phone"))
        self.assertIn("error", check_physical_geometry(sample(), "tablet"))


if __name__ == "__main__":
    unittest.main()
