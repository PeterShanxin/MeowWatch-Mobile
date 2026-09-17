"""Runner contracts; these tests do not claim Android or purchase evidence."""

import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("production_purchase_runner", Path(__file__).with_name("run.py"))
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class EvidenceContract(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        png = b"\x89PNG\r\n\x1a\n" + b"\0\0\0\rIHDR" + (1179).to_bytes(4, "big") + (2556).to_bytes(4, "big") + b"\0" * 5000
        for name in runner.SCREENSHOTS:
            (self.root / f"{name}.png").write_bytes(png)
        self.actions = [{"stage": stage} for stage in runner.STAGES]
        self.evidence = {
            "result": "passed", "runtime": runner.RUNTIME,
            "verified": sorted(runner.REQUIRED), "screenshots": sorted(runner.SCREENSHOTS),
            "finalPlus": True, "remainingFreeHosts": 0, "theme": "cinemaNoir",
            "customerHash": "a" * 64, "localizedPrice": "$2.99",
            "cancelErrorCode": "1", "failureErrorCode": "42",
            "restoreKeptSameCustomer": True,
            "sessions": [{
                "id": f"room-{index}", "usedFreeHost": index == 0, "plus": index > 0,
                "peerCompletedTlsHello": True, "peerObservedPlaying": True,
                "nativePositionMs": 1250, "remainingFreeHosts": 0, "server": "syncplay.pl:8995",
            } for index in range(3)],
        }

    def validate(self):
        return runner.validate_evidence({"purchaseJourney": self.evidence}, self.root, self.actions)

    def test_complete_contract(self):
        self.assertIs(self.validate(), self.evidence)

    def test_rejects_missing_ui_steps(self):
        for step in runner.REQUIRED:
            with self.subTest(step=step):
                self.evidence["verified"] = sorted(runner.REQUIRED - {step})
                with self.assertRaisesRegex(RuntimeError, "Missing production UI"):
                    self.validate()

    def test_rejects_claiming_two_native_devices(self):
        self.evidence["runtime"] = "two Android devices"
        with self.assertRaisesRegex(RuntimeError, "runtime boundary"):
            self.validate()

    def test_rejects_duplicate_room_ids_and_wrong_paid_accounting(self):
        original = copy.deepcopy(self.evidence["sessions"])
        for field, value in [("id", "room-0"), ("usedFreeHost", True), ("plus", False),
                             ("peerObservedPlaying", False), ("peerCompletedTlsHello", False),
                             ("nativePositionMs", 0), ("remainingFreeHosts", 1)]:
            with self.subTest(field=field):
                self.evidence["sessions"] = copy.deepcopy(original)
                self.evidence["sessions"][1][field] = value
                with self.assertRaises(RuntimeError):
                    self.validate()

    def test_rejects_missing_native_dialog_outcomes(self):
        self.actions.pop()
        with self.assertRaisesRegex(RuntimeError, "sequence incomplete"):
            self.validate()

    def test_rejects_missing_or_non_png_screenshot(self):
        path = self.root / "plus-theme-applied.png"
        path.unlink()
        with self.assertRaisesRegex(RuntimeError, "Missing screenshot"):
            self.validate()
        path.write_bytes(b"x" * 5000)
        with self.assertRaises(runner.UnsafeDialog):
            self.validate()

    def test_rejects_non_submission_native_dimensions(self):
        path = self.root / "plus-theme-applied.png"
        png = bytearray(path.read_bytes())
        png[16:20] = (1080).to_bytes(4, "big")
        path.write_bytes(png)
        with self.assertRaisesRegex(RuntimeError, "1179x2556"):
            self.validate()

    def test_rejects_raw_customer_identity(self):
        self.evidence["customerHash"] = "$RCAnonymousID:not-a-hash"
        with self.assertRaisesRegex(RuntimeError, "hashed"):
            self.validate()

    def test_rejects_incomplete_restore_theme_entitlement(self):
        for key, value in [
            ("theme", "cozy"),
            ("finalPlus", False),
            ("remainingFreeHosts", 1),
            ("restoreKeptSameCustomer", False),
        ]:
            original = self.evidence[key]
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                self.evidence[key] = value
                self.validate()
            self.evidence[key] = original

    def test_rejects_generic_purchase_error_codes(self):
        for key, value in [("cancelErrorCode", "billing_unavailable"),
                           ("failureErrorCode", "billing_unavailable")]:
            original = self.evidence[key]
            with self.subTest(key=key), self.assertRaisesRegex(RuntimeError, "RevenueCat"):
                self.evidence[key] = value
                self.validate()
            self.evidence[key] = original


class RecordingCoverageContract(unittest.TestCase):
    @staticmethod
    def segment(start, end, duration, *, early=False):
        return {
            "file": "segment.mp4",
            "coverageStartedMonotonicSeconds": start,
            "coverageEndedMonotonicSeconds": end,
            "videoDurationSeconds": duration,
            "endedBeforeRequestedStop": early,
        }

    def test_accepts_probe_durations_covering_bounded_monotonic_segments(self):
        segments = [
            self.segment(0.0, 70.0, 69.4),
            self.segment(72.0, 140.0, 67.5),
        ]
        result = runner.validate_recording_coverage(segments, 0.1, 139.9)
        self.assertGreaterEqual(result["coverageRatio"], 0.98)
        self.assertEqual(result["largestGapSeconds"], 2.0)
        self.assertEqual(segments[1]["gapFromPreviousSeconds"], 2.0)

    def test_rejects_one_second_valid_mp4_that_exited_early(self):
        completed = runner.subprocess.CompletedProcess(
            args=[], returncode=0, stdout="1.000000\n", stderr=""
        )
        with patch.object(runner.subprocess, "run", return_value=completed) as probe:
            duration = runner.ffprobe_duration(Path("early-valid.mp4"), "ffprobe")
        self.assertEqual(duration, 1.0)
        self.assertIn("format=duration", probe.call_args.args[0])
        segments = [self.segment(0.0, 70.0, duration, early=True)]
        with self.assertRaisesRegex(RuntimeError, "exited before the requested stop"):
            runner.validate_recording_coverage(segments, 0.1, 69.9)

    def test_rejects_probe_duration_shorter_than_monotonic_recording(self):
        segments = [self.segment(0.0, 70.0, 1.0)]
        with self.assertRaisesRegex(RuntimeError, "video covers only"):
            runner.validate_recording_coverage(segments, 0.1, 69.9)

    def test_rejects_large_rotation_gap(self):
        segments = [
            self.segment(0.0, 40.0, 39.5),
            self.segment(56.0, 100.0, 43.5),
        ]
        with self.assertRaisesRegex(RuntimeError, "Recording gap"):
            runner.validate_recording_coverage(segments, 0.1, 99.9)

    def test_rejects_missing_aggregate_coverage(self):
        segments = [
            self.segment(0.0, 30.0, 29.5),
            self.segment(40.0, 60.0, 19.5),
            self.segment(70.0, 100.0, 29.5),
        ]
        with self.assertRaisesRegex(RuntimeError, "covers only"):
            runner.validate_recording_coverage(segments, 0.1, 99.9)

    def test_segment_finalizes_owned_recorder_when_wait_fails(self):
        created = []

        class Recording:
            def __init__(self, _adb, output, _stage):
                self.output = output
                self.process = None
                self.finished = False
                created.append(self)

            def start(self):
                pass

            def finish(self):
                self.finished = True

        with tempfile.TemporaryDirectory() as directory:
            journey = runner.JourneyRecording(None, Path(directory), "ffprobe")
            with patch.object(runner, "PortraitRecording", Recording), patch.object(
                journey.stop, "wait", side_effect=RuntimeError("wait failed")
            ):
                journey._run()
        self.assertEqual(len(created), 1)
        self.assertTrue(created[0].finished)
        self.assertRegex(journey.errors[0], "wait failed")


class NativeDialogContract(unittest.TestCase):
    def test_display_restore_uses_override_or_reset(self):
        self.assertIsNone(runner.display_override("Physical size: 1080x2400\n"))
        self.assertEqual(runner.display_override("Physical size: 1080x2400\nOverride size: 800x1200\n"), "800x1200")
        self.assertEqual(runner.display_override("Physical density: 420\nOverride density: 320\n"), "320")

    def test_refuses_unexpected_stage_before_any_adb_action(self):
        with tempfile.TemporaryDirectory() as directory:
            driver = runner.RecordedDialogs(None, Path(directory))
            with self.assertRaisesRegex(runner.UnsafeDialog, "Unexpected native stage"):
                driver.perform("success")

    def test_reinspects_native_dialog_after_screenshot_before_tap(self):
        fixture = runner.ROOT / "tools/billing_runtime/fixtures/api35_test_store_dialog.xml"
        xml = fixture.read_text(encoding="utf-8")
        window = f"mCurrentFocus=Window{{123 u0 {runner.PACKAGE}/.MainActivity}}"
        class Device:
            def __init__(self):
                self.observations = 0
                self.taps = []
            def observe(self):
                self.observations += 1
                return xml, window if self.observations == 1 else "mCurrentFocus=Window{other/package}"
            def screenshot(self):
                return b"\x89PNG\r\n\x1a\n" + b"\0\0\0\rIHDR" + (1080).to_bytes(4, "big") + (2400).to_bytes(4, "big")
            def run(self, *args):
                self.taps.append(args)
        device = Device()
        with tempfile.TemporaryDirectory() as directory:
            driver = runner.RecordedDialogs(device, Path(directory), stage_timeout=0.02)
            with patch.object(runner.time, "sleep"), self.assertRaises(runner.UnsafeDialog):
                driver.perform("cancel")
        self.assertGreaterEqual(device.observations, 2)
        self.assertEqual(device.taps, [])


if __name__ == "__main__":
    unittest.main()
