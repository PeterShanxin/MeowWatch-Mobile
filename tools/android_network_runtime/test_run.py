from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch

from tools.android_network_runtime.run import (
    PACKAGE, PHASES, REQUIRED, Radios, Runner, RuntimeFailure,
    app_has_unobscured_focus, default_wifi_network, native_position_diagnostics,
    parse_checkpoint, parse_radio,
    require_owned_avd, validate_result,
)


RUN_ID = "network_123_1"
AVD = "meowwatch_network_123_1"
APP_WINDOW = (f"mCurrentFocus=Window{{abc u0 {PACKAGE}/.MainActivity}}\n"
              f"mFocusedApp=ActivityRecord{{def u0 {PACKAGE}/.MainActivity t1}}\n")
APP_XML = f'<hierarchy><node package="{PACKAGE}" /></hierarchy>'
SETUP_PACKAGE = "com.google.android.googlesdksetup"
ANR_WINDOW = (f"mCurrentFocus=Window{{6574fa u0 Application Not Responding: {SETUP_PACKAGE}}}\n"
              f"mFocusedApp=ActivityRecord{{def u0 {PACKAGE}/.MainActivity t1}}\n"
              f"Window{{6574fa u0 Application Not Responding: {SETUP_PACKAGE}}}\n")
ANR_XML = (
    '<hierarchy>'
    f'<node package="android" visible-to-user="true" enabled="true"'
    f' resource-id="android:id/alertTitle" class="android.widget.TextView"'
    f' text="{SETUP_PACKAGE} isn\'t responding" />'
    '<node package="android" visible-to-user="true" enabled="true"'
    ' resource-id="android:id/aerr_close" class="android.widget.Button"'
    ' clickable="true" text="Close app" bounds="[100,200][300,300]" />'
    '</hierarchy>'
)


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
        self.connectivity_responses = []
        self.radios_at_connectivity = []
        self.connectivity_timeouts = []
        self.window_responses = []

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
        elif args == ("shell", "dumpsys", "connectivity"):
            self.radios_at_connectivity.append(self.radios.copy())
            self.connectivity_timeouts.append(kwargs.get("timeout"))
            value = self.connectivity_responses.pop(0) if self.connectivity_responses else b""
        elif args == ("shell", "dumpsys", "window", "displays"):
            value = self.window_responses.pop(0) if self.window_responses else APP_WINDOW.encode()
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

    def screenshot(self, *, timeout=25):
        return (b"\x89PNG\r\n\x1a\n" + b"\0" * 4 + b"IHDR"
                + (1080).to_bytes(4, "big") + (2400).to_bytes(4, "big"))

    def observe(self):
        raise AssertionError("the playing gate must not use idle-waiting UIAutomator")


class FakeObserver:
    def __init__(self):
        self.installation = {"waitForIdle": False}
        self.observations = []
        self.owns_package = False
        self.responses = []

    def install(self):
        self.owns_package = True
        return self.installation

    def observe(self, *, deadline=None):
        self.observations.append({"status": "success", "applicationPid": 456})
        return self.responses.pop(0) if self.responses else (APP_XML, APP_WINDOW)

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
        disabled = next(item for item in evidence if item["operation"] == "disable")
        self.assertTrue(disabled["commandErrors"])

    def test_zero_exit_framework_error_is_retained_as_command_evidence(self):
        adb, evidence = FakeAdb(), []
        original = adb.run

        def report_warning(*args, **kwargs):
            result = original(*args, **kwargs)
            if args[:3] == ("shell", "svc", "data"):
                result.stderr = b"Mobile data operation failed: framework error"
            return result

        adb.run = report_warning
        radios = Radios(adb, AVD, evidence.append)
        radios.capture_initial()
        radios.disable()
        command = next(item for item in evidence
                       if item["operation"] == "radio-command" and item["radio"] == "data")
        self.assertEqual(command["exitCode"], 0)
        self.assertIn("framework error", command["stderr"])
        self.assertEqual(evidence[-1]["actual"], {"wifi": False, "data": False})

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


def connectivity(default: int, *agents: tuple[int, str, str]) -> bytes:
    lines = [f"Active default network: {default}", "Current Networks:"]
    for network_id, transport, state in agents:
        lines.append(
            f"  NetworkAgentInfo{{network{{{network_id}}}  handle{{123}}  "
            f"ni{{{transport} {state} extra: }} created=now "
            f"nc{{[ Transports: {transport} Capabilities: INTERNET&VALIDATED]}}"
        )
    return "\n".join([*lines, "Status for known UIDs:", ""]).encode()


