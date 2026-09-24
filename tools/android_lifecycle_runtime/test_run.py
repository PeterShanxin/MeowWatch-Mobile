from pathlib import Path
from contextlib import redirect_stdout
import io
import hashlib
import json
import subprocess
import struct
import tempfile
import unittest
from unittest.mock import Mock, patch
from xml.sax.saxutils import escape

from tools.android_install.runner import PACKAGE, RuntimeFailure
from tools.android_lifecycle_runtime.run import (
    FIXTURE_NAME, LifecycleRecording, Playback, PreparationRecoveryFailure, Runner, button, history_card, history_swipe, main,
    parse_time, playback, require_background_pause, require_paused_stability,
    require_playing_advance, require_restored_position, timed_out_observation,
    RecordingPictures, recording_device_elapsed, recording_frame_clock, recording_media_ready,
    recording_size, require_recorded_observation, validate_recording_duration,
    MAX_RECORDING_BYTES, MAX_FILE_QUERY_BYTES, MAX_LIVE_READ_SUMMARIES,
)
from tools.billing_runtime.native_dialog import LAUNCHER_PACKAGE, SETUP_PACKAGE
from tools.android_native_ui.observer import OBSERVER_PACKAGE, ObserverIntegrityFailure, ObserverTimeout
from tools.android_native_ui.test_observer import node as native_node, response as native_response


def node(label="", *, children="", clickable=False, extra="", class_name="android.view.View"):
    return (f'<node text="{escape(label)}" content-desc="" package="{PACKAGE}" '
            f'clickable="{str(clickable).lower()}" enabled="true" visible-to-user="true" '
            f'class="{class_name}" bounds="[10,20][310,420]" {extra}>{children}</node>')


def box(kind, payload):
    return struct.pack('>I', 8 + len(payload)) + kind + payload


def clock_media(times, *, version=2, count=None, duplicate=False):
    metadata = (b'#VV1NSC0PET1ME2#' + struct.pack('<IqI', version, 1789647215000000000,
                len(times) if count is None else count)
                + struct.pack(f'<{len(times)}Q', *(round(value * 1e9) for value in times)))
    return (box(b'ftyp', b'isom' + bytes(12)) + box(b'mdat', bytes(5000) + metadata * (2 if duplicate else 1))
            + box(b'moov', b''))


