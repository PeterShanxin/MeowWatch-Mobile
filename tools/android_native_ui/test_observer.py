import base64
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

from tools.android_install.runner import PACKAGE, RuntimeFailure
from tools.android_native_ui.observer import (
    COMPONENT, SHORT_COMPONENT, MAX_ATTRIBUTE, MAX_DEPTH, MAX_NODES, MAX_OUTPUT_BYTES, MAX_XML_BYTES,
    NativeUiObserver, OBSERVER_PACKAGE, ObserverCaptureFailure, ObserverIntegrityFailure, parse_snapshot,
    installation_diagnostics, stage_diagnostics, MAX_STAGE_EVENTS, MAX_CAPTURE_ATTEMPTS,
    InstrumentationBudget, ObserverTimeout, collect_instrumentation,
)


NONCE = "a" * 32


def progress(stage="on_start", *, nonce=NONCE, pid=567, sequence=1, uptime=1000, attempt=0, nodes=0):
    return (f"INSTRUMENTATION_STATUS: observer_stage={nonce}:{pid}:{sequence}:{stage}:"
            f"{uptime}:{attempt}:{nodes}\nINSTRUMENTATION_STATUS_CODE: 2\n").encode()


def node(children="", **attributes):
    values = {"text": "Pause", "content-desc": "", "resource-id": "", "class": "android.view.View",
              "package": PACKAGE, "bounds": "[0,0][500,900]", "enabled": "true",
              "visible-to-user": "true", "clickable": "true", "scrollable": "false", **attributes}
    element = ET.Element("node", values)
    for child in ET.fromstring("<holder>" + children + "</holder>"):
        element.append(child)
    return ET.tostring(element, encoding="unicode")


def response(xml=None, *, nonce=NONCE, uptime=1234, node_count=None, attempts=None):
    xml = "<hierarchy>" + node() + "</hierarchy>" if xml is None else xml
    if node_count is None:
        node_count = len(list(ET.fromstring(xml).iter("node")))
    fields = {"observer_protocol": "3", "observer_nonce": nonce, "observer_uptime_ms": str(uptime),
              "observer_capture_started_elapsed_ms": str(uptime + 100),
              "observer_capture_completed_elapsed_ms": str(uptime + 125),
              "observer_attempts": attempts or f"ok:{node_count}:0:0:0",
              "observer_nodes": str(node_count), "observer_xml": base64.b64encode(xml.encode()).decode()}
    return ("\n".join(f"INSTRUMENTATION_RESULT: {key}={value}" for key, value in fields.items())
            + "\nINSTRUMENTATION_CODE: -1\n").encode()


def failure_response(reason="child_missing", *, nonce=NONCE, uptime=1234, attempts=None):
    fields = {"observer_protocol": "3", "observer_nonce": nonce, "observer_uptime_ms": str(uptime),
              "observer_attempts": attempts or f"{reason}:18:5:2:3", "observer_error": reason}
    return ("\n".join(f"INSTRUMENTATION_RESULT: {key}={value}" for key, value in fields.items())
            + "\nINSTRUMENTATION_CODE: 0\n").encode()


class FakeAdb:
    def __init__(self, *, serial="emulator-5554", qemu=b"1", already_installed=False,
                 target=OBSERVER_PACKAGE, pids=None, first_timeout=False, stale=False,
                 instrumentation_output=None, capture_response=None, window_output=None, timeout_output=None):
        self.serial, self.qemu = serial, qemu
        self.already_installed, self.target = already_installed, target
        self.pids = iter(pids or [b"123"] * 50)
        self.first_timeout, self.stale = first_timeout, stale
        self.commands = []
        self.nonces = []
        self.instrumentation_output = instrumentation_output
        self.capture_response, self.window_output = capture_response, window_output
        self.timeout_output = timeout_output

    def run(self, *arguments, **kwargs):
        self.commands.append((arguments, kwargs))
        output = b""
        if arguments == ("shell", "getprop", "ro.kernel.qemu"):
            output = self.qemu
        elif arguments == ("shell", "pm", "path", OBSERVER_PACKAGE):
            output = b"package:/test.apk" if self.already_installed else b""
        elif arguments[0] == "install":
            if "--no-incremental" in arguments:
                output = b"Performing Streamed Install\nSuccess\n"
            else:
                output = b"Performing Incremental Install\nSuccess\nInstall command complete in 372 ms\n"
        elif arguments == ("shell", "pm", "list", "instrumentation", OBSERVER_PACKAGE):
            output = (self.instrumentation_output if self.instrumentation_output is not None else
                      f"instrumentation:{SHORT_COMPONENT} (target={self.target})\n".encode())
        elif arguments == ("shell", "pidof", PACKAGE):
            output = next(self.pids)
        elif arguments[:3] == ("shell", "am", "instrument"):
            self.nonces.append(arguments[7])
            if self.first_timeout and len(self.nonces) == 1:
                raise subprocess.TimeoutExpired(["adb", "-s", self.serial, *arguments], 10,
                                                output=(b"private stale snapshot payload" if self.timeout_output is None
                                                        else self.timeout_output(arguments[7])),
                                                stderr=b"private stderr payload")
            nonce = self.nonces[0] if self.stale else arguments[7]
            output = (response(nonce=nonce, uptime=1234 + len(self.nonces))
                      if self.capture_response is None else self.capture_response(nonce))
        elif arguments == ("shell", "dumpsys", "window", "displays"):
            output = (f"mCurrentFocus=Window{{abc {PACKAGE}/.MainActivity}}".encode()
                      if self.window_output is None else self.window_output)
        elif arguments == ("shell", "am", "force-stop", OBSERVER_PACKAGE):
            pass
        elif arguments == ("uninstall", OBSERVER_PACKAGE):
            output = b"Success"
        else:
            raise AssertionError(f"unexpected command {arguments}")
        return subprocess.CompletedProcess(arguments, 0, output, b"")


