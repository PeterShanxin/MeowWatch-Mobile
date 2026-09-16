import subprocess
import sys
from pathlib import Path
import unittest

from tools.android_install.runner import (
    Adb,
    PACKAGE,
    RuntimeFailure,
    focused_component,
    install_command,
    install_output_succeeded,
    launch_output_succeeded,
    parse_package_metadata,
    redact_log,
    verify_onboarding_semantics,
)


FOCUS = (
    "mCurrentFocus=Window{123 u0 "
    "com.meowwatch.meowwatch_mobile/.MainActivity}"
)


def node(
    text: str,
    *,
    package: str = PACKAGE,
    clickable: str = "false",
) -> str:
    return (
        f'<node text="{text}" content-desc="" package="{package}" '
        f'enabled="true" visible-to-user="true" clickable="{clickable}" />'
    )


def hierarchy(*nodes: str) -> str:
    return "<?xml version='1.0' encoding='UTF-8'?><hierarchy>" + "".join(nodes) + "</hierarchy>"


class RuntimeContractTests(unittest.TestCase):
    def test_android_evidence_uses_a_unique_owned_directory(self) -> None:
        adb = Adb("emulator-5554", "run-42")
        self.assertEqual(adb.remote_root, "/sdcard/meowwatch-install-run-42")
        self.assertEqual(adb.remote_prefix, f"{adb.remote_root}/")

    def test_workflow_builds_only_the_normal_release_entrypoint(self) -> None:
        workflow = Path(".github/workflows/android-install.yml").read_text(
            encoding="utf-8"
        )
        self.assertIn("flutter build apk --release", workflow)
        self.assertIn("--target=lib/main.dart", workflow)
        self.assertIn(
            "--dart-define=REVENUECAT_API_KEY=test_gjKDzmyNmHmuDfibegUnKQKTpRh",
            workflow,
        )
        self.assertNotIn("integration_test/", workflow)
        self.assertIn("meowwatch-debug-key-release.apk.sha256", workflow)

    def test_install_is_clean_non_replacement_install(self) -> None:
        command = install_command("emulator-5554", Path("app-release.apk"))
        self.assertEqual(
            command,
            ["adb", "-s", "emulator-5554", "install", "-t", "app-release.apk"],
        )
        self.assertNotIn("-r", command)
        self.assertTrue(
            install_output_succeeded("Performing Streamed Install\nSuccess\n")
        )
        self.assertFalse(
            install_output_succeeded(
                "Performing Streamed Install\nFailure [INSTALL_FAILED_INVALID_APK]\n"
            )
        )

    def test_activity_launch_accepts_android_component_normalization(self) -> None:
        self.assertTrue(
            launch_output_succeeded(
                "Status: ok\nActivity: "
                "com.meowwatch.meowwatch_mobile/.MainActivity\n"
            )
        )
        self.assertTrue(
            launch_output_succeeded(
                "Status: ok\nActivity: com.meowwatch.meowwatch_mobile/"
                "com.meowwatch.meowwatch_mobile.MainActivity\n"
            )
        )
        self.assertFalse(
            launch_output_succeeded(
                "Status: ok\nActivity: com.meowwatch.meowwatch_mobile/.OtherActivity\n"
            )
        )
        self.assertFalse(
            launch_output_succeeded(
                "Status: timeout\nActivity: "
                "com.meowwatch.meowwatch_mobile/.MainActivity\n"
            )
        )

    def test_exact_onboarding_semantics_and_focus_are_required(self) -> None:
        xml = hierarchy(
            node("Close the distance.&#10;Keep the movie night."),
            node("No account needed. Change your name anytime."),
            node("Continue", clickable="true"),
        )
        self.assertTrue(verify_onboarding_semantics(xml)["heroTitle"])
        self.assertEqual(focused_component(FOCUS), f"{PACKAGE}/.MainActivity")

        with self.assertRaises(RuntimeFailure):
            verify_onboarding_semantics(
                hierarchy(node("Continue", clickable="true"))
            )
        with self.assertRaises(RuntimeFailure):
            focused_component("mCurrentFocus=Window{1 u0 com.other/.Activity}")

    def test_duplicate_or_foreign_semantics_are_refused(self) -> None:
        duplicated = hierarchy(
            node("Close the distance.&#10;Keep the movie night."),
            node("Close the distance.&#10;Keep the movie night."),
            node("No account needed. Change your name anytime."),
            node("Continue", clickable="true"),
        )
        with self.assertRaises(RuntimeFailure):
            verify_onboarding_semantics(duplicated)
        foreign = hierarchy(
            node(
                "Close the distance.&#10;Keep the movie night.",
                package="com.other",
            ),
            node("No account needed. Change your name anytime."),
            node("Continue", clickable="true"),
        )
        with self.assertRaises(RuntimeFailure):
            verify_onboarding_semantics(foreign)

    def test_package_metadata_requires_real_version_fields(self) -> None:
        value = parse_package_metadata(
            "versionCode=1 minSdk=24 targetSdk=35\n"
            "versionName=0.1.0\nprimaryCpuAbi=x86_64\n"
        )
        self.assertEqual(value["versionCode"], 1)
        self.assertEqual(value["versionName"], "0.1.0")
        self.assertEqual(value["primaryCpuAbi"], "x86_64")
        with self.assertRaises(RuntimeFailure):
            parse_package_metadata("versionName=0.1.0")

    def test_log_redaction_removes_uri_and_secret_values(self) -> None:
        value = redact_log(
            'FATAL content://provider/private?token=abc apiKey="private-value"\n'
        )
        self.assertNotIn("content://", value)
        self.assertNotIn("private-value", value)
        self.assertNotIn("token=abc", value)

    def test_module_entrypoint_help_runs(self) -> None:
        result = subprocess.run(
            [sys.executable, "-m", "tools.android_install.runner", "--help"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--serial", result.stdout)


if __name__ == "__main__":
    unittest.main()
