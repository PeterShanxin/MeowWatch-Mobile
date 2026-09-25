"""Host contract tests; these do not claim RevenueCat or Android evidence."""

from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import run_relaunch_journey as runner


CUSTOMER_HASH = "a" * 64


def entitlement(*, active=True, renewed=False) -> dict[str, object]:
    return {
        "customerHash": CUSTOMER_HASH,
        "customerRequestDate": "2026-09-17T08:26:00Z" if renewed else "2026-09-17T08:00:01Z",
        "observedAtUtc": "2026-09-17T08:26:01Z" if renewed else "2026-09-17T08:00:02Z",
        "identifier": "meowwatch_plus",
        "productIdentifier": "meowwatch_plus_monthly",
        "isActive": active,
        "isSandbox": True,
        "originalPurchaseDate": "2026-09-17T08:00:00Z",
        "latestPurchaseDate": "2026-09-17T08:20:00Z" if renewed else "2026-09-17T08:00:00Z",
        "expirationDate": "2026-09-17T08:25:00Z" if renewed else "2026-09-17T08:05:00Z",
    }


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
            "purchasedEntitlement": entitlement() if mode == "matrix" else None,
        }
    }


def expiry_evidence(*, pending=False) -> dict[str, object]:
    value = {
        "mode": "expiry_wait",
        "customerHash": CUSTOMER_HASH,
        "verified": sorted(
            runner.BASE_REQUIRED | {"expiry_polling_fresh_customer"}
            if pending else runner.EXPIRY_REQUIRED
        ),
        "initialPlus": True,
        "finalPlus": pending,
        "expiryPending": pending,
        "expiryObservations": [entitlement(active=pending, renewed=True)],
    }
    if not pending:
        value["expiredEntitlement"] = entitlement(active=False, renewed=True)
        value["restoredEntitlement"] = entitlement(active=False, renewed=True)
    return {"revenueCatTestStore": value}


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

    def test_expiry_build_is_bound_to_customer_without_purchase_mode(self) -> None:
        command = runner.relaunch_build_command(
            "flutter", CUSTOMER_HASH, "test_public_sdk_key", "expiry_wait"
        )
        self.assertIn("--dart-define=REVENUECAT_TEST_MODE=expiry_wait", command)
        self.assertIn(
            f"--dart-define=REVENUECAT_EXPECT_CUSTOMER_HASH={CUSTOMER_HASH}", command
        )
        with self.assertRaisesRegex(ValueError, "build mode"):
            runner.relaunch_build_command("flutter", CUSTOMER_HASH, "test_key", "matrix")

    def test_runner_has_no_clear_or_uninstall_command(self) -> None:
        source = Path(runner.__file__).read_text(encoding="utf-8")
        self.assertNotIn('"pm", "clear"', source)
        self.assertNotIn('"uninstall"', source)

    def test_build_timeout_does_not_serialize_sdk_key(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(
                runner.subprocess, "run",
                side_effect=subprocess.TimeoutExpired(["flutter", "test_public_key"], 1),
            ):
                with self.assertRaises(TimeoutError) as caught:
                    runner.build_relaunch(
                        "flutter", CUSTOMER_HASH, "test_public_key", Path(directory),
                        mode="expiry_wait", timeout=1,
                    )
        self.assertNotIn("test_public_key", str(caught.exception))


class EvidenceContract(unittest.TestCase):
    def test_accepts_matrix_then_same_customer_relaunch(self) -> None:
        matrix = runner.validate_evidence(evidence("matrix"), "matrix")
        relaunched = runner.validate_evidence(
            evidence("relaunch"), "relaunch", expected_customer_hash=CUSTOMER_HASH
        )
        self.assertEqual(matrix["customerHash"], relaunched["customerHash"])

    def test_rejects_modes_outside_bounded_relaunch_journey(self) -> None:
        with self.assertRaisesRegex(ValueError, "matrix, relaunch or expiry_wait"):
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


class ExpiryContract(unittest.TestCase):
    def test_sdk_expiration_uses_server_time_when_device_clock_lags(self) -> None:
        snapshot = entitlement(active=False, renewed=True)
        snapshot["customerRequestDate"] = "2026-09-17T08:25:00.453Z"
        snapshot["observedAtUtc"] = "2026-09-17T08:24:59.967Z"
        runner.validate_entitlement(snapshot, CUSTOMER_HASH, False)

    def test_accepts_real_historical_expiry_and_inactive_restore_after_renewals(self) -> None:
        result = runner.validate_evidence(expiry_evidence(), "expiry_wait", CUSTOMER_HASH)
        runner.validate_expiry_continuity(result, entitlement())
        self.assertFalse(result["expiryPending"])

    def test_pending_is_explicit_and_cannot_claim_expiration(self) -> None:
        report = expiry_evidence(pending=True)
        result = runner.validate_evidence(report, "expiry_wait", CUSTOMER_HASH)
        self.assertTrue(result["expiryPending"])
        result["verified"].append("same_customer_entitlement_expired")
        with self.assertRaisesRegex(RuntimeError, "Pending expiry"):
            runner.validate_evidence(report, "expiry_wait", CUSTOMER_HASH)

    def test_expiry_requires_original_purchase_evidence(self) -> None:
        report = evidence("matrix")
        del report["revenueCatTestStore"]["purchasedEntitlement"]
        with self.assertRaisesRegex(RuntimeError, "Missing original"):
            runner.validate_evidence(report, "matrix")

    def test_past_expiration_alone_does_not_prove_inactive_sdk_state(self) -> None:
        for key in ("expiredEntitlement", "restoredEntitlement"):
            report = expiry_evidence()
            report["revenueCatTestStore"][key]["isActive"] = True
            with self.subTest(key=key), self.assertRaisesRegex(RuntimeError, "activity"):
                runner.validate_evidence(report, "expiry_wait", CUSTOMER_HASH)

    def test_requires_post_expiration_sdk_response_and_restore_invalidation(self) -> None:
        report = expiry_evidence()
        report["revenueCatTestStore"]["restoredEntitlement"]["customerRequestDate"] = (
            "2026-09-17T08:24:00Z"
        )
        with self.assertRaisesRegex(RuntimeError, "post-expiration"):
            runner.validate_evidence(report, "expiry_wait", CUSTOMER_HASH)
        report = expiry_evidence()
        report["revenueCatTestStore"]["verified"].remove("restore_cache_invalidated")
        with self.assertRaisesRegex(RuntimeError, "restore_cache_invalidated"):
            runner.validate_evidence(report, "expiry_wait", CUSTOMER_HASH)

    def test_rejects_missing_history_and_final_plus_reactivation(self) -> None:
        report = expiry_evidence()
        report["revenueCatTestStore"]["expiredEntitlement"] = None
        with self.assertRaisesRegex(RuntimeError, "Missing original"):
            runner.validate_evidence(report, "expiry_wait", CUSTOMER_HASH)
        report = expiry_evidence()
        report["revenueCatTestStore"]["finalPlus"] = True
        with self.assertRaisesRegex(RuntimeError, "final Plus"):
            runner.validate_evidence(report, "expiry_wait", CUSTOMER_HASH)

    def test_rejects_customer_product_and_original_purchase_changes(self) -> None:
        for key, value in (
            ("customerHash", "b" * 64),
            ("productIdentifier", "another_monthly"),
            ("originalPurchaseDate", "2026-09-17T08:01:00Z"),
        ):
            result = expiry_evidence()["revenueCatTestStore"]
            result["expiryObservations"][0][key] = value
            with self.subTest(key=key), self.assertRaisesRegex(RuntimeError, "original"):
                runner.validate_expiry_continuity(result, entitlement())

    def test_rejects_regression_between_poll_segments(self) -> None:
        result = expiry_evidence()["revenueCatTestStore"]
        previous = entitlement(renewed=True)
        previous["customerRequestDate"] = "2026-09-17T08:27:00Z"
        with self.assertRaisesRegex(RuntimeError, "regressed"):
            runner.validate_expiry_continuity(result, entitlement(), previous)

    def test_pending_segments_cannot_finish_journey_before_real_inactive_restore(self) -> None:
        reports = [
            expiry_evidence(pending=True)["revenueCatTestStore"],
            expiry_evidence()["revenueCatTestStore"],
        ]
        progress = []
        calls = []

        def probe(attempt, timeout):
            calls.append((attempt, timeout))
            return reports[attempt - 1]

        with patch.object(runner.time, "monotonic", return_value=10):
            final = runner.wait_for_expiration(
                probe, entitlement(), 1000,
                lambda attempt, result: progress.append((attempt, result["expiryPending"])),
            )
        self.assertEqual(calls, [(1, 660), (2, 660)])
        self.assertEqual(progress, [(1, True), (2, False)])
        self.assertFalse(final["finalPlus"])

    def test_deadline_never_promotes_still_active_entitlement_to_pass(self) -> None:
        calls = []

        def probe(attempt, timeout):
            calls.append((attempt, timeout))
            return expiry_evidence(pending=True)["revenueCatTestStore"]

        with patch.object(runner.time, "monotonic", side_effect=[10, 101]):
            with self.assertRaisesRegex(TimeoutError, "unproved"):
                runner.wait_for_expiration(probe, entitlement(), 100, lambda *_: None)
        self.assertEqual(calls, [(1, 90)])

    def test_probe_network_failure_is_not_retried_or_counted_as_expiration(self) -> None:
        calls = []

        def probe(attempt, _timeout):
            calls.append(attempt)
            raise RuntimeError("fresh SDK request failed")

        with patch.object(runner.time, "monotonic", return_value=10):
            with self.assertRaisesRegex(RuntimeError, "fresh SDK"):
                runner.wait_for_expiration(probe, entitlement(), 100, lambda *_: None)
        self.assertEqual(calls, [1])

    def test_expired_response_arriving_after_deadline_does_not_pass(self) -> None:
        with patch.object(runner.time, "monotonic", side_effect=[10, 101]):
            with self.assertRaisesRegex(TimeoutError, "unproved"):
                runner.wait_for_expiration(
                    lambda *_: expiry_evidence()["revenueCatTestStore"],
                    entitlement(), 100, lambda *_: None,
                )

    def test_progress_is_durable_before_final_result_without_raw_identity(self) -> None:
        import json

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            summary = {"passed": False, "expiryVerified": False}
            runner.save_progress(path, summary, "waiting_for_real_expiration")
            result = json.loads((path / "run.json").read_text(encoding="utf-8"))
            self.assertFalse(result["passed"])
            self.assertEqual(result["phase"], "waiting_for_real_expiration")
            summary["customerId"] = "raw"
            with self.assertRaisesRegex(RuntimeError, "Raw RevenueCat"):
                runner.save_progress(path, summary, "failed")


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
