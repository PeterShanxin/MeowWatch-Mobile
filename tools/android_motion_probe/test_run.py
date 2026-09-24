"""Fast contracts for the diagnostic's immutable frame and ownership evidence."""

from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

from tools.android_install.runner import RuntimeFailure
from tools.android_motion_probe import run


class FrameClockTests(unittest.TestCase):
    @mock.patch.object(run, "command")
    def test_original_pts_are_retained_without_interpolation(self, command):
        command.return_value = subprocess.CompletedProcess([], 0, "0.000000\n0.033333\n6.579356\n", "")
        values = run.frame_times(Path("original.mp4"))
        self.assertEqual(values, [0.0, 0.033333, 6.579356])
        self.assertGreater(max(b - a for a, b in zip(values, values[1:])), 6.5)

    @mock.patch.object(run, "command")
    def test_rejects_duplicate_or_single_picture(self, command):
        for output in ("0.0\n", "0.0\n0.0\n", "0.1\n0.0\n", "0.0\nnan\n"):
            with self.subTest(output=output):
                command.return_value = subprocess.CompletedProcess([], 0, output, "")
                with self.assertRaises(RuntimeFailure):
                    run.frame_times(Path("original.mp4"))


class OwnershipTests(unittest.TestCase):
    def test_unscoped_phone_avd_is_refused_before_any_command(self):
        with self.assertRaises(RuntimeFailure):
            run.verify_owned_avd(mock.Mock(), "personal_pixel_6", 42, "phone")

    def test_host_sampler_writes_timestamped_rows(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "host.jsonl"
            sampler = run.HostSampler(path, {})
            sampler.start()
            sampler.stop()
            rows = path.read_text(encoding="utf-8").splitlines()
            self.assertGreaterEqual(len(rows), 1)
            self.assertIn('"monotonic":', rows[0])
            self.assertIn('"pressure":', rows[0])


if __name__ == "__main__":
    unittest.main()
