"""Guard tests only; these fixtures are not RevenueCat purchase evidence."""

from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

from native_dialog import (
    Adb,
    DialogOrchestrator,
    PACKAGE,
    UnsafeDialog,
    select_pixel_launcher_anr_close,
    select_target,
)


FOCUS = f"mCurrentFocus=Window{{abcd u0 {PACKAGE}/{PACKAGE}.MainActivity}}"
FIXTURES = Path(__file__).with_name("fixtures")


def dialog() -> ET.Element:
    root = ET.Element("hierarchy")

    def node(text: str, resource: str, kind: str = "android.widget.TextView", bounds: str = "[0,0][100,30]") -> None:
        ET.SubElement(root, "node", {
            "text": text, "resource-id": resource, "class": kind,
            "package": PACKAGE, "enabled": "true", "bounds": bounds,
            "clickable": "true" if kind == "android.widget.Button" else "false",
        })

    node("Test Store Purchase", "android:id/alertTitle")
    node("This is a test purchase; use a RevenueCat key.\nProduct: meowwatch_plus_monthly\nPrice: $2.99", "android:id/message")
    node("Cancel", "android:id/button3", "android.widget.Button", "[20,100][180,150]")
    node("Test failed purchase", "android:id/button2", "android.widget.Button", "[20,160][180,210]")
    node("Test valid purchase", "android:id/button1", "android.widget.Button", "[20,220][180,270]")
    return root


def xml(root: ET.Element) -> str:
    return ET.tostring(root, encoding="unicode")


def launcher_anr(title: str = "Pixel Launcher isn't responding") -> str:
    root = ET.Element("hierarchy")
    ET.SubElement(
        root,
        "node",
        {
            "text": title,
            "resource-id": "android:id/alertTitle",
            "class": "android.widget.TextView",
            "package": "android",
            "enabled": "true",
            "bounds": "[100,100][900,180]",
        },
    )
    ET.SubElement(
        root,
        "node",
        {
            "text": "Close app",
            "resource-id": "android:id/aerr_close",
            "class": "android.widget.Button",
            "package": "android",
            "enabled": "true",
            "clickable": "true",
            "bounds": "[70,1170][1010,1296]",
        },
    )
    return xml(root)


LAUNCHER_WINDOW = (
    "mCurrentFocus=Window{abcd u0 Application Not Responding: "
    "com.google.android.apps.nexuslauncher}\n"
    f"mFocusedApp=ActivityRecord{{abcd u0 {PACKAGE}/{PACKAGE}.MainActivity t8}}"
)