class SnapshotParserTests(unittest.TestCase):
    def test_progress_retains_phase_timings_without_replacing_complete_snapshot_checks(self):
        stages = (progress("on_start") + progress("automation_start", sequence=2, uptime=1001)
                  + progress("automation_ready", sequence=3, uptime=1100)
                  + progress("traverse_start", sequence=4, uptime=1101, attempt=1))
        parsed = parse_snapshot(stages + response(), NONCE)
        self.assertEqual(parsed.xml, parse_snapshot(response(), NONCE).xml)
        self.assertEqual(parsed.uptime_ms, 1234)
        self.assertEqual(parsed.capture_started_elapsed_ms, 1334)
        self.assertEqual(parsed.capture_completed_elapsed_ms, 1359)

        diagnostics = stage_diagnostics(stages + response(), NONCE)
        self.assertEqual([event["stage"] for event in diagnostics["stages"]],
                         ["on_start", "automation_start", "automation_ready", "traverse_start"])
        self.assertEqual(diagnostics["stages"][2]["uptimeMs"], 1100)
        self.assertEqual(diagnostics["stages"][2]["nonce"], NONCE)
        self.assertNotIn("Pause", str(diagnostics))
        for incomplete in (stages, stages + response().replace(b"observer_xml=", b"observer_xml=%")):
            with self.assertRaises(ObserverIntegrityFailure):
                parse_snapshot(incomplete, NONCE)
        with self.assertRaises(ObserverCaptureFailure):
            parse_snapshot(stages + failure_response("root_missing", attempts="root_missing:0:-1:-1:-1"), NONCE)
        with self.assertRaises(ObserverIntegrityFailure):
            parse_snapshot(stages + response(), NONCE, previous_uptime_ms=1234)

    def test_elapsed_capture_window_requires_both_ordered_device_timestamps(self):
        good = response()
        for data in (good.replace(b"observer_capture_started_elapsed_ms=1334", b"observer_capture_started_elapsed_ms=0"),
                     good.replace(b"observer_capture_completed_elapsed_ms=1359", b"observer_capture_completed_elapsed_ms=1333"),
                     good.replace(b"observer_capture_completed_elapsed_ms=1359", b"observer_capture_completed_elapsed_ms=1.5"),
                     good.replace(b"INSTRUMENTATION_RESULT: observer_capture_started_elapsed_ms=1334\n", b"")):
            with self.subTest(data=data[:80]), self.assertRaises(ObserverIntegrityFailure):
                parse_snapshot(data, NONCE)

    def test_unknown_stale_out_of_order_and_oversized_stage_records_fail_without_echoing_payload(self):
        private = "private-view-text"
        excessive = b"".join(progress(sequence=index, uptime=1000 + index)
                              for index in range(1, MAX_STAGE_EVENTS + 2))
        for stages in (progress(private), progress(nonce="b" * 32), progress(pid=0), progress(sequence=2),
                       progress(attempt=MAX_CAPTURE_ATTEMPTS + 1), progress(nodes=MAX_NODES + 2),
                       progress() + progress(sequence=2, pid=568),
                       progress() + progress(sequence=2, uptime=999),
                       progress().replace(b"STATUS_CODE: 2", b"STATUS_CODE: 3"), excessive):
            with self.subTest(stages=stages[:100]), self.assertRaises(ObserverIntegrityFailure) as caught:
                parse_snapshot(stages + response(), NONCE)
            self.assertNotIn(private, str(caught.exception))
            self.assertNotIn(private, str(stage_diagnostics(stages, NONCE)))
        self.assertEqual(len(stage_diagnostics(excessive, NONCE)["stages"]), MAX_STAGE_EVENTS)

    def test_timeout_diagnostics_keep_only_complete_validated_stages(self):
        first = progress("on_start")
        incomplete = progress("automation_start", sequence=2).split(b"INSTRUMENTATION_STATUS_CODE")[0]
        data = first + incomplete
        diagnostics = stage_diagnostics(data, NONCE)
        self.assertEqual([event["stage"] for event in diagnostics["stages"]], ["on_start"])
        self.assertEqual(diagnostics["stageStreamStatus"], "incomplete_status")
        self.assertEqual(diagnostics["bytes"], len(data))
        with self.assertRaises(ObserverIntegrityFailure):
            parse_snapshot(data, NONCE)
        oversized = first + b"private-ui-payload" * MAX_OUTPUT_BYTES
        bounded = stage_diagnostics(oversized, NONCE)
        self.assertEqual(len(bounded["stages"]), 1)
        self.assertEqual(bounded["stageStreamStatus"], "output_limit")
        self.assertNotIn("private-ui-payload", str(bounded))
        broken_tail = stage_diagnostics(first + b"private partial UTF-8 \xe7", NONCE)
        self.assertEqual(len(broken_tail["stages"]), 1)
        self.assertEqual(broken_tail["stageStreamStatus"], "invalid_encoding")
        self.assertNotIn("private", str(broken_tail))
        self.assertEqual(stage_diagnostics(None, NONCE)["stages"], [])

    def test_stage_bound_does_not_reduce_the_existing_maximum_xml_capacity(self):
        xml = "<hierarchy>" + node() + "</hierarchy>"
        xml += " " * (MAX_XML_BYTES - len(xml.encode()))
        stages = b"".join(progress("automation_start", sequence=index, pid=9999999999,
                                    uptime=9999999999999999, attempt=MAX_CAPTURE_ATTEMPTS, nodes=MAX_NODES + 1)
                          for index in range(1, MAX_STAGE_EVENTS + 1))
        data = stages + response(xml)
        self.assertLessEqual(len(data), MAX_OUTPUT_BYTES)
        self.assertEqual(parse_snapshot(data, NONCE).xml, xml)

    def test_success_preserves_actual_accessibility_attributes(self):
        xml = "<hierarchy>" + node(node(text="0:12", **{"class": "android.widget.SeekBar"}), text="") + "</hierarchy>"
        parsed = parse_snapshot(response(xml), NONCE)
        self.assertEqual(parsed.xml, xml)
        self.assertEqual(parsed.node_count, 2)
        self.assertEqual(parsed.uptime_ms, 1234)

    def test_stale_nonce_or_nonincreasing_device_time_cannot_be_accepted(self):
        for data, previous in ((response(nonce="b" * 32), -1), (response(nonce="私" * 32), -1),
                               (response(), 1234), (response(), 9999)):
            with self.subTest(previous=previous), self.assertRaises(ObserverIntegrityFailure):
                parse_snapshot(data, NONCE, previous_uptime_ms=previous)

    def test_failure_or_raw_payload_never_enters_error_messages(self):
        marker = "private-value-that-must-not-be-reported"
        for data in [marker.encode(), b"\xff", b"INSTRUMENTATION_FAILED: " + marker.encode(),
                     response() + b"INSTRUMENTATION_CODE: -1\n",
                     response().replace(b"INSTRUMENTATION_CODE: -1", b"INSTRUMENTATION_CODE: 0"),
                     response() + f"INSTRUMENTATION_RESULT: shortMsg={marker}\n".encode()]:
            with self.subTest(data=data[:40]), self.assertRaises(ObserverIntegrityFailure) as caught:
                parse_snapshot(data, NONCE)
            self.assertNotIn(marker, str(caught.exception))

    def test_duplicate_and_missing_protocol_fields_are_rejected(self):
        good = response()
        for data in [good + f"INSTRUMENTATION_RESULT: observer_nonce={NONCE}\n".encode(),
                     good.replace(b"INSTRUMENTATION_RESULT: observer_protocol=3\n", b""),
                     good.replace(b"observer_protocol=3", b"observer_protocol=2"),
                     good.replace(b"observer_nodes=1", b"observer_nodes=2")]:
            with self.assertRaises(ObserverIntegrityFailure):
                parse_snapshot(data, NONCE)

    def test_complete_snapshot_is_required_no_partial_root_fallback(self):
        for code in ("root_missing", "root_refresh_failed", "root_invisible", "child_missing", "capture_deadline",
                     "flutter_semantics_unavailable"):
            with self.assertRaisesRegex(ObserverCaptureFailure, "complete active-window") as caught:
                parse_snapshot(failure_response(code), NONCE)
            self.assertEqual(isinstance(caught.exception, ObserverIntegrityFailure), code == "capture_deadline")
            self.assertEqual(caught.exception.reason, code)
        for xml in ("<hierarchy/>", "<hierarchy>" + node() * 2 + "</hierarchy>",
                    "<wrong>" + node() + "</wrong>"):
            with self.assertRaises(ObserverIntegrityFailure):
                parse_snapshot(response(xml), NONCE)

    def test_native_exceptions_and_structural_limits_are_not_retryable(self):
        for reason in ("node_limit", "depth_limit", "child_count_limit", "attribute_limit", "byte_limit",
                       "native_security_exception", "native_state_exception",
                       "native_argument_exception", "serialization_io_exception", "native_exception"):
            with self.subTest(reason=reason), self.assertRaises(ObserverIntegrityFailure) as caught:
                parse_snapshot(failure_response(reason), NONCE)
            self.assertEqual(caught.exception.reason, reason)

    def test_native_failure_nonce_and_time_are_verified_before_retry_is_allowed(self):
        for data, previous in ((failure_response(nonce="b" * 32), -1), (failure_response(), 1234),
                               (b"INSTRUMENTATION_RESULT: observer_error=root_unavailable\n"
                                b"INSTRUMENTATION_CODE: 0\n", -1)):
            with self.assertRaises(ObserverIntegrityFailure):
                parse_snapshot(data, NONCE, previous_uptime_ms=previous)

    def test_retry_trace_requires_complete_fresh_final_tree_and_records_discarded_attempts(self):
        attempts = "root_missing:0:-1:-1:-1;child_missing:18:5:2:3;ok:1:0:0:0"
        parsed = parse_snapshot(response(attempts=attempts), NONCE)
        self.assertEqual([item["reason"] for item in parsed.attempts], ["root_missing", "child_missing", "ok"])
        self.assertEqual(parsed.node_count, 1)
        self.assertEqual(parsed.attempts[1]["childIndex"], 2)
        for data in (response(attempts=attempts.replace("ok:1", "ok:18")),
                     response(attempts=attempts).replace(b"observer_xml=", b"observer_xml=%"),
                     failure_response(attempts=attempts),
                     response(attempts="byte_limit:18:5:2:3;ok:1:0:0:0"),
                     response(attempts="capture_deadline:18:5:2:3;ok:1:0:0:0"),
                     response(attempts="ok:1:0:0:0;ok:1:0:0:0")):
            with self.assertRaises(ObserverIntegrityFailure):
                parse_snapshot(data, NONCE)

    def test_structural_diagnostics_are_bounded_and_never_echo_unknown_values(self):
        marker = "private-view-text"
        for attempts in (";".join(["root_missing:0:-1:-1:-1"] * MAX_CAPTURE_ATTEMPTS + ["ok:1:0:0:0"]),
                         "ok:1:0:0:0;", "ok:1:50:0:0", "ok:2050:0:0:0", "ok:1:0:2049:0",
                         "ok:1:0:0:2050", "ok:1:-2:0:0", f"{marker}:1:0:0:0", "ok:1:0:0:0:0"):
            with self.subTest(attempts=attempts), self.assertRaises(ObserverIntegrityFailure) as caught:
                parse_snapshot(response(attempts=attempts), NONCE)
            self.assertNotIn(marker, str(caught.exception))

    def test_expected_flutter_container_shell_cannot_be_a_successful_snapshot(self):
        # API 35 evidence: the visible dialog remained rendered, but Android
        # temporarily returned only these two native FrameLayout containers.
        container = {"text": "", "class": "android.widget.FrameLayout", "clickable": "false",
                     "checkable": "false", "long-clickable": "false", "focusable": "true"}
        xml = "<hierarchy>" + node(node(**container), **container) + "</hierarchy>"
        with self.assertRaisesRegex(ObserverIntegrityFailure, "incomplete Flutter accessibility shell"):
            parse_snapshot(response(xml), NONCE)

    def test_shell_detection_is_package_and_content_specific_not_a_minimum_node_count(self):
        container = {"text": "", "class": "android.widget.FrameLayout", "clickable": "false"}
        for content in ({"text": "A different screen"}, {"content-desc": "Loading video"},
                        {"resource-id": "android:id/content"}, {"clickable": "true"},
                        {"long-clickable": "true"}, {"scrollable": "true"}, {"checkable": "true"},
                        {"class": "android.widget.ProgressBar"}, {"package": "com.android.documentsui"}):
            with self.subTest(content=content):
                xml = "<hierarchy>" + node(**(container | content)) + "</hierarchy>"
                parsed = parse_snapshot(response(xml), NONCE)
                self.assertEqual(parsed.node_count, 1)
                self.assertEqual(parsed.xml, xml)

    def test_shell_recapture_trace_is_bounded_and_requires_actual_published_content(self):
        pending = "flutter_semantics_unavailable:2:1:0:0"
        parsed = parse_snapshot(response(attempts=pending + ";ok:1:0:0:0"), NONCE)
        self.assertEqual(parsed.attempts[0]["reason"], "flutter_semantics_unavailable")
        self.assertEqual(parsed.attempts[0]["visitedNodes"], 2)
        with self.assertRaises(ObserverCaptureFailure) as caught:
            parse_snapshot(failure_response("flutter_semantics_unavailable",
                                            attempts=";".join([pending] * 4)), NONCE)
        self.assertNotIsInstance(caught.exception, ObserverIntegrityFailure)
        self.assertEqual(len(caught.exception.attempts), 4)
        with self.assertRaises(ObserverIntegrityFailure):
            parse_snapshot(response(attempts=";".join([pending] * MAX_CAPTURE_ATTEMPTS + ["ok:1:0:0:0"])), NONCE)

    def test_output_xml_size_and_entity_bounds_are_enforced(self):
        for data in [b"x" * (MAX_OUTPUT_BYTES + 1),
                     response().replace(b"observer_xml=", b"observer_xml=%"),
                     response("<!DOCTYPE hierarchy [<!ENTITY a 'secret'>]><hierarchy>" + node() + "</hierarchy>")]:
            with self.assertRaises(ObserverIntegrityFailure):
                parse_snapshot(data, NONCE)
        xml = "<hierarchy>" + node() + " " * MAX_XML_BYTES + "</hierarchy>"
        with self.assertRaises(ObserverIntegrityFailure):
            parse_snapshot(response(xml), NONCE)

    def test_node_depth_attribute_and_required_semantics_bounds_are_enforced(self):
        too_deep = node()
        for _ in range(MAX_DEPTH + 1):
            too_deep = node(too_deep)
        for content in (too_deep, node(node() * MAX_NODES), node(text="x" * (MAX_ATTRIBUTE + 1)),
                        node().replace('clickable="true"', 'clickable="maybe"'),
                        node(**{"visible-to-user": "false"}),
                        node().replace('package="' + PACKAGE + '"', ''),
                        node().replace('[0,0][500,900]', 'unsafe')):
            with self.assertRaises(ObserverIntegrityFailure):
                parse_snapshot(response("<hierarchy>" + content + "</hierarchy>"), NONCE)


