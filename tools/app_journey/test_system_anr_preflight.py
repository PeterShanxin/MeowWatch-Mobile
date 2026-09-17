"""Unit contracts for the app journey's strict system ANR preflight."""

from contextlib import redirect_stderr
import io
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

from tools.app_journey import system_anr_preflight
from tools.app_journey.system_anr_preflight import (
    LAUNCHER_PACKAGE,
    SETUP_PACKAGE,
    UnsafeDialog,
    assert_clean,
    focused_anr_package,
    recover_once,
)


APP_PACKAGE = "com.meowwatch.meowwatch_mobile"


def png(width: int = 1080, height: int = 2400) -> bytes:
    return b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR" + struct.pack(">II", width, height)


def anr_xml(package: str) -> str:
    title = (
        "Pixel Launcher isn't responding"
        if package == LAUNCHER_PACKAGE
        else f"{package} isn't responding"
    )
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
    return ET.tostring(root, encoding="unicode")


def clean_window(package: str = LAUNCHER_PACKAGE) -> str:
    return f"mCurrentFocus=Window{{abcd u0 {package}/.Activity}}"


def anr_window(package: str, underlying: str = LAUNCHER_PACKAGE) -> str:
    return (
        f"mCurrentFocus=Window{{abcd u0 Application Not Responding: {package}}}\n"
        f"mFocusedApp=ActivityRecord{{efgh u0 {underlying}/.Activity t7}}"
    )


class FakeAdb:
    def __init__(
        self,
        observations: list[tuple[str, str]],
        windows: list[str] | None = None,
        *,
        emulator: bool = True,
    ) -> None:
        self.serial = "emulator-5554"
        self.observations = list(observations)
        self.windows = list(windows or [])
        self.emulator = emulator
        self.taps: list[tuple[str, ...]] = []

    def verified_emulator(self) -> bool:
        return self.emulator

    def observe(self) -> tuple[str, str]:
        return self.observations.pop(0)

    def screenshot(self) -> bytes:
        return png()

    def run(self, *args: str) -> bytes:
        if args == ("shell", "dumpsys", "window", "displays"):
            return self.windows.pop(0).encode()
        if args[:3] == ("shell", "input", "tap"):
            self.taps.append(args)
            return b""
        raise AssertionError(f"Unexpected adb call: {args!r}")


class FocusTests(unittest.TestCase):
    def test_reports_exact_anr_package(self) -> None:
        self.assertEqual(
            focused_anr_package(anr_window(LAUNCHER_PACKAGE)), LAUNCHER_PACKAGE
        )
        self.assertIsNone(focused_anr_package(clean_window()))

    def test_rejects_ambiguous_or_invalid_anr_focus(self) -> None:
        with self.assertRaises(UnsafeDialog):
            focused_anr_package(clean_window() + "\n" + clean_window())
        with self.assertRaises(UnsafeDialog):
            focused_anr_package(
                "mCurrentFocus=Window{x u0 Application Not Responding: invalid}"
            )


class RecoveryTests(unittest.TestCase):
    def test_clean_preflight_performs_no_action(self) -> None:
        adb = FakeAdb([(anr_xml(LAUNCHER_PACKAGE), clean_window())])
        with tempfile.TemporaryDirectory() as temporary:
            recovered = recover_once(adb, Path(temporary), "preflight")
            self.assertFalse(recovered)
            self.assertEqual(adb.taps, [])
            self.assertIn(
                "status\tclean",
                (Path(temporary) / "preflight.tsv").read_text(encoding="utf-8"),
            )

    def test_exact_allowlisted_anr_over_launcher_is_closed_once(self) -> None:
        for package in (LAUNCHER_PACKAGE, SETUP_PACKAGE):
            with self.subTest(package=package), tempfile.TemporaryDirectory() as temporary:
                observed = (anr_xml(package), anr_window(package))
                adb = FakeAdb([observed, observed], [clean_window()])
                self.assertTrue(recover_once(adb, Path(temporary), "preflight"))
                self.assertEqual(len(adb.taps), 1)
                report = (Path(temporary) / "preflight.tsv").read_text(
                    encoding="utf-8"
                )
                self.assertIn(f"package\t{package}", report)
                self.assertIn("recovery_count\t1", report)
                for suffix in (
                    "-observed.xml",
                    "-observed-window.txt",
                    "-before.png",
                    "-fresh.xml",
                    "-fresh-window.txt",
                    "-after-window.txt",
                    "-after.png",
                ):
                    self.assertTrue((Path(temporary) / f"preflight{suffix}").is_file())

    def test_app_unrelated_and_wrong_underlying_anrs_are_never_tapped(self) -> None:
        cases = (
            (APP_PACKAGE, APP_PACKAGE),
            ("com.example.unrelated", LAUNCHER_PACKAGE),
            (LAUNCHER_PACKAGE, APP_PACKAGE),
        )
        for package, underlying in cases:
            with self.subTest(package=package), tempfile.TemporaryDirectory() as temporary:
                adb = FakeAdb(
                    [(anr_xml(package), anr_window(package, underlying))]
                )
                with self.assertRaises(UnsafeDialog):
                    recover_once(adb, Path(temporary), "preflight")
                self.assertEqual(adb.taps, [])
                self.assertTrue((Path(temporary) / "preflight-before.png").is_file())

    def test_stale_dialog_is_reobserved_and_never_tapped(self) -> None:
        first = (anr_xml(LAUNCHER_PACKAGE), anr_window(LAUNCHER_PACKAGE))
        changed = (anr_xml(LAUNCHER_PACKAGE), clean_window())
        adb = FakeAdb([first, changed])
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaises(UnsafeDialog):
                recover_once(adb, Path(temporary), "preflight")
        self.assertEqual(adb.taps, [])

    def test_non_emulator_is_rejected_before_observation(self) -> None:
        adb = FakeAdb([], emulator=False)
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaises(UnsafeDialog):
                recover_once(adb, Path(temporary), "preflight")
        self.assertEqual(adb.taps, [])

    def test_anr_remaining_after_single_action_fails_without_retry(self) -> None:
        observed = (
            anr_xml(LAUNCHER_PACKAGE),
            anr_window(LAUNCHER_PACKAGE),
        )
        adb = FakeAdb([observed, observed], [anr_window(LAUNCHER_PACKAGE)])
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaisesRegex(UnsafeDialog, "remained"):
                recover_once(adb, Path(temporary), "preflight")
        self.assertEqual(len(adb.taps), 1)