class SelectorTests(unittest.TestCase):
    def test_exact_pixel_launcher_anr_selects_system_close(self) -> None:
        target = select_pixel_launcher_anr_close(launcher_anr(), LAUNCHER_WINDOW)
        self.assertEqual(target.label, "Close app")
        self.assertEqual(target.center, (540, 1233))

    def test_launcher_recovery_rejects_other_anr_and_underlying_app(self) -> None:
        for observed_xml, window in [
            (
                launcher_anr("MeowWatch isn't responding"),
                LAUNCHER_WINDOW.replace(
                    "com.google.android.apps.nexuslauncher", PACKAGE
                ),
            ),
            (launcher_anr(), LAUNCHER_WINDOW.replace(PACKAGE, "com.other")),
            (launcher_anr(), LAUNCHER_WINDOW.replace("nexuslauncher", "other")),
        ]:
            with self.subTest(xml=observed_xml, window=window):
                with self.assertRaises(UnsafeDialog):
                    select_pixel_launcher_anr_close(observed_xml, window)

    def test_launcher_recovery_requires_android_close_id_and_package(self) -> None:
        for attribute, value in [
            ("resource-id", "android:id/aerr_wait"),
            ("package", PACKAGE),
            ("text", "Wait"),
            ("clickable", "false"),
        ]:
            root = ET.fromstring(launcher_anr())
            root[-1].set(attribute, value)
            with self.subTest(attribute=attribute, value=value):
                with self.assertRaises(UnsafeDialog):
                    select_pixel_launcher_anr_close(xml(root), LAUNCHER_WINDOW)

    def test_actual_api35_dialog_bounds_with_explicit_focus(self) -> None:
        observed = (FIXTURES / "api35_test_store_dialog.xml").read_text(encoding="utf-8")
        self.assertEqual(select_target(observed, FOCUS, "cancel").center, (542, 1587))
        self.assertEqual(select_target(observed, FOCUS, "failure").center, (873, 1588))
        self.assertEqual(select_target(observed, FOCUS, "success").center, (211, 1588))

    def test_actual_dialog_button_uppercase_keeps_exact_semantics(self) -> None:
        root = ET.fromstring((FIXTURES / "api35_test_store_dialog.xml").read_text(encoding="utf-8"))
        for node in root.iter("node"):
            if node.get("class") == "android.widget.Button":
                node.set("text", node.get("text", "").upper())
        self.assertEqual(select_target(xml(root), FOCUS, "cancel").center, (542, 1587))
        self.assertEqual(select_target(xml(root), FOCUS, "failure").center, (873, 1588))
        self.assertEqual(select_target(xml(root), FOCUS, "success").center, (211, 1588))

    def test_multiple_display_focus_entries_remain_ambiguous(self) -> None:
        with self.assertRaises(UnsafeDialog):
            select_target(xml(dialog()), FOCUS + "\n" + FOCUS, "cancel")

    def test_actual_windows_only_capture_remains_insufficient_focus_proof(self) -> None:
        observed = (FIXTURES / "api35_test_store_dialog.xml").read_text(encoding="utf-8")
        windows = (FIXTURES / "api35_windows_without_focus.txt").read_text(encoding="utf-8")
        with self.assertRaises(UnsafeDialog):
            select_target(observed, windows, "cancel")

    def test_observation_requests_display_focus_section_for_android35(self) -> None:
        observed = (FIXTURES / "api35_test_store_dialog.xml").read_bytes()
        windows = (FIXTURES / "api35_windows_without_focus.txt").read_bytes()
        adb = Adb("adb", "emulator-5554", "regression")
        calls = []

        def respond(*args: str) -> bytes:
            calls.append(args)
            if args[:3] == ("shell", "uiautomator", "dump"):
                return b"UI hierarchy dumped"
            if args[:2] == ("exec-out", "cat"):
                return observed
            if args == ("shell", "dumpsys", "window", "displays"):
                # Explicit boundary stub, not claimed to be a device capture.
                return ("WINDOW MANAGER DISPLAY CONTENTS\n" + FOCUS).encode()
            if args == ("shell", "dumpsys", "window", "windows"):
                return windows
            self.fail(f"Unexpected adb query {args!r}")

        with patch.object(adb, "run", side_effect=respond):
            observed_xml, observed_focus = adb.observe()
        self.assertEqual(select_target(observed_xml, observed_focus, "cancel").center, (542, 1587))
        self.assertIn(("shell", "dumpsys", "window", "displays"), calls)

    def test_exact_native_trio_selects_observed_centers(self) -> None:
        observed = xml(dialog())
        self.assertEqual(select_target(observed, FOCUS, "cancel").center, (100, 125))
        self.assertEqual(select_target(observed, FOCUS, "failure").center, (100, 185))
        self.assertEqual(select_target(observed, FOCUS, "success").center, (100, 245))

    def test_uppercase_native_button_transformation_is_supported(self) -> None:
        root = dialog()
        root[-1].set("text", "TEST VALID PURCHASE")
        self.assertEqual(select_target(xml(root), FOCUS, "success").center, (100, 245))

    def test_documented_full_button_labels_are_supported(self) -> None:
        root = dialog()
        root[-1].set("text", "Successful Purchase")
        root[-2].set("text", "Failed Purchase")
        self.assertEqual(select_target(xml(root), FOCUS, "success").center, (100, 245))

    def test_unrelated_foreground_window_never_matches(self) -> None:
        with self.assertRaises(UnsafeDialog):
            select_target(xml(dialog()), "mCurrentFocus=Window{aa u0 com.other/.Activity}", "success")

    def test_prefix_package_is_not_the_target_application(self) -> None:
        with self.assertRaises(UnsafeDialog):
            select_target(xml(dialog()), FOCUS.replace(PACKAGE, PACKAGE + ".other"), "success")

    def test_foreign_package_node_cannot_supply_button(self) -> None:
        root = dialog()
        root[-1].set("package", "com.other")
        with self.assertRaises(UnsafeDialog):
            select_target(xml(root), FOCUS, "success")

    def test_flutter_instruction_text_is_not_a_native_dialog(self) -> None:
        root = dialog()
        root[0].set("resource-id", "")
        with self.assertRaises(UnsafeDialog):
            select_target(xml(root), FOCUS, "success")

    def test_wrong_product_or_missing_other_buttons_refuses_all_taps(self) -> None:
        root = dialog()
        root[1].set("text", "RevenueCat test purchase\nProduct: another_product")
        with self.assertRaises(UnsafeDialog):
            select_target(xml(root), FOCUS, "cancel")
        root = dialog()
        root.remove(root[-1])
        with self.assertRaises(UnsafeDialog):
            select_target(xml(root), FOCUS, "cancel")

    def test_duplicate_disabled_hidden_partial_or_invalid_button_refused(self) -> None:
        for attribute, value in [
            ("enabled", "false"), ("visible-to-user", "false"),
            ("clickable", "false"), ("text", "Successful Purchase now"),
            ("bounds", "[0,0][0,0]"), ("bounds", "garbage"),
        ]:
            with self.subTest(attribute=attribute, value=value):
                root = dialog()
                root[-1].set(attribute, value)
                with self.assertRaises(UnsafeDialog):
                    select_target(xml(root), FOCUS, "success")
        root = dialog()
        root.append(ET.fromstring(ET.tostring(root[-1])))
        with self.assertRaises(UnsafeDialog):
            select_target(xml(root), FOCUS, "success")

    def test_serial_and_generated_run_id_are_required(self) -> None:
        for serial in ("", "device; rm", "device with spaces"):
            with self.assertRaises(ValueError):
                Adb("adb", serial, "test")
        with self.assertRaises(ValueError):
            Adb("adb", "emulator-5554", "../escape")

    def test_emulator_recovery_requires_serial_and_qemu_property(self) -> None:
        emulator = Adb("adb", "emulator-5554", "test")
        with patch.object(emulator, "run", return_value=b"1\n") as run:
            self.assertTrue(emulator.verified_emulator())
            run.assert_called_once_with("shell", "getprop", "ro.kernel.qemu")
        physical = Adb("adb", "R58M1234", "test")
        with patch.object(physical, "run") as run:
            self.assertFalse(physical.verified_emulator())
            run.assert_not_called()