class NativeObserverTests(unittest.TestCase):
    def helper(self, root, adb):
        apk = root / "observer.apk"
        apk.write_bytes(b"helper apk")
        observer = NativeUiObserver(adb, apk)
        # These tests own the app/PID/result protocol. The actual streaming
        # subprocess and watchdogs have separate tests below.
        observer._instrument = lambda nonce, *, deadline: adb.run(
            "shell", "am", "instrument", "-w", "-r", "-e", "nonce", nonce,
            "-e", "expectedPackage", PACKAGE, COMPONENT, timeout=30)
        return observer

    def test_install_is_verified_emulator_only_and_targets_its_own_package(self):
        with tempfile.TemporaryDirectory() as directory:
            adb = FakeAdb()
            observer = self.helper(Path(directory), adb)
            metadata = observer.install()
            self.assertEqual(metadata["targetPackage"], OBSERVER_PACKAGE)
            observer.observe()
            observer.cleanup()
            commands = [args for args, _ in adb.commands]
            self.assertIn(("uninstall", OBSERVER_PACKAGE), commands)
            self.assertNotIn(("uninstall", PACKAGE), commands)
            self.assertNotIn(("shell", "am", "force-stop", PACKAGE), commands)
            instrumentation = [args for args in commands if args[:3] == ("shell", "am", "instrument")]
            self.assertEqual(instrumentation[0][-1], COMPONENT)
            self.assertEqual(instrumentation[0][8:11], ("-e", "expectedPackage", PACKAGE))
            self.assertEqual(observer.observations[0]["applicationPid"], 123)

    def test_helper_with_idsig_requires_completed_non_incremental_install(self):
        with tempfile.TemporaryDirectory() as directory:
            adb = FakeAdb()
            observer = self.helper(Path(directory), adb)
            observer.apk.with_suffix(".apk.idsig").write_bytes(b"test-only signature sidecar")
            metadata = observer.install()
            installs = [arguments for arguments, _ in adb.commands if arguments[0] == "install"]
            self.assertEqual(installs, [("install", "--no-incremental", "-t", str(observer.apk))])
            self.assertTrue(observer.installed)
            self.assertEqual(metadata["installation"]["observedModes"], ["streamed"])
            self.assertTrue(metadata["installation"]["terminalSuccess"])

    def test_installer_failure_is_retained_safely_and_never_invokes_instrumentation(self):
        class FailedInstallAdb(FakeAdb):
            def run(self, *arguments, **kwargs):
                if arguments[0] == "install":
                    self.commands.append((arguments, kwargs))
                    return subprocess.CompletedProcess([], 1, b"Performing Streamed Install\n",
                                                       b"Failure [INSTALL_FAILED_INVALID_APK: private-value]")
                return super().run(*arguments, **kwargs)
        with tempfile.TemporaryDirectory() as directory:
            adb = FailedInstallAdb()
            observer = self.helper(Path(directory), adb)
            with self.assertRaisesRegex(RuntimeFailure, "installation failed"):
                observer.install()
            self.assertFalse(observer.installed)
            self.assertEqual(observer.installation["errorCodes"], ["INSTALL_FAILED_INVALID_APK"])
            self.assertNotIn("private-value", str(observer.installation))
            self.assertFalse(any(arguments[:3] == ("shell", "pm", "list") for arguments, _ in adb.commands))
            observer.cleanup()
            self.assertFalse(observer.owns_package)

    def test_incremental_completion_is_diagnosed_but_not_accepted_as_terminal_success(self):
        data = b"Performing Incremental Install\nSuccess\nInstall command complete in 372 ms\n"
        diagnostics = installation_diagnostics(subprocess.CompletedProcess([], 0, data, b""))
        self.assertEqual(diagnostics["observedModes"], ["incremental"])
        self.assertTrue(diagnostics["successLinePresent"])
        self.assertTrue(diagnostics["incrementalCompletionPresent"])
        self.assertFalse(diagnostics["terminalSuccess"])

    def test_existing_helper_or_physical_device_is_never_replaced(self):
        for adb in (FakeAdb(serial="physical-device"), FakeAdb(qemu=b"0"), FakeAdb(already_installed=True)):
            with tempfile.TemporaryDirectory() as directory:
                observer = self.helper(Path(directory), adb)
                with self.assertRaises(ObserverIntegrityFailure):
                    observer.install()
                observer.cleanup()
                self.assertFalse(any(args[0] in {"install", "uninstall"} for args, _ in adb.commands))

    def test_instrumentation_target_mismatch_is_never_invoked(self):
        with tempfile.TemporaryDirectory() as directory:
            adb = FakeAdb(target=PACKAGE)
            observer = self.helper(Path(directory), adb)
            with self.assertRaisesRegex(ObserverIntegrityFailure, "only its own"):
                observer.install()
            with self.assertRaises(ObserverIntegrityFailure):
                observer.observe()
            observer.cleanup()
            self.assertFalse(any(args[:3] == ("shell", "am", "instrument") for args, _ in adb.commands))

    def test_android_short_component_is_verified_without_accepting_extra_instrumentation(self):
        exact = f"instrumentation:{SHORT_COMPONENT} (target={OBSERVER_PACKAGE})\n".encode()
        with tempfile.TemporaryDirectory() as directory:
            observer = self.helper(Path(directory), FakeAdb(instrumentation_output=exact))
            result = observer.install()
            self.assertTrue(result["installation"]["instrumentationCheck"]["matchesExactSelfTarget"])
            observer.cleanup()
        for output in (b"", exact + exact, exact.replace(b".SnapshotInstrumentation", b".Other"),
                       exact + b"unrelated private output\n"):
            with self.subTest(output=output), tempfile.TemporaryDirectory() as directory:
                adb = FakeAdb(instrumentation_output=output)
                observer = self.helper(Path(directory), adb)
                with self.assertRaises(ObserverIntegrityFailure):
                    observer.install()
                self.assertFalse(observer.installation["instrumentationCheck"]["matchesExactSelfTarget"])
                observer.cleanup()
                self.assertFalse(any(args[:3] == ("shell", "am", "instrument") for args, _ in adb.commands))

    def test_capture_fails_if_the_real_application_process_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            observer = self.helper(Path(directory), FakeAdb(pids=[b"123", b"124"]))
            observer.install()
            with self.assertRaisesRegex(ObserverIntegrityFailure, "process changed"):
                observer.observe()
            self.assertEqual(observer.observations[0]["status"], "failure")
            self.assertEqual(observer.observations[0]["applicationPidAfter"], 124)
            self.assertEqual(observer.observations[0]["failure"], "application_pid_after_failed")

    def test_missing_or_multiple_application_processes_fail_before_instrumentation(self):
        for pid in (b"", b"123 456"):
            with tempfile.TemporaryDirectory() as directory:
                adb = FakeAdb(pids=[pid])
                observer = self.helper(Path(directory), adb)
                observer.install()
                with self.assertRaises(ObserverIntegrityFailure):
                    observer.observe()
                self.assertEqual(adb.nonces, [])

    def test_timeout_stops_only_owned_helper_and_next_capture_has_fresh_nonce(self):
        with tempfile.TemporaryDirectory() as directory:
            adb = FakeAdb(first_timeout=True)
            observer = self.helper(Path(directory), adb)
            observer.install()
            with self.assertRaises(subprocess.TimeoutExpired):
                observer.observe()
            self.assertEqual(observer.observations[0]["failure"], "instrumentation_timeout")
            self.assertNotIn("private stale snapshot payload", str(observer.observations))
            observer.observe()
            self.assertEqual(len(set(adb.nonces)), 2)
            stopped = [args for args, _ in adb.commands if args[:3] == ("shell", "am", "force-stop")]
            self.assertEqual(stopped, [("shell", "am", "force-stop", OBSERVER_PACKAGE)])
            self.assertEqual([item["status"] for item in observer.observations], ["failure", "success"])
            capture_timeouts = [kwargs["timeout"] for args, kwargs in adb.commands
                                if args[:3] == ("shell", "am", "instrument")]
            self.assertEqual(capture_timeouts, [30, 30])

    def test_timeout_preserves_connected_stage_and_discards_partial_ui_output(self):
        def partial(nonce):
            return (progress("on_start", nonce=nonce)
                    + progress("automation_start", nonce=nonce, sequence=2, uptime=1001)
                    + progress("automation_ready", nonce=nonce, sequence=3, uptime=4500)
                    + b"INSTRUMENTATION_RESULT: observer_xml=private partial UI payload")
        with tempfile.TemporaryDirectory() as directory:
            adb = FakeAdb(first_timeout=True, timeout_output=partial)
            observer = self.helper(Path(directory), adb)
            observer.install()
            with self.assertRaises(subprocess.TimeoutExpired):
                observer.observe()
            evidence = observer.observations[0]
            self.assertEqual(evidence["failure"], "instrumentation_timeout")
            stages = evidence["instrumentationProgress"]["stages"]
            self.assertEqual(stages[-1]["stage"], "automation_ready")
            self.assertEqual(stages[-1]["uptimeMs"] - stages[1]["uptimeMs"], 3499)
            self.assertEqual({stage["nonce"] for stage in stages}, {adb.nonces[0]})
            self.assertNotIn("private", str(evidence))
            observer.observe()
            self.assertEqual(len(set(adb.nonces)), 2)
            self.assertEqual(observer.observations[-1]["status"], "success")
            self.assertFalse(any(args == ("shell", "am", "force-stop", PACKAGE) for args, _ in adb.commands))
            self.assertEqual([kwargs["timeout"] for args, kwargs in adb.commands
                              if args[:3] == ("shell", "am", "instrument")], [30, 30])

    def test_completed_capture_retains_stages_on_success_and_native_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            adb = FakeAdb(capture_response=lambda nonce: progress(nonce=nonce) + response(nonce=nonce))
            observer = self.helper(Path(directory), adb)
            observer.install()
            observer.observe()
            self.assertEqual(observer.observations[0]["instrumentationProgress"]["stages"][0]["stage"], "on_start")
            adb.capture_response = lambda nonce: progress(nonce=nonce) + failure_response(nonce=nonce, uptime=1235)
            with self.assertRaises(ObserverCaptureFailure):
                observer.observe()
            self.assertEqual(observer.observations[-1]["failure"], "child_missing")
            self.assertEqual(len(observer.observations[-1]["instrumentationProgress"]["stages"]), 1)

    def test_timeout_cannot_mask_an_application_restart(self):
        with tempfile.TemporaryDirectory() as directory:
            observer = self.helper(Path(directory), FakeAdb(first_timeout=True, pids=[b"123", b"124"]))
            observer.install()
            with self.assertRaisesRegex(ObserverIntegrityFailure, "timed-out"):
                observer.observe()

    def test_old_response_cannot_satisfy_a_later_capture(self):
        with tempfile.TemporaryDirectory() as directory:
            adb = FakeAdb(stale=True)
            observer = self.helper(Path(directory), adb)
            observer.install()
            observer.observe()
            with self.assertRaisesRegex(ObserverIntegrityFailure, "this capture request"):
                observer.observe()
            self.assertEqual([item["status"] for item in observer.observations], ["success", "failure"])

    def test_incomplete_tree_retains_fixed_reason_location_focus_and_pid_without_payload(self):
        attempts = "root_missing:0:-1:-1:-1;child_missing:18:5:2:3"
        private = "private-view-text-and-url"
        with tempfile.TemporaryDirectory() as directory:
            adb = FakeAdb(capture_response=lambda nonce: failure_response(nonce=nonce, attempts=attempts),
                          window_output=f"mCurrentFocus=Window{{abc {PACKAGE}/.MainActivity}}\n{private}".encode())
            observer = self.helper(Path(directory), adb)
            observer.install()
            with self.assertRaises(ObserverCaptureFailure):
                observer.observe()
            evidence = observer.observations[0]
            self.assertEqual(evidence["failure"], "child_missing")
            self.assertFalse(evidence["integrityFailure"])
            self.assertEqual(evidence["applicationPid"], evidence["applicationPidAfter"])
            self.assertTrue(evidence["window"]["applicationFocused"])
            self.assertEqual(evidence["attempts"][-1], {"reason": "child_missing", "visitedNodes": 18,
                                                      "depth": 5, "childIndex": 2, "childCount": 3})
            self.assertGreaterEqual(evidence["completedAtMonotonic"], evidence["startedAtMonotonic"])
            self.assertNotIn(private, str(evidence))
            self.assertEqual(observer.previous_uptime_ms, 1234)
            adb.capture_response = None
            observer.observe()
            self.assertEqual(observer.observations[-1]["status"], "success")
            self.assertEqual(len(set(adb.nonces)), 2)

    def test_a_failed_complete_tree_read_still_prevents_device_time_moving_backwards(self):
        with tempfile.TemporaryDirectory() as directory:
            adb = FakeAdb(capture_response=lambda nonce: failure_response(nonce=nonce, uptime=2000))
            observer = self.helper(Path(directory), adb)
            observer.install()
            with self.assertRaises(ObserverCaptureFailure):
                observer.observe()
            adb.capture_response = lambda nonce: response(nonce=nonce, uptime=1999)
            with self.assertRaisesRegex(ObserverIntegrityFailure, "stale"):
                observer.observe()
            self.assertEqual(observer.previous_uptime_ms, 2000)
            self.assertEqual([item["status"] for item in observer.observations], ["failure", "failure"])

    def test_unknown_raw_response_and_foreign_window_remain_failed_and_content_free(self):
        private = "private-view-text-and-url"
        with tempfile.TemporaryDirectory() as directory:
            adb = FakeAdb(capture_response=lambda nonce: private.encode(),
                          window_output=f"mCurrentFocus=Window{{abc {private}}}".encode())
            observer = self.helper(Path(directory), adb)
            observer.install()
            with self.assertRaises(ObserverIntegrityFailure):
                observer.observe()
            evidence = observer.observations[0]
            self.assertEqual(evidence["status"], "failure")
            self.assertEqual(evidence["failure"], "response_failed")
            self.assertFalse(evidence["window"]["applicationFocused"])
            self.assertNotIn(private, str(evidence))

    def test_native_terminal_error_is_retained_and_not_retried_by_host(self):
        with tempfile.TemporaryDirectory() as directory:
            adb = FakeAdb(capture_response=lambda nonce: failure_response("native_exception", nonce=nonce))
            observer = self.helper(Path(directory), adb)
            observer.install()
            with self.assertRaises(ObserverIntegrityFailure):
                observer.observe()
            self.assertEqual(len(adb.nonces), 1)
            self.assertTrue(observer.observations[0]["integrityFailure"])
            self.assertEqual(observer.observations[0]["failure"], "native_exception")

    def test_late_complete_result_and_pid_query_cannot_escape_caller_deadline(self):
        with tempfile.TemporaryDirectory() as directory:
            for late_at in ("instrumentation", "pid"):
                adb = FakeAdb()
                observer = self.helper(Path(directory), adb)
                observer.install()
                clock = [0.0]
                original = adb.run
                def command(*args, **kwargs):
                    value = original(*args, **kwargs)
                    if ((late_at == "instrumentation" and args[:3] == ("shell", "am", "instrument"))
                            or (late_at == "pid" and args == ("shell", "pidof", PACKAGE))):
                        clock[0] = 9
                    return value
                with self.subTest(late_at=late_at), patch.object(adb, "run", side_effect=command), \
                        patch("tools.android_native_ui.observer.time.monotonic", side_effect=lambda: clock[0]), \
                        self.assertRaises(ObserverTimeout):
                    observer.observe(deadline=8)
                self.assertEqual(observer.observations[-1]["status"], "failure")
                self.assertNotIn("xmlSha256", observer.observations[-1])
                if late_at == "pid":
                    self.assertEqual(adb.nonces, [])

    def test_checked_in_manifest_has_no_permissions_activity_or_production_target(self):
        root = ET.parse(Path(__file__).with_name("AndroidManifest.xml")).getroot()
        self.assertEqual(root.get("package"), OBSERVER_PACKAGE)
        self.assertEqual(root.findall("uses-permission"), [])
        self.assertEqual(root.findall(".//activity"), [])
        instrumentation = root.findall("instrumentation")
        self.assertEqual(len(instrumentation), 1)
        self.assertEqual(instrumentation[0].get("{http://schemas.android.com/apk/res/android}targetPackage"),
                         OBSERVER_PACKAGE)


