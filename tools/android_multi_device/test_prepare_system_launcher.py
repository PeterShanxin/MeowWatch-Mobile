from pathlib import Path
import json
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from tools.android_multi_device.test_prepare_sdk_setup import (
    DEVICES, FakeADB, HOME, state,
)
from tools.android_multi_device.prepare_sdk_setup import prepare


LAUNCHER = "com.google.android.apps.nexuslauncher"
# Original phone events/window from Together 35236920607, before installation.
LAUNCHER_EVENT = "1789657712.111   579  2328 I am_anr  : [0,1221,com.google.android.apps.nexuslauncher,885767749,Input dispatching timed out (Application does not have a focused window).]"
SETUP_HISTORY = "1789657705.833   579  1949 I am_anr  : [0,1529,com.google.android.googlesdksetup,814267973,Input dispatching timed out (Application does not have a focused window).]"


def launcher_state():
    values = state()
    values["window"] = ("mCurrentFocus=Window{865019b u0 Application Not Responding: " + LAUNCHER + "}\n"
                        "mFocusedApp=ActivityRecord{b48c8c9 u0 " + HOME + " t7}\n"
                        "mFocusedWindow=Window{865019b u0 Application Not Responding: " + LAUNCHER + "}")
    values["anr"] = SETUP_HISTORY + "\n" + LAUNCHER_EVENT
    return values


class LauncherADB(FakeADB):
    def __init__(self):
        super().__init__(phone=launcher_state())
        self.recovery_package = LAUNCHER
        self.system_package = f"package:{LAUNCHER} uid:10179"
        self.processes = f"PID UID NAME\n1221 10179 {LAUNCHER}"
        self.identity_changed = False
        self.identity_reads = 0
        self.home_started = False
        self.post_uid_changed = False
        self.same_pid_after_home = False
        self.api = "35"
        self.abi = "x86_64"

    def __call__(self, command, **kwargs):
        if "MW_READY_BEGIN launcher_system_package" in command[-1]:
            self.calls.append(command)
            self.value += .1
            self.identity_reads += 1
            package = self.system_package
            if (self.identity_changed and self.identity_reads >= 2
                    or self.post_uid_changed and self.stopped):
                package = package.replace("10179", "10180")
            processes = self.processes
            if self.stopped:
                processes = (processes.replace("1221", "2333") if self.home_started else "PID UID NAME")
                if self.post_uid_changed:
                    processes = processes.replace("10179", "10180")
                if self.same_pid_after_home and self.home_started:
                    processes = processes.replace("2333", "1221")
            out = (f"MW_READY_BEGIN launcher_system_package\n{package}\nMW_READY_END launcher_system_package 0\n"
                   f"MW_READY_BEGIN launcher_processes\n{processes}\nMW_READY_END launcher_processes 0\n"
                   f"MW_READY_BEGIN launcher_api\n{self.api}\nMW_READY_END launcher_api 0\n"
                   f"MW_READY_BEGIN launcher_abi\n{self.abi}\nMW_READY_END launcher_abi 0")
            return subprocess.CompletedProcess(command, 0, out.encode(), b"")
        if command[-1].startswith("am start -W --user 0"):
            self.home_started = True
        return super().__call__(command, **kwargs)