class FakeAdb:
    remote_prefix = "/sdcard/meowwatch-billing-fixture-"

    def __init__(self, focus_changes: bool = False):
        self.serial = "emulator-5554"
        self.remote_files: list[str] = []
        self.observations = 0
        self.commands: list[tuple[str, ...]] = []
        self.focus_changes = focus_changes

    def observe(self) -> tuple[str, str]:
        self.observations += 1
        focus = "mCurrentFocus=null" if self.focus_changes and self.observations > 1 else FOCUS
        return xml(dialog()), focus

    def screenshot(self) -> bytes:
        return b"\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR" + struct.pack(">II", 1080, 2400)

    def run(self, *args: str) -> bytes:
        self.commands.append(args)
        return b""

    def verified_emulator(self) -> bool:
        return True


class RecoveringFakeAdb(FakeAdb):
    def __init__(self, *, emulator: bool = True, always_anr: bool = False):
        super().__init__()
        self.emulator = emulator
        self.always_anr = always_anr

    def observe(self) -> tuple[str, str]:
        self.observations += 1
        if self.always_anr or self.observations <= 2:
            return launcher_anr(), LAUNCHER_WINDOW
        return xml(dialog()), FOCUS

    def verified_emulator(self) -> bool:
        return self.emulator


class OrchestratorTests(unittest.TestCase):
    def test_launcher_anr_is_recorded_closed_then_purchase_flow_continues(self) -> None:
        with tempfile.TemporaryDirectory() as temporary, patch(
            "native_dialog.NativeRecording"
        ), patch("native_dialog.time.sleep"):
            adb = RecoveringFakeAdb()
            controller = DialogOrchestrator(adb, Path(temporary))
            controller.perform("cancel")

            taps = [
                command
                for command in adb.commands
                if command[:3] == ("shell", "input", "tap")
            ]
            self.assertEqual(
                taps,
                [
                    ("shell", "input", "tap", "540", "1233"),
                    ("shell", "input", "tap", "100", "125"),
                ],
            )
            self.assertEqual(controller.launcher_recoveries, 1)
            artifacts = Path(temporary)
            self.assertTrue((artifacts / "cancel-launcher-recovery-1.xml").exists())
            self.assertTrue((artifacts / "cancel-launcher-recovery-1.png").exists())
            recovery_log = (artifacts / "launcher-recovery.log").read_text(
                encoding="utf-8"
            )
            self.assertIn("serial=emulator-5554", recovery_log)
            self.assertIn("package=com.google.android.apps.nexuslauncher", recovery_log)

    def test_launcher_anr_recovery_is_bounded_to_two_closes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary, patch(
            "native_dialog.NativeRecording"
        ), patch("native_dialog.time.sleep"):
            adb = RecoveringFakeAdb(always_anr=True)
            controller = DialogOrchestrator(adb, Path(temporary), stage_timeout=0.01)
            with self.assertRaises(UnsafeDialog):
                controller.perform("cancel")
            taps = [
                command
                for command in adb.commands
                if command[:3] == ("shell", "input", "tap")
            ]
            self.assertEqual(len(taps), 2)
            self.assertEqual(controller.launcher_recoveries, 2)

    def test_launcher_anr_on_non_emulator_is_never_tapped(self) -> None:
        with tempfile.TemporaryDirectory() as temporary, patch(
            "native_dialog.NativeRecording"
        ), patch("native_dialog.time.sleep"):
            adb = RecoveringFakeAdb(emulator=False, always_anr=True)
            controller = DialogOrchestrator(adb, Path(temporary), stage_timeout=0.01)
            with self.assertRaises(UnsafeDialog):
                controller.perform("cancel")
            self.assertEqual(adb.commands, [])

    def test_fresh_window_is_rechecked_before_one_tap(self) -> None:
        with tempfile.TemporaryDirectory() as temporary, patch("native_dialog.NativeRecording"), patch("native_dialog.time.sleep"):
            adb = FakeAdb()
            controller = DialogOrchestrator(adb, Path(temporary))
            controller.perform("cancel")
            self.assertGreaterEqual(adb.observations, 2)
            self.assertEqual(adb.commands, [("shell", "input", "tap", "100", "125")])
            with self.assertRaises(UnsafeDialog):
                controller.perform("cancel")
            self.assertEqual(len(adb.commands), 1)

    def test_changed_focus_after_screenshot_prevents_tap(self) -> None:
        with tempfile.TemporaryDirectory() as temporary, patch("native_dialog.NativeRecording"), patch("native_dialog.time.sleep"):
            adb = FakeAdb(focus_changes=True)
            controller = DialogOrchestrator(adb, Path(temporary), stage_timeout=0.01)
            with self.assertRaises(UnsafeDialog):
                controller.perform("cancel")
            self.assertEqual(adb.commands, [])
            self.assertTrue((Path(temporary) / "cancel-failure.xml").exists())
            self.assertTrue((Path(temporary) / "cancel-failure.png").exists())

    def test_success_marker_before_cancel_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            adb = FakeAdb()
            controller = DialogOrchestrator(adb, Path(temporary))
            with self.assertRaises(UnsafeDialog):
                controller.perform("success")
            self.assertEqual(adb.observations, 0)
            self.assertEqual(adb.commands, [])


if __name__ == "__main__":
    unittest.main()
