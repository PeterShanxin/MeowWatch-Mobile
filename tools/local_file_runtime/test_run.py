import contextlib
import io
import json
import subprocess
import sys
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

from tools.local_file_runtime.picker import (
    Adb, DocumentsUiSelector, PickerNotReady, search_field_diagnostics, select_picker_target,
)
from tools.local_file_runtime.run import (
    drive_command,
    redact_log,
    validate_result,
    wait_for_owned_process,
)


FIXTURE = "meowwatch-saf-fixture.mp4"
DOCS = "com.google.android.documentsui"
FOCUS = (
    "mCurrentFocus=Window{123 u0 "
    "com.google.android.documentsui/com.android.documentsui.files.FilesActivity}"
)


def node(
    *,
    text: str = "",
    description: str = "",
    package: str = DOCS,
    class_name: str = "android.widget.TextView",
    clickable: str = "true",
    bounds: str = "[10,20][210,80]",
    resource_id: str = "",
) -> str:
    return (
        f'<node text="{text}" content-desc="{description}" package="{package}" '
        f'class="{class_name}" resource-id="{resource_id}" clickable="{clickable}" enabled="true" '
        f'visible-to-user="true" bounds="{bounds}" />'
    )


def hierarchy(*nodes: str) -> str:
    return "<?xml version='1.0' encoding='UTF-8'?><hierarchy>" + "".join(nodes) + "</hierarchy>"


LAUNCHER_WINDOW = (
    "mCurrentFocus=Window{123 u0 Application Not Responding: "
    "com.google.android.apps.nexuslauncher}\n"
    f"mFocusedApp=ActivityRecord{{123 u0 {DOCS}/com.android.documentsui.files.FilesActivity t8}}"
)
LAUNCHER_XML = hierarchy(
    node(text="Pixel Launcher isn't responding", package="android",
         resource_id="android:id/alertTitle"),
    node(text="Close app", package="android", class_name="android.widget.Button",
         resource_id="android:id/aerr_close"),
)
SETUP_WINDOW = (
    "mCurrentFocus=Window{123 u0 Application Not Responding: "
    "com.google.android.googlesdksetup}\n"
    f"mFocusedApp=ActivityRecord{{123 u0 {DOCS}/com.android.documentsui.files.FilesActivity t8}}"
)
SETUP_XML = hierarchy(
    node(text="com.google.android.googlesdksetup isn't responding", package="android",
         resource_id="android:id/alertTitle"),
    node(text="Close app", package="android", class_name="android.widget.Button",
         resource_id="android:id/aerr_close"),
)


class RecoveryAdb:
    def __init__(self, frames: list[tuple[str, str]], *, emulator: bool = True) -> None:
        self.frames = iter(frames)
        self.emulator = emulator
        self.commands: list[tuple[str, ...]] = []
        self.app_focused = False

    def observe(self) -> tuple[str, str]:
        return next(self.frames)

    def screenshot(self) -> bytes:
        return (
            b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR"
            + (400).to_bytes(4, "big") + (300).to_bytes(4, "big")
        )

    def run(self, *arguments: str) -> None:
        self.commands.append(arguments)

    def wait_for_app_focus(self) -> None:
        self.app_focused = True

    def verified_emulator(self) -> bool:
        return self.emulator