class StablePrimaryRecoveryTests(unittest.TestCase):
    def test_default_wifi_must_match_one_current_connected_agent(self):
        cellular = connectivity(102, (102, "MOBILE[HSPA]", "CONNECTED"),
                                (103, "WIFI", "CONNECTED"))
        self.assertIn("not connected Wi-Fi", default_wifi_network(cellular.decode())[1])
        self.assertEqual(default_wifi_network(connectivity(
            103, (102, "MOBILE[HSPA]", "CONNECTED"),
            (103, "WIFI", "CONNECTED")).decode())[0], 103)
        for text in (
            connectivity(103, (102, "MOBILE[HSPA]", "CONNECTED")),
            connectivity(103, (103, "WIFI", "CONNECTING")),
            connectivity(103, (103, "WIFI|CELLULAR", "CONNECTED")),
            connectivity(103, (103, "WIFI", "CONNECTED"), (103, "WIFI", "CONNECTED")),
            connectivity(103, (103, "WIFI", "CONNECTED"))
            + b"Active default network: 103\n",
        ):
            with self.subTest(text=text[:80]):
                self.assertIsNone(default_wifi_network(text.decode())[0])

    def test_cellular_default_then_two_fresh_wifi_observations_restore_data_last(self):
        adb, evidence = FakeAdb(), []
        adb.radios["data"] = True
        adb.connectivity_responses = [
            connectivity(102, (102, "MOBILE[HSPA]", "CONNECTED")),
            connectivity(103, (103, "WIFI", "CONNECTED")),
            connectivity(103, (103, "WIFI", "CONNECTED")),
        ]
        radios = Radios(adb, AVD, evidence.append)
        radios.capture_initial()
        radios.disable()
        with patch("tools.android_network_runtime.run.WIFI_READY_POLL_INTERVAL", 0):
            radios.restore(stable_primary=True)
        self.assertEqual(adb.radios, {"wifi": True, "data": True})
        self.assertEqual(adb.radios_at_connectivity,
                         [{"wifi": True, "data": False}] * 3)
        self.assertTrue(all(0 < timeout <= 5 for timeout in adb.connectivity_timeouts))
        self.assertEqual([item["networkId"] for item in evidence
                          if item["operation"] == "wifi-default-observation"],
                         [None, 103, 103])
        self.assertTrue(all(len(item["stdoutSha256"]) == 64 for item in evidence
                            if item["operation"] == "wifi-default-observation"))
        self.assertLess(adb.calls.index(("shell", "dumpsys", "connectivity")),
                        adb.calls.index(("shell", "svc", "data", "enable")))
        self.assertEqual(evidence[-1]["operation"], "restore")

    def test_single_original_radio_uses_existing_restore_path(self):
        adb, evidence = FakeAdb(), []
        radios = Radios(adb, AVD, evidence.append)
        radios.capture_initial()
        radios.disable()
        radios.restore(stable_primary=True)
        self.assertEqual(adb.radios, {"wifi": True, "data": False})
        self.assertEqual(adb.radios_at_connectivity, [])
        self.assertEqual([item["operation"] for item in evidence if
                          item["operation"].startswith("restore")], ["restore"])

    def test_ambiguous_wifi_observation_breaks_consecutive_streak(self):
        adb, evidence = FakeAdb(), []
        adb.radios["data"] = True
        ready = connectivity(103, (103, "WIFI", "CONNECTED"))
        adb.connectivity_responses = [ready, ready + b"Active default network: 103\n",
                                      ready, ready]
        radios = Radios(adb, AVD, evidence.append)
        radios.capture_initial()
        radios.disable()
        with patch("tools.android_network_runtime.run.WIFI_READY_POLL_INTERVAL", 0):
            radios.restore(stable_primary=True)
        self.assertEqual(len(adb.radios_at_connectivity), 4)
        self.assertEqual(adb.radios, {"wifi": True, "data": True})

    def test_wifi_timeout_and_failure_still_restore_original_exact_state(self):
        for failure in ("timeout", "dumpsys failure"):
            with self.subTest(failure=failure):
                adb, evidence = FakeAdb(), []
                adb.radios["data"] = True
                radios = Radios(adb, AVD, evidence.append)
                radios.capture_initial()
                radios.disable()
                if failure == "timeout":
                    with patch("tools.android_network_runtime.run.WIFI_READY_TIMEOUT", 0), \
                            self.assertRaisesRegex(RuntimeFailure, "stable default Wi-Fi"):
                        radios.restore(stable_primary=True)
                else:
                    with patch.object(radios, "_wait_for_default_wifi",
                                      side_effect=RuntimeFailure("dumpsys failed")), \
                            self.assertRaisesRegex(RuntimeFailure, "dumpsys failed"):
                        radios.restore(stable_primary=True)
                self.assertEqual(adb.radios, {"wifi": True, "data": True})
                self.assertEqual([item["operation"] for item in evidence[-2:]],
                                 ["restore", "wifi-default-ready"])
                self.assertTrue(any(item["operation"] == "wifi-default-ready"
                                    and item.get("passed") is False for item in evidence))

    def test_expired_poll_budget_never_issues_adb_with_negative_timeout(self):
        adb, evidence = FakeAdb(), []
        radios = Radios(adb, AVD, evidence.append)
        with patch("tools.android_network_runtime.run.WIFI_READY_TIMEOUT", 0.5), \
                patch("tools.android_network_runtime.run.time.monotonic",
                      side_effect=[0.0, 0.0, 1.0]), \
                self.assertRaisesRegex(RuntimeFailure, "stable default Wi-Fi"):
            radios._wait_for_default_wifi()
        self.assertNotIn(("shell", "dumpsys", "connectivity"), adb.calls)

    def test_wifi_readiness_and_final_restore_errors_are_both_reported(self):
        adb, evidence = FakeAdb(), []
        adb.radios["data"] = True
        radios = Radios(adb, AVD, evidence.append)
        radios.capture_initial()
        radios.disable()
        original_run = adb.run

        def fail_after_data_enable(*args, **kwargs):
            result = original_run(*args, **kwargs)
            if args == ("shell", "svc", "data", "enable"):
                raise RuntimeFailure("data enable reported failure")
            return result

        with patch.object(adb, "run", side_effect=fail_after_data_enable), \
                patch.object(radios, "_wait_for_default_wifi",
                             side_effect=RuntimeFailure("Wi-Fi never became default")), \
                self.assertRaisesRegex(RuntimeFailure,
                                       "Wi-Fi recovery failed:.*Wi-Fi never became default; "
                                       "original radio restore failed"):
            radios.restore(stable_primary=True)
        self.assertEqual(adb.radios, {"wifi": True, "data": True})
        self.assertTrue(any("data: data enable reported failure" in error
                            for item in evidence if item["operation"] == "restore"
                            for error in item["commandErrors"]))


