from pathlib import Path
from contextlib import redirect_stdout
import io
import json
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch
from xml.sax.saxutils import escape

from tools.android_install.runner import PACKAGE, RuntimeFailure
from tools.android_lifecycle_runtime.run import (
    FIXTURE_NAME, LifecycleRecording, Playback, PreparationRecoveryFailure, Runner, button, history_card, history_swipe, main,
    parse_time, playback, require_background_pause, require_paused_stability,
    require_playing_advance, require_restored_position, timed_out_observation,
    recording_device_elapsed, recording_media_ready, recording_size, validate_recording_duration,
)
from tools.billing_runtime.native_dialog import LAUNCHER_PACKAGE, SETUP_PACKAGE
from tools.android_native_ui.observer import OBSERVER_PACKAGE, ObserverIntegrityFailure
from tools.android_native_ui.test_observer import node as native_node, response as native_response


def node(label="", *, children="", clickable=False, extra="", class_name="android.view.View"):
    return (f'<node text="{escape(label)}" content-desc="" package="{PACKAGE}" '
            f'clickable="{str(clickable).lower()}" enabled="true" visible-to-user="true" '
            f'class="{class_name}" bounds="[10,20][310,420]" {extra}>{children}</node>')


def player(position="0:12", action="Pause"):
    return '<hierarchy>' + ''.join([
        node(FIXTURE_NAME), node(position), node("1:30"),
        node(position, class_name="android.widget.SeekBar"), node(action, clickable=True),
    ]) + '</hierarchy>'


def history(*, position="0:19", filename=FIXTURE_NAME, context="Local player"):
    card = node(clickable=True, children=node(filename) + node(f"{context} · {position} of 1:30"))
    return '<hierarchy>' + node("Continue Watching") + card + '</hierarchy>'


def preparation_anr(package=LAUNCHER_PACKAGE, underlying=PACKAGE):
    title = "Pixel Launcher" if package == LAUNCHER_PACKAGE else package
    xml = '<hierarchy>' + ''.join([
        node(f"{title} isn't responding", class_name="android.widget.TextView",
             extra='resource-id="android:id/alertTitle"'),
        node("Close app", clickable=True, class_name="android.widget.Button",
             extra='resource-id="android:id/aerr_close"'),
    ]).replace(f'package="{PACKAGE}"', 'package="android"') + '</hierarchy>'
    window = (f"mCurrentFocus=Window{{abc u0 Application Not Responding: {package}}}\n"
              f"mFocusedApp=ActivityRecord{{abc u0 {underlying}/.MainActivity t8}}")
    return xml, window


class PreparationAdb:
    def __init__(self, frames, *, qemu=b"1", serial="emulator-5554", tap_error=None):
        self.frames = iter(frames)
        self.qemu, self.serial, self.tap_error = qemu, serial, tap_error
        self.taps = []
        self.captures = 0

    def observe(self):
        return next(self.frames)

    def screenshot(self):
        self.captures += 1
        return (b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR"
                + (400).to_bytes(4, "big") + (500).to_bytes(4, "big"))

    def run(self, *arguments):
        if arguments == ("shell", "getprop", "ro.kernel.qemu"):
            return subprocess.CompletedProcess([], 0, self.qemu)
        if arguments[:3] == ("shell", "input", "tap"):
            self.taps.append(arguments)
            if self.tap_error:
                raise self.tap_error
            return subprocess.CompletedProcess([], 0, b"")
        raise AssertionError(f"Unexpected command: {arguments}")


def preparation_runner(root, adb):
    apk, fixture = root / "app.apk", root / FIXTURE_NAME
    apk.write_bytes(b"apk")
    fixture.write_bytes(b"fixture")
    runner = Runner("emulator-5554", apk, fixture, root)
    runner.adb = adb
    runner.observer.observe = adb.observe
    runner.phase = "01-fixture-review"
    return runner


