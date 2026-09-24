"""Fast contracts for the diagnostic's immutable frame and ownership evidence."""

from pathlib import Path
import itertools
import json
import subprocess
import tempfile
import unittest
from unittest import mock
import xml.etree.ElementTree as ET

from tools.android_install.runner import PACKAGE, RuntimeFailure
from tools.android_motion_probe import run


def native_player(position, playing=False):
    # API 35's SeekBar exposes its 48dp thumb, not the rendered track width.
    root = ET.Element("hierarchy")
    for label, kind, clickable, bounds in (
        ("sync-fixture.mp4", "View", False, "[35,720][685,770]"),
        (f"{position // 60}:{position % 60:02d}", "View", False, "[35,1330][119,1360]"),
        ("1:30", "View", False, "[601,1330][685,1360]"),
        ("timeline", "SeekBar", True, "[35,1243][119,1327]"),
        ("Pause" if playing else "Play", "Button", True, "[304,1362][416,1460]"),
        ("Back 10 seconds", "Button", True, "[199,1369][283,1453]"),
        ("Forward 10 seconds", "Button", True, "[437,1369][521,1453]"),
    ):
        ET.SubElement(root, "node", {"package": PACKAGE, "content-desc": label,
                      "class": "android.widget." + kind, "clickable": str(clickable).lower(),
                      "enabled": "true", "visible-to-user": "true", "bounds": bounds})
    return ET.tostring(root, encoding="unicode")


class SeekTests(unittest.TestCase):
    def test_native_controls_normalize_both_fresh_and_already_advanced_media(self):
        for initial in (0, 1, 5, 10, 45, 83, 90):
            with self.subTest(initial=initial):
                runner = mock.Mock()
                position = [initial]
                runner.wait.side_effect = lambda phase, check, **kwargs: (
                    native_player(position[0]), check(native_player(position[0])))
                def tap(node, **kwargs):
                    delta = -10 if node.get("content-desc") == "Back 10 seconds" else 10
                    position[0] = max(0, position[0] + delta)
                runner.tap.side_effect = tap
                runner.pid.return_value = "123"
                result, _ = run.seek_to_start(runner, "A-phone")
                self.assertTrue(7 <= result["seekedPosition"] <= 13)
                self.assertLessEqual(runner.tap.call_count, 11)
                runner.adb.run.assert_not_called()

    def test_eof_is_accepted_only_for_setup_and_with_both_time_labels(self):
        ended = native_player(90)
        self.assertEqual(run.playback(ended, allow_ended=True).position_seconds, 90)
        with self.assertRaises(RuntimeFailure):
            run.playback(ended)
        for invalid in (ended.replace("1:30", "1:10"),
                        ended.replace("sync-fixture.mp4", "uncontrolled.mp4")):
            with self.subTest(xml=invalid), self.assertRaises(RuntimeFailure):
                run.playback(invalid, allow_ended=True)
        root = ET.fromstring(ended)
        root.remove(root[1])
        with self.assertRaises(RuntimeFailure):
            run.playback(ET.tostring(root, encoding="unicode"), allow_ended=True)

    def test_no_op_seek_does_not_pass(self):
        runner = mock.Mock()
        runner.wait.side_effect = lambda phase, check, **kwargs: (native_player(45), check(native_player(45)))
        with self.assertRaises(RuntimeFailure):
            run.seek_to_start(runner, "B-tablet")


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


class CaptureBoundaryTests(unittest.TestCase):
    def test_both_players_pause_and_recorders_stop_before_any_offline_analysis(self):
        events, receipts = self.capture()
        first_analysis = events.index("phone-analyze")
        for device in ("phone", "tablet"):
            self.assertLess(events.index(device + "-Pause"), first_analysis)
            self.assertLess(events.index(device + "-stopped"), first_analysis)
            self.assertTrue(receipts["after"][device]["playing"])
            self.assertEqual(receipts["pausedAfterCapture"][device]["positionSeconds"], 60)

    def test_uncertain_stop_skips_transfer_and_decode_for_both_recorders(self):
        for failure in ("request_stop", "wait_stopped"):
            with self.subTest(failure=failure):
                events, receipts = self.capture(failure)
                self.assertFalse(any(event.endswith("-analyze") for event in events))
                self.assertTrue(all(row["status"] == "unverified" for row in receipts["recordings"].values()))

    def capture(self, failure=None):
        events = []
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            runners, recorders = {}, {}
            for device in ("phone", "tablet"):
                runner = mock.Mock(output=output / device)
                runner.output.mkdir()
                runner.pid.return_value = "42"
                runner.adb.screenshot.return_value = b"retained-original"
                runner.observe.return_value = native_player(60, True)
                runner.tap.side_effect = lambda node, device=device: events.append(device + "-" + node.get("content-desc"))
                runner.sample.side_effect = lambda phase, *, playing, **kwargs: (
                    native_player(20 if playing else 60, playing),
                    run.playback(native_player(20 if playing else 60, playing)))
                runners[device] = runner
                recorder = mock.Mock(receipt={"status": "recording"})
                recorder.wait_stopped.side_effect = lambda device=device: events.append(device + "-stopped")
                recorder.analyze.side_effect = lambda device=device: (
                    events.append(device + "-analyze") or {"status": "verified", "pictureSpanSeconds": 30})
                recorders[device] = recorder
            if failure:
                getattr(recorders["phone"], failure).side_effect = RuntimeFailure("owned recorder not confirmed stopped")
            samples = output / "host.jsonl"
            samples.write_text("{}\n" * 30, encoding="utf-8")
            with (mock.patch.object(run, "seek_to_start", return_value=(
                      {"seekedPosition": 10, "appPid": "42"}, native_player(10))),
                  mock.patch.object(run, "device_elapsed", return_value=100),
                  mock.patch.object(run, "Recording", side_effect=list(recorders.values())),
                  mock.patch.object(run, "HostSampler", return_value=mock.Mock(output=samples)),
                  mock.patch.object(run.time, "monotonic", side_effect=itertools.count(step=100))):
                if failure:
                    with self.assertRaisesRegex(RuntimeFailure, "recording was not verified"):
                        run.phase("A", runners, output, 30, {})
                    receipts = json.loads((output / "A" / "result.json").read_text())
                    for recorder in recorders.values():
                        recorder.retain_partial.assert_not_called()
                else:
                    receipts = run.phase("A", runners, output, 30, {})
            return events, receipts


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
