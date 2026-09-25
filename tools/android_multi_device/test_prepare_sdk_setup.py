from copy import deepcopy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from tools.android_multi_device.prepare_sdk_setup import (
    APP_PACKAGE, SETUP_PACKAGE, QUERIES, MeasurementError, inspect_state, prepare,
)

HOME = "com.google.android.apps.nexuslauncher/.NexusLauncherActivity"
EVENT = "1789650062.703   566  1868 I am_anr  : [0,1577,com.google.android.googlesdksetup,814267973,Input dispatching timed out (Application does not have a focused window).]"
# Actual user-0 history from run 35223362923, tablet sample-001 (Home ready).
GMS_HISTORY = "1789650070.003   579  2287 I am_anr  : [0,1614,com.google.android.gms,-1597325755,Broadcast of Intent { act=android.intent.action.SIM_STATE_CHANGED flg=0x15000010 cmp=com.google.android.gms/.checkin.CheckinServiceTriggerReceiver (has extras) }]"
DEVICES = {"emulator-5554": "meowwatch_phone_test", "emulator-5556": "meowwatch_tablet_test"}
PNG = bytes.fromhex("89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000b49444154789c636000020000050001a5f645400000000049454e44ae426082")


def state(anr=True):
    focus = f"Window{{8423e07 u0 Application Not Responding: {SETUP_PACKAGE}}}" if anr else f"Window{{a123 u0 {HOME}}}"
    return {"qemu": "1", "debuggable": "1", "boot": "1", "provisioned": "1", "setup": "1",
            "packages": "", "home": HOME,
            "window": f"  mCurrentFocus={focus}\n  mFocusedApp=ActivityRecord{{24d28e1 u0 {HOME} t7}}\n    mFocusedWindow={focus}",
            "anr": EVENT if anr else "--------- beginning of events"}


def raw(values):
    return "\n".join(f"MW_READY_BEGIN {name}\n{values[name]}\nMW_READY_END {name} 0" for name in QUERIES)


class FakeADB:
    def __init__(self, phone=None, tablet=None):
        self.states = {"emulator-5554": phone or state(), "emulator-5556": tablet or state(False)}
        self.calls = []
        self.value = 0
        self.state_reads = {}
        self.force_fails = False
        self.force_timeout = False
        self.home_fails = False
        self.keep_dialog = False
        self.after_stop_other_anr = False
        self.changed_before = False
        self.changed_before_event = False
        self.after_home_event = False
        self.after_home_history_changed = False
        self.after_home_history_missing = False
        self.async_retire = False
        self.after_stop_replaced_window = False
        self.stopped = False
        self.recovery_package = SETUP_PACKAGE
        self.late_after_stop = False
        self.bad_png = False
        self.timeout = False
        self.late = False
        self.truncated_png = False

    def clock(self): return self.value
    def sleep(self, seconds): self.value += seconds

    def __call__(self, command, **kwargs):
        self.calls.append(command)
        self.value += 0.1
        if self.late: self.value += 90
        if self.late_after_stop and self.stopped: self.value += 31
        serial, arguments = command[2], command[3:]
        values = self.states[serial]
        exit_code, out, error = 0, b"", b""
        if self.timeout:
            raise subprocess.TimeoutExpired(command, kwargs["timeout"], output=b"partial evidence")
        if arguments == ["emu", "avd", "name"]:
            out = (DEVICES[serial] + "\nOK\n").encode()
        elif arguments == ["exec-out", "screencap", "-p"]:
            out = b"invalid screenshot" if self.bad_png else PNG[:8] if self.truncated_png else PNG
        elif arguments[0] == "shell" and "MW_READY_BEGIN" in arguments[1]:
            self.state_reads[serial] = self.state_reads.get(serial, 0) + 1
            if self.async_retire and self.stopped and serial == "emulator-5554":
                if self.state_reads[serial] >= 5:
                    values["window"] = state(False)["window"]
            if self.changed_before and serial == "emulator-5554" and self.state_reads[serial] == 2:
                values = deepcopy(values)
                values["window"] = values["window"].replace("8423e07", "9999999")
            if self.changed_before_event and serial == "emulator-5554" and self.state_reads[serial] == 2:
                values = deepcopy(values)
                values["anr"] += "\n" + GMS_HISTORY
            out = raw(values).encode()
        elif arguments == ["shell", f"am force-stop --user 0 {self.recovery_package}"]:
            self.stopped = True
            if self.force_timeout:
                raise subprocess.TimeoutExpired(command, kwargs["timeout"], output=b"uncertain outcome")
            if self.force_fails:
                exit_code, error = 1, b"force-stop failed"
            elif not self.keep_dialog:
                values["window"] = state(False)["window"]
            if self.async_retire:
                window_id = "865019b" if self.recovery_package != SETUP_PACKAGE else "8423e07"
                values["window"] += f"\nWindow{{{window_id} u0 Application Not Responding: {self.recovery_package}}}"
            if self.after_stop_replaced_window:
                values["window"] += f"\nWindow{{bbbb u0 Application Not Responding: {self.recovery_package}}}"
            if self.after_stop_other_anr:
                values["anr"] += "\n" + EVENT.replace(SETUP_PACKAGE, "com.google.android.gms")
        elif arguments[0] == "shell" and arguments[1].startswith("am start -W --user 0"):
            if self.home_fails:
                out = b"Error: Activity not started"
            elif not self.keep_dialog:
                values["window"] = state(False)["window"]
            if self.after_home_event:
                values["anr"] += "\n" + GMS_HISTORY
            if self.after_home_history_changed:
                values["anr"] = values["anr"].replace("1789650062.703", "1789650063.703")
            if self.after_home_history_missing:
                values["anr"] = ""
        else:
            raise AssertionError(f"Unexpected command: {command}")
        return subprocess.CompletedProcess(command, exit_code, out, error)

    def mutations(self):
        return [call for call in self.calls if any("am force-stop" in arg or "am start" in arg for arg in call)]


