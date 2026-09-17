from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from tools.android_network_runtime.run import (
    PACKAGE, PHASES, REQUIRED, Radios, Runner, RuntimeFailure,
    parse_checkpoint, parse_radio, require_owned_avd, validate_result,
)


RUN_ID = "network_123_1"
AVD = "meowwatch_network_123_1"


class FakeAdb:
    serial = "emulator-5554"

    def __init__(self):
        self.name = AVD
        self.qemu = b"1"
        self.sdk = b"35"
        self.radios = {"wifi": True, "data": False}
        self.calls = []
        self.fail_once = None
        self.pid = b""
        self.installed = True

    def run(self, *args, **kwargs):
        self.calls.append(args)
        if args == ("emu", "avd", "name"):
            value = f"{self.name}\nOK\n".encode()
        elif args == ("shell", "getprop", "ro.kernel.qemu"):
            value = self.qemu
        elif args == ("shell", "getprop", "ro.build.version.sdk"):
            value = self.sdk
        elif args[:4] == ("shell", "settings", "get", "global"):
            value = b"1" if self.radios["wifi" if args[4] == "wifi_on" else "data"] else b"0"
        elif args[:2] == ("shell", "svc"):
            if self.fail_once == args[2:]:
                self.fail_once = None
                raise RuntimeFailure("native svc failure")
            self.radios[args[2]] = args[3] == "enable"
            value = b""
        elif args == ("shell", "pidof", PACKAGE):
            value = self.pid
        elif args == ("shell", "pm", "list", "packages", "--user", "0", PACKAGE):
            value = f"package:{PACKAGE}\n".encode() if self.installed else b""
        else:
            value = b""
        return subprocess.CompletedProcess(args, 0, value, b"")

    def prepare_storage(self):
        pass

    def cleanup(self):
        pass

    def screenshot(self):
        return b"original native PNG"

    def observe(self):
        raise AssertionError("the playing gate must not use idle-waiting UIAutomator")


class FakeObserver:
    def __init__(self):
        self.installation = {"waitForIdle": False}
        self.observations = []
        self.owns_package = False

    def install(self):
        self.owns_package = True
        return self.installation

    def observe(self):
        self.observations.append({"status": "success", "applicationPid": 456})
        return "<hierarchy />", "owned application window"

    def cleanup(self):
        self.owns_package = False


class OwnershipTests(unittest.TestCase):
    def test_only_exact_dedicated_api35_avd_is_admitted(self):
        require_owned_avd(FakeAdb(), AVD)
        for field, value in (("name", "personal"), ("sdk", b"34"),
                             ("qemu", b"0"), ("serial", "R58physical")):
            with self.subTest(field=field):
                adb = FakeAdb()
                setattr(adb, field, value)
                with self.assertRaises(RuntimeFailure):
                    require_owned_avd(adb, AVD)
                self.assertFalse(any(call[:2] == ("shell", "svc") for call in adb.calls))

    def test_generic_or_shell_sensitive_avd_names_are_rejected(self):
        for name in ("test", "pixel_6", "meowwatch_network_x; echo unsafe", "../network"):
            with self.subTest(name=name), self.assertRaises(RuntimeFailure):
                require_owned_avd(FakeAdb(), name)

    def test_unknown_original_radio_value_cannot_be_guessed(self):
        for value in (b"null", b"", b"2", b"enabled", b"0\n1"):
            with self.subTest(value=value), self.assertRaises(RuntimeFailure):
                parse_radio(value)
        self.assertFalse(parse_radio(b"0\n"))
        self.assertTrue(parse_radio(b"1\n"))

    def test_originally_disabled_mobile_data_remains_disabled(self):
        adb, evidence = FakeAdb(), []
        radios = Radios(adb, AVD, evidence.append)
        radios.capture_initial()
        radios.disable()
        self.assertEqual(adb.radios, {"wifi": False, "data": False})
        radios.restore()
        self.assertEqual(adb.radios, {"wifi": True, "data": False})
        self.assertNotIn(("shell", "svc", "data", "enable"), adb.calls)
        self.assertEqual(evidence[-1]["operation"], "restore")

    def test_partial_disable_failure_still_restores_original_state(self):
        adb, evidence = FakeAdb(), []
        radios = Radios(adb, AVD, evidence.append)
        radios.capture_initial()
        adb.fail_once = ("data", "disable")
        with self.assertRaisesRegex(RuntimeFailure, "disable failed"):
            radios.disable()
        self.assertTrue(radios.changed)
        self.assertFalse(adb.radios["wifi"])
        radios.restore()
        self.assertEqual(adb.radios, {"wifi": True, "data": False})
        self.assertTrue(evidence[-2]["commandErrors"])

    def test_no_mutation_without_captured_state(self):
        adb = FakeAdb()
        with self.assertRaises(RuntimeFailure):
            Radios(adb, AVD, lambda _: None).disable()
        self.assertEqual(adb.calls, [])

    def test_restore_revalidates_target_before_any_radio_mutation(self):
        adb = FakeAdb()
        radios = Radios(adb, AVD, lambda _: None)
        radios.capture_initial()
        radios.disable()
        adb.name = "somebody_elses_avd"
        before = len(adb.calls)
        with self.assertRaises(RuntimeFailure):
            radios.restore()
        self.assertFalse(any(call[:2] == ("shell", "svc") for call in adb.calls[before:]))