def startup_progress(*, nonce=NONCE, pid=567, ready_uptime=7000):
    names = ("on_create", "on_start", "automation_start", "automation_ready", "service_ready")
    return b"".join(progress(name, nonce=nonce, pid=pid, sequence=index + 1,
                             uptime=ready_uptime - 4 + index) for index, name in enumerate(names))


class InstrumentationBudgetTests(unittest.TestCase):
    def test_slow_cold_start_does_not_spend_the_hierarchy_budget(self):
        budget = InstrumentationBudget(NONCE, 0, 100)
        budget.progress(startup_progress(), 12)
        self.assertEqual(budget.phase, "capture")
        self.assertEqual(budget.deadline, 22)  # Eight for tree, two for delivery.
        data = startup_progress() + progress("finish", sequence=6, uptime=10000, attempt=1, nodes=1)
        budget.progress(data, 15)
        self.assertEqual(budget.deadline, 17)
        self.assertTrue(budget.finished)

    def test_startup_cap_and_total_cap_are_independent(self):
        budget = InstrumentationBudget(NONCE, 0, 100)
        with self.assertRaises(ObserverTimeout) as caught:
            budget.progress(startup_progress(), 20)
        self.assertEqual(caught.exception.phase, "startup")
        budget = InstrumentationBudget(NONCE, 0, 100)
        budget.progress(startup_progress(), 19.9)
        self.assertLessEqual(budget.deadline, 30)
        with self.assertRaises(ObserverTimeout):
            budget.progress(startup_progress(), 30)

    def test_caller_deadline_dominates_readiness_and_result(self):
        budget = InstrumentationBudget(NONCE, 0, 8)
        budget.progress(startup_progress(), 7)
        self.assertEqual(budget.deadline, 8)
        with self.assertRaises(ObserverTimeout):
            budget.progress(startup_progress() + progress("finish", sequence=6, uptime=7100), 8)

    def test_wrong_nonce_pid_sequence_or_repeated_ready_cannot_extend_time(self):
        first = startup_progress()
        for data in (startup_progress(nonce="b" * 32),
                     first + progress("service_ready", sequence=6, uptime=7001),
                     first + progress("root_start", sequence=6, uptime=7001, pid=568),
                     progress("service_ready"),
                     first + progress("finish", sequence=6, uptime=7001)
                     + progress("finish", sequence=7, uptime=7002)):
            budget = InstrumentationBudget(NONCE, 0, 100)
            with self.subTest(data=data[-120:]), self.assertRaises(ObserverIntegrityFailure):
                budget.progress(data, 10)

    def test_incomplete_ready_is_not_a_new_budget_and_repeated_buffer_does_not_refresh(self):
        data = startup_progress()
        budget = InstrumentationBudget(NONCE, 0, 100)
        budget.progress(data.rsplit(b"INSTRUMENTATION_STATUS_CODE", 1)[0], 12)
        self.assertEqual(budget.deadline, 20)
        budget.progress(data, 13)
        self.assertEqual(budget.deadline, 23)
        budget.progress(data, 18)
        self.assertEqual(budget.deadline, 23)

    def test_capture_deadline_is_terminal_and_does_not_grant_another_connection(self):
        with self.assertRaises(ObserverIntegrityFailure) as caught:
            parse_snapshot(failure_response("capture_deadline"), NONCE)
        self.assertIsInstance(caught.exception, ObserverCaptureFailure)

    def test_native_traversal_over_eight_seconds_cannot_use_response_delivery_allowance(self):
        for uptime, accepted in ((14999, True), (15000, False), (16000, False)):
            budget = InstrumentationBudget(NONCE, 0, 100)
            budget.progress(startup_progress(), 12)
            data = startup_progress() + progress("traverse_ready", sequence=6, uptime=uptime,
                                                attempt=1, nodes=1)
            if accepted:
                budget.progress(data, 20.5)
                self.assertTrue(budget.traversed)
            else:
                with self.assertRaisesRegex(ObserverIntegrityFailure, "eight-second"):
                    budget.progress(data, 20.5)