class PickerSelectorTests(unittest.TestCase):
    def test_launcher_anr_recovery_then_real_exact_fixture_selection(self) -> None:
        anr = (LAUNCHER_XML, LAUNCHER_WINDOW)
        fixture = (hierarchy(node(text=FIXTURE)), FOCUS)
        adb = RecoveryAdb([anr, anr, fixture, fixture])
        with tempfile.TemporaryDirectory() as directory:
            artifacts = Path(directory)
            selector = DocumentsUiSelector(adb, artifacts, FIXTURE)
            selector.select()
            self.assertTrue(selector.selected)
            self.assertTrue(adb.app_focused)
            self.assertEqual(selector.launcher_recoveries, 1)
            self.assertEqual(adb.commands, [
                ("shell", "input", "tap", "110", "50"),
                ("shell", "input", "tap", "110", "50"),
            ])
            for suffix in ("xml", "window.txt", "png", "fresh.xml", "fresh.window.txt"):
                self.assertTrue((artifacts / f"documentsui-launcher-recovery-1.{suffix}").is_file())
            report = json.loads((artifacts / "documentsui-selector.json").read_text())
            self.assertEqual(report["launcherRecoveries"], 1)
            self.assertTrue(report["selected"])

    def test_setup_anr_recovery_then_real_exact_fixture_selection(self) -> None:
        anr = (SETUP_XML, SETUP_WINDOW)
        fixture = (hierarchy(node(text=FIXTURE)), FOCUS)
        adb = RecoveryAdb([anr, anr, fixture, fixture])
        with tempfile.TemporaryDirectory() as directory:
            artifacts = Path(directory)
            selector = DocumentsUiSelector(adb, artifacts, FIXTURE)
            selector.select()
            self.assertTrue(selector.selected)
            self.assertTrue(adb.app_focused)
            self.assertEqual(selector.setup_recoveries, 1)
            self.assertEqual(selector.launcher_recoveries, 0)
            self.assertEqual(adb.commands, [
                ("shell", "input", "tap", "110", "50"),
                ("shell", "input", "tap", "110", "50"),
            ])
            for suffix in ("xml", "window.txt", "png", "fresh.xml", "fresh.window.txt"):
                self.assertTrue((artifacts / f"documentsui-setup-recovery-1.{suffix}").is_file())
            report = json.loads((artifacts / "documentsui-selector.json").read_text())
            self.assertEqual(report["setupRecoveries"], 1)
            self.assertTrue(report["selected"])

    def test_system_anr_recovery_is_emulator_only_and_shares_budget(self) -> None:
        anr = (LAUNCHER_XML, LAUNCHER_WINDOW)
        setup_anr = (SETUP_XML, SETUP_WINDOW)
        with tempfile.TemporaryDirectory() as directory:
            adb = RecoveryAdb([anr, setup_anr])
            selector = DocumentsUiSelector(adb, Path(directory), FIXTURE)
            self.assertTrue(selector._recover_emulator_system_anr(*anr))
            self.assertTrue(selector._recover_emulator_system_anr(*setup_anr))
            with self.assertRaisesRegex(RuntimeError, "recovery limit"):
                selector._recover_emulator_system_anr(*setup_anr)
            self.assertEqual(len(adb.commands), 2)
            physical = RecoveryAdb([], emulator=False)
            selector = DocumentsUiSelector(physical, Path(directory), FIXTURE)
            with self.assertRaisesRegex(RuntimeError, "emulator-only"):
                selector._recover_emulator_system_anr(*setup_anr)
            self.assertEqual(physical.commands, [])

    def test_system_recovery_refuses_app_anr_foreign_activity_and_changed_focus(self) -> None:
        app_anr = (
            SETUP_XML.replace("com.google.android.googlesdksetup", "MeowWatch"),
            SETUP_WINDOW.replace("com.google.android.googlesdksetup", "com.meowwatch.meowwatch_mobile"),
        )
        with tempfile.TemporaryDirectory() as directory:
            adb = RecoveryAdb([(SETUP_XML, SETUP_WINDOW.replace(DOCS, "com.other"))])
            selector = DocumentsUiSelector(adb, Path(directory), FIXTURE)
            self.assertFalse(selector._recover_emulator_system_anr(*app_anr))
            self.assertFalse(selector._recover_emulator_system_anr(
                SETUP_XML, SETUP_WINDOW.replace(DOCS, "com.other"),
            ))
            self.assertFalse(selector._recover_emulator_system_anr(
                SETUP_XML.replace("isn't responding", "has stopped"), SETUP_WINDOW,
            ))
            with self.assertRaises(RuntimeError):
                selector._recover_emulator_system_anr(SETUP_XML, SETUP_WINDOW)
            self.assertEqual(adb.commands, [])

    def test_setup_recovery_accepts_both_documentsui_packages(self) -> None:
        alternate = "com.android.documentsui"
        anr = (SETUP_XML, SETUP_WINDOW.replace(DOCS, alternate))
        with tempfile.TemporaryDirectory() as directory:
            adb = RecoveryAdb([anr])
            selector = DocumentsUiSelector(adb, Path(directory), FIXTURE)
            self.assertTrue(selector._recover_emulator_system_anr(*anr))
            self.assertEqual(selector.setup_recoveries, 1)
            self.assertEqual(adb.commands, [("shell", "input", "tap", "110", "50")])

    def test_recovery_verifies_emulator_serial_and_qemu_property(self) -> None:
        adb = Adb("emulator-5554", "test")
        for value, expected in [(b"1\n", True), (b"0\n", False), (b"", False)]:
            with patch.object(adb, "run", return_value=subprocess.CompletedProcess([], 0, stdout=value)) as run:
                self.assertEqual(adb.verified_emulator(), expected)
                run.assert_called_once_with("shell", "getprop", "ro.kernel.qemu")
        with self.assertRaises(ValueError):
            Adb("physical-serial", "test")

    def test_exact_fixture_is_selected_only_in_focused_documents_ui(self) -> None:
        target = select_picker_target(
            hierarchy(node(text=FIXTURE)), FOCUS, FIXTURE, "initial"
        )
        self.assertEqual(target.action, "fixture")
        self.assertEqual(target.center, (110, 50))

        with self.assertRaises(PickerNotReady):
            select_picker_target(
                hierarchy(node(text=FIXTURE)),
                "mCurrentFocus=Window{123 u0 com.other/.Activity}",
                FIXTURE,
                "initial",
            )

    def test_ambiguous_or_foreign_fixture_is_refused(self) -> None:
        with self.assertRaises(PickerNotReady):
            select_picker_target(
                hierarchy(node(text=FIXTURE), node(description=FIXTURE)),
                FOCUS,
                FIXTURE,
                "initial",
            )
        with self.assertRaises(PickerNotReady):
            select_picker_target(
                hierarchy(node(text=FIXTURE, package="com.other")),
                FOCUS,
                FIXTURE,
                "results",
            )

    def test_search_controls_require_exact_accessibility_shape(self) -> None:
        search = select_picker_target(
            hierarchy(node(description="Search")), FOCUS, FIXTURE, "initial"
        )
        self.assertEqual(search.action, "search")
        query = select_picker_target(
            hierarchy(node(class_name="android.widget.EditText", resource_id=f"{DOCS}:id/search_src_text")),
            FOCUS,
            FIXTURE,
            "search",
        )
        self.assertEqual(query.action, "query")
        with self.assertRaises(PickerNotReady):
            select_picker_target(
                hierarchy(node(description="Search files")),
                FOCUS,
                FIXTURE,
                "initial",
            )

    def test_downloads_root_is_preferred_over_unindexed_recent_search(self) -> None:
        initial = hierarchy(
            node(description="Show roots", class_name="android.widget.ImageButton"),
            node(description="Search", class_name="android.widget.ImageButton"),
        )
        target = select_picker_target(initial, FOCUS, FIXTURE, "initial")
        self.assertEqual(target.action, "roots")
        downloads = select_picker_target(
            hierarchy(node(text="Downloads", bounds="[0,120][260,200]")),
            FOCUS,
            FIXTURE,
            "roots",
        )
        self.assertEqual(downloads.action, "downloads")
        selected = select_picker_target(
            hierarchy(node(text=FIXTURE, bounds="[20,100][220,180]")),
            FOCUS,
            FIXTURE,
            "downloads",
        )
        self.assertEqual(selected.action, "fixture")

    def test_downloads_root_refuses_missing_or_ambiguous_targets(self) -> None:
        with self.assertRaises(PickerNotReady):
            select_picker_target(hierarchy(), FOCUS, FIXTURE, "roots")
        with self.assertRaises(PickerNotReady):
            select_picker_target(
                hierarchy(node(text="Downloads", package="com.other")),
                FOCUS,
                FIXTURE,
                "roots",
            )
        with self.assertRaises(PickerNotReady):
            select_picker_target(
                hierarchy(node(text="Downloads"), node(description="Downloads")),
                FOCUS,
                FIXTURE,
                "roots",
            )

    def test_android_search_autocomplete_is_an_exact_query_control(self) -> None:
        # Android's SearchView.SearchAutoComplete reports this accessibility
        # class, despite inheriting EditText. An EditText-only selector stalls.
        xml = hierarchy(node(
            class_name="android.widget.AutoCompleteTextView",
            resource_id=f"{DOCS}:id/search_src_text",
        ))
        target = select_picker_target(xml, FOCUS, FIXTURE, "search")
        self.assertEqual(target.action, "query")
        self.assertEqual(target.center, (110, 50))
        for foreign in [
            node(class_name="android.widget.AutoCompleteTextView", resource_id="other:id/search_src_text"),
            node(class_name="android.widget.EditText", resource_id=f"{DOCS}:id/rename"),
            node(class_name="android.widget.AutoCompleteTextView", resource_id=f"{DOCS}:id/search_src_text", package="com.other"),
        ]:
            with self.assertRaises(PickerNotReady):
                select_picker_target(hierarchy(foreign), FOCUS, FIXTURE, "search")

    def test_search_diagnostics_never_retain_query_or_document_content(self) -> None:
        fields = search_field_diagnostics(hierarchy(node(
            text="content://private/document/secret",
            description="private filename",
            class_name="android.widget.AutoCompleteTextView",
            resource_id=f"{DOCS}:id/search_src_text",
        )))
        self.assertEqual(fields, [{
            "class": "android.widget.AutoCompleteTextView",
            "clickable": True,
            "enabled": True,
        }])

    def test_entered_search_query_is_not_mistaken_for_a_file_result(self) -> None:
        query = node(
            text=FIXTURE,
            class_name="android.widget.AutoCompleteTextView",
            resource_id=f"{DOCS}:id/search_src_text",
        )
        with self.assertRaises(PickerNotReady):
            select_picker_target(hierarchy(query), FOCUS, FIXTURE, "results")
        target = select_picker_target(
            hierarchy(query, node(text=FIXTURE, bounds="[20,100][220,180]")),
            FOCUS, FIXTURE, "results",
        )
        self.assertEqual(target.action, "fixture")
        self.assertEqual(target.center, (120, 140))

    def test_selector_enters_query_and_selects_fixture_after_search_opens(self) -> None:
        search = hierarchy(node(description="Search"))
        query = hierarchy(node(
            class_name="android.widget.AutoCompleteTextView",
            resource_id=f"{DOCS}:id/search_src_text",
        ))
        results = hierarchy(
            node(text=FIXTURE, class_name="android.widget.AutoCompleteTextView",
                 resource_id=f"{DOCS}:id/search_src_text"),
            node(text=FIXTURE, bounds="[20,100][220,180]"),
        )

        class PickerAdb:
            def __init__(self) -> None:
                self.frames = iter([search, search, query, query, results, results])
                self.commands: list[tuple[str, ...]] = []
                self.app_focused = False

            def observe(self) -> tuple[str, str]:
                return next(self.frames), FOCUS

            def screenshot(self) -> bytes:
                return b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR" + (400).to_bytes(4, "big") + (300).to_bytes(4, "big")

            def run(self, *arguments: str) -> None:
                self.commands.append(arguments)

            def wait_for_app_focus(self) -> None:
                self.app_focused = True

        adb = PickerAdb()
        with tempfile.TemporaryDirectory() as directory, patch("tools.local_file_runtime.picker.time.sleep"):
            selector = DocumentsUiSelector(adb, Path(directory), FIXTURE)
            selector.select()
            self.assertTrue(selector.selected)
            self.assertTrue(adb.app_focused)
            self.assertEqual(adb.commands, [
                ("shell", "input", "tap", "110", "50"),
                ("shell", "input", "tap", "110", "50"),
                ("shell", "input", "text", FIXTURE),
                ("shell", "input", "keyevent", "66"),
                ("shell", "input", "tap", "120", "140"),
            ])
            evidence = json.loads((Path(directory) / "documentsui-selector.json").read_text())
            self.assertTrue(evidence["selected"])
            self.assertEqual(evidence["phase"], "results")

    def test_selector_opens_downloads_and_selects_exact_fixture(self) -> None:
        initial = hierarchy(
            node(description="Show roots", class_name="android.widget.ImageButton")
        )
        roots = hierarchy(node(text="Downloads", bounds="[0,120][260,200]"))
        downloads = hierarchy(node(text=FIXTURE, bounds="[20,100][220,180]"))

        class PickerAdb:
            def __init__(self) -> None:
                self.frames = iter(
                    [initial, initial, roots, roots, downloads, downloads]
                )
                self.commands: list[tuple[str, ...]] = []
                self.app_focused = False

            def observe(self) -> tuple[str, str]:
                return next(self.frames), FOCUS

            def screenshot(self) -> bytes:
                return (
                    b"\x89PNG\r\n\x1a\n"
                    + b"\x00\x00\x00\rIHDR"
                    + (400).to_bytes(4, "big")
                    + (300).to_bytes(4, "big")
                )

            def run(self, *arguments: str) -> None:
                self.commands.append(arguments)

            def wait_for_app_focus(self) -> None:
                self.app_focused = True

        adb = PickerAdb()
        with tempfile.TemporaryDirectory() as directory, patch(
            "tools.local_file_runtime.picker.time.sleep"
        ):
            selector = DocumentsUiSelector(adb, Path(directory), FIXTURE)
            selector.select()
            self.assertTrue(selector.selected)
            self.assertTrue(adb.app_focused)
            self.assertEqual(
                adb.commands,
                [
                    ("shell", "input", "tap", "110", "50"),
                    ("shell", "input", "tap", "130", "160"),
                    ("shell", "input", "tap", "120", "140"),
                ],
            )
            evidence = json.loads(
                (Path(directory) / "documentsui-selector.json").read_text()
            )
            self.assertTrue(evidence["selected"])
            self.assertEqual(evidence["phase"], "downloads")