class SetupPreparationTests(unittest.TestCase):
    def run_fake(self, fake, output):
        return prepare("adb", DEVICES, output, execute=fake, clock=fake.clock, sleep=fake.sleep)

    def test_exact_real_setup_dialog_recovers_once_and_retains_original_evidence(self):
        fake = FakeADB()
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "prepare"
            result = self.run_fake(fake, output)
            self.assertEqual(result["status"], "prepared")
            self.assertEqual(result["devices"]["emulator-5554"]["status"], "recovered-once")
            self.assertEqual(result["devices"]["emulator-5556"]["status"], "not-needed")
            self.assertEqual(len(fake.mutations()), 2)
            self.assertEqual(fake.mutations()[0][-1], f"am force-stop --user 0 {SETUP_PACKAGE}")
            self.assertIn("-c android.intent.category.HOME -n com.google.android.apps.nexuslauncher/", fake.mutations()[1][-1])
            self.assertEqual((output / "emulator-5554/before.png").read_bytes(), PNG)
            before = json.loads((output / "emulator-5554/before.json").read_text())
            self.assertIn(EVENT, before["commands"]["state"]["stdout"])
            self.assertEqual(result["devices"]["emulator-5554"]["after"]["anrEvents"][0]["raw"], EVENT)
            with self.assertRaises(FileExistsError):
                self.run_fake(fake, output)
            self.assertEqual(len(fake.mutations()), 2)

    def test_no_anr_and_historical_setup_event_never_mutate(self):
        for historical in (None, EVENT, GMS_HISTORY, EVENT + "\n" + GMS_HISTORY):
            values = state(False)
            if historical: values["anr"] = historical
            fake = FakeADB(values)
            with tempfile.TemporaryDirectory() as directory:
                result = self.run_fake(fake, Path(directory) / "prepare")
                self.assertEqual(result["status"], "prepared")
                self.assertEqual(fake.mutations(), [])

    def test_actual_tablet_gms_history_does_not_block_phone_setup_recovery(self):
        tablet = state(False)
        tablet["window"] = ("  mCurrentFocus=Window{babe430 u0 com.google.android.apps.nexuslauncher/com.google.android.apps.nexuslauncher.NexusLauncherActivity}\n"
                            "  mFocusedApp=ActivityRecord{83e8d98 u0 com.google.android.apps.nexuslauncher/.NexusLauncherActivity t7}")
        tablet["anr"] = GMS_HISTORY
        phone = state()
        phone["anr"] += "\n" + GMS_HISTORY
        fake = FakeADB(phone, tablet)
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "prepare"
            result = self.run_fake(fake, output)
            self.assertEqual(result["status"], "prepared")
            self.assertEqual(result["devices"]["emulator-5556"]["status"], "not-needed")
            self.assertEqual([call[2] for call in fake.mutations()], ["emulator-5554"] * 2)
            self.assertEqual(result["devices"]["emulator-5554"]["after"]["anrEvents"][-1]["raw"], GMS_HISTORY)
            retained = json.loads((output / "emulator-5556/before.json").read_text())
            self.assertIn(GMS_HISTORY, retained["commands"]["state"]["stdout"])

    def test_no_current_anr_during_normal_provisioning_defers_to_read_only_gate(self):
        for home in ("com.android.settings/.FallbackHome", "No activity found"):
            with self.subTest(home=home), tempfile.TemporaryDirectory() as directory:
                values = state(False)
                values.update(home=home, provisioned="0", setup="0", boot="0")
                values["window"] = ("mCurrentFocus=Window{a123 u0 com.android.settings/.FallbackHome}\n"
                                    "mFocusedApp=ActivityRecord{b123 u0 com.android.settings/.FallbackHome t1}")
                fake = FakeADB(values)
                result = self.run_fake(fake, Path(directory) / "prepare")
                self.assertEqual(result["status"], "prepared")
                self.assertEqual(result["devices"]["emulator-5554"]["status"], "not-needed")
                self.assertEqual(fake.mutations(), [])

    def test_original_sdk_window_can_retire_asynchronously_before_home_intent(self):
        fake = FakeADB(); fake.async_retire = True
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "prepare"
            result = self.run_fake(fake, output)
            self.assertEqual(result["status"], "prepared")
            self.assertEqual(len(fake.mutations()), 2)
            stopped = json.loads((output / "emulator-5554/after-force-stop.json").read_text())["state"]
            self.assertTrue(stopped["homeFocused"])
            self.assertEqual(stopped["sdkAnrWindow"], "8423e07")
            self.assertIsNone(result["devices"]["emulator-5554"]["after"]["sdkAnrWindow"])
            self.assertTrue((output / "emulator-5554/after-force-stop-settle-01.json").exists())

    def test_ambiguous_other_anr_physical_installed_and_incomplete_refuse_without_mutation(self):
        cases = [("qemu", "0"), ("debuggable", "0"), ("boot", "0"), ("provisioned", "0"), ("setup", "0"),
                 ("packages", f"package:{APP_PACKAGE}"), ("packages", "Error: package manager unavailable"),
                 ("anr", ""), ("anr", EVENT[:-1]), ("anr", EVENT.replace(SETUP_PACKAGE, "com.google.android.gms")),
                 ("window", state()["window"].replace(SETUP_PACKAGE, "com.google.android.gms")),
                 ("window", state()["window"] + "\nmCurrentFocus=null"),
                 ("window", state()["window"] + f"\nWindow{{bbbb u0 Application Not Responding: {SETUP_PACKAGE}}}"),
                 ("window", state()["window"] + "\nWindow{cccc u0 Application Error: com.google.android.gms}"),
                 ("home", SETUP_PACKAGE + "/.DefaultActivity"),
                 ("home", "com.android.settings/.FallbackHome"), ("home", "No activity found")]
        for key, value in cases:
            with self.subTest(key=key, value=value[:70]), tempfile.TemporaryDirectory() as directory:
                values = state(); values[key] = value; fake = FakeADB(values)
                result = self.run_fake(fake, Path(directory) / "prepare")
                self.assertEqual(result["status"], "failed")
                self.assertEqual(fake.mutations(), [])

    def test_wrong_avd_name_cannot_be_authorized_by_serial_alone(self):
        with self.assertRaisesRegex(MeasurementError, "expected AVD"):
            inspect_state(raw(state()), "meowwatch_phone_other", "meowwatch_phone_test\nOK")

    def test_other_device_anr_blocks_global_preflight_before_any_mutation(self):
        tablet = state(); tablet["anr"] = EVENT.replace(SETUP_PACKAGE, "com.google.android.gms")
        tablet["window"] = tablet["window"].replace(SETUP_PACKAGE, "com.google.android.gms")
        fake = FakeADB(tablet=tablet)
        with tempfile.TemporaryDirectory() as directory:
            result = self.run_fake(fake, Path(directory) / "prepare")
            self.assertEqual(result["status"], "failed")
            self.assertEqual(fake.mutations(), [])

    def test_changed_preconditions_failed_screenshot_and_timeouts_do_not_mutate(self):
        for flag in ("changed_before", "changed_before_event", "bad_png", "truncated_png", "timeout", "late"):
            fake = FakeADB(); setattr(fake, flag, True)
            with self.subTest(flag=flag), tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "prepare"
                result = self.run_fake(fake, output)
                self.assertEqual(result["status"], "failed")
                self.assertEqual(fake.mutations(), [])
                self.assertTrue((output / "emulator-5554/before.json").exists())

    def test_failed_or_uncertain_mutation_is_never_retried(self):
        for flag, count in (("force_fails", 1), ("force_timeout", 1), ("home_fails", 2),
                            ("after_stop_other_anr", 1), ("after_home_event", 2),
                            ("after_home_history_changed", 2), ("after_home_history_missing", 2),
                            ("after_stop_replaced_window", 1), ("late_after_stop", 1), ("keep_dialog", 1)):
            fake = FakeADB(); setattr(fake, flag, True)
            with self.subTest(flag=flag), tempfile.TemporaryDirectory() as directory:
                result = self.run_fake(fake, Path(directory) / "prepare")
                self.assertEqual(result["status"], "failed")
                self.assertEqual(len(fake.mutations()), count)
                self.assertLess(fake.value, 90)


if __name__ == "__main__":
    unittest.main()