class InstrumentationPipeTests(unittest.TestCase):
    def command(self, payload, *, after=""):
        return [sys.executable, "-u", "-c",
                f"import sys,time;sys.stdout.buffer.write({payload!r});sys.stdout.buffer.flush();{after}"]

    def test_actual_child_stream_delivers_complete_owned_response(self):
        data = startup_progress() + progress("traverse_ready", sequence=6, uptime=7100, attempt=1, nodes=1)
        data += progress("finish", sequence=7, uptime=7101, attempt=1, nodes=1)
        data += response(uptime=7100)
        result = collect_instrumentation(self.command(data), NONCE, deadline=time.monotonic() + 5)
        self.assertEqual(parse_snapshot(result.stdout, NONCE).node_count, 1)
        self.assertEqual(result.stderr, b"")

    def test_delayed_root_keeps_one_connection_and_accepts_only_complete_last_attempt(self):
        data = startup_progress()
        sequence = 6
        for attempt in range(1, MAX_CAPTURE_ATTEMPTS):
            for stage in ("root_start", "attempt_failed"):
                data += progress(stage, sequence=sequence, uptime=7000 + (attempt - 1) * 500,
                                 attempt=attempt)
                sequence += 1
        for stage in ("root_start", "root_ready", "refresh_start", "refresh_ready", "traverse_start",
                      "traverse_ready", "finish"):
            data += progress(stage, sequence=sequence, uptime=14510,
                             attempt=MAX_CAPTURE_ATTEMPTS, nodes=1)
            sequence += 1
        attempts = ";".join(["root_missing:0:-1:-1:-1"] * (MAX_CAPTURE_ATTEMPTS - 1) + ["ok:1:0:0:0"])
        data += response(uptime=14510, attempts=attempts)
        result = collect_instrumentation(self.command(data), NONCE, deadline=time.monotonic() + 5)
        parsed = parse_snapshot(result.stdout, NONCE)
        self.assertEqual(len(parsed.attempts), MAX_CAPTURE_ATTEMPTS)
        self.assertEqual(parsed.node_count, 1)
        self.assertEqual(parsed.attempts[-1]["reason"], "ok")

    def test_expired_child_is_reaped_and_partial_xml_is_never_returned(self):
        child = []
        real_popen = subprocess.Popen
        def launch(*args, **kwargs):
            process = real_popen(*args, **kwargs)
            child.append(process)
            return process
        with patch("tools.android_native_ui.observer.subprocess.Popen", side_effect=launch), \
                self.assertRaises(ObserverTimeout) as caught:
            collect_instrumentation(self.command(b"partial private XML", after="time.sleep(5)"),
                                    NONCE, deadline=time.monotonic() + 0.5)
        self.assertEqual(len(child), 1)
        self.assertIsNotNone(child[0].poll())
        self.assertEqual(caught.exception.phase, "startup")
        self.assertLessEqual(len(caught.exception.output), MAX_OUTPUT_BYTES)

    def test_excessive_output_and_unready_success_are_rejected(self):
        for data in (b"x" * (MAX_OUTPUT_BYTES + 1),
                     progress("finish") + response()):
            with self.subTest(size=len(data)), self.assertRaises(ObserverIntegrityFailure):
                # Keep the command line bounded even on Windows.
                command = ([sys.executable, "-u", "-c", f"import sys;sys.stdout.buffer.write(b'x'*{len(data)})"]
                           if len(data) > MAX_OUTPUT_BYTES else self.command(data))
                collect_instrumentation(command, NONCE, deadline=time.monotonic() + 5)

    def test_expired_caller_never_starts_an_instrumentation_child(self):
        with patch("tools.android_native_ui.observer.subprocess.Popen") as launch, \
                self.assertRaises(ObserverTimeout):
            collect_instrumentation(["must-not-start"], NONCE, deadline=time.monotonic() - 1)
        launch.assert_not_called()


if __name__ == "__main__":
    unittest.main()
