import base64
from pathlib import Path
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

from tools.android_install.runner import PACKAGE, RuntimeFailure
from tools.android_native_ui.observer import (
    COMPONENT, MAX_ATTRIBUTE, MAX_DEPTH, MAX_NODES, MAX_OUTPUT_BYTES, MAX_XML_BYTES,
    NativeUiObserver, OBSERVER_PACKAGE, ObserverIntegrityFailure, parse_snapshot,
    installation_diagnostics,
)


NONCE = "a" * 32


def node(children="", **attributes):
    values = {"text": "Pause", "content-desc": "", "resource-id": "", "class": "android.view.View",
              "package": PACKAGE, "bounds": "[0,0][500,900]", "enabled": "true",
              "visible-to-user": "true", "clickable": "true", "scrollable": "false", **attributes}
    element = ET.Element("node", values)
    for child in ET.fromstring("<holder>" + children + "</holder>"):
        element.append(child)
    return ET.tostring(element, encoding="unicode")


def response(xml=None, *, nonce=NONCE, uptime=1234, node_count=None):
    xml = "<hierarchy>" + node() + "</hierarchy>" if xml is None else xml
    if node_count is None:
        node_count = len(list(ET.fromstring(xml).iter("node")))
    fields = {"observer_protocol": "1", "observer_nonce": nonce, "observer_uptime_ms": str(uptime),
              "observer_nodes": str(node_count), "observer_xml": base64.b64encode(xml.encode()).decode()}
    return ("\n".join(f"INSTRUMENTATION_RESULT: {key}={value}" for key, value in fields.items())
            + "\nINSTRUMENTATION_CODE: -1\n").encode()


class FakeAdb:
    def __init__(self, *, serial="emulator-5554", qemu=b"1", already_installed=False,
                 target=OBSERVER_PACKAGE, pids=None, first_timeout=False, stale=False):
        self.serial, self.qemu = serial, qemu
        self.already_installed, self.target = already_installed, target
        self.pids = iter(pids or [b"123"] * 50)
        self.first_timeout, self.stale = first_timeout, stale
        self.commands = []
        self.nonces = []

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
            output = f"instrumentation:{COMPONENT} (target={self.target})\n".encode()
        elif arguments == ("shell", "pidof", PACKAGE):
            output = next(self.pids)
        elif arguments[:3] == ("shell", "am", "instrument"):
            self.nonces.append(arguments[7])
            if self.first_timeout and len(self.nonces) == 1:
                raise subprocess.TimeoutExpired(["adb", "-s", self.serial, *arguments], 10,
                                                output=b"private stale snapshot payload")
            nonce = self.nonces[0] if self.stale else arguments[7]
            output = response(nonce=nonce, uptime=1234 + len(self.nonces))
        elif arguments == ("shell", "dumpsys", "window", "displays"):
            output = f"mCurrentFocus=Window{{abc {PACKAGE}/.MainActivity}}".encode()
        elif arguments == ("shell", "am", "force-stop", OBSERVER_PACKAGE):
            pass
        elif arguments == ("uninstall", OBSERVER_PACKAGE):
            output = b"Success"
        else:
            raise AssertionError(f"unexpected command {arguments}")
        return subprocess.CompletedProcess(arguments, 0, output, b"")


class SnapshotParserTests(unittest.TestCase):
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
                     good.replace(b"INSTRUMENTATION_RESULT: observer_protocol=1\n", b""),
                     good.replace(b"observer_protocol=1", b"observer_protocol=2"),
                     good.replace(b"observer_nodes=1", b"observer_nodes=2")]:
            with self.assertRaises(ObserverIntegrityFailure):
                parse_snapshot(data, NONCE)

    def test_complete_snapshot_is_required_no_partial_root_fallback(self):
        for code in ("root_unavailable", "snapshot_failed"):
            data = f"INSTRUMENTATION_RESULT: observer_error={code}\nINSTRUMENTATION_CODE: 0\n".encode()
            with self.assertRaisesRegex(RuntimeFailure, "complete active-window"):
                parse_snapshot(data, NONCE)
        for xml in ("<hierarchy/>", "<hierarchy>" + node() * 2 + "</hierarchy>",
                    "<wrong>" + node() + "</wrong>"):
            with self.assertRaises(ObserverIntegrityFailure):
                parse_snapshot(response(xml), NONCE)

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
        return NativeUiObserver(adb, apk)

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

    def test_capture_fails_if_the_real_application_process_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            observer = self.helper(Path(directory), FakeAdb(pids=[b"123", b"124"]))
            observer.install()
            with self.assertRaisesRegex(ObserverIntegrityFailure, "process changed"):
                observer.observe()
            self.assertEqual(observer.observations, [])

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
            self.assertEqual(observer.observations, [])
            observer.observe()
            self.assertEqual(len(set(adb.nonces)), 2)
            stopped = [args for args, _ in adb.commands if args[:3] == ("shell", "am", "force-stop")]
            self.assertEqual(stopped, [("shell", "am", "force-stop", OBSERVER_PACKAGE)])
            self.assertEqual(len(observer.observations), 1)
            capture_timeouts = [kwargs["timeout"] for args, kwargs in adb.commands
                                if args[:3] == ("shell", "am", "instrument")]
            self.assertEqual(capture_timeouts, [10, 10])

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
            self.assertEqual(len(observer.observations), 1)

    def test_checked_in_manifest_has_no_permissions_activity_or_production_target(self):
        root = ET.parse(Path(__file__).with_name("AndroidManifest.xml")).getroot()
        self.assertEqual(root.get("package"), OBSERVER_PACKAGE)
        self.assertEqual(root.findall("uses-permission"), [])
        self.assertEqual(root.findall(".//activity"), [])
        instrumentation = root.findall("instrumentation")
        self.assertEqual(len(instrumentation), 1)
        self.assertEqual(instrumentation[0].get("{http://schemas.android.com/apk/res/android}targetPackage"),
                         OBSERVER_PACKAGE)


if __name__ == "__main__":
    unittest.main()