def result():
    return {"runId": RUN_ID, "passed": True, "verified": sorted(REQUIRED),
            "teardownErrors": [], "observations": [
                {"phase": "probe-healthy", "address": "sync.example", "port": 8997,
                 "resolvedAddress": "192.0.2.1", "reachable": True},
                {"phase": "probe-offline", "address": "192.0.2.1", "port": 8997, "reachable": False},
                {"phase": "probe-restored", "address": "192.0.2.1", "port": 8997, "reachable": True}]}


class EvidenceTests(unittest.TestCase):
    def test_checkpoint_requires_run_id_pid_and_known_phase(self):
        self.assertIsNone(parse_checkpoint("unrelated native output", RUN_ID))
        marker = {"runId": RUN_ID, "phase": "initial-ready", "pid": 456}
        self.assertEqual(parse_checkpoint("I/flutter: NETWORK_CHECKPOINT " + json.dumps(marker), RUN_ID), marker)
        for change in ({"runId": "other"}, {"pid": "456"}, {"pid": True}, {"phase": "passed"}):
            with self.subTest(change=change), self.assertRaises(RuntimeFailure):
                parse_checkpoint("NETWORK_CHECKPOINT " + json.dumps({**marker, **change}), RUN_ID)

    def test_checkpoints_or_elapsed_time_alone_cannot_pass(self):
        for invalid in ({"passed": True, "elapsed": 60},
                        {"runId": RUN_ID, "passed": True, "verified": sorted(REQUIRED),
                         "teardownErrors": [], "observations": []}):
            with self.assertRaises(RuntimeFailure):
                validate_result(invalid, RUN_ID)

    def test_real_same_endpoint_probe_sequence_is_required(self):
        validate_result(result(), RUN_ID)
        for phase, changes in ((1, {"reachable": True}), (2, {"reachable": False}),
                               (1, {"address": "192.0.2.2"}), (2, {"port": 80})):
            value = result()
            value["observations"][phase].update(changes)
            with self.subTest(changes=changes), self.assertRaises(RuntimeFailure):
                validate_result(value, RUN_ID)

    def test_incomplete_app_teardown_or_controls_fail(self):
        for changes in ({"teardownErrors": ["decoder close failed"]},
                        {"verified": sorted(REQUIRED)[:-1]}, {"passed": False}):
            value = result()
            value.update(changes)
            with self.subTest(changes=changes), self.assertRaises(RuntimeFailure):
                validate_result(value, RUN_ID)

    def make_runner(self, root):
        apk = root / "test.apk"
        apk.write_bytes(b"test fixture")
        runner = Runner("emulator-5554", AVD, apk, RUN_ID, root / "evidence")
        runner.adb = FakeAdb()
        runner.radios.adb = runner.adb
        runner.observer = FakeObserver()
        return runner

    def test_playing_capture_uses_fresh_native_observer_without_idle_wait(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            runner.output.mkdir()
            runner.capture("initial-ready")
            self.assertEqual(len(runner.observer.observations), 1)
            self.assertTrue((runner.output / "observations/initial-ready/ui.xml").is_file())
            self.assertFalse(any(call[:3] == ("shell", "input", "tap") for call in runner.adb.calls))

    def test_network_only_capture_does_not_require_unmounted_app_hierarchy(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            runner.output.mkdir()
            with patch.object(runner.observer, "observe", side_effect=AssertionError("no app hierarchy")):
                runner.capture("initial-network")
                runner.capture("finally-restored")
            for phase in ("initial-network", "finally-restored"):
                self.assertTrue((runner.output / f"observations/{phase}/screen.png").is_file())
                self.assertFalse((runner.output / f"observations/{phase}/ui.xml").exists())

    def test_native_observer_cleanup_failure_fails_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            with patch.object(runner, "capture"), \
                    patch.object(runner, "start_processes", side_effect=RuntimeFailure("test failed")), \
                    patch.object(runner.observer, "cleanup", side_effect=RuntimeFailure("helper remains")), \
                    patch("tools.android_network_runtime.run.ARTIFACT_ROOT", Path(directory) / "storage"):
                self.assertFalse(runner.run())
            gate = json.loads((runner.output / "gate.json").read_text())
            self.assertIn("remove-owned-native-ui-observer: helper remains", gate["errors"])

    def test_driver_failure_restores_radios_and_preserves_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            def fail_after_cut():
                runner.radios.disable()
                raise RuntimeFailure("driver failed while offline")
            with patch.object(runner, "capture"), patch.object(runner, "start_processes", fail_after_cut), \
                    patch("tools.android_network_runtime.run.ARTIFACT_ROOT", Path(directory) / "storage"):
                self.assertFalse(runner.run())
            self.assertEqual(runner.adb.radios, {"wifi": True, "data": False})
            gate = json.loads((runner.output / "gate.json").read_text())
            self.assertFalse(gate["passed"])
            self.assertIn("RuntimeFailure: driver failed while offline", gate["errors"])
            restored = [event for event in runner.events if event.get("operation") == "restore"]
            self.assertEqual(len(restored), 1)

    def test_finally_restore_failure_is_recorded_and_fails_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            with patch.object(runner, "capture"), \
                    patch.object(runner, "start_processes", side_effect=RuntimeFailure("test failed")), \
                    patch.object(runner.radios, "restore", side_effect=RuntimeFailure("restore rejected")), \
                    patch("tools.android_network_runtime.run.ARTIFACT_ROOT", Path(directory) / "storage"):
                self.assertFalse(runner.run())
            gate = json.loads((runner.output / "gate.json").read_text())
            self.assertIn("restore-original-radios: restore rejected", gate["errors"])
            event = next(event for event in runner.events if event.get("name") == "restore-original-radios")
            self.assertFalse(event["passed"])

    def test_duplicate_and_wrong_process_checkpoints_cannot_advance(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            runner.output.mkdir()
            runner.adb.pid = b"456"
            marker = {"runId": RUN_ID, "phase": PHASES[0], "pid": 456}
            with patch.object(runner, "capture"), patch.object(runner, "ack"):
                runner.observe_checkpoint(marker)
            with self.assertRaises(RuntimeFailure):
                runner.observe_checkpoint(marker)
            self.assertEqual(runner.phase_index, 1)
            with self.assertRaises(RuntimeFailure):
                runner.observe_checkpoint({**marker, "phase": PHASES[1], "pid": 789})
            self.assertEqual(runner.phase_index, 1)

    def test_cleanup_does_not_stop_replacement_app_process(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            runner.android_pid = 456
            runner.adb.pid = b"789"
            with self.assertRaises(RuntimeFailure):
                runner.stop_test_app()
            self.assertNotIn(("shell", "am", "force-stop", PACKAGE), runner.adb.calls)

    def test_early_failed_teardown_preserves_first_failure_without_crediting_phases(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            runner.output.mkdir()
            runner.adb.pid = b"456"
            runner.android_pid = 456
            runner.phase_index = 2
            marker = {"runId": RUN_ID, "phase": "teardown-complete", "pid": 456,
                      "passed": False, "failure": {"stage": "initial-playback",
                      "message": "Both native decoders did not advance in initial"}}
            with self.assertRaisesRegex(RuntimeFailure, "integration failed during initial-playback"):
                runner.observe_checkpoint(marker)
            self.assertEqual(runner.phase_index, 2)
            self.assertEqual(runner.events[-1]["failure"], marker["failure"])
            self.assertFalse(any(call[:2] == ("shell", "svc") for call in runner.adb.calls))

    def test_early_successful_teardown_and_wrong_pid_failure_cannot_bypass_protocol(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            runner.output.mkdir()
            runner.adb.pid = b"456"
            runner.android_pid = 456
            runner.phase_index = 2
            for changes in ({"passed": True, "pid": 456}, {"passed": False, "pid": 789}):
                with self.subTest(changes=changes), self.assertRaises(RuntimeFailure):
                    runner.observe_checkpoint({"runId": RUN_ID, "phase": "teardown-complete", **changes})
                self.assertEqual(runner.phase_index, 2)
                self.assertEqual(runner.events, [])

    def test_failed_teardown_without_new_diagnostics_still_names_last_completed_phase(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            runner.output.mkdir()
            runner.adb.pid = b"456"
            runner.phase_index = 2
            with self.assertRaisesRegex(RuntimeFailure, "failed after players-ready"):
                runner.observe_checkpoint({"runId": RUN_ID, "phase": "teardown-complete",
                                           "pid": 456, "passed": False})
            self.assertEqual(runner.phase_index, 2)

    def test_uninstalled_integration_app_has_no_remaining_ack_sandbox(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            runner.output.mkdir()
            runner.adb.installed = False
            path = f"files/network-{RUN_ID}-recording-ready"
            runner.remove_ack(path)
            self.assertFalse(any(call[:2] == ("shell", "run-as") for call in runner.adb.calls))
            self.assertEqual(runner.events[-1]["status"], "app-already-uninstalled")
            self.assertEqual(runner.events[-1]["path"], path)

    def test_installed_app_ack_is_removed_and_query_or_removal_errors_are_not_hidden(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            path = f"files/network-{RUN_ID}-recording-ready"
            runner.remove_ack(path)
            self.assertIn(("shell", "run-as", PACKAGE, "rm", "-f", path), runner.adb.calls)
            run = runner.adb.run
            for failing in (("shell", "pm"), ("shell", "run-as")):
                def fail(*args, **kwargs):
                    if args[:2] == failing:
                        raise RuntimeFailure("native cleanup command failed")
                    return run(*args, **kwargs)
                with self.subTest(failing=failing), patch.object(runner.adb, "run", side_effect=fail):
                    with self.assertRaisesRegex(RuntimeFailure, "native cleanup command failed"):
                        runner.remove_ack(path)


if __name__ == "__main__":
    unittest.main()
