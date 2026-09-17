import subprocess
import sys
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

from tools.android_install.runner import (
    Adb,
    PACKAGE,
    RuntimeFailure,
    Runner,
    SETUP_PACKAGE,
    artifact_boundary,
    focused_component,
    install_command,
    install_output_succeeded,
    launch_output_succeeded,
    launch_output_timed_out,
    parse_package_metadata,
    redact_log,
    setup_anr_close,
    verify_onboarding_semantics,
    verify_build_mode,
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


SETUP_WINDOW = f"mCurrentFocus=Window{{123 u0 Application Not Responding: {SETUP_PACKAGE}}}"
SETUP_XML = hierarchy(
    f'<node package="android" enabled="true" resource-id="android:id/alertTitle" '
    f'text="{SETUP_PACKAGE} isn\'t responding" />',
    '<node package="android" enabled="true" resource-id="android:id/aerr_close" '
    'text="Close app" class="android.widget.Button" clickable="true" bounds="[20,100][120,160]" />',
)


class SetupAdb:
    def __init__(self, *, qemu="1", xml=SETUP_XML, window=SETUP_WINDOW, outcomes=(False, True)):
        self.qemu, self.xml, self.window = qemu, xml, window
        self.outcomes = list(outcomes)
        self.commands = []
        self.observations = 0
        self.change_dialog = False

    def run(self, *args, **kwargs):
        self.commands.append(args)
        output = b""
        if args[:3] == ("shell", "am", "start"):
            ok = self.outcomes.pop(0)
            output = (f"Status: {'ok' if ok else 'timeout'}\nActivity: {PACKAGE}/.MainActivity\n").encode()
        elif args == ("shell", "getprop", "ro.kernel.qemu"):
            output = self.qemu.encode()
        return subprocess.CompletedProcess(args, 0, output, b"")

    def observe(self):
        self.observations += 1
        if self.change_dialog and self.observations > 1:
            return self.xml, FOCUS
        return self.xml, self.window

    def screenshot(self):
        return b"retained-test-evidence"


class SetupRecoveryTests(unittest.TestCase):
    def runner(self, adb):
        runner = Runner.__new__(Runner)
        runner.adb = adb
        return runner

    def test_only_the_exact_system_setup_dialog_can_be_closed(self):
        self.assertEqual(setup_anr_close(SETUP_XML, SETUP_WINDOW), (70, 130))
        self.assertIsNone(setup_anr_close(SETUP_XML, SETUP_WINDOW.replace(SETUP_PACKAGE, PACKAGE)))
        for changed in (
            SETUP_XML.replace(f"{SETUP_PACKAGE} isn't responding", "MeowWatch isn't responding"),
            SETUP_XML.replace('package="android"', f'package="{PACKAGE}"'),
            SETUP_XML.replace('android:id/aerr_close', 'android:id/aerr_wait'),
            SETUP_XML.replace('clickable="true"', 'clickable="false"'),
            SETUP_XML.replace('[20,100][120,160]', '[20,100][20,160]'),
        ):
            with self.subTest(changed=changed), self.assertRaises(RuntimeFailure):
                setup_anr_close(changed, SETUP_WINDOW)

    def test_setup_failure_is_retained_then_launch_is_reverified(self):
        with tempfile.TemporaryDirectory() as temporary, patch(
            'tools.android_install.runner.ARTIFACT_ROOT', Path(temporary)
        ):
            adb = SetupAdb()
            evidence = self.runner(adb).launch()
            self.assertEqual(evidence, {"attempts": 2, "googleSetupAnrRecovered": True})
            self.assertEqual(adb.commands.count(('shell', 'input', 'tap', '70', '130')), 1)
            self.assertIn('Status: timeout', (Path(temporary) / 'launch-1.txt').read_text())
            self.assertIn('Status: ok', (Path(temporary) / 'launch-2.txt').read_text())
            self.assertTrue((Path(temporary) / 'setup-anr.png').is_file())

    def test_other_anrs_and_physical_devices_are_not_retried(self):
        for adb in (SetupAdb(qemu="0"), SetupAdb(window=SETUP_WINDOW.replace(SETUP_PACKAGE, PACKAGE))):
            with self.subTest(adb=adb), tempfile.TemporaryDirectory() as temporary, patch(
                'tools.android_install.runner.ARTIFACT_ROOT', Path(temporary)
            ):
                with self.assertRaises(RuntimeFailure):
                    self.runner(adb).launch()
                self.assertFalse(any(command[:3] == ('shell', 'input', 'tap') for command in adb.commands))
                self.assertEqual(sum(command[:3] == ('shell', 'am', 'start') for command in adb.commands), 1)

    def test_changed_dialog_or_second_failed_launch_remains_failure(self):
        for change in (False, True):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as temporary, patch(
                'tools.android_install.runner.ARTIFACT_ROOT', Path(temporary)
            ):
                adb = SetupAdb(outcomes=(False, False))
                adb.change_dialog = change
                with self.assertRaises(RuntimeFailure):
                    self.runner(adb).launch()
                taps = sum(command[:3] == ('shell', 'input', 'tap') for command in adb.commands)
                self.assertEqual(taps, 0 if change else 1)

    def test_draw_wait_timeout_preserves_evidence_and_defers_without_relaunch(self):
        with tempfile.TemporaryDirectory() as temporary, patch(
            'tools.android_install.runner.ARTIFACT_ROOT', Path(temporary)
        ):
            adb = SetupAdb(xml=hierarchy(), window=FOCUS, outcomes=(False,))
            evidence = self.runner(adb).launch()
            self.assertEqual(evidence, {
                'attempts': 1, 'googleSetupAnrRecovered': False,
                'activityManagerWaitTimedOut': True,
            })
            self.assertIn('Status: timeout', (Path(temporary) / 'launch-1.txt').read_text())
            self.assertEqual(sum(command[:3] == ('shell', 'am', 'start') for command in adb.commands), 1)
            self.assertFalse(any(command[:3] == ('shell', 'input', 'tap') for command in adb.commands))
            # No UI success is fabricated by launch(); run() owns the native gate.
            with self.assertRaises(RuntimeFailure):
                verify_onboarding_semantics(adb.xml)

    def test_draw_wait_timeout_requires_current_main_activity_focus(self):
        for focus in (FOCUS.replace('.MainActivity', '.OtherActivity'), 'mCurrentFocus=null'):
            with self.subTest(focus=focus), tempfile.TemporaryDirectory() as temporary, patch(
                'tools.android_install.runner.ARTIFACT_ROOT', Path(temporary)
            ):
                with self.assertRaises(RuntimeFailure):
                    self.runner(SetupAdb(xml=hierarchy(), window=focus, outcomes=(False,))).launch()

    def test_adb_timeout_and_nonzero_exit_are_not_draw_wait_timeouts(self):
        for outcome in (
            subprocess.TimeoutExpired('adb', 30),
            subprocess.CompletedProcess([], 1, f'Status: timeout\nActivity: {PACKAGE}/.MainActivity\n'.encode(), b''),
        ):
            with self.subTest(outcome=outcome), tempfile.TemporaryDirectory() as temporary, patch(
                'tools.android_install.runner.ARTIFACT_ROOT', Path(temporary)
            ):
                adb = SetupAdb(xml=hierarchy(), window=FOCUS)
                original = adb.run
                def run(*args, **kwargs):
                    if args[:3] == ('shell', 'am', 'start'):
                        if isinstance(outcome, Exception):
                            raise outcome
                        return outcome
                    return original(*args, **kwargs)
                adb.run = run
                with self.assertRaises(RuntimeFailure):
                    self.runner(adb).launch()


class RuntimeContractTests(unittest.TestCase):
    def test_draw_wait_timeout_requires_unambiguous_exact_activity(self):
        output = f'Starting: Intent {{ cmp={PACKAGE}/.MainActivity }}\nStatus: timeout\nActivity: {PACKAGE}/.MainActivity\n'
        self.assertTrue(launch_output_timed_out(output))
        for changed in (
            output.replace('timeout', 'ok'),
            output.replace(f'Activity: {PACKAGE}/.MainActivity', 'Activity: other/.MainActivity'),
            output.replace(f'Activity: {PACKAGE}/.MainActivity', ''),
            output + 'Status: ok\n',
            output + f'Activity: {PACKAGE}/.MainActivity\n',
            output + 'Error: Activity not started\n',
        ):
            with self.subTest(changed=changed):
                self.assertFalse(launch_output_timed_out(changed))

    def test_android_evidence_uses_a_unique_owned_directory(self) -> None:
        adb = Adb("emulator-5554", "run-42")
        self.assertEqual(adb.remote_root, "/sdcard/meowwatch-install-run-42")
        self.assertEqual(adb.remote_prefix, f"{adb.remote_root}/")

    def test_workflow_builds_normal_debug_and_release_entrypoints(self) -> None:
        workflow = Path(".github/workflows/android-install.yml").read_text(
            encoding="utf-8"
        )
        services = Path("lib/app/app_services.dart").read_text(encoding="utf-8")
        self.assertIn("variant: debug-test-store", workflow)
        self.assertIn("variant: release-no-billing", workflow)
        self.assertIn("flutter build apk --debug --target=lib/main.dart", workflow)
        self.assertIn("flutter build apk --release", workflow)
        self.assertIn("--target=lib/main.dart", workflow)
        self.assertIn(
            "--dart-define=REVENUECAT_API_KEY=",
            workflow,
        )
        self.assertNotRegex(workflow, r"REVENUECAT_API_KEY=test_")
        self.assertRegex(
            services,
            r"defaultValue:\s*kDebugMode\s*\?\s*'test_[^']+'\s*:\s*''",
        )
        self.assertNotIn("integration_test/", workflow)
        self.assertIn("apk-name: meowwatch-debug-test-store.apk", workflow)
        self.assertIn("apk-name: meowwatch-debug-key-release.apk", workflow)
        self.assertIn(
            'sha256sum "$packaged_apk" > "$packaged_apk.sha256"', workflow
        )
        self.assertIn("--build-mode ${{ matrix.build-mode }}", workflow)
        self.assertIn("tools.incoming_media_runtime.run", workflow)
        self.assertIn("android-normal-${{ matrix.variant }}-install", workflow)

    def test_installed_debuggability_must_match_declared_mode(self) -> None:
        debug_dump = "  flags=[ DEBUGGABLE HAS_CODE ALLOW_CLEAR_USER_DATA ]\n"
        release_dump = "  pkgFlags=[ HAS_CODE ALLOW_CLEAR_USER_DATA ]\n"
        self.assertTrue(verify_build_mode(debug_dump, "debug"))
        self.assertFalse(verify_build_mode(release_dump, "release"))
        with self.assertRaises(RuntimeFailure):
            verify_build_mode(debug_dump, "release")
        with self.assertRaises(RuntimeFailure):
            verify_build_mode(release_dump, "debug")
        with self.assertRaises(RuntimeFailure):
            verify_build_mode("versionCode=1", "debug")

    def test_build_mode_controls_truthful_billing_boundary(self) -> None:
        debug = artifact_boundary("debug")
        self.assertEqual(debug["revenueCatBackend"], "Test Store")
        self.assertEqual(debug["revenueCatSdkKeyKind"], "public Test Store key")
        self.assertTrue(debug["debuggable"])
        release = artifact_boundary("release")
        self.assertEqual(release["revenueCatBackend"], "disabled")
        self.assertEqual(release["revenueCatSdkKeyKind"], "none")
        self.assertFalse(release["debuggable"])
        with self.assertRaises(ValueError):
            artifact_boundary("profile")

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
        self.assertIn("--build-mode", result.stdout)


if __name__ == "__main__":
    unittest.main()