class AssertionTests(unittest.TestCase):
    def test_clean_boundary_records_proof_without_action(self) -> None:
        adb = FakeAdb([], [clean_window(APP_PACKAGE)])
        with tempfile.TemporaryDirectory() as temporary:
            assert_clean(adb, Path(temporary), "before-recording")
            self.assertTrue(
                (Path(temporary) / "before-recording-window.txt").is_file()
            )
            self.assertEqual(adb.taps, [])

    def test_any_boundary_anr_fails_without_action_and_keeps_screenshot(self) -> None:
        for package in (LAUNCHER_PACKAGE, SETUP_PACKAGE, APP_PACKAGE, "com.other.app"):
            with self.subTest(package=package), tempfile.TemporaryDirectory() as temporary:
                adb = FakeAdb([], [anr_window(package, APP_PACKAGE)])
                with self.assertRaises(UnsafeDialog):
                    assert_clean(adb, Path(temporary), "after-recording")
                self.assertEqual(adb.taps, [])
                self.assertTrue(
                    (Path(temporary) / "after-recording-anr.png").is_file()
                )


class CommandTests(unittest.TestCase):
    def test_each_command_uses_a_fresh_valid_remote_namespace(self) -> None:
        run_ids: list[str] = []

        class CapturingAdb(FakeAdb):
            def __init__(self, _executable: str, serial: str, run_id: str) -> None:
                super().__init__([], [clean_window(APP_PACKAGE)])
                self.serial = serial
                run_ids.append(run_id)

            def cleanup(self) -> None:
                pass

        with tempfile.TemporaryDirectory() as temporary, patch.object(
            system_anr_preflight, "Adb", CapturingAdb
        ):
            for phase in ("before-recording", "after-recording"):
                self.assertEqual(
                    system_anr_preflight.main(
                        [
                            "assert-clean",
                            "--serial",
                            "emulator-5554",
                            "--evidence-dir",
                            temporary,
                            "--phase",
                            phase,
                        ]
                    ),
                    0,
                )
        self.assertEqual(len(run_ids), 2)
        self.assertNotEqual(run_ids[0], run_ids[1])
        for run_id in run_ids:
            self.assertRegex(run_id, r"\A[A-Za-z0-9_-]+\Z")

    def test_owned_remote_cleanup_failure_fails_the_command(self) -> None:
        class CleanupFailAdb(FakeAdb):
            def __init__(self, _executable: str, serial: str, _run_id: str) -> None:
                super().__init__([], [clean_window(APP_PACKAGE)])
                self.serial = serial

            def cleanup(self) -> None:
                raise RuntimeError("owned cleanup failed")

        with tempfile.TemporaryDirectory() as temporary, patch.object(
            system_anr_preflight, "Adb", CleanupFailAdb
        ):
            stderr = io.StringIO()
            with redirect_stderr(stderr):
                status = system_anr_preflight.main(
                    [
                        "assert-clean",
                        "--serial",
                        "emulator-5554",
                        "--evidence-dir",
                        temporary,
                        "--phase",
                        "before-recording",
                    ]
                )
            self.assertEqual(status, 1)
            self.assertIn("owned cleanup failed", stderr.getvalue())
            self.assertTrue(
                (Path(temporary) / "before-recording-cleanup-error.txt").is_file()
            )


if __name__ == "__main__":
    unittest.main()