class RunnerContractTests(unittest.TestCase):
    def test_module_entrypoint_help_runs_from_repository_root(self) -> None:
        result = subprocess.run(
            [sys.executable, "-m", "tools.local_file_runtime.run", "--help"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--serial", result.stdout)

    def test_drive_uses_prebuilt_apk_and_retains_application_data(self) -> None:
        command = drive_command("emulator-5554", Path("app-debug.apk"), 2)
        self.assertIn("--keep-app-running", command)
        self.assertIn("--timeout=300", command)
        self.assertIn("--use-application-binary=app-debug.apk", command)
        self.assertEqual(command[-2:], ["-d", "emulator-5554"])

    def test_result_accepts_bounded_stage_and_rejects_uri_values(self) -> None:
        runtime = validate_result(
            {
                "localFileRuntime": {
                    "stage": 1,
                    "completed": True,
                    "rawContentUriReported": False,
                }
            },
            1,
        )
        self.assertFalse(runtime["rawContentUriReported"])
        with self.assertRaises(ValueError):
            validate_result(
                {
                    "localFileRuntime": {
                        "stage": 1,
                        "completed": True,
                        "value": "content://provider/document/private",
                    }
                },
                1,
            )
        with self.assertRaises(ValueError):
            validate_result(
                {
                    "localFileRuntime": {"stage": 1, "completed": True},
                    "framework": "content://provider/document/private",
                },
                1,
            )
        with self.assertRaises(ValueError):
            validate_result(
                {
                    "localFileRuntime": {
                        "stage": 1,
                        "completed": True,
                        "uri": "redacted",
                    }
                },
                1,
            )

    def test_flutter_drive_log_redacts_content_uri(self) -> None:
        redacted = redact_log("failed content://provider/document/thing?token=value\n")
        self.assertNotIn("content://", redacted)
        self.assertNotIn("token=value", redacted)
        self.assertIn("[REDACTED_CONTENT_URI]", redacted)
        redacted_secret = redact_log("password = hunter2; ok\n")
        self.assertNotIn("hunter2", redacted_secret)
        self.assertIn("[REDACTED]", redacted_secret)
        redacted_json_secret = redact_log('{"apiKey":"private-value"}\n')
        self.assertNotIn("private-value", redacted_json_secret)

    def test_owned_process_timeout_terminates_exact_child_and_keeps_log(self) -> None:
        process = subprocess.Popen(
            [sys.executable, "-c", "import time; print('started', flush=True); time.sleep(30)"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        log = io.StringIO()
        with contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(RuntimeError, "wall timeout"):
                wait_for_owned_process(process, log, timeout=1)
        self.assertIsNotNone(process.returncode)
        self.assertIn("started", log.getvalue())

    def test_picker_failure_stops_owned_drive_without_waiting_wall_timeout(self) -> None:
        process = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(30)"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )
        with contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(RuntimeError, "DocumentsUI selection failed: missing search field"):
                wait_for_owned_process(
                    process, io.StringIO(), timeout=10,
                    abort_error=lambda: PickerNotReady("missing search field"),
                )
        self.assertIsNotNone(process.returncode)


if __name__ == "__main__":
    unittest.main()