def result():
    return {"runId": RUN_ID, "passed": True, "buildMode": "debug", "variant": "normal",
            "verified": sorted(REQUIRED),
            "billingSetup": {"status": "success", "errorCode": None, "configured": True, "isPlus": False},
            "teardownErrors": [], "observations": [
                {"phase": "probe-healthy", "address": "sync.example", "port": 8997,
                 "resolvedAddress": "192.0.2.1", "reachable": True},
                {"phase": "probe-offline", "address": "192.0.2.1", "port": 8997, "reachable": False},
                {"phase": "probe-restored", "address": "192.0.2.1", "port": 8997, "reachable": True}]}


def position_record(**changes):
    return {"runId": RUN_ID, "pid": 456, "phase": "initial", "readStage": "baseline",
            "readIndex": 1, "role": "host", "controllerId": 7,
            "startedAtUtc": "2026-09-18T00:00:00.000Z", "timeoutMs": 5000,
            "event": "start", "status": "pending", **changes}


class NativePositionDiagnosticTests(unittest.TestCase):
    def summarize(self, root, records, app_pid=456):
        path = root / "logcat.txt"
        text = "unrelated native output\n" + "".join(
            "I/flutter: NETWORK_NATIVE_POSITION " + json.dumps(record) + "\n" for record in records)
        path.write_text(text, encoding="utf-8")
        evidence = native_position_diagnostics(path, RUN_ID, app_pid)
        self.assertEqual(path.read_text(encoding="utf-8"), text)
        return evidence

    def test_first_baseline_timeout_is_retained_without_result_or_later_reads(self):
        start = position_record()
        end = position_record(event="end", status="timeout", elapsedMs=5013,
                              endedAtUtc="2026-09-18T00:00:05.013Z",
                              error="TimeoutException after 0:00:05.000000: Future not completed")
        with tempfile.TemporaryDirectory() as directory:
            evidence = self.summarize(Path(directory), [start, end])
        self.assertEqual(evidence["acceptedRecords"], 2)
        self.assertEqual(evidence["rejectedRecords"], 0)
        self.assertEqual(evidence["records"][-1], {"logcatLine": 3, **end})
        self.assertEqual(evidence["pendingReadsInRetainedTail"], [])
        self.assertEqual(evidence["unpairedEndsInRetainedTail"], [])

    def test_interrupted_start_is_pending_not_inferred_as_a_timeout(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence = self.summarize(Path(directory), [position_record()])
        self.assertEqual(len(evidence["pendingReadsInRetainedTail"]), 1)
        pending = evidence["pendingReadsInRetainedTail"][0]
        self.assertEqual(pending["status"], "pending")
        self.assertNotIn("elapsedMs", pending)
        self.assertNotIn("positionMs", pending)

    def test_foreign_or_unbounded_records_cannot_complete_an_owned_start(self):
        end = position_record(event="end", status="success", elapsedMs=4, positionMs=123,
                              endedAtUtc="2026-09-18T00:00:00.004Z")
        changes = ({"runId": "other"}, {"pid": 789}, {"pid": True},
                   {"phase": "unknown"}, {"phase": []}, {"role": "unknown"},
                   {"readStage": "paused"}, {"controllerId": "7"}, {"controllerId": 2**63},
                   {"readIndex": 1000001}, {"timeoutMs": 6000}, {"error": "x" * 401},
                   {"logcatLine": 1}, {"startedAtUtc": "x" * 41})
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            evidence = self.summarize(path, [position_record(), *({**end, **item} for item in changes)])
        self.assertEqual(evidence["acceptedRecords"], 1)
        self.assertEqual(evidence["rejectedRecords"], len(changes))
        self.assertEqual(len(evidence["pendingReadsInRetainedTail"]), 1)

    def test_different_role_or_controller_end_does_not_pair_with_start(self):
        for changes in ({"role": "guest"}, {"controllerId": 8}):
            end = position_record(event="end", status="success", elapsedMs=4, positionMs=123,
                                  endedAtUtc="2026-09-18T00:00:00.004Z", **changes)
            with self.subTest(changes=changes), tempfile.TemporaryDirectory() as directory:
                evidence = self.summarize(Path(directory), [position_record(), end])
            self.assertEqual(len(evidence["pendingReadsInRetainedTail"]), 1)
            self.assertEqual(len(evidence["unpairedEndsInRetainedTail"]), 1)

    def test_retention_limit_is_explicit_and_does_not_invent_missing_starts(self):
        records = []
        for index in range(1, 4):
            records.extend([position_record(readIndex=index), position_record(
                readIndex=index, event="end", status="success", elapsedMs=4, positionMs=index,
                endedAtUtc="2026-09-18T00:00:00.004Z")])
        with tempfile.TemporaryDirectory() as directory, \
                patch("tools.android_network_runtime.run.POSITION_RECORD_LIMIT", 3):
            evidence = self.summarize(Path(directory), records)
        self.assertEqual(evidence["acceptedRecords"], 6)
        self.assertEqual(evidence["droppedRecords"], 3)
        self.assertEqual(len(evidence["records"]), 3)
        self.assertEqual(evidence["pendingReadsInRetainedTail"], [])
        self.assertEqual(evidence["unpairedEndsInRetainedTail"][0]["readIndex"], 2)

    def test_malformed_records_are_diagnostic_metadata_and_do_not_hide_valid_tail(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "logcat.txt"
            path.write_text("NETWORK_NATIVE_POSITION {broken\n" * 22
                            + "NETWORK_NATIVE_POSITION " + json.dumps(position_record()) + "\n",
                            encoding="utf-8")
            evidence = native_position_diagnostics(path, RUN_ID, 456)
        self.assertEqual(evidence["rejectedRecords"], 22)
        self.assertEqual(len(evidence["rejectionSamples"]), 20)
        self.assertEqual(evidence["acceptedRecords"], 1)

    def test_missing_log_or_unverified_pid_is_not_reported_as_zero_native_reads(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            self.assertEqual(native_position_diagnostics(path / "missing", RUN_ID, 456)["status"], "unavailable")
            evidence = self.summarize(path, [position_record()], app_pid=None)
        self.assertEqual(evidence["status"], "unavailable")
        self.assertEqual(evidence["records"], [])


class EvidenceTests(unittest.TestCase):
    def test_decoder_failure_variant_requires_original_error_and_rebuild_receipts(self):
        value = result()
        value["variant"] = "decoder_failure"
        value["verified"].append("original_native_guest_decoder_failed_during_radio_outage")
        value["observations"].extend([
            {"phase": "offline-decoder-failure", "controlledCacheMiss": True, "seekMs": 85000,
             "nativeError": "source error"},
            {"phase": "decoder-continuity", "role": "host", "validated": True,
             "rebuiltFailedDecoder": False},
            {"phase": "decoder-continuity", "role": "guest", "validated": True,
             "rebuiltFailedDecoder": True},
        ])
        validate_result(value, RUN_ID, variant="decoder_failure")
        with self.assertRaisesRegex(RuntimeFailure, "variant"):
            validate_result(value, RUN_ID)
        for item in (value["observations"][-3], value["observations"][-1]):
            changed = json.loads(json.dumps(value))
            changed_item = changed["observations"][value["observations"].index(item)]
            changed_item.pop("nativeError" if item is value["observations"][-3]
                             else "rebuiltFailedDecoder")
            with self.assertRaisesRegex(RuntimeFailure, "original guest native failure"):
                validate_result(changed, RUN_ID, variant="decoder_failure")

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

    def test_profile_must_be_proven_by_actual_dart_runtime(self):
        value = result()
        with self.assertRaisesRegex(RuntimeFailure, "actual Dart build mode"):
            validate_result(value, RUN_ID, "profile")
        value["buildMode"] = "profile"
        with self.assertRaisesRegex(RuntimeFailure, "real free billing setup"):
            validate_result(value, RUN_ID, "profile")
        value["billingSetup"] = {"status": "unavailable", "errorCode": "missing_public_sdk_key",
                                 "configured": False, "isPlus": False}
        validate_result(value, RUN_ID, "profile")
        with self.assertRaisesRegex(RuntimeFailure, "actual Dart build mode"):
            validate_result(value, RUN_ID, "debug")
        del value["buildMode"]
        with self.assertRaisesRegex(RuntimeFailure, "actual Dart build mode"):
            validate_result(value, RUN_ID, "profile")

    def test_billing_failure_or_paid_customer_cannot_pass_free_network_gate(self):
        for billing in (None, {"status": "success"},
                        {"status": "failure", "errorCode": "network", "configured": True, "isPlus": False},
                        {"status": "success", "errorCode": None, "configured": True, "isPlus": True}):
            value = result()
            value["billingSetup"] = billing
            with self.subTest(billing=billing), self.assertRaisesRegex(RuntimeFailure, "real free billing setup"):
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

    def test_failed_decoder_releases_owned_fixture_before_radio_restore(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            runner.variant = "decoder_failure"
            runner.output.mkdir()
            runner.adb.pid = b"456"
            runner.android_pid = 456
            runner.phase_index = runner.phases.index("offline-confirmed")
            runner.offline_proof_at = 100.0
            runner.adb.radios = {"wifi": False, "data": False}
            order = []
            proof = {"maxBodyOffset": 900, "bodyBytesPerSecond": 160 * 1024}
            marker = {"runId": RUN_ID, "phase": "offline-confirmed", "pid": 456}
            with patch.object(runner, "capture"), \
                    patch.object(runner, "finish_recording"), \
                    patch.object(runner, "start_recording"), \
                    patch.object(runner, "ack"), \
                    patch("tools.android_network_runtime.run.Path.read_text",
                          return_value=json.dumps(proof)), \
                    patch("tools.android_network_runtime.run.validate_spans",
                          return_value={"highestServedOffset": 899,
                                        "postProofCapWaitCount": 0}) as spans, \
                    patch("tools.android_network_runtime.run.release_owned_server",
                          side_effect=lambda *_: order.append("release") or {"event": "body_cap_released"}), \
                    patch.object(runner.radios, "restore",
                                 side_effect=lambda **_: order.append("restore")):
                runner.observe_checkpoint(marker)
            self.assertEqual(order, ["release", "restore"])
            spans.assert_called_once_with(
                Path("build/android-network-fixture-server/http-server.log"), proof, 100.0)
            self.assertEqual(runner.fixture_release_receipt["event"], "body_cap_released")

    def test_failed_cap_release_cannot_ack_or_restore_in_checkpoint(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            runner.variant = "decoder_failure"
            runner.output.mkdir()
            runner.adb.pid = b"456"
            runner.android_pid = 456
            runner.phase_index = runner.phases.index("offline-confirmed")
            runner.offline_proof_at = 100.0
            runner.adb.radios = {"wifi": False, "data": False}
            marker = {"runId": RUN_ID, "phase": "offline-confirmed", "pid": 456}
            with patch.object(runner, "capture"), \
                    patch("tools.android_network_runtime.run.Path.read_text",
                          return_value='{}'), \
                    patch("tools.android_network_runtime.run.validate_spans",
                          return_value={"highestServedOffset": 899,
                                        "postProofCapWaitCount": 1}), \
                    patch("tools.android_network_runtime.run.release_owned_server",
                          side_effect=RuntimeFailure("release missing")), \
                    patch.object(runner.radios, "restore") as restore, \
                    patch.object(runner, "ack") as ack, \
                    self.assertRaisesRegex(RuntimeFailure, "release missing"):
                runner.observe_checkpoint(marker)
            restore.assert_not_called()
            ack.assert_not_called()

    def test_variant_offline_socket_checkpoint_precedes_seek_and_cap_release(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            runner.variant = "decoder_failure"
            runner.output.mkdir()
            runner.adb.pid = b"456"
            runner.android_pid = 456
            runner.phase_index = runner.phases.index("offline-unreachable")
            runner.adb.radios = {"wifi": False, "data": False}
            marker = {"runId": RUN_ID, "phase": "offline-unreachable", "pid": 456}
            proof = {"maxBodyOffset": 900, "bodyBytesPerSecond": 160 * 1024}
            with patch("tools.android_network_runtime.run.time.monotonic", return_value=100.0), \
                    patch("tools.android_network_runtime.run.Path.read_text",
                          return_value=json.dumps(proof)), \
                    patch("tools.android_network_runtime.run.validate_spans",
                          return_value={"postProofCapWaitCount": 0}) as spans, \
                    patch("tools.android_network_runtime.run.release_owned_server") as release, \
                    patch.object(runner, "ack") as ack:
                runner.observe_checkpoint(marker)
            spans.assert_called_once_with(
                Path("build/android-network-fixture-server/http-server.log"), proof, 100.0)
            self.assertEqual(runner.offline_proof_at, 100.0)
            ack.assert_called_once_with("offline-proof-accepted")
            release.assert_not_called()
            self.assertEqual(runner.phase_index, runner.phases.index("offline-confirmed"))

    def test_variant_offline_checkpoint_fails_closed_without_radios_or_valid_receipts(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            runner.variant = "decoder_failure"
            runner.output.mkdir()
            runner.adb.pid = b"789"
            runner.android_pid = 456
            runner.phase_index = runner.phases.index("offline-unreachable")
            marker = {"runId": RUN_ID, "phase": "offline-unreachable", "pid": 456}
            with patch.object(runner, "ack") as ack, \
                    self.assertRaisesRegex(RuntimeFailure, "current MainApp process"):
                runner.observe_checkpoint(marker)
            ack.assert_not_called()
            runner.adb.pid = b"456"
            with patch.object(runner, "ack") as ack, \
                    patch("tools.android_network_runtime.run.validate_spans") as spans, \
                    self.assertRaisesRegex(RuntimeFailure, "radios changed"):
                runner.observe_checkpoint(marker)
            ack.assert_not_called()
            spans.assert_not_called()
            runner.phase_index = runner.phases.index("offline-unreachable")
            runner.adb.radios = {"wifi": False, "data": False}
            with patch.object(runner, "ack") as ack, \
                    patch("tools.android_network_runtime.run.Path.read_text",
                          return_value='{}'), \
                    patch("tools.android_network_runtime.run.validate_spans",
                          side_effect=RuntimeFailure("pre-proof cap wait")), \
                    self.assertRaisesRegex(RuntimeFailure, "pre-proof cap wait"):
                runner.observe_checkpoint(marker)
            ack.assert_not_called()

    def test_normal_variant_rejects_extra_checkpoint(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            runner.output.mkdir()
            runner.adb.pid = b"456"
            runner.phase_index = PHASES.index("offline-confirmed")
            with self.assertRaisesRegex(RuntimeFailure, "out-of-order"):
                runner.observe_checkpoint({"runId": RUN_ID,
                                           "phase": "offline-unreachable", "pid": 456})

    def test_wifi_readiness_failure_restores_original_radios_without_ack(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            runner.output.mkdir()
            runner.adb.pid = b"456"
            runner.adb.radios["data"] = True
            runner.radios.capture_initial()
            runner.radios.disable()
            runner.android_pid = 456
            runner.phase_index = PHASES.index("offline-confirmed")
            marker = {"runId": RUN_ID, "phase": "offline-confirmed", "pid": 456}
            with patch.object(runner, "capture"), \
                    patch.object(runner, "finish_recording"), \
                    patch.object(runner, "start_recording"), \
                    patch.object(runner, "ack") as ack, \
                    patch.object(runner.radios, "_wait_for_default_wifi",
                                 side_effect=RuntimeFailure("Wi-Fi never became default")), \
                    self.assertRaisesRegex(RuntimeFailure, "Wi-Fi never became default"):
                runner.observe_checkpoint(marker)
            ack.assert_not_called()
            self.assertEqual(runner.adb.radios, {"wifi": True, "data": True})
            self.assertTrue(any(item["operation"] == "wifi-default-ready"
                                and item.get("passed") is False for item in runner.events))

    def test_playing_capture_uses_fresh_native_observer_without_idle_wait(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            runner.output.mkdir()
            runner.capture("initial-ready")
            self.assertEqual(len(runner.observer.observations), 1)
            self.assertTrue((runner.output / "observations/initial-ready/ui.xml").is_file())
            self.assertFalse(any(call[:3] == ("shell", "input", "tap") for call in runner.adb.calls))

    def test_system_anr_is_never_credited_as_main_app_capture(self):
        self.assertFalse(app_has_unobscured_focus(ANR_XML, ANR_WINDOW))
        self.assertTrue(app_has_unobscured_focus(APP_XML, APP_WINDOW))
        self.assertFalse(app_has_unobscured_focus(
            APP_XML, APP_WINDOW.replace(PACKAGE, "evil." + PACKAGE)))
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            runner.output.mkdir()
            runner.adb.window_responses = [ANR_WINDOW.encode()]
            runner.observer.responses = [(ANR_XML.replace(SETUP_PACKAGE, PACKAGE),
                                          ANR_WINDOW.replace(SETUP_PACKAGE, PACKAGE))]
            with self.assertRaisesRegex(RuntimeFailure, "foreign foreground window"):
                runner.capture("initial-ready")
            evidence = runner.output / "observations/initial-ready"
            self.assertTrue((evidence / "screen.png").is_file())
            self.assertIn("Application Not Responding", (evidence / "window.txt").read_text())
            self.assertFalse(any(call[:3] == ("shell", "input", "tap") for call in runner.adb.calls))

    def test_raw_foreign_window_cannot_inherit_observer_main_app_focus(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            runner.output.mkdir()
            runner.adb.window_responses = [APP_WINDOW.replace(PACKAGE, "com.other.app").encode()]
            with self.assertRaisesRegex(RuntimeFailure, "foreign foreground window"):
                runner.capture("initial-ready")
            evidence = runner.output / "observations/initial-ready"
            self.assertIn("com.other.app", (evidence / "window.txt").read_text())
            self.assertEqual((evidence / "ui.xml").read_text(), APP_XML)
            self.assertFalse(any(call[:3] == ("shell", "input", "tap") for call in runner.adb.calls))

    def test_exact_sdk_anr_recovery_retains_original_and_recaptures_main_app(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            runner.output.mkdir()
            runner.adb.window_responses = [ANR_WINDOW.encode(), APP_WINDOW.encode()]
            runner.observer.responses = [(ANR_XML, ANR_WINDOW), (ANR_XML, ANR_WINDOW),
                                         (APP_XML, APP_WINDOW)]
            runner.capture("initial-ready")
            evidence = runner.output / "observations/initial-ready"
            self.assertEqual((evidence / "sdk-anr-original-observer-window.txt").read_text(),
                             ANR_WINDOW)
            self.assertEqual((evidence / "sdk-anr-original-ui.xml").read_text(), ANR_XML)
            self.assertTrue((evidence / "sdk-anr-original-screen.png").is_file())
            self.assertTrue((evidence / "sdk-anr-confirmed-screen.png").is_file())
            self.assertEqual((evidence / "window.txt").read_text(), APP_WINDOW)
            self.assertEqual((evidence / "ui.xml").read_text(), APP_XML)
            self.assertEqual(runner.sdk_setup_recovery_attempts, 1)
            self.assertEqual([call for call in runner.adb.calls
                              if call[:3] == ("shell", "input", "tap")],
                             [("shell", "input", "tap", "200", "250")])

    def test_changed_sdk_anr_window_refuses_close_tap(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            runner.output.mkdir()
            runner.adb.window_responses = [ANR_WINDOW.encode()]
            runner.observer.responses = [(ANR_XML, ANR_WINDOW),
                                         (ANR_XML, ANR_WINDOW.replace("6574fa", "999999"))]
            with self.assertRaisesRegex(RuntimeFailure, "window changed"):
                runner.capture("initial-ready")
            evidence = runner.output / "observations/initial-ready"
            self.assertTrue((evidence / "sdk-anr-original-screen.png").is_file())
            self.assertTrue((evidence / "sdk-anr-confirmed-window.txt").is_file())
            self.assertFalse(any(call[:3] == ("shell", "input", "tap") for call in runner.adb.calls))

    def test_new_ambiguous_dialog_refuses_close_tap(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            runner.output.mkdir()
            runner.adb.window_responses = [ANR_WINDOW.encode()]
            runner.observer.responses = [(ANR_XML, ANR_WINDOW),
                                         (ANR_XML, ANR_WINDOW + "\nAppErrorDialog\n")]
            with self.assertRaisesRegex(RuntimeFailure, "another system dialog appeared"):
                runner.capture("initial-ready")
            self.assertFalse(any(call[:3] == ("shell", "input", "tap") for call in runner.adb.calls))

    def test_sdk_anr_over_lookalike_package_refuses_close_tap(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            runner.output.mkdir()
            foreign_window = ANR_WINDOW.replace(PACKAGE, "evil." + PACKAGE)
            runner.adb.window_responses = [foreign_window.encode()]
            runner.observer.responses = [(ANR_XML, foreign_window)]
            with self.assertRaisesRegex(RuntimeFailure, "focus is ambiguous"):
                runner.capture("initial-ready")
            self.assertFalse(any(call[:3] == ("shell", "input", "tap") for call in runner.adb.calls))

    def test_failed_sdk_anr_close_consumes_single_attempt(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            runner.output.mkdir()
            runner.adb.window_responses = [ANR_WINDOW.encode(), ANR_WINDOW.encode()]
            runner.observer.responses = [(ANR_XML, ANR_WINDOW), (ANR_XML, ANR_WINDOW),
                                         (ANR_XML, ANR_WINDOW)]
            original_run = runner.adb.run
            tap_attempts = []

            def fail_tap(*args, **kwargs):
                if args[:3] == ("shell", "input", "tap"):
                    tap_attempts.append(args)
                    raise RuntimeFailure("tap outcome unknown")
                return original_run(*args, **kwargs)

            with patch.object(runner.adb, "run", side_effect=fail_tap), \
                    self.assertRaisesRegex(RuntimeFailure, "tap outcome unknown"):
                runner.capture("initial-ready")
            self.assertEqual(runner.sdk_setup_recovery_attempts, 1)
            with self.assertRaisesRegex(RuntimeFailure, "second SDK setup ANR"):
                runner.capture("offline-confirmed")
            self.assertEqual(tap_attempts, [("shell", "input", "tap", "200", "250")])

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

    def test_gate_reports_preflight_recovery_and_rejects_wrong_avd_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report = root / "sdk-setup-result.json"
            runner = self.make_runner(root)
            report.write_text(json.dumps({"status": "prepared", "devices": {
                "emulator-5554": {"status": "recovered-once", "before": {"verifiedAvd": AVD}}
            }}))
            with patch.dict(os.environ, {"NETWORK_SDK_SETUP_REPORT": str(report)}), \
                    patch.object(runner, "capture"), \
                    patch.object(runner, "start_processes", side_effect=RuntimeFailure("stop after preparation")), \
                    patch("tools.android_network_runtime.run.ARTIFACT_ROOT", root / "storage"):
                self.assertFalse(runner.run())
            gate = json.loads((runner.output / "gate.json").read_text())
            self.assertTrue(gate["sdkSetupRecoveryExercised"])
            self.assertTrue(gate["sdkSetupPreflightRecovered"])
            self.assertEqual(gate["sdkSetupInRunRecoveryAttempts"], 0)

            report.write_text(json.dumps({"status": "prepared", "devices": {
                "emulator-5554": {"status": "recovered-once", "before": {"verifiedAvd": "other-avd"}}
            }}))
            second_root = root / "second"
            second_root.mkdir()
            second = self.make_runner(second_root)
            with patch.dict(os.environ, {"NETWORK_SDK_SETUP_REPORT": str(report)}), \
                    patch.object(second, "capture"), \
                    patch("tools.android_network_runtime.run.ARTIFACT_ROOT", root / "storage"):
                self.assertFalse(second.run())
            gate = json.loads((second.output / "gate.json").read_text())
            self.assertIn("task AVD SDK setup preparation receipt is invalid", gate["errors"][0])

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

    def test_offline_diagnostic_failure_never_changes_gate_errors_or_touches_device(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            for errors in ([], ["TimeoutException: original position read failure"]):
                runner.errors = errors.copy()
                with patch("tools.android_network_runtime.run.native_position_diagnostics",
                           side_effect=OSError("raw log could not be indexed")):
                    evidence = runner.write_position_diagnostics()
                self.assertEqual(evidence["status"], "unavailable")
                self.assertEqual(runner.errors, errors)
                self.assertEqual(runner.adb.calls, [])

    def test_failed_gate_keeps_original_failure_when_diagnostic_indexing_also_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            with patch.object(runner, "capture"), \
                    patch.object(runner, "start_processes", side_effect=RuntimeFailure("original read timeout")), \
                    patch("tools.android_network_runtime.run.native_position_diagnostics",
                          side_effect=ValueError("diagnostic parser failed")), \
                    patch("tools.android_network_runtime.run.ARTIFACT_ROOT", Path(directory) / "storage"):
                self.assertFalse(runner.run())
            gate = json.loads((runner.output / "gate.json").read_text())
            self.assertEqual(gate["errors"], ["RuntimeFailure: original read timeout"])
            self.assertEqual(gate["completedPhases"], [])
            self.assertEqual(gate["nativePositionDiagnostics"]["status"], "unavailable")

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

    def test_ack_rejects_unknown_phase_and_replacement_process_before_publication(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            runner.android_pid = 456
            runner.adb.pid = b"789"
            with self.assertRaisesRegex(RuntimeFailure, "invalid network acknowledgement"):
                runner.ack("recording-ready'; exit 0")
            self.assertEqual(runner.adb.calls, [])
            with self.assertRaisesRegex(RuntimeFailure, "process changed"):
                runner.ack("bootstrap-observed")
            self.assertFalse(any(call[:2] == ("shell", "run-as") for call in runner.adb.calls))
            self.assertEqual(runner.acknowledgements, [])

    def test_ack_readback_failure_is_terminal_and_both_paths_are_owned_for_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.make_runner(Path(directory))
            runner.android_pid = 456
            runner.adb.pid = b"456"
            # FakeAdb returns an empty readback, matching the observed failure.
            with self.assertRaisesRegex(RuntimeFailure, "readback does not match"):
                runner.ack("bootstrap-observed")
            self.assertEqual(len(runner.acknowledgements), 2)
            self.assertTrue(runner.acknowledgements[0].endswith(".pending"))
            self.assertEqual(runner.acknowledgements[1], f"files/network-{RUN_ID}-bootstrap-observed")
            self.assertEqual(runner.events, [])
            with self.assertRaisesRegex(RuntimeFailure, "duplicate"):
                runner.ack("bootstrap-observed")

    @unittest.skipIf(os.name == "nt", "POSIX shell publication contract runs on Linux or WSL")
    def test_partial_shell_write_is_invisible_until_atomic_publication(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runner = self.make_runner(root)
            runner.output.mkdir()
            (root / "files").mkdir()
            runner.android_pid = 456
            runner.adb.pid = b"456"
            original_run = runner.adb.run
            final = root / f"files/network-{RUN_ID}-bootstrap-observed"
            # Pause the real shell writer after its first bytes. The consumer's
            # exists/read protocol must not see that in-progress payload.
            writer = """printf() {
  command printf '%s' 'network_123_1:'
  touch writer-paused
  while test ! -f writer-release; do sleep 0.01; done
  command printf '%s' 'bootstrap-observed'
}
"""

            def shell_adb(*args, **kwargs):
                if args[:5] == ("shell", "run-as", PACKAGE, "sh", "-c"):
                    return subprocess.run(["sh", "-c", writer + args[5][1:-1]],
                                          cwd=root, capture_output=True, check=True, timeout=5)
                if args[:4] == ("shell", "run-as", PACKAGE, "cat"):
                    return subprocess.CompletedProcess(args, 0, (root / args[4]).read_bytes(), b"")
                return original_run(*args, **kwargs)

            with patch.object(runner.adb, "run", side_effect=shell_adb), ThreadPoolExecutor() as pool:
                future = pool.submit(runner.ack, "bootstrap-observed")
                try:
                    deadline = time.monotonic() + 3
                    while not (root / "writer-paused").exists() and time.monotonic() < deadline:
                        time.sleep(0.01)
                    self.assertTrue((root / "writer-paused").exists())
                    self.assertFalse(final.exists(), "consumer can see the partial acknowledgement")
                    self.assertEqual((root / runner.acknowledgements[0]).read_bytes(), b"network_123_1:")
                finally:
                    (root / "writer-release").touch()
                future.result(timeout=5)
            self.assertEqual(final.read_bytes(), f"{RUN_ID}:bootstrap-observed".encode())
            self.assertFalse((root / runner.acknowledgements[0]).exists())
            self.assertTrue(runner.events[-1]["readbackVerified"])

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
