"""Contract tests for the hosted-session and purchase runtime runner."""

from pathlib import Path
import tempfile
import unittest

from run_hosting_purchase import (
    REQUIRED_OBSERVATIONS,
    REQUIRED_VERIFIED,
    parse_stage_marker,
    validate_evidence,
)


def valid_report() -> dict[str, object]:
    observations = [{"stage": stage} for stage in sorted(REQUIRED_OBSERVATIONS)]
    return {
        "hostingPurchase": {
            "mode": "hosting_purchase",
            "runtime": "Android; two native video targets and two TLS clients in one process",
            "result": "passed",
            "verified": sorted(REQUIRED_VERIFIED),
            "customerHash": "a" * 64,
            "localizedPrice": "$2.99",
            "remainingFreeHosts": 0,
            "finalPlus": True,
            "observations": observations,
            "screenshots": sorted(REQUIRED_OBSERVATIONS),
        }
    }


class MarkerTests(unittest.TestCase):
    def test_accepts_only_complete_purchase_markers(self) -> None:
        self.assertEqual(parse_stage_marker("I/flutter: RC_SMOKE_STAGE cancel\n"), "cancel")
        self.assertIsNone(parse_stage_marker("RC_SMOKE_STAGE success later\n"))
        self.assertIsNone(parse_stage_marker("RC_SMOKE_STAGE fabricated\n"))


class EvidenceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.artifacts = Path(self.temporary.name)
        for stage in REQUIRED_OBSERVATIONS:
            (self.artifacts / f"{stage}.png").write_bytes(b"x" * 4097)
        self.actions = [{"stage": stage} for stage in ("cancel", "failure", "success")]

    def test_accepts_complete_real_boundary_evidence(self) -> None:
        evidence = validate_evidence(valid_report(), self.artifacts, self.actions)
        self.assertTrue(evidence["finalPlus"])

    def test_rejects_missing_quota_or_entitlement_claim(self) -> None:
        for missing in (
            "actual_peer_and_native_play_consume_one_host",
            "real_purchase_activates_plus_and_unlocks_next_host",
            "real_restore_preserves_entitlement_and_quota",
        ):
            with self.subTest(missing=missing):
                report = valid_report()
                report["hostingPurchase"]["verified"].remove(missing)  # type: ignore[index,union-attr]
                with self.assertRaisesRegex(RuntimeError, "Missing hosting verification"):
                    validate_evidence(report, self.artifacts, self.actions)

    def test_rejects_incomplete_native_dialog_sequence(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "cancel/failure/success"):
            validate_evidence(valid_report(), self.artifacts, self.actions[:2])

    def test_rejects_missing_runtime_screenshot(self) -> None:
        missing = next(iter(REQUIRED_OBSERVATIONS))
        (self.artifacts / f"{missing}.png").unlink()
        with self.assertRaisesRegex(RuntimeError, "Missing non-empty runtime screenshot"):
            validate_evidence(valid_report(), self.artifacts, self.actions)

    def test_rejects_raw_or_malformed_customer_identity(self) -> None:
        report = valid_report()
        report["hostingPurchase"]["customerHash"] = "anonymous-user-id"  # type: ignore[index]
        with self.assertRaisesRegex(RuntimeError, "SHA-256"):
            validate_evidence(report, self.artifacts, self.actions)


if __name__ == "__main__":
    unittest.main()