def device_file_response(arguments, remote, media):
    if arguments == ('exec-out', 'stat', '-c', '%s', remote):
        return subprocess.CompletedProcess([], 0, f'{len(media)}\n'.encode(), b'')
    if arguments == ('exec-out', 'sha256sum', remote):
        return subprocess.CompletedProcess([], 0, f'{hashlib.sha256(media).hexdigest()}  {remote}\n'.encode(), b'')
    return None


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

    def observe(self, *, deadline=None):
        return next(self.frames)

    def screenshot(self, *, timeout=25):
        self.captures += 1
        return (b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR"
                + (400).to_bytes(4, "big") + (500).to_bytes(4, "big"))

    def run(self, *arguments, **kwargs):
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
    def test_unwritable_storage_retains_diagnostics_and_cleans_only_owned_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'app.apk').write_bytes(b'never installed')
            (root / FIXTURE_NAME).write_bytes(b'never opened')
            runner = Runner('emulator-5554', root / 'app.apk', root / FIXTURE_NAME, root / 'evidence')
            commands = []

            def run(*arguments, **kwargs):
                commands.append(arguments)
                if arguments == ('get-state',):
                    return subprocess.CompletedProcess([], 0, b'device\n', b'')
                if arguments == ('shell', 'getprop', 'ro.kernel.qemu'):
                    return subprocess.CompletedProcess([], 0, b'1\n', b'')
                if arguments[:3] == ('shell', 'test', '-e'):
                    return subprocess.CompletedProcess([], 1, b'', b'')
                if arguments[:2] in (('shell', 'mkdir'), ('shell', 'rmdir')) or arguments[:3] == ('shell', 'rm', '-f'):
                    return subprocess.CompletedProcess([], 0, b'', b'')
                if arguments[:2] == ('shell', 'touch'):
                    return subprocess.CompletedProcess([], 1, b'', b'external_primary not ready')
                raise AssertionError(f'Unexpected command: {arguments}')

            with patch.object(runner.adb, 'run', side_effect=run), patch(
                'tools.android_install.runner.time.monotonic', side_effect=[0, 0, 0, 21]
            ), patch('tools.android_install.runner.time.sleep'):
                with self.assertRaisesRegex(RuntimeFailure, 'not writable within 20 seconds'):
                    runner.prepare()
                self.assertTrue(runner.adb.remote_root_created)
                self.assertFalse(runner.cleanup_authorized)
                self.assertIn('external_primary not ready', (runner.output / 'storage-readiness.log').read_text())
                runner.cleanup()
            self.assertIn(('shell', 'rmdir', runner.adb.remote_root), commands)
            self.assertFalse(any(row[:2] in (('install', '-t'), ('shell', 'am'), ('shell', 'pm')) for row in commands))

    def test_winscope_clock_matches_actual_frames_with_muxer_rounding(self):
        times = [62.507731899, 64.321667899, 123.391883899]
        self.assertEqual(recording_frame_clock(clock_media(times), [0, 1.813933, 60.884156]), times)
        for media, pts in (
            (box(b'ftyp', bytes(12)) + box(b'mdat', bytes(80)), [0]),
            (clock_media(times, version=3), [0, 1.813933, 60.884156]),
            (clock_media(times, count=4), [0, 1.813933, 60.884156]),
            (clock_media(times, duplicate=True), [0, 1.813933, 60.884156]),
            (clock_media(times)[:-1], [0, 1.813933, 60.884156]),
            (clock_media([10, 9]), [0, 1]),
            (clock_media([0, 1]), [0, 1]),
            (clock_media([10, 11]), [0, 2]),
            (clock_media([10, 11]), [0, float('nan')]),
        ):
            with self.subTest(pts=pts), self.assertRaises(RuntimeFailure):
                recording_frame_clock(media, pts)

    def test_actual_frame_clock_rejects_observation_beyond_last_picture(self):
        # Run 35219098578: its last real video frame precedes 04-advanced.
        times = [62.507731899, 123.391883899]
        with self.assertRaisesRegex(RuntimeFailure, 'final required device observation'):
            require_recorded_observation(times, 125.929, 130.79)
        require_recorded_observation([62.5, 133.0], 130.79, 138.8)
        for required in (float('nan'), 0, 61, 134):
            with self.subTest(required=required), self.assertRaises(RuntimeFailure):
                require_recorded_observation(times, required, 130.79)
        # Post-roll never narrows the original ready-to-stop coverage gate.
        with self.assertRaises(RuntimeFailure):
            validate_recording_duration(61.237922, 65.02, False)

    def test_incremental_picture_progress_rejects_headers_and_partial_nals(self):
        pictures = RecordingPictures()
        prefix = box(b'ftyp', b'isom' + bytes(12)) + b'\0\0\0\0mdat'
        nal = struct.pack('>I', 5) + b'\x65abcd'
        pictures.feed(prefix + nal[:-1])
        self.assertEqual(pictures.picture_ends, [])
        pictures.feed(nal[-1:] + struct.pack('>I', 5) + b'\x67abcd')
        self.assertEqual(pictures.picture_ends, [len(prefix) + len(nal)])
        pictures.feed(nal)
        self.assertEqual(len(pictures.picture_ends), 2)
        self.assertEqual(pictures.read_bytes, len(prefix) + 3 * len(nal))
        with self.assertRaises(RuntimeFailure):
            RecordingPictures().feed(b'\0\0\0\0free')

    def test_post_roll_is_bounded_and_requires_new_complete_picture_data(self):
        for advances in (True, False):
            with self.subTest(advances=advances), tempfile.TemporaryDirectory() as directory:
                clock = [0.0]
                prefix = box(b'ftyp', b'isom' + bytes(12)) + b'\0\0\0\0mdat'
                nal = struct.pack('>I', 5) + b'\x65abcd'
                initial = prefix + nal
                chunks = [initial, nal if advances else b'']
                adb = Mock(remote_prefix='/sdcard/meowwatch-install-test/', remote_files=[])
                commands = []
                def run(*arguments, **kwargs):
                    clock[0] += 0.2
                    if arguments == ('exec-out', 'cat', '/proc/uptime'):
                        return subprocess.CompletedProcess([], 0, b'130.79 20.00\n')
                    if arguments[:3] == ('shell', 'stat', '-c'):
                        return subprocess.CompletedProcess([], 0, str(len(initial)).encode())
                    commands.append((arguments, kwargs))
                    return subprocess.CompletedProcess([], 0, chunks.pop(0) if chunks else b'')
                adb.run.side_effect = run
                recording = LifecycleRecording(adb, Path(directory), 1, (720, 1600))
                recording.process = Mock()
                recording.process.poll.return_value = None
                with patch('tools.android_lifecycle_runtime.run.time.monotonic', side_effect=lambda: clock[0]), patch(
                    'tools.android_lifecycle_runtime.run.time.sleep', side_effect=lambda delay: clock.__setitem__(0, clock[0] + delay)
                ):
                    if advances:
                        recording.post_roll('04-advanced')
                    else:
                        with self.assertRaisesRegex(RuntimeFailure, 'no new complete picture'):
                            recording.post_roll('04-advanced')
                self.assertLessEqual(clock[0], 8.21)
                self.assertEqual(recording.metadata['requiredThroughDeviceElapsedSeconds'], 130.79)
                self.assertEqual(recording.metadata['postRoll']['newCompletePictureNals'], int(advances))
                self.assertIn('tail -c +1 ', commands[0][0][-1])
                self.assertIn(f'tail -c +{len(initial) + 1} ', commands[1][0][-1])
                self.assertTrue(all(call[1]['timeout'] <= 2 for call in commands))
                reads = recording.metadata['postRoll']['readSummaries']
                self.assertEqual(reads[0]['offset'], 0)
                self.assertEqual(reads[0]['bytes'], len(initial))
                self.assertEqual(reads[0]['sha256'], hashlib.sha256(initial).hexdigest())
                self.assertEqual(reads[1]['offset'], len(initial))
                complete = initial + (nal if advances else b'')
                self.assertEqual(reads[-1]['prefixBytes'], len(complete))
                self.assertEqual(reads[-1]['prefixSha256'], hashlib.sha256(complete).hexdigest())
                self.assertEqual(reads[-1]['lastCompletePictureEnd'], len(complete))
                self.assertTrue(all(row['finishedAtMonotonic'] >= row['startedAtMonotonic'] for row in reads))

    def test_post_roll_retries_timeouts_without_accepting_partial_or_late_bytes(self):
        for mode in ('recover', 'all-timeout', 'late-success'):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                clock = [0.0]
                prefix = box(b'ftyp', b'isom' + bytes(12)) + b'\0\0\0\0mdat'
                nal = struct.pack('>I', 5) + b'\x65abcd'
                initial = prefix + nal
                reads = []
                adb = Mock(remote_prefix='/sdcard/meowwatch-install-test/', remote_files=[])

                def run(*arguments, **kwargs):
                    if arguments == ('exec-out', 'cat', '/proc/uptime'):
                        return subprocess.CompletedProcess([], 0, b'130.79 20.00\n')
                    if arguments[:3] == ('shell', 'stat', '-c'):
                        clock[0] += 0.2
                        return subprocess.CompletedProcess([], 0, str(len(initial)).encode())
                    reads.append((arguments[-1], kwargs['timeout']))
                    if len(reads) == 1 or mode == 'all-timeout':
                        clock[0] += kwargs['timeout']
                        raise subprocess.TimeoutExpired('adb', kwargs['timeout'], output=initial[:-1])
                    if mode == 'late-success':
                        clock[0] = 8.01
                        return subprocess.CompletedProcess([], 0, initial + nal)
                    clock[0] += min(0.1, 8 - clock[0])
                    return subprocess.CompletedProcess([], 0, initial + nal if len(reads) == 2 else b'')

                adb.run.side_effect = run
                recording = LifecycleRecording(adb, Path(directory), 1, (720, 1600))
                recording.process = Mock()
                recording.process.poll.return_value = None
                with patch('tools.android_lifecycle_runtime.run.time.monotonic', side_effect=lambda: clock[0]), patch(
                    'tools.android_lifecycle_runtime.run.time.sleep', side_effect=lambda delay: clock.__setitem__(0, clock[0] + delay)
                ):
                    if mode == 'recover':
                        recording.post_roll('04-advanced')
                    else:
                        expected = 'no new complete picture' if mode == 'all-timeout' else 'original deadline'
                        with self.assertRaisesRegex(RuntimeFailure, expected):
                            recording.post_roll('04-advanced')
                self.assertEqual(reads[0][0], reads[1][0], 'retry must reread the identical byte range')
                self.assertTrue(all(0 < timeout <= 2 for _, timeout in reads))
                summary = recording.metadata['postRoll']['readSummaries']
                self.assertEqual(summary[0]['acceptedBytes'], 0)
                self.assertEqual(summary[0]['discardedBytes'], len(initial) - 1)
                if mode == 'recover':
                    self.assertEqual(recording.metadata['postRoll']['newCompletePictureNals'], 1)
                    self.assertEqual(summary[1]['offset'], 0)
                    self.assertEqual(summary[1]['prefixBytes'], len(initial + nal))
                    self.assertEqual(summary[1]['prefixSha256'], hashlib.sha256(initial + nal).hexdigest())
                    self.assertLessEqual(clock[0], 8)
                elif mode == 'all-timeout':
                    self.assertEqual(recording.metadata['postRoll']['newCompletePictureNals'], 0)
                    self.assertEqual(clock[0], 8)
                else:
                    self.assertEqual(len(summary), 1, 'late successful bytes must not enter evidence')

    def test_final_coverage_and_post_roll_failures_keep_original_recording(self):
        for required, post_error, missing_clock, error_message in (
            (19.8, False, False, None),
            (19.9, False, False, 'final required device observation'),
            (19.8, True, False, 'post-roll failed'),
            (19.8, False, True, 'frame-clock evidence'),
        ):
            with self.subTest(required=required, post_error=post_error, missing=missing_clock), tempfile.TemporaryDirectory() as directory:
                adb = Mock(remote_prefix='/sdcard/meowwatch-install-test/', remote_files=[])
                recording = LifecycleRecording(adb, Path(directory), 1, (720, 1600))
                recording.output.parent.mkdir()
                media = clock_media([10, 19.8]) if not missing_clock else box(b'ftyp', bytes(12)) + box(b'mdat', bytes(5000)) + box(b'moov', b'')
                def run(*arguments, **kwargs):
                    receipt = device_file_response(arguments, recording.remote, media)
                    if receipt is not None:
                        return receipt
                    if arguments == ('exec-out', 'cat', '/proc/uptime'):
                        return subprocess.CompletedProcess([], 0, b'20.0 0.0\n')
                    if arguments[:2] == ('exec-out', 'cat'):
                        return subprocess.CompletedProcess([], 0, f'screenrecord\0{recording.remote}\0'.encode())
                    if arguments[0] == 'pull':
                        recording.output.write_bytes(media)
                    return subprocess.CompletedProcess([], 0, b'')
                def post_roll(phase):
                    recording.metadata['requiredThroughDeviceElapsedSeconds'] = required
                    if post_error:
                        raise RuntimeFailure('no new complete picture during bounded post-roll')
                adb.run.side_effect = run
                recording.pid = '44'
                recording.process = Mock()
                recording.process.poll.side_effect = [None, 0]
                recording.process.wait.return_value = 0
                recording.metadata.update({'startedAtMonotonic': 0.0, 'mediaReadyAtDeviceElapsedSeconds': 10.0})
                probe = {'streams': [{'codec_type': 'video', 'width': 720, 'height': 1600, 'duration': '10'}],
                         'frames': [{'media_type': 'video', 'pts_time': '0'}, {'media_type': 'video', 'pts_time': '9.8'}]}
                with patch.object(recording, 'post_roll', side_effect=post_roll), patch(
                    'tools.android_lifecycle_runtime.run.subprocess.run', side_effect=[
                        subprocess.CompletedProcess([], 0, json.dumps(probe).encode()),
                        subprocess.CompletedProcess([], 0, b'', b''),
                    ]
                ):
                    if error_message:
                        with self.assertRaisesRegex(RuntimeFailure, error_message):
                            recording.finish(required_phase='04-advanced')
                    else:
                        recording.finish(required_phase='04-advanced')
                self.assertEqual(recording.output.read_bytes(), media)
                self.assertEqual(len(recording.metadata['sha256']), 64)
                self.assertEqual(recording.metadata['decodeExitCode'], 0)
                self.assertEqual(recording.metadata['status'], 'failed' if error_message else 'verified')
                if not missing_clock:
                    self.assertEqual(recording.metadata['lastFrameDeviceElapsedSeconds'], 19.8)
                    self.assertTrue(recording.output.with_suffix('.frame-clock.json').is_file())

    def test_runner_binds_required_phase_to_recording_and_cleans_up_without_post_roll(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk, fixture = root / 'app.apk', root / FIXTURE_NAME
            apk.write_bytes(b'apk')
            fixture.write_bytes(b'fixture')
            runner = Runner('emulator-5554', apk, fixture, root)
            recording = Mock()
            runner.recording = recording
            runner.finish_recording(required_phase='14-restored-play-advanced')
            recording.finish.assert_called_once_with(required_phase='14-restored-play-advanced')
            self.assertIsNone(runner.recording)
            runner.recording = Mock()
            recording = runner.recording
            runner.finish_recording()
            recording.finish.assert_called_once_with(required_phase=None)

    def test_restart_manual_play_follows_stability_and_requires_real_advancement(self):
        for failure in (None, 'autoplay', 'paused-progress', 'no-progress', 'changed-pid'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                apk, fixture = root / 'app.apk', root / FIXTURE_NAME
                apk.write_bytes(b'apk')
                fixture.write_bytes(b'fixture')
                runner = Runner('emulator-5554', apk, fixture, root)
                runner.adb = Mock()
                runner.adb.screenshot.return_value = b'original screenshot'
                runner.prepare = Mock(return_value={})
                runner.load_fixture = Mock()
                runner.start_recording = Mock()
                runner.finish_recording = Mock()
                runner.launch_main = Mock()
                runner.go_home = Mock(side_effect=[(8, Playback(10, 90, True)), (8, None)])
                runner.pid = Mock(side_effect=['123', '123', '123', '', '456',
                                              '789' if failure == 'changed-pid' else '456'])
                history_xml = history(position='0:16')
                runner.wait_history = Mock(return_value=(history_xml, history_card(history_xml)))
                events = []
                states = {
                    '02-loaded-paused': Playback(0, 90, False),
                    '03-playing': Playback(2, 90, True),
                    '04-advanced': Playback(6, 90, True),
                    '05-foreground-paused': Playback(10, 90, False),
                    '06-no-autoplay': Playback(10, 90, False),
                    '07-explicit-replay': Playback(11, 90, True),
                    '08-replay-advanced': Playback(15, 90, True),
                    '09-saved-paused': Playback(16, 90, False),
                    '11-resumed-paused': Playback(16, 90, False),
                    '12-restored-no-autoplay': Playback(19 if failure == 'paused-progress' else 16,
                                                      90, failure == 'autoplay'),
                    '13-restored-explicit-play': Playback(17, 90, True),
                    '14-restored-play-advanced': Playback(17 if failure == 'no-progress' else 21, 90, True),
                }
                def sample(phase, **kwargs):
                    runner.phase = phase
                    events.append(('sample', phase, kwargs['playing']))
                    state = states[phase]
                    return player(f'0:{state.position_seconds:02}', 'Pause' if state.playing else 'Play'), state
                runner.sample = Mock(side_effect=sample)
                real_tap = runner.tap
                def tap(element):
                    events.append(('tap', runner.phase, element.get('text')))
                    real_tap(element)
                runner.tap = Mock(side_effect=tap)
                with patch('tools.android_lifecycle_runtime.run.time.sleep', side_effect=lambda delay: events.append(('sleep', delay))):
                    if failure:
                        with self.assertRaises(RuntimeFailure):
                            runner.run()
                    else:
                        report = runner.run()
                        self.assertTrue(report['noAutoplayAfterRestart'])
                        self.assertEqual(report['explicitReplayAfterRestartAdvanceSeconds'], 4)
                        self.assertEqual((report['oldPid'], report['newPid']), (123, 456))
                manual_tap = ('tap', '12-restored-no-autoplay', 'Play')
                if failure in ('autoplay', 'paused-progress'):
                    self.assertNotIn(manual_tap, events)
                    self.assertFalse(any(item[:2] == ('sample', '13-restored-explicit-play') for item in events))
                else:
                    restored_index = events.index(('sample', '11-resumed-paused', False))
                    stable_index = events.index(('sample', '12-restored-no-autoplay', False))
                    self.assertIn(('sleep', 4), events[restored_index + 1:stable_index])
                    self.assertLess(stable_index, events.index(manual_tap))
                    play_index = events.index(('sample', '13-restored-explicit-play', True))
                    advance_index = events.index(('sample', '14-restored-play-advanced', True))
                    self.assertLess(events.index(manual_tap), play_index)
                    self.assertIn(('sleep', 4), events[play_index + 1:advance_index])
                    self.assertEqual(sum(call.args[:3] == ('shell', 'input', 'tap')
                                         for call in runner.adb.run.call_args_list), 5)
                phases = [call.kwargs['required_phase'] for call in runner.finish_recording.call_args_list]
                self.assertEqual(phases, ['04-advanced'] if failure else
                                 ['04-advanced', '14-restored-play-advanced'])

    def test_native_recording_uses_even_proportional_dimensions(self):
        self.assertEqual(recording_size("Physical size: 1080x2400\n"), (432, 960))
        self.assertEqual(recording_size("Physical size: 1080x2400\nOverride size: 1179x2556\n"), (432, 936))
        self.assertEqual(recording_size("Physical size: 2560x1600\n"), (432, 270))
        self.assertEqual(recording_size("Physical size: 360x800\n"), (360, 800))
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

    def test_codec_diagnostics_bound_output_and_preserve_collection_failures(self):
        cases = [
            (subprocess.CompletedProcess([], 0, b"x" * (256 * 1024 + 1), b""), "collected", True),
            (subprocess.CompletedProcess([], 1, b"", b"codec service unavailable"), "failed", False),
            (subprocess.TimeoutExpired("adb", 3, output=b"partial codec state", stderr=b"partial error"), "timeout", False),
        ]
        for result, status, truncated in cases:
            with self.subTest(status=status), tempfile.TemporaryDirectory() as directory:
                adb = Mock(remote_prefix="/sdcard/meowwatch-install-test/")
                if isinstance(result, Exception):
                    adb.run.side_effect = result
                else:
                    adb.run.return_value = result
                recording = LifecycleRecording(adb, Path(directory), 1, (432, 960))
                recording.output.parent.mkdir()
                recording.codec_evidence("codec-state", ("shell", "dumpsys", "media.codec"))
                adb.run.assert_called_once_with("shell", "dumpsys", "media.codec", timeout=3, check=False)
                evidence = recording.metadata["codecEvidence"]["codec-state"]
                self.assertEqual(evidence["status"], status)
                self.assertEqual(evidence["stdout"]["truncated"], truncated)
                payload = recording.output.with_suffix(".codec-state.stdout.txt").read_bytes()
                self.assertLessEqual(len(payload), 256 * 1024)
                if status == "timeout":
                    self.assertEqual(payload, b"partial codec state")
                self.assertEqual(recording.metadata["status"], "not-started")

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
            recording.codec_log_since = "09-17 13:00:00.000"
            media = b"ftyp" + b"x" * 5000 + b"moov"
            def command(*arguments, **_kwargs):
                if arguments[:2] == ("exec-out", "logcat"):
                    self.assertEqual(arguments[arguments.index("--pid") + 1], "44")
                    self.assertEqual(arguments[arguments.index("-T") + 1], recording.codec_log_since)
                    self.assertEqual(arguments[-1], "*:S")
                    self.assertNotIn("-c", arguments)
                    self.assertEqual(_kwargs["timeout"], 3)
                    raise subprocess.TimeoutExpired("adb", 3, output=b"partial current recorder codec log")
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
            self.assertIn("does not cover", recording.metadata["error"])
            self.assertEqual(recording.metadata["codecEvidence"]["codec-log"]["status"], "timeout")
            self.assertEqual(recording.output.with_suffix(".codec-log.stdout.txt").read_bytes(),
                             b"partial current recorder codec log")

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
            media = clock_media([67.0, 139.672067])
            def command(*arguments, **_kwargs):
                receipt = device_file_response(arguments, recording.remote, media)
                if receipt is not None:
                    return receipt
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
                     "format": {"duration": "72.672067"}, "frames": [{"media_type": "video", "pts_time": "0"}, {"media_type": "video", "pts_time": "72.672067"}]}
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

    def test_final_device_receipt_is_required_after_exit_before_pull_without_hiding_decode_errors(self):
        cases = (("match", b"", None), ("hash-mismatch", b"", "digest differ"),
                 ("size-mismatch", b"", "digest differ"), ("query-failed", b"", "receipt is unavailable"),
                 ("query-timeout", b"", "receipt is unavailable"),
                 ("query-failed", b"original corrupt decoded frame", "decoded completely"),
                 ("diagnostic-log-write-failed", b"original corrupt decoded frame", "decoded completely"))
        for failure, decode_stderr, expected_error in cases:
            with self.subTest(failure=failure, decode_stderr=decode_stderr), tempfile.TemporaryDirectory() as directory:
                adb = Mock(remote_prefix='/sdcard/meowwatch-install-test/', remote_files=[])
                recording = LifecycleRecording(adb, Path(directory), 1, (432, 960))
                recording.output.parent.mkdir()
                media = clock_media([10.0, 19.8])
                order = []
                def command(*arguments, **kwargs):
                    if arguments == ('exec-out', 'cat', '/proc/uptime'):
                        return subprocess.CompletedProcess([], 0, b'20.00 10.00\n')
                    if arguments[:2] == ('exec-out', 'cat'):
                        return subprocess.CompletedProcess([], 0, f'screenrecord\0{recording.remote}\0'.encode())
                    if arguments[:2] in (('exec-out', 'stat'), ('exec-out', 'sha256sum')):
                        order.append(arguments[1])
                        self.assertIn('recorder-exited', order)
                        self.assertNotIn('pull', order)
                        self.assertEqual(kwargs, {'timeout': 3, 'check': False})
                        if failure == 'query-failed':
                            return subprocess.CompletedProcess([], 1, b'', b'device query rejected')
                        if failure == 'query-timeout':
                            raise subprocess.TimeoutExpired('adb', 3)
                        response = device_file_response(arguments, recording.remote, media)
                        if arguments[1] == 'stat' and failure == 'size-mismatch':
                            response.stdout = f'{len(media) + 1}\n'.encode()
                        if arguments[1] == 'sha256sum' and failure == 'hash-mismatch':
                            response.stdout = f'{"0" * 64}  {recording.remote}\n'.encode()
                        return response
                    if arguments[0] == 'pull':
                        order.append('pull')
                        recording.output.write_bytes(media)
                    return subprocess.CompletedProcess([], 0, b'', b'')
                adb.run.side_effect = command
                recording.process = Mock()
                recording.process.poll.side_effect = [None, 0]
                recording.process.wait.side_effect = lambda **_: order.append('recorder-exited') or 0
                recording.pid = '44'
                recording.metadata.update({'startedAtMonotonic': 0.0, 'mediaReadyAtDeviceElapsedSeconds': 10.0})
                probe = {'streams': [{'codec_type': 'video', 'width': 432, 'height': 960, 'duration': '10'}],
                         'frames': [{'media_type': 'video', 'pts_time': '0'}, {'media_type': 'video', 'pts_time': '9.8'}]}
                def decode(arguments, **_kwargs):
                    if arguments[0] == 'ffprobe':
                        return subprocess.CompletedProcess([], 0, json.dumps(probe).encode(), b'')
                    order.append('full-decode')
                    self.assertIn('-xerror', arguments)
                    self.assertNotIn('-t', arguments)
                    return subprocess.CompletedProcess([], 0, b'', decode_stderr)
                if decode_stderr:
                    recording.codec_log_since = '09-17 17:20:34.000'
                    recording.codec_evidence = Mock(side_effect=OSError('diagnostic file write failed'))
                write_bytes, write_text = Path.write_bytes, Path.write_text
                def retain_bytes(path, data):
                    if failure == 'diagnostic-log-write-failed' and path.name.endswith('.decode.log'):
                        raise OSError('decode diagnostic file write failed')
                    return write_bytes(path, data)
                def retain_text(path, data, **kwargs):
                    if failure == 'diagnostic-log-write-failed' and path.name.endswith('.screenrecord.log'):
                        raise OSError('recorder diagnostic file write failed')
                    return write_text(path, data, **kwargs)
                with patch('tools.android_lifecycle_runtime.run.subprocess.run', side_effect=decode), patch.object(
                    Path, 'write_bytes', retain_bytes,
                ), patch.object(Path, 'write_text', retain_text):
                    if expected_error:
                        with self.assertRaisesRegex(RuntimeFailure, expected_error):
                            recording.finish()
                    else:
                        recording.finish()
                self.assertEqual(order[-1], 'full-decode')
                self.assertEqual(recording.output.read_bytes(), media)
                self.assertEqual(recording.metadata['deviceFileMatchesPulledFile'], failure in ('match', 'diagnostic-log-write-failed'))
                self.assertEqual(recording.metadata['status'], 'failed' if expected_error else 'verified')
                if failure == 'diagnostic-log-write-failed':
                    self.assertEqual(recording.metadata['decodeLogWriteError'], 'OSError')
                    self.assertEqual(recording.metadata['screenrecordLogWriteError'], 'OSError')
                    recording.process.stdout.close.assert_called_once()
                else:
                    self.assertEqual(recording.output.with_suffix('.decode.log').read_bytes(), decode_stderr)
                self.assertLessEqual(recording.metadata['recorderExitedAtMonotonic'], recording.metadata['deviceFileReceipt']['queries']['size']['startedAtMonotonic'])
                self.assertLessEqual(recording.metadata['deviceFileReceipt']['queries']['size']['finishedAtMonotonic'], recording.metadata['pullStartedAtMonotonic'])
                if decode_stderr:
                    self.assertEqual(recording.metadata['error'], 'native lifecycle recording could not be decoded completely')
                    self.assertEqual(recording.metadata['codecLogCollectionError'], 'OSError')
                    self.assertEqual(recording.metadata['firstDecodeError']['stderrPrefix'], decode_stderr.decode())
                    self.assertEqual(recording.metadata['firstDecodeError']['stderrSha256'], hashlib.sha256(decode_stderr).hexdigest())

    def test_device_file_receipt_rejects_unowned_paths_and_unbounded_or_ambiguous_results(self):
        with tempfile.TemporaryDirectory() as directory:
            adb = Mock(remote_prefix='/sdcard/meowwatch-install-test/', remote_files=[])
            recording = LifecycleRecording(adb, Path(directory), 1, (432, 960))
            owned = recording.remote
            for remote in ('/sdcard/personal.mp4', owned + ';id', '/sdcard/meowwatch-install-other/lifecycle-01.mp4'):
                recording.remote = remote
                with self.subTest(remote=remote), self.assertRaisesRegex(RuntimeFailure, 'exact owned'):
                    recording.device_file_receipt()
            adb.run.assert_not_called()
            recording.remote = owned
            for invalid in (b'0\n', b'-1\n', b'1\n2\n', f'{MAX_RECORDING_BYTES + 1}\n'.encode(), b'1' * (MAX_FILE_QUERY_BYTES + 1)):
                adb.run.reset_mock()
                adb.run.return_value = subprocess.CompletedProcess([], 0, invalid, b'')
                self.assertEqual(recording.device_file_receipt()['status'], 'failed')
                adb.run.assert_called_once_with('exec-out', 'stat', '-c', '%s', owned, timeout=3, check=False)
            for invalid in (b'0' * 64 + b'  /sdcard/personal.mp4\n', b'0' * 64 + b'  ' + owned.encode() + b'\nextra', b'not a digest'):
                adb.run.side_effect = [subprocess.CompletedProcess([], 0, b'5000\n', b''),
                                       subprocess.CompletedProcess([], 0, invalid, b'')]
                self.assertEqual(recording.device_file_receipt()['status'], 'failed')

    def test_live_read_summaries_retain_latest_offsets_with_a_fixed_metadata_bound(self):
        section = {}
        for offset in range(MAX_LIVE_READ_SUMMARIES + 5):
            LifecycleRecording.live_read_summary(section, {'offset': offset})
        self.assertEqual(len(section['readSummaries']), MAX_LIVE_READ_SUMMARIES)
        self.assertEqual(section['droppedEarlierReadSummaries'], 5)
        self.assertEqual(section['readSummaries'][0]['offset'], 5)
        self.assertEqual(section['readSummaries'][-1]['offset'], MAX_LIVE_READ_SUMMARIES + 4)

    def test_recording_start_waits_for_actual_picture_before_measuring(self):
        with tempfile.TemporaryDirectory() as directory:
            adb = Mock(serial="emulator-5554", prefix=["adb", "-s", "emulator-5554"],
                       remote_prefix="/sdcard/meowwatch-install-test/", remote_files=[])
            recording = LifecycleRecording(adb, Path(directory), 1, recording_size("Physical size: 1080x2400\n"))
            prefixes = iter([b"\0\0\0\0mdat", b"\0\0\0\0mdat\0\0\0\x05\x65abcd"])
            def command(*arguments, **_kwargs):
                if arguments == ("exec-out", "date", "+%m-%d %H:%M:%S.000"):
                    self.assertIsNone(recording.process)
                    return subprocess.CompletedProcess([], 0, b"09-17 13:00:00.000\n")
                if arguments == ("shell", "dumpsys", "media.codec"):
                    self.assertEqual(recording.metadata["mediaReadyAtDeviceElapsedSeconds"], 67)
                    return subprocess.CompletedProcess([], 0, b"c2.android.avc.encoder")
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
            with patch("tools.android_lifecycle_runtime.run.subprocess.Popen", return_value=process) as launch, patch(
                "tools.android_lifecycle_runtime.run.time.monotonic",
                side_effect=[100, 101, 102, 102, 103, 103, 104, 105],
            ), patch("tools.android_lifecycle_runtime.run.time.sleep"):
                recording.start()
            recording.reader.join(timeout=1)
            self.assertEqual(recording.metadata["pidObservedAtMonotonic"], 101)
            self.assertEqual(recording.metadata["startedAtMonotonic"], 105)
            self.assertEqual(recording.metadata["mediaReadyAtDeviceElapsedSeconds"], 67)
            self.assertIn("--size 432x960 --bit-rate 2000000", launch.call_args.args[0][-1])
            self.assertEqual(recording.codec_log_since, "09-17 13:00:00.000")
            self.assertEqual(recording.metadata["codecEvidence"]["codec-state"]["status"], "collected")
            reads = recording.metadata["readinessProbe"]["readSummaries"]
            self.assertEqual(len(reads), 2)
            self.assertEqual(reads[0]["sha256"], hashlib.sha256(b"\0\0\0\0mdat").hexdigest())
            self.assertEqual(reads[1]["bytes"], 17)

    def startup_recording(self, directory, *, owner=None, action_error=None, action_delay=0,
                          produces_picture=True):
        adb = Mock(serial="emulator-5554", prefix=["adb", "-s", "emulator-5554"],
                   remote_prefix="/sdcard/meowwatch-install-test/", remote_files=[])
        recording = LifecycleRecording(adb, Path(directory), 1, (432, 960))
        process = Mock(stdout=io.StringIO("LIFECYCLE_RECORDER_PID=44\n"))
        process.poll.return_value = None
        events, clock = [], [100.0]

        def now():
            clock[0] += 0.1
            return clock[0]

        def command(*arguments, **kwargs):
            if arguments == ("shell", "getprop", "ro.kernel.qemu"):
                return subprocess.CompletedProcess([], 0, b"1")
            if arguments == ("shell", "pidof", "screenrecord"):
                return subprocess.CompletedProcess([], 0, b"")
            if arguments == ("exec-out", "date", "+%m-%d %H:%M:%S.000"):
                return subprocess.CompletedProcess([], 0, b"09-17 13:00:00.000\n")
            if arguments == ("exec-out", "cat", "/proc/44/cmdline"):
                events.append("ownership-query")
                self.assertLessEqual(kwargs["timeout"], 3)
                value = owner if owner is not None else (
                    f"/system/bin/screenrecord\0--verbose\0--size\0{recording.size[0]}x{recording.size[1]}"
                    f"\0--bit-rate\x002000000\0--time-limit\x00180\0{recording.remote}\0").encode()
                return subprocess.CompletedProcess([], 0, value)
            if arguments[:2] == ("exec-out", "head"):
                events.append("picture-probe")
                self.assertIn("startup-action", events)
                picture = b"\0\0\0\0mdat\0\0\0\x05\x65abcd" if produces_picture else b"\0\0\0\0mdat"
                return subprocess.CompletedProcess([], 0, picture)
            if arguments == ("exec-out", "cat", "/proc/uptime"):
                events.append("device-clock" if "startup-action" in events else "trigger-clock")
                return subprocess.CompletedProcess([], 0, b"67.00 30.00\n")
            if arguments == ("shell", "dumpsys", "media.codec"):
                return subprocess.CompletedProcess([], 0, b"c2.android.avc.encoder")
            raise AssertionError(arguments)

        def perform(deadline):
            self.assertEqual(events, ["ownership-query", "trigger-clock"])
            self.assertEqual(deadline, recording.metadata["launchRequestedAtMonotonic"] + 20)
            self.assertNotIn("startedAtMonotonic", recording.metadata)
            self.assertNotIn("mediaReadyAtDeviceElapsedSeconds", recording.metadata)
            events.append("startup-action")
            clock[0] += action_delay
            if action_error is not None:
                raise action_error

        adb.run.side_effect = command
        return recording, process, Mock(side_effect=perform), events, now

    def test_startup_action_runs_once_after_exact_ownership_and_before_evidence_start(self):
        with tempfile.TemporaryDirectory() as directory:
            recording, process, action, events, now = self.startup_recording(directory)
            with patch("tools.android_lifecycle_runtime.run.subprocess.Popen", return_value=process) as launch, patch(
                "tools.android_lifecycle_runtime.run.time.monotonic", side_effect=now,
            ):
                recording.start(startup_action=action)
                with self.assertRaisesRegex(RuntimeFailure, "cannot be started"):
                    recording.start(startup_action=action)
            recording.reader.join(timeout=1)
            action.assert_called_once()
            launch.assert_called_once()
            self.assertEqual(events, ["ownership-query", "trigger-clock", "startup-action", "picture-probe", "device-clock"])
            receipt = recording.metadata["startupAction"]
            self.assertEqual(receipt["status"], "completed")
            self.assertEqual(receipt["ownedRecorderPid"], 44)
            self.assertTrue(receipt["beforeMediaReadiness"])
            self.assertEqual(receipt["triggerDeviceElapsedSeconds"], 67)
            self.assertLess(receipt["ownershipVerifiedAtMonotonic"], receipt["startedAtMonotonic"])
            self.assertLess(receipt["finishedAtMonotonic"], recording.metadata["startedAtMonotonic"])
            self.assertEqual(recording.metadata["mediaReadyAtDeviceElapsedSeconds"], 67)
            self.assertEqual(recording.metadata["status"], "recording")

    def test_changed_recorder_executable_output_or_options_never_authorize_startup_action(self):
        remote = "/sdcard/meowwatch-install-test/lifecycle-01.mp4"
        valid = f"screenrecord\0--verbose\0--size\x00432x960\0--bit-rate\x002000000\0--time-limit\x00180\0{remote}\0".encode()
        for owner in (valid.replace(b"screenrecord", b"other"), valid.replace(remote.encode(), b"/sdcard/personal.mp4"),
                      valid.replace(b"432x960", b"960x432"), valid.replace(b"2000000", b"8000000"),
                      valid + b"--extra\0", b"screenrecord\0" + b"x" * 4096):
            with self.subTest(owner=owner[:80]), tempfile.TemporaryDirectory() as directory:
                recording, process, action, events, now = self.startup_recording(directory, owner=owner)
                with patch("tools.android_lifecycle_runtime.run.subprocess.Popen", return_value=process), patch(
                    "tools.android_lifecycle_runtime.run.time.monotonic", side_effect=now,
                ), self.assertRaisesRegex(RuntimeFailure, "ownership changed"):
                    recording.start(startup_action=action)
                recording.reader.join(timeout=1)
                action.assert_not_called()
                self.assertEqual(events, ["ownership-query"])
                self.assertEqual(recording.metadata["startupAction"]["status"], "not-sent")
                self.assertNotIn("startedAtMonotonic", recording.metadata)

    def test_failed_or_uncertain_startup_action_is_retained_without_readiness_retry(self):
        for error in (RuntimeFailure("native control disappeared"), subprocess.TimeoutExpired("input", 3), ValueError("bad action")):
            with self.subTest(error=type(error).__name__), tempfile.TemporaryDirectory() as directory:
                recording, process, action, events, now = self.startup_recording(directory, action_error=error)
                with patch("tools.android_lifecycle_runtime.run.subprocess.Popen", return_value=process) as launch, patch(
                    "tools.android_lifecycle_runtime.run.time.monotonic", side_effect=now,
                ):
                    with self.assertRaisesRegex(RuntimeFailure, "refusing to repeat") as raised:
                        recording.start(startup_action=action)
                    self.assertIs(raised.exception.__cause__, error)
                    with self.assertRaisesRegex(RuntimeFailure, "cannot be started"):
                        recording.start(startup_action=action)
                recording.reader.join(timeout=1)
                action.assert_called_once()
                launch.assert_called_once()
                self.assertEqual(events, ["ownership-query", "trigger-clock", "startup-action"])
                self.assertEqual(recording.metadata["startupAction"]["status"], "uncertain")
                self.assertEqual(recording.metadata["startupAction"]["errorType"], type(error).__name__)
                self.assertEqual(recording.metadata["status"], "failed")
                self.assertNotIn("startedAtMonotonic", recording.metadata)
                self.assertFalse(recording.finished)  # The caller must still stop/pull its owned recorder.

    def test_expired_ownership_bad_trigger_clock_or_recorder_exit_never_sends_action(self):
        for failure in ("ownership-deadline", "invalid-trigger-clock", "exit-before-dispatch"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                recording, process, action, events, now = self.startup_recording(directory)
                original_command = recording.adb.run.side_effect
                def command(*arguments, **kwargs):
                    if failure == "invalid-trigger-clock" and arguments == ("exec-out", "cat", "/proc/uptime"):
                        return subprocess.CompletedProcess([], 0, b"invalid clock")
                    return original_command(*arguments, **kwargs)
                recording.adb.run.side_effect = command
                def bounded_now():
                    return 121 if failure == "ownership-deadline" and "ownership-query" in events else now()
                if failure == "exit-before-dispatch":
                    process.poll.side_effect = [None, None, 0]
                with patch("tools.android_lifecycle_runtime.run.subprocess.Popen", return_value=process), patch(
                    "tools.android_lifecycle_runtime.run.time.monotonic", side_effect=bounded_now,
                ), self.assertRaises(RuntimeFailure):
                    recording.start(startup_action=action)
                recording.reader.join(timeout=1)
                action.assert_not_called()
                self.assertNotIn("picture-probe", events)
                self.assertNotIn("startup-action", events)
                self.assertEqual(recording.metadata["startupAction"]["status"], "not-sent")

    def test_completed_action_never_substitutes_for_picture_or_extends_launch_deadline(self):
        for delay, picture in ((21, True), (0, False)):
            with self.subTest(delay=delay, picture=picture), tempfile.TemporaryDirectory() as directory:
                recording, process, action, events, now = self.startup_recording(
                    directory, action_delay=delay, produces_picture=picture)
                with patch("tools.android_lifecycle_runtime.run.subprocess.Popen", return_value=process), patch(
                    "tools.android_lifecycle_runtime.run.time.monotonic", side_effect=now,
                ), patch("tools.android_lifecycle_runtime.run.time.sleep"), self.assertRaisesRegex(RuntimeFailure, "picture and device clock"):
                    recording.start(startup_action=action)
                recording.reader.join(timeout=1)
                action.assert_called_once()
                self.assertEqual(recording.metadata["startupAction"]["status"], "completed")
                self.assertEqual(recording.metadata["readinessProbe"]["deadlineAtMonotonic"],
                                 recording.metadata["launchRequestedAtMonotonic"] + 20)
                self.assertNotIn("mediaReadyAtDeviceElapsedSeconds", recording.metadata)
                self.assertNotIn("startedAtMonotonic", recording.metadata)
                if delay:
                    self.assertEqual(events, ["ownership-query", "trigger-clock", "startup-action"])
                else:
                    self.assertGreater(events.count("picture-probe"), 1)

    def test_first_post_action_observation_needs_readiness_and_cannot_be_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            recording, process, action, _, now = self.startup_recording(directory)
            with self.assertRaises(RuntimeFailure):
                recording.observe_startup_result("03-playing")
            with patch("tools.android_lifecycle_runtime.run.subprocess.Popen", return_value=process), patch(
                "tools.android_lifecycle_runtime.run.time.monotonic", side_effect=now,
            ):
                recording.start(startup_action=action)
                recording.observe_startup_result("03-playing")
                with self.assertRaisesRegex(RuntimeFailure, "cannot be replaced"):
                    recording.observe_startup_result("later")
            recording.reader.join(timeout=1)
            self.assertEqual(recording.metadata["firstPostActionObservation"]["phase"], "03-playing")
            self.assertEqual(recording.metadata["firstPostActionObservation"]["deviceElapsedSeconds"], 67)

    def test_finite_transition_dispatches_once_after_ownership_without_waiting_for_live_picture(self):
        with tempfile.TemporaryDirectory() as directory:
            recording, process, action, events, now = self.startup_recording(
                directory, produces_picture=False)
            with patch("tools.android_lifecycle_runtime.run.subprocess.Popen", return_value=process), patch(
                "tools.android_lifecycle_runtime.run.time.monotonic", side_effect=now,
            ):
                recording.start(startup_action=action, finite_transition=True)
                recording.observe_startup_result("15-normal-return-home",
                                                 deadline=recording.metadata["readinessProbe"]["deadlineAtMonotonic"])
                with self.assertRaisesRegex(RuntimeFailure, "cannot be replaced"):
                    recording.observe_startup_result("later")
            recording.reader.join(timeout=1)
            self.assertEqual(events, ["ownership-query", "trigger-clock", "startup-action", "device-clock"])
            self.assertEqual(recording.metadata["status"], "recording")
            self.assertTrue(recording.metadata["finiteTransition"])
            self.assertNotIn("mediaReadyAtDeviceElapsedSeconds", recording.metadata)
            self.assertEqual(recording.metadata["readinessProbe"]["probeAttempts"], 0)
            self.assertEqual(action.call_count, 1)

    def test_finite_transition_requires_action_and_rejects_wrong_owner_before_input(self):
        with tempfile.TemporaryDirectory() as directory:
            recording, _, _, _, _ = self.startup_recording(directory)
            with self.assertRaisesRegex(RuntimeFailure, "requires one owned startup action"):
                recording.start(finite_transition=True)
            self.assertIsNone(recording.process)
        with tempfile.TemporaryDirectory() as directory:
            wrong_remote = "/sdcard/other.mp4"
            wrong_owner = ("/system/bin/screenrecord\x00--verbose\x00--size\x00432x960\x00"
                           "--bit-rate\x002000000\x00--time-limit\x00180\x00" + wrong_remote + "\x00").encode()
            recording, process, action, events, now = self.startup_recording(
                directory, owner=wrong_owner)
            with patch("tools.android_lifecycle_runtime.run.subprocess.Popen", return_value=process), patch(
                "tools.android_lifecycle_runtime.run.time.monotonic", side_effect=now,
            ), self.assertRaisesRegex(RuntimeFailure, "ownership changed"):
                recording.start(startup_action=action, finite_transition=True)
            recording.reader.join(timeout=1)
            action.assert_not_called()
            self.assertEqual(events, ["ownership-query"])

    def test_recorded_observation_must_be_covered_but_trigger_may_precede_first_frame(self):
        for trigger, observed, expected in ((9, 12, None), (11, 12, None),
                                             (9, 9.5, "does not cover"), (9, 20, "does not cover"),
                                             (9, None, "missing its first post-action")):
            with self.subTest(trigger=trigger, observed=observed), tempfile.TemporaryDirectory() as directory:
                adb = Mock(remote_prefix="/sdcard/meowwatch-install-test/", remote_files=[])
                recording = LifecycleRecording(adb, Path(directory), 1, (432, 960))
                recording.output.parent.mkdir()
                media = clock_media([10, 19.8])
                def command(*arguments, **_kwargs):
                    receipt = device_file_response(arguments, recording.remote, media)
                    if receipt is not None:
                        return receipt
                    if arguments == ("exec-out", "cat", "/proc/uptime"):
                        return subprocess.CompletedProcess([], 0, b"20.00 10.00\n")
                    if arguments[:2] == ("exec-out", "cat"):
                        return subprocess.CompletedProcess([], 0, f"screenrecord\0{recording.remote}\0".encode())
                    if arguments[0] == "pull":
                        recording.output.write_bytes(media)
                    return subprocess.CompletedProcess([], 0, b"", b"")
                adb.run.side_effect = command
                recording.process = Mock()
                recording.process.poll.side_effect = [None, 0]
                recording.process.wait.return_value = 0
                recording.pid = "44"
                recording.metadata.update({"status": "recording", "startedAtMonotonic": 0,
                    "mediaReadyAtDeviceElapsedSeconds": 10,
                    "startupAction": {"status": "completed", "triggerDeviceElapsedSeconds": trigger}})
                if observed is not None:
                    recording.metadata["firstPostActionObservation"] = {"phase": "first", "deviceElapsedSeconds": observed}
                probe = {"streams": [{"codec_type": "video", "width": 432, "height": 960, "duration": "10"}],
                         "frames": [{"media_type": "video", "pts_time": "0"}, {"media_type": "video", "pts_time": "9.8"}]}
                with patch("tools.android_lifecycle_runtime.run.subprocess.run", side_effect=[
                    subprocess.CompletedProcess([], 0, json.dumps(probe).encode(), b""),
                    subprocess.CompletedProcess([], 0, b"", b""),
                ]) as decode:
                    if expected:
                        with self.assertRaisesRegex(RuntimeFailure, expected):
                            recording.finish()
                    else:
                        recording.finish()
                self.assertEqual(decode.call_args_list[-1].args[0][0], "ffmpeg")
                self.assertEqual(recording.output.read_bytes(), media)
                self.assertEqual(recording.metadata["startupAction"]["firstFrameAfterTriggerSeconds"], 10 - trigger)
                self.assertEqual(recording.metadata["startupAction"]["triggerTimeWithinFrameClock"], trigger == 11)
                self.assertEqual(recording.metadata["status"], "failed" if expected else "verified")
                if observed is not None:
                    self.assertEqual(recording.metadata["firstPostActionObservation"]["coveredByFrameClock"], expected is None)

    def test_finite_transition_validates_finalized_frames_without_claiming_static_tail_coverage(self):
        cases = (
            ("valid", [10.5, 11.5], "15-normal-return-home", 110, None),
            ("stale-phase", [10.5, 11.5], "14-normal-player-restored", 110, "fresh Home observation"),
            ("late-home", [10.5, 11.5], "15-normal-return-home", 121, "fresh Home observation"),
            ("pre-trigger-only", [9.0, 9.5], "15-normal-return-home", 110, "post-trigger picture"),
            ("one-frame", [11.5], "15-normal-return-home", 110, "post-trigger picture"),
        )
        for name, times, phase, observed_at, expected in cases:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                adb = Mock(remote_prefix="/sdcard/meowwatch-install-test/", remote_files=[])
                recording = LifecycleRecording(adb, Path(directory), 3, (432, 960))
                recording.output.parent.mkdir()
                media = clock_media(times)
                def command(*arguments, **_kwargs):
                    receipt = device_file_response(arguments, recording.remote, media)
                    if receipt is not None:
                        return receipt
                    if arguments == ("exec-out", "cat", "/proc/uptime"):
                        return subprocess.CompletedProcess([], 0, b"13.00 10.00\n")
                    if arguments == ("exec-out", "cat", "/proc/44/cmdline"):
                        return subprocess.CompletedProcess([], 0, f"screenrecord\0{recording.remote}\0".encode())
                    if arguments[0] == "pull":
                        recording.output.write_bytes(media)
                    return subprocess.CompletedProcess([], 0, b"", b"")
                adb.run.side_effect = command
                recording.process = Mock()
                recording.process.poll.side_effect = [None, 0]
                recording.process.wait.return_value = 0
                recording.pid = "44"
                recording.metadata.update({"status": "recording", "startedAtMonotonic": 100,
                    "finiteTransition": True,
                    "readinessProbe": {"deadlineAtMonotonic": 120},
                    "startupAction": {"status": "completed", "triggerDeviceElapsedSeconds": 10,
                                      "finishedAtMonotonic": 101},
                    "firstPostActionObservation": {"phase": phase, "deviceElapsedSeconds": 12,
                                                    "observedAtMonotonic": observed_at}})
                probe = {"streams": [{"codec_type": "video", "width": 432, "height": 960,
                                      "duration": "1.1"}],
                         "frames": [{"media_type": "video", "pts_time": str(value - times[0])}
                                    for value in times]}
                with patch("tools.android_lifecycle_runtime.run.subprocess.run", side_effect=[
                    subprocess.CompletedProcess([], 0, json.dumps(probe).encode(), b""),
                    subprocess.CompletedProcess([], 0, b"", b""),
                ]) as decode:
                    if expected:
                        with self.assertRaisesRegex(RuntimeFailure, expected):
                            recording.finish()
                    else:
                        recording.finish()
                self.assertEqual(decode.call_args_list[-1].args[0][0], "ffmpeg")
                self.assertEqual(recording.output.read_bytes(), media)
                self.assertTrue(recording.metadata["deviceFileMatchesPulledFile"])
                self.assertEqual(recording.metadata["status"], "failed" if expected else "verified")
                if not expected:
                    self.assertFalse(recording.metadata["firstPostActionObservation"]["coveredByFrameClock"])
                    self.assertEqual(recording.metadata["transitionVisualReview"]["status"], "pending")
                    self.assertFalse(recording.metadata["transitionVisualReview"]["continuousCoverageAfterLastFrame"])

    def test_finite_transition_does_not_signal_changed_recorder_owner(self):
        with tempfile.TemporaryDirectory() as directory:
            adb = Mock(remote_prefix="/sdcard/meowwatch-install-test/", remote_files=[])
            adb.run.return_value = subprocess.CompletedProcess([], 0, b"screenrecord\0/sdcard/other.mp4\0")
            recording = LifecycleRecording(adb, Path(directory), 3, (432, 960))
            recording.process = Mock()
            recording.process.poll.side_effect = [None, 0]
            recording.pid = "44"
            recording.metadata["finiteTransition"] = True
            with self.assertRaisesRegex(RuntimeFailure, "ownership changed"):
                recording.finish()
            self.assertFalse(any(call.args[:2] == ("shell", "kill") for call in adb.run.call_args_list))
            self.assertEqual(recording.metadata["status"], "failed")

    def test_recording_start_retries_only_bounded_readiness_timeouts(self):
        with tempfile.TemporaryDirectory() as directory:
            adb = Mock(serial="emulator-5554", prefix=["adb", "-s", "emulator-5554"],
                       remote_prefix="/sdcard/meowwatch-install-test/", remote_files=[])
            recording = LifecycleRecording(adb, Path(directory), 1, (432, 960))
            picture = b"\0\0\0\0mdat\0\0\0\x05\x65abcd"
            prefix_results = iter([
                subprocess.TimeoutExpired("private command must not be retained", 3),
                subprocess.CompletedProcess([], 0, picture),
                subprocess.CompletedProcess([], 0, picture),
            ])
            clock_results = iter([
                subprocess.TimeoutExpired("private command must not be retained", 3),
                subprocess.CompletedProcess([], 0, b"67.00 30.00\n"),
            ])

            def command(*arguments, **_kwargs):
                if arguments == ("exec-out", "date", "+%m-%d %H:%M:%S.000"):
                    return subprocess.CompletedProcess([], 0, b"09-17 13:00:00.000\n")
                if arguments == ("shell", "dumpsys", "media.codec"):
                    return subprocess.CompletedProcess([], 0, b"c2.android.avc.encoder")
                if arguments == ("shell", "getprop", "ro.kernel.qemu"):
                    return subprocess.CompletedProcess([], 0, b"1")
                if arguments == ("shell", "pidof", "screenrecord"):
                    return subprocess.CompletedProcess([], 0, b"")
                if arguments[:2] == ("exec-out", "head"):
                    result = next(prefix_results)
                    if isinstance(result, Exception):
                        raise result
                    return result
                if arguments == ("exec-out", "cat", "/proc/uptime"):
                    result = next(clock_results)
                    if isinstance(result, Exception):
                        raise result
                    return result
                raise AssertionError(arguments)

            adb.run.side_effect = command
            process = Mock(stdout=io.StringIO("LIFECYCLE_RECORDER_PID=44\n"))
            process.poll.return_value = None
            with patch("tools.android_lifecycle_runtime.run.subprocess.Popen", return_value=process), patch(
                "tools.android_lifecycle_runtime.run.time.monotonic",
                side_effect=[100, 101, 102, 103, 104, 104, 105, 106, 107, 107, 108, 109],
            ), patch("tools.android_lifecycle_runtime.run.time.sleep"):
                recording.start()
            recording.reader.join(timeout=1)
            self.assertEqual(recording.metadata["mediaReadyAtDeviceElapsedSeconds"], 67)
            readiness = dict(recording.metadata["readinessProbe"])
            reads = readiness.pop("readSummaries")
            self.assertEqual([row["sha256"] for row in reads], [hashlib.sha256(picture).hexdigest()] * 2)
            self.assertEqual(readiness, {
                "deadlineAtMonotonic": 120,
                "probeAttempts": 3,
                "timeoutCount": 2,
                "timeouts": [
                    {"operation": "media-prefix", "probeAttempt": 1,
                     "timeoutSeconds": 3.0, "occurredAtMonotonic": 103},
                    {"operation": "device-clock", "probeAttempt": 2,
                     "timeoutSeconds": 3.0, "occurredAtMonotonic": 106},
                ],
            })
            self.assertNotIn("private command", json.dumps(recording.metadata))

    def test_recording_start_readiness_timeout_cannot_extend_deadline(self):
        with tempfile.TemporaryDirectory() as directory:
            adb = Mock(serial="emulator-5554", prefix=["adb", "-s", "emulator-5554"],
                       remote_prefix="/sdcard/meowwatch-install-test/", remote_files=[])
            recording = LifecycleRecording(adb, Path(directory), 1, (432, 960))

            def command(*arguments, **_kwargs):
                if arguments == ("exec-out", "date", "+%m-%d %H:%M:%S.000"):
                    return subprocess.CompletedProcess([], 0, b"09-17 13:00:00.000\n")
                if arguments == ("shell", "getprop", "ro.kernel.qemu"):
                    return subprocess.CompletedProcess([], 0, b"1")
                if arguments == ("shell", "pidof", "screenrecord"):
                    return subprocess.CompletedProcess([], 0, b"")
                if arguments[:2] == ("exec-out", "head"):
                    raise subprocess.TimeoutExpired("adb", 3)
                raise AssertionError(arguments)

            adb.run.side_effect = command
            process = Mock(stdout=io.StringIO("LIFECYCLE_RECORDER_PID=44\n"))
            process.poll.return_value = None
            with patch("tools.android_lifecycle_runtime.run.subprocess.Popen", return_value=process), patch(
                "tools.android_lifecycle_runtime.run.time.monotonic",
                side_effect=[100, 101, 102, 121, 122],
            ), patch("tools.android_lifecycle_runtime.run.time.sleep"):
                with self.assertRaisesRegex(RuntimeFailure, "picture and device clock"):
                    recording.start()
            recording.reader.join(timeout=1)
            self.assertEqual(recording.metadata["readinessProbe"]["timeoutCount"], 1)
            self.assertEqual(recording.metadata["readinessProbe"]["probeAttempts"], 1)
            self.assertNotIn("startedAtMonotonic", recording.metadata)
            self.assertEqual(recording.metadata["status"], "failed")

    def test_recording_start_rejects_late_success_after_readiness_deadline(self):
        with tempfile.TemporaryDirectory() as directory:
            adb = Mock(serial="emulator-5554", prefix=["adb", "-s", "emulator-5554"],
                       remote_prefix="/sdcard/meowwatch-install-test/", remote_files=[])
            recording = LifecycleRecording(adb, Path(directory), 1, (432, 960))
            picture = b"\0\0\0\0mdat\0\0\0\x05\x65abcd"

            def command(*arguments, **kwargs):
                if arguments == ("exec-out", "date", "+%m-%d %H:%M:%S.000"):
                    return subprocess.CompletedProcess([], 0, b"09-17 13:00:00.000\n")
                if arguments == ("shell", "getprop", "ro.kernel.qemu"):
                    return subprocess.CompletedProcess([], 0, b"1")
                if arguments == ("shell", "pidof", "screenrecord"):
                    return subprocess.CompletedProcess([], 0, b"")
                if arguments[:2] == ("exec-out", "head"):
                    self.assertEqual(kwargs["timeout"], 1)
                    return subprocess.CompletedProcess([], 0, picture)
                if arguments == ("exec-out", "cat", "/proc/uptime"):
                    self.assertEqual(kwargs["timeout"], 0.5)
                    return subprocess.CompletedProcess([], 0, b"67.00 30.00\n")
                raise AssertionError(arguments)

            adb.run.side_effect = command
            process = Mock(stdout=io.StringIO("LIFECYCLE_RECORDER_PID=44\n"))
            process.poll.return_value = None
            with patch("tools.android_lifecycle_runtime.run.subprocess.Popen", return_value=process), patch(
                "tools.android_lifecycle_runtime.run.time.monotonic",
                side_effect=[100, 101, 119, 119.5, 119.5, 120.1],
            ), patch("tools.android_lifecycle_runtime.run.time.sleep"):
                with self.assertRaisesRegex(RuntimeFailure, "picture and device clock"):
                    recording.start()
            recording.reader.join(timeout=1)
            self.assertEqual(recording.metadata["readinessProbe"]["probeAttempts"], 1)
            self.assertEqual(recording.metadata["readinessProbe"]["timeoutCount"], 0)
            self.assertNotIn("startedAtMonotonic", recording.metadata)
            self.assertNotIn("mediaReadyAtDeviceElapsedSeconds", recording.metadata)

    def test_recording_start_fails_on_exit_or_missing_picture_without_restarting(self):
        for early in (True, False):
            with self.subTest(early=early), tempfile.TemporaryDirectory() as directory:
                adb = Mock(serial="emulator-5554", prefix=["adb", "-s", "emulator-5554"],
                           remote_prefix="/sdcard/meowwatch-install-test/", remote_files=[])
                adb.run.side_effect = [subprocess.CompletedProcess([], 0, b"1"),
                                       subprocess.CompletedProcess([], 0, b""),
                                       subprocess.CompletedProcess([], 0, b"invalid device clock"),
                                       subprocess.CompletedProcess([], 0, b"\0\0\0\0mdat")]
                recording = LifecycleRecording(adb, Path(directory), 1, (720, 1600))
                process = Mock(stdout=io.StringIO("LIFECYCLE_RECORDER_PID=44\n"))
                process.poll.return_value = 1 if early else None
                with patch("tools.android_lifecycle_runtime.run.subprocess.Popen", return_value=process) as launch, patch(
                    "tools.android_lifecycle_runtime.run.time.monotonic", side_effect=[100, 101, 102, 102, 121],
                ), patch("tools.android_lifecycle_runtime.run.time.sleep"):
                    with self.assertRaisesRegex(RuntimeFailure, "before media|picture and device clock"):
                        recording.start()
                recording.reader.join(timeout=1)
                launch.assert_called_once()
                self.assertEqual(recording.metadata["status"], "failed")
                self.assertNotIn("startedAtMonotonic", recording.metadata)
                self.assertIsNone(recording.codec_log_since)
                self.assertIn("baseline unavailable or invalid", recording.metadata["codecLogSkipped"])

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

    def test_preparation_ownership_and_screenshot_share_remaining_deadline(self):
        for late in (None, "getprop", "screenshot"):
            with self.subTest(late=late), tempfile.TemporaryDirectory() as directory:
                clock = [10.0]
                adb = PreparationAdb([preparation_anr()])
                runner = preparation_runner(Path(directory), adb)
                original_run, original_screenshot = adb.run, adb.screenshot
                calls = []
                def command(*arguments, **kwargs):
                    if arguments == ("shell", "getprop", "ro.kernel.qemu"):
                        calls.append(("getprop", kwargs["timeout"]))
                        clock[0] = 11.0 if late == "getprop" else 10.4
                    return original_run(*arguments, **kwargs)
                def screenshot(**kwargs):
                    calls.append(("screenshot", kwargs["timeout"]))
                    if late == "screenshot":
                        clock[0] = 11.0
                    return original_screenshot(**kwargs)
                adb.run, adb.screenshot = command, screenshot
                with patch("tools.android_lifecycle_runtime.run.time.monotonic", side_effect=lambda: clock[0]):
                    if late:
                        with self.assertRaises(ObserverIntegrityFailure):
                            runner.recover_preparation_anr(*preparation_anr(), deadline=11)
                        self.assertEqual(adb.taps, [])
                    else:
                        self.assertTrue(runner.recover_preparation_anr(*preparation_anr(), deadline=11))
                        self.assertEqual(len(adb.taps), 1)
                self.assertEqual(calls[0], ("getprop", 1.0))
                if late == "getprop":
                    self.assertEqual(len(calls), 1)
                else:
                    self.assertEqual(calls[1][0], "screenshot")
                    self.assertAlmostEqual(calls[1][1], 0.6)

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
            def run(self, *arguments, **kwargs):
                result = super().run(*arguments, **kwargs)
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

    def test_longer_fixture_requires_matching_expected_duration(self):
        longer = player().replace("1:30", "3:00")
        self.assertEqual(playback(longer, expected_duration_seconds=180), Playback(12, 180, True))
        for xml, duration in ((longer, 90), (player(), 180), (longer, 0), (longer, -1)):
            with self.subTest(duration=duration), self.assertRaises(RuntimeFailure):
                playback(xml, expected_duration_seconds=duration)

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
                "tools.android_native_ui.observer.collect_instrumentation",
                side_effect=lambda command, nonce, *, deadline: native_command(command),
            ), patch(
                "tools.android_lifecycle_runtime.run.time.sleep",
            ):
                xml, state = runner.sample("04-advanced", playing=True, screenshot=False)

            self.assertEqual(state, Playback(20, 90, True))
            self.assertEqual(xml, observed_xml)
            self.assertEqual(len(dump_commands), 2)
            self.assertNotEqual(
                dump_commands[0][dump_commands[0].index("nonce") + 1],
                dump_commands[1][dump_commands[1].index("nonce") + 1],
            )
            self.assertEqual([item["position_seconds"] for item in runner.samples], [20])
            self.assertEqual(runner.observation_timeouts[0]["operation"], "native accessibility snapshot")
            self.assertEqual([item["status"] for item in runner.observer.observations], ["failure", "success"])
            self.assertEqual(runner.observer.observations[0]["failure"], "instrumentation_timeout")
            self.assertNotEqual(runner.observer.observations[0]["requestNonce"],
                                runner.observer.observations[1]["requestNonce"])
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

            def expired_observation(*, deadline=None):
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

    def test_late_xml_never_calls_predicate_and_late_predicate_never_passes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk, fixture = root / "app.apk", root / FIXTURE_NAME
            apk.write_bytes(b"apk")
            fixture.write_bytes(b"fixture")
            for late_at in ("observation", "predicate"):
                runner = Runner("emulator-5554", apk, fixture, root)
                clock = [0.0]
                deadlines, checks = [], []
                def observation(*, deadline=None):
                    deadlines.append(deadline)
                    if late_at == "observation":
                        clock[0] = 11
                    return player()
                def check(xml):
                    checks.append(xml)
                    clock[0] = 11
                    return playback(xml)
                with self.subTest(late_at=late_at), patch.object(runner, "observe", side_effect=observation), \
                        patch("tools.android_lifecycle_runtime.run.time.monotonic", side_effect=lambda: clock[0]), \
                        patch("tools.android_lifecycle_runtime.run.time.sleep"), \
                        self.assertRaisesRegex(RuntimeFailure, "deadline"):
                    runner.wait("late-result", check, timeout=10)
                self.assertEqual(deadlines, [10])
                self.assertEqual(len(checks), 0 if late_at == "observation" else 1)
                self.assertFalse((root / "late-result.xml").exists())

    def test_expired_observer_budget_is_terminal_without_cold_restart(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            apk, fixture = root / "app.apk", root / FIXTURE_NAME
            apk.write_bytes(b"apk")
            fixture.write_bytes(b"fixture")
            runner = Runner("emulator-5554", apk, fixture, root)
            with patch.object(runner, "observe", side_effect=ObserverTimeout(
                "native accessibility snapshot", 20, phase="startup")) as observe, \
                    self.assertRaises(ObserverTimeout):
                runner.wait("startup-budget", playback)
            self.assertEqual(observe.call_count, 1)
            self.assertEqual(runner.samples, [])

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
