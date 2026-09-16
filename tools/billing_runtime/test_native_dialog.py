"""Guard tests only; these fixtures are not RevenueCat purchase evidence."""

from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

from native_dialog import Adb, DialogOrchestrator, PACKAGE, UnsafeDialog, select_target


FOCUS = f"mCurrentFocus=Window{{abcd u0 {PACKAGE}/{PACKAGE}.MainActivity}}"


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


class SelectorTests(unittest.TestCase):
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


class FakeAdb:
    remote_prefix = "/sdcard/meowwatch-billing-fixture-"

    def __init__(self, focus_changes: bool = False):
        self.remote_files: list[str] = []
        self.observations = 0
        self.commands: list[tuple[str, ...]] = []
        self.focus_changes = focus_changes

    def observe(self) -> tuple[str, str]:
        self.observations += 1
        focus = "mCurrentFocus=null" if self.focus_changes and self.observations > 1 else FOCUS
        return xml(dialog()), focus

    def screenshot(self) -> bytes:
        return b"\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR" + struct.pack(">II", 240, 400)

    def run(self, *args: str) -> bytes:
        self.commands.append(args)
        return b""


class OrchestratorTests(unittest.TestCase):
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
