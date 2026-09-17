"""Host contract tests; these do not claim RevenueCat or Android evidence."""

from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

import run_relaunch_journey as runner


CUSTOMER_HASH = "a" * 64


def evidence(mode: str) -> dict[str, object]:
    verified = sorted(
        runner.MATRIX_REQUIRED if mode == "matrix" else runner.RELAUNCH_REQUIRED
    )
    return {
        "revenueCatTestStore": {
            "mode": mode,
            "customerHash": CUSTOMER_HASH,
            "verified": verified,
            "initialPlus": mode == "relaunch",
            "finalPlus": True,
            "cancelErrorCode": "1" if mode == "matrix" else None,
            "failureErrorCode": "42" if mode == "matrix" else None,
        }
    }


class CommandContract(unittest.TestCase):
    def test_drive_keeps_each_exact_emulator_process_running(self) -> None:
        command = runner.drive_command(
            "flutter", "emulator-5554", Path("matrix.apk"), 39701
        )
        self.assertIn("--keep-app-running", command)
        self.assertIn("--use-application-binary=matrix.apk", command)
        self.assertIn("--host-vmservice-port=39701", command)

    def test_drive_refuses_non_emulator_serial(self) -> None:
        with self.assertRaisesRegex(ValueError, "emulator"):
            runner.drive_command("flutter", "physical-device", Path("matrix.apk"), 39701)

    def test_relaunch_build_binds_same_hashed_customer_and_test_store(self) -> None:
        command = runner.relaunch_build_command(
            "flutter", CUSTOMER_HASH, "test_public_sdk_key"
        )
        self.assertIn("--dart-define=REVENUECAT_TEST_MODE=relaunch", command)
        self.assertIn(
            f"--dart-define=REVENUECAT_EXPECT_CUSTOMER_HASH={CUSTOMER_HASH}", command
        )
        self.assertIn("--no-pub", command)
        with self.assertRaisesRegex(ValueError, "Test Store"):
            runner.relaunch_build_command("flutter", CUSTOMER_HASH, "goog_production")

    def test_runner_has_no_clear_or_uninstall_command(self) -> None:
        source = Path(runner.__file__).read_text(encoding="utf-8")
        self.assertNotIn('"pm", "clear"', source)
        self.assertNotIn('"uninstall"', source)


class EvidenceContract(unittest.TestCase):
    def test_accepts_matrix_then_same_customer_relaunch(self) -> None:
        matrix = runner.validate_evidence(evidence("matrix"), "matrix")
        relaunched = runner.validate_evidence(
            evidence("relaunch"), "relaunch", expected_customer_hash=CUSTOMER_HASH
        )
        self.assertEqual(matrix["customerHash"], relaunched["customerHash"])

    def test_rejects_modes_outside_bounded_relaunch_journey(self) -> None:
        with self.assertRaisesRegex(ValueError, "matrix or relaunch"):
            runner.validate_evidence(evidence("relaunch"), "expired")

    def test_relaunch_requires_cache_invalidation_and_matching_customer(self) -> None:
        report = evidence("relaunch")
        report["revenueCatTestStore"]["verified"].remove(
            "restore_cache_invalidated"
        )
        with self.assertRaisesRegex(RuntimeError, "restore_cache_invalidated"):
            runner.validate_evidence(report, "relaunch", CUSTOMER_HASH)
        with self.assertRaisesRegex(RuntimeError, "different"):
            runner.validate_evidence(evidence("relaunch"), "relaunch", "b" * 64)

    def test_rejects_raw_customer_identity_anywhere_in_report(self) -> None:
        report = evidence("relaunch")
        report["revenueCatTestStore"]["originalAppUserId"] = "$RCAnonymousID:raw"
        with self.assertRaisesRegex(RuntimeError, "Raw RevenueCat"):
            runner.validate_evidence(report, "relaunch", CUSTOMER_HASH)

    def test_matrix_requires_exact_native_error_codes(self) -> None:
        for key in ("cancelErrorCode", "failureErrorCode"):
            report = evidence("matrix")
            report["revenueCatTestStore"][key] = "billing_unavailable"
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                runner.validate_evidence(report, "matrix")


class ProcessContract(unittest.TestCase):
    def test_force_stop_waits_for_exact_old_pid_to_disappear(self) -> None:
        class Device:
            prefix = ["adb", "-s", "emulator-5554"]

            def __init__(self):
                self.commands = []

            def run(self, *args):
                self.commands.append(args)
                return b""

        gone = subprocess.CompletedProcess(
            args=[], returncode=1, stdout=b"", stderr=b""
        )
        device = Device()
        with patch.object(runner.subprocess, "run", return_value=gone):
            runner.force_stop_and_wait(device, 1234)
        self.assertEqual(
            device.commands,
            [("shell", "am", "force-stop", runner.PACKAGE)],
        )

    def test_pid_contract_rejects_multiple_or_non_numeric_processes(self) -> None:
        class Device:
            prefix = ["adb", "-s", "emulator-5554"]

        for output in (b"123 456\n", b"not-a-pid\n"):
            result = subprocess.CompletedProcess(
                args=[], returncode=0, stdout=output, stderr=b""
            )
            with self.subTest(output=output), patch.object(
                runner.subprocess, "run", return_value=result
            ), self.assertRaises(RuntimeError):
                runner.single_pid(Device())


if __name__ == "__main__":
    unittest.main()