class SystemLauncherPreparationTests(unittest.TestCase):
    def run_fake(self, fake, output, *, system="Linux", machine="x86_64"):
        with patch("platform.system", return_value=system), patch("platform.machine", return_value=machine):
            return prepare("adb", DEVICES, output, execute=fake, clock=fake.clock, sleep=fake.sleep)

    def test_actual_launcher_with_sdk_history_recovers_only_launcher_once(self):
        fake = LauncherADB()
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "prepare"
            result = self.run_fake(fake, output)
            self.assertEqual(result["status"], "prepared", result)
            self.assertEqual(len(fake.mutations()), 2)
            self.assertEqual(fake.mutations()[0][-1], f"am force-stop --user 0 {LAUNCHER}")
            recovered = result["devices"]["emulator-5554"]
            self.assertEqual(recovered["package"], LAUNCHER)
            self.assertEqual(recovered["before"]["launcherIdentity"]["pid"], 1221)
            self.assertEqual(recovered["after"]["launcherIdentity"]["pid"], 2333)
            self.assertEqual(recovered["before"]["anrEvents"], recovered["after"]["anrEvents"])
            self.assertIn(SETUP_HISTORY, (output / "emulator-5554/before.json").read_text())

    def test_launcher_identity_and_runtime_guards_refuse_before_mutation(self):
        cases = [
            ("system_package", ""),
            ("system_package", f"package:{LAUNCHER} uid:110179"),
            ("system_package", f"package:{LAUNCHER}.other uid:10179"),
            ("processes", f"PID UID NAME\n1222 10179 {LAUNCHER}"),
            ("processes", f"PID UID NAME\n1221 10180 {LAUNCHER}"),
            ("processes", f"PID UID NAME\n1221 10179 {LAUNCHER}\n1222 10179 {LAUNCHER}"),
            ("identity_changed", True),
            ("api", "34"), ("abi", "arm64-v8a"),
        ]
        for field, value in cases:
            with self.subTest(field=field, value=value), tempfile.TemporaryDirectory() as directory:
                fake = LauncherADB(); setattr(fake, field, value)
                self.assertEqual(self.run_fake(fake, Path(directory) / "prepare")["status"], "failed")
                self.assertEqual(fake.mutations(), [])
        for system, machine in (("Windows", "AMD64"), ("Linux", "aarch64")):
            with self.subTest(system=system), tempfile.TemporaryDirectory() as directory:
                fake = LauncherADB()
                self.assertEqual(self.run_fake(fake, Path(directory) / "prepare", system=system, machine=machine)["status"], "failed")
                self.assertEqual(fake.mutations(), [])

    def test_launcher_ownership_and_history_guards_refuse_before_mutation(self):
        cases = [("packages", "package:com.meowwatch.meowwatch_mobile"), ("qemu", "0"),
                 ("debuggable", "0"), ("boot", "0"), ("provisioned", "0"), ("setup", "0"),
                 ("anr", SETUP_HISTORY), ("home", "other.launcher/.Home"),
                 ("anr", SETUP_HISTORY + "\n" + LAUNCHER_EVENT.replace("[0,1221,", "[0,1222,")),
                 ("window", launcher_state()["window"] + "\nPermissionDialog"),
                 ("window", launcher_state()["window"] + "\nWindow{abc u0 Application Error: com.google.android.gms}")]
        for key, value in cases:
            with self.subTest(key=key), tempfile.TemporaryDirectory() as directory:
                fake = LauncherADB(); fake.states["emulator-5554"][key] = value
                self.assertEqual(self.run_fake(fake, Path(directory) / "prepare")["status"], "failed")
                self.assertEqual(fake.mutations(), [])

    def test_launcher_recovery_never_retries_or_chains_another_package(self):
        for flag, count in (("force_timeout", 1), ("force_fails", 1), ("home_fails", 2),
                            ("after_stop_other_anr", 1), ("after_stop_replaced_window", 1),
                            ("after_home_event", 2), ("after_home_history_missing", 2),
                            ("post_uid_changed", 1), ("same_pid_after_home", 2),
                            ("keep_dialog", 1)):
            with self.subTest(flag=flag), tempfile.TemporaryDirectory() as directory:
                fake = LauncherADB(); setattr(fake, flag, True)
                self.assertEqual(self.run_fake(fake, Path(directory) / "prepare")["status"], "failed")
                self.assertEqual(len(fake.mutations()), count)
                self.assertLess(fake.value, 90)

    def test_launcher_window_retires_before_home_and_new_process_is_required(self):
        fake = LauncherADB(); fake.async_retire = True
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "prepare"
            result = self.run_fake(fake, output)
            self.assertEqual(result["status"], "prepared", result)
            after_stop = json.loads((output / "emulator-5554/after-force-stop.json").read_text())
            self.assertEqual(after_stop["state"]["anrWindow"], "865019b")
            self.assertIsNone(after_stop["state"]["launcherIdentity"]["pid"])
            retired = json.loads((output / "emulator-5554/after-force-stop-settle-01.json").read_text())
            self.assertIsNone(retired["state"]["anrWindow"])
            self.assertIsNone(retired["state"]["launcherIdentity"]["pid"])
            self.assertTrue((output / "emulator-5554/after-force-stop.png").is_file())
            self.assertEqual(len(fake.mutations()), 2)

    def test_normal_home_with_original_history_has_no_launcher_probe_or_mutation(self):
        fake = LauncherADB()
        fake.states["emulator-5554"]["window"] = state(False)["window"]
        with tempfile.TemporaryDirectory() as directory:
            result = self.run_fake(fake, Path(directory) / "prepare")
            self.assertEqual(result["status"], "prepared")
            self.assertEqual(fake.identity_reads, 0)
            self.assertEqual(fake.mutations(), [])


if __name__ == "__main__":
    unittest.main()