class LifecycleRuntimeTests(unittest.TestCase):
    def test_native_recording_uses_even_proportional_dimensions(self):
        self.assertEqual(recording_size("Physical size: 1080x2400\n"), (720, 1600))
        self.assertEqual(recording_size("Physical size: 1080x2400\nOverride size: 1179x2556\n"), (720, 1560))
        self.assertEqual(recording_size("Physical size: 2560x1600\n"), (720, 450))
        for value in ("", "Physical size: 0x0", "Physical size: 1080x2400\nPhysical size: 720x1600"):
            with self.assertRaises(RuntimeFailure):
                recording_size(value)

    def test_native_recording_short_early_and_expired_segments_fail(self):
        validate_recording_duration(58, 60, False)
        for duration, elapsed, early in ((30, 60, False), (60, 60, True), (180, 182, False),
                                         (0, 10, False), (float("nan"), 10, False),
                                         (10, float("inf"), False)):
            with self.assertRaises(RuntimeFailure):
                validate_recording_duration(duration, elapsed, early)

    def test_recording_does_not_signal_a_changed_android_pid_owner(self):
        with tempfile.TemporaryDirectory() as directory:
            adb = Mock(remote_prefix="/sdcard/meowwatch-install-test/", remote_files=[])
            adb.run.return_value = subprocess.CompletedProcess([], 0, b"unrelated\0process\0")
            recording = LifecycleRecording(adb, Path(directory), 1, (720, 1600))
            recording.pid = "44"
            recording.process = Mock()
            recording.process.poll.return_value = None
            recording.metadata["startedAtMonotonic"] = 1.0
            with self.assertRaisesRegex(RuntimeFailure, "ownership changed"):
                recording.finish()
            self.assertEqual(recording.metadata["status"], "failed")
            self.assertFalse(any(call.args[:3] == ("shell", "kill", "-2") for call in adb.run.call_args_list))
            recording.process.terminate.assert_called_once()

    def test_existing_screen_recorder_is_not_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            adb = Mock(serial="emulator-5554", remote_prefix="/sdcard/meowwatch-install-test/", remote_files=[])
            adb.run.side_effect = [subprocess.CompletedProcess([], 0, b"1"),
                                   subprocess.CompletedProcess([], 0, b"44")]
            recording = LifecycleRecording(adb, Path(directory), 1, (720, 1600))
            with patch("tools.android_lifecycle_runtime.run.subprocess.Popen") as process:
                with self.assertRaisesRegex(RuntimeFailure, "existing Android screen recorder"):
                    recording.start()
            process.assert_not_called()
            self.assertEqual(adb.remote_files, [])

    def test_short_native_recording_is_retained_with_failure_and_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            adb = Mock(remote_prefix="/sdcard/meowwatch-install-test/", remote_files=[])
            recording = LifecycleRecording(adb, Path(directory), 1, (720, 1600))
            recording.output.parent.mkdir()
            media = b"ftyp" + b"x" * 5000 + b"moov"
            def command(*arguments, **_kwargs):
                if arguments == ("exec-out", "cat", "/proc/uptime"):
                    return subprocess.CompletedProcess([], 0, b"160.00 80.00\n")
                if arguments[:2] == ("exec-out", "cat"):
                    return subprocess.CompletedProcess([], 0, f"screenrecord\0{recording.remote}\0".encode())
                if arguments[0] == "pull":
                    recording.output.write_bytes(media)
                return subprocess.CompletedProcess([], 0, b"")
            adb.run.side_effect = command
            recording.process = Mock()
            recording.process.poll.side_effect = [None, 0]
            recording.process.wait.return_value = 0
            recording.pid = "44"
            recording.metadata["startedAtMonotonic"] = 0.0
            recording.metadata["mediaReadyAtDeviceElapsedSeconds"] = 100.0
            probe = {"streams": [{"codec_type": "video", "width": 720, "height": 1600, "duration": "20"}],
                     "format": {"duration": "20"}}
            with patch("tools.android_lifecycle_runtime.run.time.monotonic", return_value=60.0), patch(
                "tools.android_lifecycle_runtime.run.subprocess.run",
                return_value=subprocess.CompletedProcess([], 0, json.dumps(probe).encode()),
            ):
                with self.assertRaisesRegex(RuntimeFailure, "does not cover"):
                    recording.finish()
            self.assertEqual(recording.output.read_bytes(), media)
            self.assertEqual(recording.metadata["status"], "failed")
            self.assertEqual(recording.metadata["videoDurationSeconds"], 20)
            self.assertEqual(len(recording.metadata["sha256"]), 64)

    def test_media_readiness_requires_picture_payload_not_pid_or_container_header(self):
        ftyp = (24).to_bytes(4, "big") + b"ftyp" + b"isom" + b"\0" * 12
        free = (16).to_bytes(4, "big") + b"free" + b"\0" * 8
        mdat = (1).to_bytes(4, "big") + b"mdat" + b"\0" * 8
        nal = (5).to_bytes(4, "big") + b"\x65abcd"
        self.assertTrue(recording_media_ready(ftyp + free + mdat + nal))
        self.assertTrue(recording_media_ready(ftyp + b"\0\0\0\0mdat" + nal))
        for incomplete in (b"", ftyp, ftyp + free, ftyp + free + mdat,
                           ftyp + free + mdat + nal[:-1], ftyp + free + mdat + b"\0\0\0\0",
                           ftyp + free + mdat + (5).to_bytes(4, "big") + b"\x67abcd",
                           b"\0\0\0\0free"):
            with self.subTest(prefix=incomplete):
                self.assertFalse(recording_media_ready(incomplete))

    def test_device_elapsed_clock_rejects_missing_or_invalid_clock(self):
        self.assertEqual(recording_device_elapsed(b"66.58 72.04\n"), 66.58)
        for value in (b"", b"nan 0\n", b"inf 0\n", b"0.0 0.0\n", b"-1 0\n", b"12.3\n"):
            with self.subTest(clock=value), self.assertRaises(RuntimeFailure):
                recording_device_elapsed(value)

    def test_native_recording_accepts_android_metadata_and_uses_device_clock(self):
        with tempfile.TemporaryDirectory() as directory:
            adb = Mock(remote_prefix="/sdcard/meowwatch-install-test/", remote_files=[])
            recording = LifecycleRecording(adb, Path(directory), 1, (720, 1600))
            recording.output.parent.mkdir()
            media = b"ftyp" + b"x" * 5000 + b"moov"
            def command(*arguments, **_kwargs):
                if arguments == ("exec-out", "cat", "/proc/uptime"):
                    return subprocess.CompletedProcess([], 0, b"140.00 80.00\n")
                if arguments[:2] == ("exec-out", "cat"):
                    return subprocess.CompletedProcess([], 0, f"screenrecord\0{recording.remote}\0".encode())
                if arguments[0] == "pull":
                    recording.output.write_bytes(media)
                return subprocess.CompletedProcess([], 0, b"")
            adb.run.side_effect = command
            recording.process = Mock()
            recording.process.poll.side_effect = [None, 0]
            recording.process.wait.return_value = 0
            recording.pid = "44"
            recording.metadata.update({"startedAtMonotonic": 746.18454515,
                                       "mediaReadyAtDeviceElapsedSeconds": 67.0})
            probe = {"streams": [{"codec_type": "video", "width": 720, "height": 1600,
                                    "duration": "72.672067"},
                                   {"codec_type": "data"}, {"codec_type": "data"}],
                     "format": {"duration": "72.672067"}}
            with patch("tools.android_lifecycle_runtime.run.time.monotonic", return_value=825.194393661), patch(
                "tools.android_lifecycle_runtime.run.subprocess.run",
                side_effect=[subprocess.CompletedProcess([], 0, json.dumps(probe).encode()),
                             subprocess.CompletedProcess([], 0, b"", b"")],
            ):
                recording.finish()
            self.assertEqual(recording.metadata["status"], "verified")
            self.assertEqual(recording.metadata["measuredSegmentSeconds"], 73)
            self.assertAlmostEqual(recording.metadata["hostSegmentSeconds"], 79.009848511)
            self.assertEqual(recording.output.read_bytes(), media)

    def test_recording_start_waits_for_actual_picture_before_measuring(self):
        with tempfile.TemporaryDirectory() as directory:
            adb = Mock(serial="emulator-5554", prefix=["adb", "-s", "emulator-5554"],
                       remote_prefix="/sdcard/meowwatch-install-test/", remote_files=[])
            recording = LifecycleRecording(adb, Path(directory), 1, (720, 1600))
            prefixes = iter([b"\0\0\0\0mdat", b"\0\0\0\0mdat\0\0\0\x05\x65abcd"])
            def command(*arguments, **_kwargs):
                if arguments == ("shell", "getprop", "ro.kernel.qemu"):
                    return subprocess.CompletedProcess([], 0, b"1")
                if arguments == ("shell", "pidof", "screenrecord"):
                    return subprocess.CompletedProcess([], 0, b"")
                if arguments[:2] == ("exec-out", "head"):
                    self.assertNotIn("mediaReadyAtDeviceElapsedSeconds", recording.metadata)
                    return subprocess.CompletedProcess([], 0, next(prefixes))
                if arguments == ("exec-out", "cat", "/proc/uptime"):
                    return subprocess.CompletedProcess([], 0, b"67.00 30.00\n")
                raise AssertionError(arguments)
            adb.run.side_effect = command
            process = Mock(stdout=io.StringIO("LIFECYCLE_RECORDER_PID=44\n"))
            process.poll.return_value = None
            with patch("tools.android_lifecycle_runtime.run.subprocess.Popen", return_value=process), patch(
                "tools.android_lifecycle_runtime.run.time.monotonic", side_effect=[100, 101, 102, 103, 104],
            ), patch("tools.android_lifecycle_runtime.run.time.sleep"):
                recording.start()
            recording.reader.join(timeout=1)
            self.assertEqual(recording.metadata["pidObservedAtMonotonic"], 101)
            self.assertEqual(recording.metadata["startedAtMonotonic"], 104)
            self.assertEqual(recording.metadata["mediaReadyAtDeviceElapsedSeconds"], 67)

    def test_recording_start_fails_on_exit_or_missing_picture_without_restarting(self):
        for early in (True, False):
            with self.subTest(early=early), tempfile.TemporaryDirectory() as directory:
                adb = Mock(serial="emulator-5554", prefix=["adb", "-s", "emulator-5554"],
                           remote_prefix="/sdcard/meowwatch-install-test/", remote_files=[])
                adb.run.side_effect = [subprocess.CompletedProcess([], 0, b"1"),
                                       subprocess.CompletedProcess([], 0, b""),
                                       subprocess.CompletedProcess([], 0, b"\0\0\0\0mdat")]
                recording = LifecycleRecording(adb, Path(directory), 1, (720, 1600))
                process = Mock(stdout=io.StringIO("LIFECYCLE_RECORDER_PID=44\n"))
                process.poll.return_value = 1 if early else None
                with patch("tools.android_lifecycle_runtime.run.subprocess.Popen", return_value=process) as launch, patch(
                    "tools.android_lifecycle_runtime.run.time.monotonic", side_effect=[100, 101, 102, 121],
                ), patch("tools.android_lifecycle_runtime.run.time.sleep"):
                    with self.assertRaisesRegex(RuntimeFailure, "before media|no picture"):
                        recording.start()
                recording.reader.join(timeout=1)
                launch.assert_called_once()
                self.assertEqual(recording.metadata["status"], "failed")
                self.assertNotIn("startedAtMonotonic", recording.metadata)

    def test_recording_finish_rejects_invalid_video_decode_and_process_exit(self):
        video = {"codec_type": "video", "width": 720, "height": 1600, "duration": "10"}
        cases = [
            ([video, video], 0, 0, b"", "dimensions"),
            ([dict(video, width=1600)], 0, 0, b"", "dimensions"),
            ([dict(video, duration="nan")], 0, 0, b"", "does not cover"),
            ([dict(video, duration="0")], 0, 0, b"", "does not cover"),
            ([{"codec_type": "data"}], 0, 0, b"", "dimensions"),
            ([video, {"codec_type": "audio"}], 0, 0, b"", "dimensions"),
            ([video], 1, 0, b"", "exit successfully"),
            ([video], 0, 1, b"decode error", "decoded completely"),
            ([video], 0, 0, b"decode error", "decoded completely"),
        ]
        for streams, exit_code, decode_code, decode_error, error in cases:
            with self.subTest(streams=streams, exit=exit_code, decode=decode_error), tempfile.TemporaryDirectory() as directory:
                adb = Mock(remote_prefix="/sdcard/meowwatch-install-test/", remote_files=[])
                recording = LifecycleRecording(adb, Path(directory), 1, (720, 1600))
                recording.output.parent.mkdir()
                def command(*arguments, **_kwargs):
                    if arguments == ("exec-out", "cat", "/proc/uptime"):
                        return subprocess.CompletedProcess([], 0, b"20.00 10.00\n")
                    if arguments[:2] == ("exec-out", "cat"):
                        return subprocess.CompletedProcess([], 0, f"screenrecord\0{recording.remote}\0".encode())
                    if arguments[0] == "pull":
                        recording.output.write_bytes(b"ftyp" + b"x" * 5000 + b"moov")
                    return subprocess.CompletedProcess([], 0, b"")
                adb.run.side_effect = command
                recording.pid = "44"
                recording.process = Mock()
                recording.process.poll.side_effect = [None, 0]
                recording.process.wait.return_value = exit_code
                recording.metadata.update({"startedAtMonotonic": 0.0, "mediaReadyAtDeviceElapsedSeconds": 10.0})
                with patch("tools.android_lifecycle_runtime.run.time.monotonic", return_value=10.0), patch(
                    "tools.android_lifecycle_runtime.run.subprocess.run", side_effect=[
                        subprocess.CompletedProcess([], 0, json.dumps({"streams": streams}).encode()),
                        subprocess.CompletedProcess([], decode_code, b"", decode_error),
                    ],
                ):
                    with self.assertRaisesRegex(RuntimeFailure, error):
                        recording.finish()
                self.assertEqual(recording.metadata["status"], "failed")
                self.assertEqual(len(recording.metadata["sha256"]), 64)

    def test_missing_device_clock_still_stops_owned_recorder_and_keeps_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            adb = Mock(remote_prefix="/sdcard/meowwatch-install-test/", remote_files=[])
            recording = LifecycleRecording(adb, Path(directory), 1, (720, 1600))
            recording.output.parent.mkdir()
            def command(*arguments, **_kwargs):
                if arguments == ("exec-out", "cat", "/proc/uptime"):
                    return subprocess.CompletedProcess([], 0, b"invalid clock")
                if arguments[:2] == ("exec-out", "cat"):
                    return subprocess.CompletedProcess([], 0, f"screenrecord\0{recording.remote}\0".encode())
                if arguments[0] == "pull":
                    recording.output.write_bytes(b"ftyp" + b"x" * 5000 + b"moov")
                return subprocess.CompletedProcess([], 0, b"")
            adb.run.side_effect = command
            recording.pid = "44"
            recording.process = Mock()
            recording.process.poll.side_effect = [None, 0]
            recording.process.wait.return_value = 0
            with self.assertRaisesRegex(RuntimeFailure, "device elapsed clock"):
                recording.finish()
            self.assertTrue(any(call.args == ("shell", "kill", "-2", "44") for call in adb.run.call_args_list))
            self.assertEqual(recording.metadata["status"], "failed")
            self.assertEqual(len(recording.metadata["sha256"]), 64)

    def test_cleanup_failure_cannot_leave_a_successful_result(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk, fixture, output = root / "app.apk", root / FIXTURE_NAME, root / "evidence"
            apk.write_bytes(b"apk")
            fixture.write_bytes(b"fixture")
            def complete(runner):
                output.mkdir()
                runner.evidence_started = True
                return {"completed": True}
            with patch.object(Runner, "run", complete), patch.object(
                Runner, "cleanup", side_effect=RuntimeFailure("observer could not be removed"),
            ), redirect_stdout(io.StringIO()) as logged:
                status = main(["--serial", "emulator-5554", "--apk", str(apk),
                               "--fixture", str(fixture), "--output", str(output)])
            self.assertEqual(status, 1)
            self.assertNotIn("RUNTIME_PASS", logged.getvalue())
            self.assertFalse(json.loads((output / "result.json").read_text())["completed"])

    def test_initial_launcher_and_sdk_setup_recovery_requires_fresh_app_ui(self):
        for package in (LAUNCHER_PACKAGE, SETUP_PACKAGE):
            with self.subTest(package=package), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                anr = preparation_anr(package)
                app_frame = (player("0:00", "Play"), f"mCurrentFocus=Window{{abc {PACKAGE}/.MainActivity}}")
                adb = PreparationAdb([anr, anr, app_frame])
                runner = preparation_runner(root, adb)
                with patch("tools.android_lifecycle_runtime.run.time.sleep"):
                    xml, state = runner.wait("01-fixture-review", playback)
                self.assertEqual(state, Playback(0, 90, False))
                self.assertEqual(xml, app_frame[0])
                self.assertEqual(runner.last_window, app_frame[1])
                self.assertEqual(len(adb.taps), 1)
                self.assertEqual(runner.preparation_recoveries[0]["package"], package)
                self.assertEqual(runner.preparation_recoveries[0]["status"], "closed")
                for suffix in ("xml", "window.txt", "png", "fresh.xml", "fresh.window.txt"):
                    self.assertTrue((root / f"01-preparation-anr-1.{suffix}").is_file())

    def test_preparation_anr_recovery_never_runs_during_measured_phases(self):
        anr = preparation_anr()
        for phase in ("02-loaded-paused", "04-pre-home-playing", "05-foreground-paused",
                      "07-explicit-replay", "10-persisted-history", "11-resumed-paused"):
            with self.subTest(phase=phase), tempfile.TemporaryDirectory() as directory:
                adb = PreparationAdb([anr])
                runner = preparation_runner(Path(directory), adb)
                runner.phase = phase
                with self.assertRaisesRegex(RuntimeFailure, "not the focused"):
                    runner.observe()
                self.assertEqual(adb.taps, [])
                self.assertEqual(adb.captures, 0)
                self.assertEqual(runner.preparation_recoveries, [])

    def test_initial_recovery_refuses_app_anr_foreign_activity_and_changed_focus(self):
        anr = preparation_anr()
        app_anr = preparation_anr(PACKAGE)
        with tempfile.TemporaryDirectory() as directory:
            adb = PreparationAdb([app_anr])
            runner = preparation_runner(Path(directory), adb)
            self.assertFalse(runner.recover_preparation_anr(*app_anr))
            self.assertFalse(runner.recover_preparation_anr(*preparation_anr(underlying="com.other")))
            with self.assertRaisesRegex(RuntimeFailure, "changed before recovery"):
                runner.recover_preparation_anr(*anr)
            self.assertEqual(adb.taps, [])
            self.assertEqual(runner.last_window, app_anr[1])

    def test_initial_recovery_is_verified_emulator_only_and_combined_limit_two(self):
        launcher, setup = preparation_anr(), preparation_anr(SETUP_PACKAGE)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            adb = PreparationAdb([launcher, setup])
            runner = preparation_runner(root, adb)
            self.assertTrue(runner.recover_preparation_anr(*launcher))
            self.assertTrue(runner.recover_preparation_anr(*setup))
            with self.assertRaisesRegex(PreparationRecoveryFailure, "limit"):
                runner.recover_preparation_anr(*launcher)
            self.assertEqual(len(adb.taps), 2)
        for serial, qemu in (("physical-phone", b"1"), ("emulator-5554", b"0")):
            with tempfile.TemporaryDirectory() as directory:
                adb = PreparationAdb([], serial=serial, qemu=qemu)
                runner = preparation_runner(Path(directory), adb)
                with self.assertRaisesRegex(PreparationRecoveryFailure, "emulator-only"):
                    runner.recover_preparation_anr(*launcher)
                self.assertEqual(adb.taps, [])

    def test_uncertain_preparation_close_stops_without_repeating_tap(self):
        anr = preparation_anr()
        timeout = subprocess.TimeoutExpired(["adb", "shell", "input", "tap"], 20)
        with tempfile.TemporaryDirectory() as directory:
            adb = PreparationAdb([anr, anr], tap_error=timeout)
            runner = preparation_runner(Path(directory), adb)
            with self.assertRaisesRegex(PreparationRecoveryFailure, "refusing another tap"):
                runner.wait("01-fixture-review", playback)
            self.assertEqual(len(adb.taps), 1)
            self.assertEqual(runner.preparation_recoveries[0]["status"], "uncertain")
            self.assertEqual(runner.observation_timeouts, [])

    def test_initial_recovery_keeps_original_phase_deadline(self):
        anr = preparation_anr()
        clock = [0.0]
        class SlowRecoveryAdb(PreparationAdb):
            def run(self, *arguments):
                result = super().run(*arguments)
                if arguments[:3] == ("shell", "input", "tap"):
                    clock[0] = 66.0
                return result
        with tempfile.TemporaryDirectory() as directory:
            adb = SlowRecoveryAdb([anr, anr])
            runner = preparation_runner(Path(directory), adb)
            with patch("tools.android_lifecycle_runtime.run.time.monotonic", side_effect=lambda: clock[0]), patch(
                "tools.android_lifecycle_runtime.run.time.sleep",
            ):
                with self.assertRaisesRegex(RuntimeFailure, "awaiting fresh application UI"):
                    runner.wait("01-fixture-review", playback, timeout=65)
            self.assertEqual(len(adb.taps), 1)
            self.assertEqual(runner.samples, [])

    def test_failure_retains_last_window_and_recovery_provenance(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk, fixture, output = root / "app.apk", root / FIXTURE_NAME, root / "evidence"
            apk.write_bytes(b"apk")
            fixture.write_bytes(b"fixture")
            xml, window = preparation_anr()
            def failed_run(runner):
                output.mkdir()
                runner.evidence_started = True
                runner.last_xml, runner.last_window = xml, window
                runner.phase = "01-fixture-review"
                runner.preparation_recoveries.append({"attempt": 1, "status": "uncertain"})
                raise PreparationRecoveryFailure("unconfirmed close")
            with patch.object(Runner, "run", failed_run), patch(
                "tools.android_install.runner.Adb.screenshot", return_value=b"png",
            ), redirect_stdout(io.StringIO()):
                status = main(["--serial", "emulator-5554", "--apk", str(apk),
                               "--fixture", str(fixture), "--output", str(output)])
            self.assertEqual(status, 1)
            self.assertEqual((output / "failure-window.txt").read_text(), window)
            report = json.loads((output / "result.json").read_text())
            self.assertFalse(report["completed"])
            self.assertEqual(report["preparationAnrRecoveries"], [{"attempt": 1, "status": "uncertain"}])

    def test_actual_timeline_and_action_parse_together(self):
        self.assertEqual(playback(player()), Playback(12, 90, True))
        self.assertEqual(playback(player("0:00", "Play")), Playback(0, 90, False))
        self.assertEqual(playback(player(action="Pause together")), Playback(12, 90, True))

    def test_time_labels_are_strict_and_support_long_videos(self):
        self.assertEqual(parse_time("1:02:03"), 3723)
        for value in ["1:60", "-0:01", "0:5", "0:04 remaining", "", "1:99:03"]:
            with self.subTest(value=value):
                self.assertIsNone(parse_time(value))

    def test_play_button_or_screenshot_alone_cannot_establish_playback(self):
        original = player()
        for xml in [
            original.replace("android.widget.SeekBar", "android.view.View"),
            original.replace(FIXTURE_NAME, "other.mp4"),
            original.replace("1:30", "0:30"),
            original.replace('</hierarchy>', node("Play", clickable=True) + '</hierarchy>'),
            '<hierarchy>' + node("Pause", clickable=True) + '</hierarchy>',
        ]:
            with self.subTest(xml=xml), self.assertRaises(RuntimeFailure):
                playback(xml)

    def test_hidden_disabled_or_other_app_ui_cannot_pass(self):
        original = player()
        for xml in [original.replace('enabled="true"', 'enabled="false"'),
                    original.replace('visible-to-user="true"', 'visible-to-user="false"'),
                    original.replace(PACKAGE, "other.app"), '<broken']:
            with self.subTest(xml=xml), self.assertRaises(RuntimeFailure):
                playback(xml)

    def test_duplicate_or_disabled_actions_cannot_be_tapped(self):
        original = player()
        self.assertEqual(button(original, "Play", "Pause").get("text"), "Pause")
        for xml in [original.replace('</hierarchy>', node("Pause", clickable=True) + '</hierarchy>'),
                    original.replace('enabled="true"', 'enabled="false"')]:
            with self.assertRaises(RuntimeFailure):
                button(xml, "Play", "Pause")

    def test_play_state_without_progress_is_a_failure(self):
        self.assertEqual(require_playing_advance(Playback(5, 90, True), Playback(8, 90, True)), 3)
        for after in [Playback(5, 90, True), Playback(6, 90, True), Playback(9, 90, False)]:
            with self.assertRaises(RuntimeFailure):
                require_playing_advance(Playback(5, 90, True), after)

    def test_home_requires_real_hold_pause_and_limited_position_delta(self):
        before = Playback(10, 90, True)
        require_background_pause(before, Playback(12, 90, False), 8)
        for after, elapsed in [(Playback(12, 90, False), 7.9),
                               (Playback(18, 90, False), 8),
                               (Playback(10, 90, True), 8),
                               (Playback(0, 90, False), 8)]:
            with self.subTest(after=after, elapsed=elapsed), self.assertRaises(RuntimeFailure):
                require_background_pause(before, after, elapsed)

    def test_fresh_pre_home_sample_excludes_foreground_capture_delay(self):
        stale_screenshot_sample = Playback(17, 90, True)
        immediate_pre_home_sample = Playback(26, 90, True)
        foreground = Playback(26, 90, False)
        with self.assertRaises(RuntimeFailure):
            require_background_pause(stale_screenshot_sample, foreground, 8)
        require_background_pause(immediate_pre_home_sample, foreground, 8)

    def test_home_refreshes_playback_after_screenshot_before_keyevent(self):
        events = []

        class FakeAdb:
            def run(self, *arguments, **_kwargs):
                events.append(("adb", arguments))
                if arguments[:3] == ("shell", "dumpsys", "window"):
                    return type(
                        "Result",
                        (),
                        {
                            "stdout": (
                                b"mCurrentFocus=Window{abc "
                                b"com.google.android.apps.nexuslauncher/"
                                b".NexusLauncherActivity}\n"
                            ),
                        },
                    )()
                return type("Result", (), {"stdout": b""})()

            def screenshot(self):
                events.append(("screenshot", ()))
                return b"png"

        class HomeRunner(Runner):
            def sample(self, phase, *, playing, screenshot=True):
                events.append(("sample", (phase, playing, screenshot)))
                self.phase = phase
                return player("0:26", "Pause"), Playback(26, 90, True)

        with tempfile.TemporaryDirectory() as directory, patch(
            "tools.android_lifecycle_runtime.run.time.sleep",
        ):
            runner = HomeRunner.__new__(HomeRunner)
            runner.adb = FakeAdb()
            runner.output = Path(directory)
            runner.phase = "04-advanced"
            elapsed, state = runner.go_home(
                pre_home_phase="04-pre-home-playing",
                playing=True,
            )

        self.assertEqual(state, Playback(26, 90, True))
        self.assertGreaterEqual(elapsed, 0)
        self.assertEqual(events[0], ("sample", ("04-pre-home-playing", True, False)))
        self.assertEqual(
            events[1],
            ("adb", ("shell", "input", "keyevent", "KEYCODE_HOME")),
        )
        self.assertEqual(events[-1], ("screenshot", ()))

    def test_home_baseline_arguments_must_be_paired(self):
        runner = Runner.__new__(Runner)
        with self.assertRaises(ValueError):
            runner.go_home(pre_home_phase="04-pre-home-playing")
        with self.assertRaises(ValueError):
            runner.go_home(playing=True)

    def test_observation_timeout_retries_fresh_xml_without_accepting_old_sample(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk, fixture = root / "app.apk", root / FIXTURE_NAME
            apk.write_bytes(b"apk")
            fixture.write_bytes(b"fixture")
            runner = Runner("emulator-5554", apk, fixture, root)
            runner.observer.installed = True
            runner.last_xml = player("0:03", "Pause")
            dump_commands = []
            observed_xml = '<hierarchy>' + native_node(
                player("0:20", "Pause").removeprefix('<hierarchy>').removesuffix('</hierarchy>'),
                text='', clickable='false',
            ) + '</hierarchy>'
            observed_xml = observed_xml.replace('content-desc="" package=',
                                                'content-desc="" resource-id="" scrollable="false" package=')

            def native_command(command, **_kwargs):
                arguments = command[3:]
                if arguments[:3] == ["shell", "pidof", PACKAGE]:
                    return subprocess.CompletedProcess(command, 0, b"123", b"")
                if arguments[:3] == ["shell", "am", "instrument"]:
                    dump_commands.append(command)
                    if len(dump_commands) == 1:
                        raise subprocess.TimeoutExpired(command, 10)
                    return subprocess.CompletedProcess(command, 0,
                                                       native_response(observed_xml, nonce=arguments[7]), b"")
                if arguments == ["shell", "am", "force-stop", OBSERVER_PACKAGE]:
                    return subprocess.CompletedProcess(command, 0, b"", b"")
                if arguments[:4] == ["shell", "dumpsys", "window", "displays"]:
                    window = f"mCurrentFocus=Window{{abc {PACKAGE}/.MainActivity}}\n".encode()
                    return subprocess.CompletedProcess(command, 0, window, b"")
                self.fail(f"Unexpected observation command: {arguments[:3]}")

            with patch("tools.android_install.runner.subprocess.run", side_effect=native_command), patch(
                "tools.android_lifecycle_runtime.run.time.sleep",
            ):
                xml, state = runner.sample("04-advanced", playing=True, screenshot=False)

            self.assertEqual(state, Playback(20, 90, True))
            self.assertEqual(xml, observed_xml)
            self.assertEqual(len(dump_commands), 2)
            self.assertNotEqual(dump_commands[0][-2], dump_commands[1][-2])
            self.assertEqual([item["position_seconds"] for item in runner.samples], [20])
            self.assertEqual(runner.observation_timeouts[0]["operation"], "native accessibility snapshot")
            self.assertEqual(len(runner.observer.observations), 1)
            self.assertEqual(runner.observation_timeouts[0]["phase"], "04-advanced")
            self.assertEqual(runner.last_observation["phase"], "04-advanced")

    def test_observer_integrity_failure_is_not_retried_into_a_false_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk, fixture = root / "app.apk", root / FIXTURE_NAME
            apk.write_bytes(b"apk")
            fixture.write_bytes(b"fixture")
            runner = Runner("emulator-5554", apk, fixture, root)
            with patch.object(runner.observer, "observe", side_effect=[
                ObserverIntegrityFailure("application process changed during native UI capture"),
                (player(), f"mCurrentFocus=Window{{abc {PACKAGE}/.MainActivity}}"),
            ]) as observe:
                with self.assertRaisesRegex(ObserverIntegrityFailure, "process changed"):
                    runner.sample("03-playing", playing=True)
            self.assertEqual(observe.call_count, 1)
            self.assertEqual(runner.samples, [])

    def test_fresh_snapshot_still_requires_exact_production_window_focus(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk, fixture = root / "app.apk", root / FIXTURE_NAME
            apk.write_bytes(b"apk")
            fixture.write_bytes(b"fixture")
            runner = Runner("emulator-5554", apk, fixture, root)
            runner.phase = "03-playing"
            with patch.object(runner.observer, "observe", return_value=(
                player(), f"mCurrentFocus=Window{{abc {OBSERVER_PACKAGE}/.Activity}}",
            )):
                with self.assertRaisesRegex(RuntimeFailure, "not the focused"):
                    runner.observe()
            self.assertEqual(runner.samples, [])

    def test_repeated_ui_timeouts_fail_without_a_playback_sample(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk, fixture = root / "app.apk", root / FIXTURE_NAME
            apk.write_bytes(b"apk")
            fixture.write_bytes(b"fixture")
            runner = Runner("emulator-5554", apk, fixture, root)
            runner.last_xml = player("0:03", "Pause")
            timeout = subprocess.TimeoutExpired(
                ["adb", "-s", "emulator-5554", "shell", "uiautomator", "dump"], 10,
            )
            with patch.object(runner, "observe", side_effect=timeout) as observe, patch(
                "tools.android_lifecycle_runtime.run.time.sleep",
            ):
                with self.assertRaisesRegex(RuntimeFailure, "04-advanced.*3 attempts"):
                    runner.sample("04-advanced", playing=True, screenshot=False)
            self.assertEqual(observe.call_count, 3)
            self.assertEqual(runner.samples, [])
            self.assertEqual(len(runner.observation_timeouts), 3)
            self.assertFalse((root / "04-advanced.xml").exists())

    def test_timeout_retry_keeps_original_phase_deadline(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk, fixture = root / "app.apk", root / FIXTURE_NAME
            apk.write_bytes(b"apk")
            fixture.write_bytes(b"fixture")
            runner = Runner("emulator-5554", apk, fixture, root)
            clock = [0.0]

            def expired_observation():
                clock[0] = 46.0
                raise subprocess.TimeoutExpired(["adb", "-s", "emulator-5554", "exec-out", "cat"], 10)

            with patch.object(runner, "observe", side_effect=expired_observation) as observe, patch(
                "tools.android_lifecycle_runtime.run.time.monotonic", side_effect=lambda: clock[0],
            ), patch("tools.android_lifecycle_runtime.run.time.sleep"):
                with self.assertRaisesRegex(RuntimeFailure, "UI hierarchy transfer timed out"):
                    runner.wait("04-advanced", playback, timeout=45)
            self.assertEqual(observe.call_count, 1)

    def test_action_timeout_is_not_retried_as_an_observation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk, fixture = root / "app.apk", root / FIXTURE_NAME
            apk.write_bytes(b"apk")
            fixture.write_bytes(b"fixture")
            runner = Runner("emulator-5554", apk, fixture, root)
            taps = []

            def action(_xml):
                taps.append("tap")
                raise subprocess.TimeoutExpired(["adb", "shell", "input", "tap"], 25)

            with patch.object(runner, "observe", return_value=player()) as observe:
                with self.assertRaises(subprocess.TimeoutExpired):
                    runner.wait("01-fixture-review", action)
            self.assertEqual(taps, ["tap"])
            self.assertEqual(observe.call_count, 1)
            self.assertEqual(runner.observation_timeouts, [])

    def test_observation_timeout_diagnostics_never_include_raw_payloads(self):
        for command in ["adb secret-private-data", ["adb", "-s", "emulator-5554", "shell", "private-value"]]:
            self.assertEqual(timed_out_observation(subprocess.TimeoutExpired(command, 10)),
                             "Android UI observation")

    def test_paused_controls_with_advancing_position_still_fail(self):
        before = Playback(20, 90, False)
        require_paused_stability(before, Playback(20, 90, False))
        for after in [Playback(24, 90, False), Playback(20, 90, True), Playback(0, 90, False)]:
            with self.assertRaises(RuntimeFailure):
                require_paused_stability(before, after)

    def test_restart_requires_same_saved_position_and_no_autoplay(self):
        saved = Playback(19, 90, False)
        require_restored_position(saved, Playback(20, 90, False))
        for restored in [Playback(0, 90, False), Playback(22, 90, False), Playback(19, 90, True)]:
            with self.assertRaises(RuntimeFailure):
                require_restored_position(saved, restored)

    def test_history_must_bind_filename_and_position_to_one_clickable_card(self):
        card, position = history_card(history())
        self.assertEqual(position, 19)
        self.assertEqual(card.get("clickable"), "true")
        self.assertEqual(len(list(card)), 2)
        for xml in [history(filename="different.mp4"), history(context="Room example"),
                    history().replace("1:30", "2:30"),
                    history().replace('clickable="true"', 'clickable="false"'),
                    history().replace('visible-to-user="true"', 'visible-to-user="false"'),
                    history().replace('</hierarchy>', history()[len('<hierarchy>'):-len('</hierarchy>')] + '</hierarchy>')]:
            with self.subTest(xml=xml), self.assertRaises(RuntimeFailure):
                history_card(xml)

    def test_split_history_metadata_does_not_match_an_unrelated_card(self):
        xml = '<hierarchy>' + node('Continue Watching') + node(FIXTURE_NAME, clickable=True)
        xml += node('Local player · 0:19 of 1:30', clickable=True) + '</hierarchy>'
        with self.assertRaises(RuntimeFailure):
            history_card(xml)

    def test_scroll_coordinates_come_only_from_unique_visible_container(self):
        scroll = node(extra='scrollable="true"')
        xml = '<hierarchy>' + scroll + '</hierarchy>'
        self.assertEqual(history_swipe(xml), (160, 300, 160, 140))
        for invalid in [xml.replace('scrollable="true"', 'scrollable="false"'),
                        xml.replace('visible-to-user="true"', 'visible-to-user="false"'),
                        xml.replace('</hierarchy>', scroll + '</hierarchy>')]:
            with self.assertRaises(RuntimeFailure):
                history_swipe(invalid)

    def test_runner_rejects_physical_device_before_adb_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk, fixture = root / 'app.apk', root / FIXTURE_NAME
            apk.write_bytes(b'apk')
            fixture.write_bytes(b'fixture')
            with self.assertRaises(ValueError):
                Runner('physical-phone', apk, fixture, root / 'evidence')

    def test_reused_evidence_directory_is_rejected_without_overwriting_it(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk, fixture, evidence = root / 'app.apk', root / FIXTURE_NAME, root / 'evidence'
            apk.write_bytes(b'apk')
            fixture.write_bytes(b'fixture')
            evidence.mkdir()
            result = evidence / 'result.json'
            result.write_text('previous evidence', encoding='utf-8')
            with redirect_stdout(io.StringIO()):
                status = main(['--serial', 'emulator-5554', '--apk', str(apk),
                               '--fixture', str(fixture), '--output', str(evidence)])
            self.assertEqual(status, 1)
            self.assertEqual(result.read_text(encoding='utf-8'), 'previous evidence')
            self.assertEqual(list(evidence.iterdir()), [result])


if __name__ == '__main__':
    unittest.main()
