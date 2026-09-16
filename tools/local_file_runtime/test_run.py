import contextlib
import io
import subprocess
import sys
from pathlib import Path
import unittest

from tools.local_file_runtime.picker import PickerNotReady, select_picker_target
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
) -> str:
    return (
        f'<node text="{text}" content-desc="{description}" package="{package}" '
        f'class="{class_name}" clickable="{clickable}" enabled="true" '
        f'visible-to-user="true" bounds="{bounds}" />'
    )


def hierarchy(*nodes: str) -> str:
    return "<?xml version='1.0' encoding='UTF-8'?><hierarchy>" + "".join(nodes) + "</hierarchy>"


class PickerSelectorTests(unittest.TestCase):
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
            hierarchy(node(class_name="android.widget.EditText")),
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


if __name__ == "__main__":
    unittest.main()
