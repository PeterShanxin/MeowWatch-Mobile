import io
import json
import subprocess
import sys
import tempfile
from contextlib import contextmanager
from itertools import count
from pathlib import Path
import unittest
from unittest.mock import Mock, patch

from tools.android_install.runner import (
    Adb,
    NativeRecording,
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


class FirstRunAdb(SetupAdb):
    def __init__(self, *, persist=False, bad_ui=False, changed_pid=False, **kwargs):
        super().__init__(outcomes=(True,), **kwargs)
        self.persist, self.bad_ui, self.changed_pid = persist, bad_ui, changed_pid
        self.closed = False

    def run(self, *args, **kwargs):
        result = super().run(*args, **kwargs)
        if args[:3] == ('shell', 'input', 'tap'):
            self.closed = True
        elif args == ('shell', 'pidof', PACKAGE):
            result.stdout = b'43' if self.closed and self.changed_pid else b'42'
        elif args == ('shell', 'dumpsys', 'package', PACKAGE):
            result.stdout = (f'Package [{PACKAGE}]\nversionCode=1 versionName=0.1.0 '
                             'targetSdk=36 primaryCpuAbi=x86_64\nflags=[ HAS_CODE ]\n').encode()
        elif args == ('shell', 'getprop', 'ro.product.cpu.abi'):
            result.stdout = b'x86_64'
        elif args == ('shell', 'getprop', 'ro.build.version.sdk'):
            result.stdout = b'35'
        elif args == ('shell', 'getprop', 'ro.product.model'):
            result.stdout = b'sdk_gphone64_x86_64'
        return result

    def observe(self):
        if self.closed and not self.persist:
            self.observations += 1
            return (hierarchy() if self.bad_ui else hierarchy(
                node('Close the distance.&#10;Keep the movie night.'),
                node('No account needed. Change your name anytime.'),
                node('Continue', clickable='true'),
            )), FOCUS
        return super().observe()


class FirstRunSetupRecoveryTests(unittest.TestCase):
    @contextmanager
    def fixture(self, adb):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            apk = root / 'app.apk'
            apk.write_bytes(b'test-apk')
            artifacts = root / 'artifacts'
            artifacts.mkdir()
            runner = Runner('emulator-5554', apk, 'release')
            runner.adb = adb
            with patch('tools.android_install.runner.ARTIFACT_ROOT', artifacts), patch.object(
                runner, 'prepare', return_value={'installSucceeded': True}
            ), patch.object(runner, 'cleanup'), patch(
                'tools.android_install.runner.NativeRecording'
            ) as recorder, patch('tools.android_install.runner.time.sleep'), patch(
                'tools.android_install.runner.time.monotonic', side_effect=count()
            ):
                yield runner, artifacts, recorder.return_value

    def test_successful_launch_recovers_late_setup_without_relaunch_and_rechecks_ui(self):
        adb = FirstRunAdb()
        with self.fixture(adb) as (runner, artifacts, recorder):
            runner.run()
            summary = json.loads((artifacts / 'summary.json').read_text())
            self.assertTrue(summary['launch']['googleSetupAnrRecovered'])
            self.assertEqual(summary['launch']['googleSetupAnrRecoveryPhase'], 'first-run-ui')
            self.assertEqual(summary['launch']['attempts'], 1)
            self.assertEqual(summary['application']['pid'], 42)
            self.assertTrue(all(summary['firstRun']['uiautomatorOnboardingSemantics'].values()))
            self.assertTrue((artifacts / 'setup-anr.png').is_file())
            self.assertTrue((artifacts / 'setup-anr-window.txt').is_file())
            self.assertGreaterEqual(adb.observations, 4)
            recorder.finish.assert_called_once()
        self.assertEqual(adb.commands.count(('shell', 'input', 'tap', '70', '130')), 1)
        self.assertEqual(sum(command[:3] == ('shell', 'am', 'start') for command in adb.commands), 1)

    def test_persistent_setup_or_invalid_ui_never_pass_and_use_only_one_close(self):
        for options, message in (
            ({'persist': True}, 'not the focused Android package'),
            ({'bad_ui': True}, 'Exact first-run onboarding'),
            ({'changed_pid': True}, 'process changed during setup ANR recovery'),
        ):
            with self.subTest(options=options):
                adb = FirstRunAdb(**options)
                with self.fixture(adb) as (runner, artifacts, recorder):
                    with self.assertRaisesRegex(RuntimeFailure, message):
                        runner.run()
                    self.assertFalse((artifacts / 'summary.json').exists())
                    recorder.finish.assert_called_once()
                self.assertEqual(adb.commands.count(('shell', 'input', 'tap', '70', '130')), 1)

    def test_first_run_reuses_the_launch_recovery_budget(self):
        adb = FirstRunAdb(persist=True)
        adb.outcomes = [False, True]
        with self.fixture(adb) as (runner, artifacts, _):
            with self.assertRaisesRegex(RuntimeFailure, 'not the focused Android package'):
                runner.run()
            self.assertFalse((artifacts / 'summary.json').exists())
        self.assertEqual(adb.commands.count(('shell', 'input', 'tap', '70', '130')), 1)

    def test_late_foreign_anr_or_physical_device_is_never_closed(self):
        for options in (
            {'window': SETUP_WINDOW.replace(SETUP_PACKAGE, PACKAGE)},
            {'window': SETUP_WINDOW.replace(SETUP_PACKAGE, 'com.google.android.gms')},
            {'qemu': '0'},
        ):
            with self.subTest(options=options):
                adb = FirstRunAdb(**options)
                with self.fixture(adb) as (runner, artifacts, _):
                    with self.assertRaises(RuntimeFailure):
                        runner.run()
                    self.assertFalse((artifacts / 'summary.json').exists())
                self.assertFalse(any(command[:3] == ('shell', 'input', 'tap') for command in adb.commands))

    def test_replaced_setup_window_before_action_is_not_closed(self):
        adb = FirstRunAdb()
        original = adb.observe
        def observe():
            xml, window = original()
            if adb.observations > 1:
                window = window.replace('Window{123 ', 'Window{456 ')
            return xml, window
        adb.observe = observe
        with self.fixture(adb) as (runner, artifacts, _):
            with self.assertRaisesRegex(RuntimeFailure, 'setup ANR changed'):
                runner.run()
            self.assertFalse((artifacts / 'summary.json').exists())
        self.assertFalse(any(command[:3] == ('shell', 'input', 'tap') for command in adb.commands))

    def test_failed_close_action_is_not_retried_as_a_ui_observation(self):
        adb = FirstRunAdb()
        original = adb.run
        def run(*args, **kwargs):
            result = original(*args, **kwargs)
            if args[:3] == ('shell', 'input', 'tap'):
                raise RuntimeFailure('close action failed')
            return result
        adb.run = run
        with self.fixture(adb) as (runner, artifacts, _):
            with self.assertRaisesRegex(RuntimeFailure, 'close action failed'):
                runner.run()
            self.assertFalse((artifacts / 'summary.json').exists())
        self.assertEqual(adb.commands.count(('shell', 'input', 'tap', '70', '130')), 1)

    def test_late_recovery_does_not_extend_the_original_ui_deadline(self):
        adb = FirstRunAdb()
        with self.fixture(adb) as (runner, artifacts, _), patch(
            'tools.android_install.runner.time.monotonic', side_effect=[0, 0, 56]
        ):
            with self.assertRaisesRegex(RuntimeFailure, 'timed out waiting for first Flutter UI'):
                runner.run()
            self.assertFalse((artifacts / 'summary.json').exists())
        self.assertEqual(adb.commands.count(('shell', 'input', 'tap', '70', '130')), 1)


class ObservationDeadlineTests(unittest.TestCase):
    def test_android_queries_share_caller_deadline_and_reject_late_window(self):
        adb = Adb("emulator-5554", "deadline-test")
        clock = [0.0]
        commands = []
        def run(*args, **kwargs):
            commands.append((args, kwargs["timeout"]))
            clock[0] += 2
            return subprocess.CompletedProcess([], 0, b"<hierarchy/>")
        with patch.object(adb, "run", side_effect=run), \
                patch("tools.android_install.runner.time.monotonic", side_effect=lambda: clock[0]), \
                self.assertRaises(subprocess.TimeoutExpired):
            adb.observe(deadline=5)
        self.assertEqual([timeout for _, timeout in commands], [5, 3, 1])

    def test_expired_deadline_sends_no_device_command(self):
        adb = Adb("emulator-5554", "deadline-test")
        with patch.object(adb, "run") as run, \
                patch("tools.android_install.runner.time.monotonic", return_value=6), \
                self.assertRaises(subprocess.TimeoutExpired):
            adb.observe(deadline=5)
        run.assert_not_called()


class StorageReadinessTests(unittest.TestCase):
    def test_caller_receives_probe_errors_without_writing_default_output(self):
        adb = Adb("emulator-5554", "storage-test")
        results = [
            subprocess.CompletedProcess([], 1, b'', b''),
            subprocess.CompletedProcess([], 1, b'', b'not mounted'),
        ]
        with tempfile.TemporaryDirectory() as temporary:
            caller = Path(temporary) / 'caller'
            caller.mkdir()
            default = Path(temporary) / 'default-must-not-be-created'
            with patch('tools.android_install.runner.ARTIFACT_ROOT', default), patch.object(
                adb, 'run', side_effect=results
            ), patch('tools.android_install.runner.time.monotonic', side_effect=[0, 0, 21]), patch(
                'tools.android_install.runner.time.sleep'
            ):
                with self.assertRaisesRegex(RuntimeFailure, 'not writable within 20 seconds'):
                    adb.prepare_storage(output=caller)
            self.assertIn('not mounted', (caller / 'storage-readiness.log').read_text())
            self.assertFalse(default.exists())
            self.assertFalse(adb.remote_root_created)

    def test_delayed_mount_and_write_readiness_keep_original_errors(self):
        adb = Adb("emulator-5554", "storage-test")
        results = [
            (1, b""), (1, b"mkdir: No such file or directory"),
            (0, b""), (1, b"touch: external_primary not ready"), (0, b""), (0, b""),
        ]
        commands = []
        def run(*args, **kwargs):
            commands.append(args)
            code, error = results.pop(0)
            return subprocess.CompletedProcess(args, code, b"", error)
        with tempfile.TemporaryDirectory() as temporary, patch(
            'tools.android_install.runner.ARTIFACT_ROOT', Path(temporary)
        ), patch.object(adb, 'run', side_effect=run), patch(
            'tools.android_install.runner.time.sleep'
        ):
            adb.prepare_storage()
            self.assertTrue(adb.remote_root_created)
            self.assertEqual(commands.count(('shell', 'mkdir', adb.remote_root)), 2)
            self.assertEqual(commands.count(('shell', 'touch', adb.remote_prefix + 'storage-probe.mp4')), 2)
            log = (Path(temporary) / 'storage-readiness.log').read_text()
            self.assertIn('No such file or directory', log)
            self.assertIn('external_primary not ready', log)

    def test_unavailable_storage_has_a_deadline_and_does_not_become_owned(self):
        adb = Adb("emulator-5554", "storage-test")
        with tempfile.TemporaryDirectory() as temporary, patch(
            'tools.android_install.runner.ARTIFACT_ROOT', Path(temporary)
        ), patch.object(adb, 'run', return_value=subprocess.CompletedProcess([], 1, b'', b'not ready')), patch(
            'tools.android_install.runner.time.monotonic', side_effect=[0, 0, 21]
        ), patch('tools.android_install.runner.time.sleep'):
            with self.assertRaisesRegex(RuntimeFailure, 'not writable within 20 seconds'):
                adb.prepare_storage()
            self.assertFalse(adb.remote_root_created)
            self.assertIn('not ready', (Path(temporary) / 'storage-readiness.log').read_text())

    def test_existing_directory_is_never_reused(self):
        adb = Adb("emulator-5554", "storage-test")
        with patch.object(adb, 'run', return_value=subprocess.CompletedProcess([], 0, b'', b'')) as run:
            with self.assertRaisesRegex(RuntimeFailure, 'already exists'):
                adb.prepare_storage()
            self.assertEqual(run.call_count, 1)
            self.assertFalse(adb.remote_root_created)


class RecordingTests(unittest.TestCase):
    def test_foreground_exec_keeps_the_announced_pid_as_the_recorder(self):
        adb = Adb("emulator-5554", "recording-test")
        process = Mock(stdout=io.StringIO('INSTALL_RECORDER_PID=42\n'))
        with patch.object(adb, 'run', return_value=subprocess.CompletedProcess([], 0, b'', b'')), patch(
            'tools.android_install.runner.subprocess.Popen', return_value=process
        ) as popen:
            recording = NativeRecording(adb)
            recording.start()
            recording.reader.join(timeout=1)
            self.assertEqual(recording.pid, '42')
            command = popen.call_args.args[0][-1]
            self.assertIn('"$$"; exec screenrecord --verbose', command)
            self.assertNotIn('&', command)
            self.assertIn('--time-limit 90', command)

    def finish_case(self, *, timeout=False, never_exits=False, decode_status=0, foreign=False, exit_status=0):
        adb = Adb("emulator-5554", "recording-test")
        recording = NativeRecording(adb)
        recording.pid = '42'
        recording.started_at = 100
        process = Mock(stdout=None, returncode=exit_status)
        process.poll.side_effect = [None, None if never_exits or foreign else exit_status]
        process.wait.side_effect = (
            [subprocess.TimeoutExpired('adb', 20), subprocess.TimeoutExpired('adb', 62), 0]
            if never_exits else [subprocess.TimeoutExpired('adb', 20), 0, 0] if timeout else [0, 0]
        )
        recording.process = process
        def run(*args, **kwargs):
            output = b''
            if args[:2] == ('exec-out', 'cat'):
                output = (f"other\0{recording.remote}\0" if foreign else f"screenrecord\0{recording.remote}\0").encode()
            if args[0] == 'pull':
                Path(args[2]).write_bytes(b'ftypmoov' + bytes(8192))
            return subprocess.CompletedProcess(args, 0, output, b'')
        media_results = [
            subprocess.CompletedProcess([], 0, b'{"streams":[{"duration":"32.0","width":1080,"height":2400}]}', b''),
            subprocess.CompletedProcess([], decode_status, b'', b'decode failed' if decode_status else b''),
        ]
        return recording, process, patch.object(adb, 'run', side_effect=run), patch(
            'tools.android_install.runner.subprocess.run', side_effect=media_results
        )

    def test_slow_sigint_drain_waits_only_the_original_deadline_and_decodes(self):
        with tempfile.TemporaryDirectory() as temporary, patch(
            'tools.android_install.runner.ARTIFACT_ROOT', Path(temporary)
        ), patch('tools.android_install.runner.time.monotonic', side_effect=[125, 148]):
            recording, process, adb_patch, media_patch = self.finish_case(timeout=True)
            with adb_patch as adb_run, media_patch as media_run:
                recording.finish()
            self.assertEqual([call.kwargs['timeout'] for call in process.wait.call_args_list[:2]], [20, 62])
            self.assertEqual(sum(call.args[:3] == ('shell', 'kill', '-2') for call in adb_run.call_args_list), 1)
            self.assertEqual(media_run.call_count, 2)
            process.terminate.assert_not_called()
            metadata = json.loads((Path(temporary) / 'recording-metadata.json').read_text())
            self.assertEqual(metadata['finishRequestedAfterSeconds'], 25)
            self.assertEqual(metadata['streams'][0]['duration'], '32.0')

    def test_foreign_pid_stuck_recorder_and_bad_decode_still_fail(self):
        for options, error in (
            ({'foreign': True}, RuntimeFailure),
            ({'never_exits': True}, subprocess.TimeoutExpired),
            ({'decode_status': 1}, RuntimeFailure),
            ({'exit_status': 1}, RuntimeFailure),
        ):
            with self.subTest(options=options), tempfile.TemporaryDirectory() as temporary, patch(
                'tools.android_install.runner.ARTIFACT_ROOT', Path(temporary)
            ), patch('tools.android_install.runner.time.monotonic', side_effect=[125, 148]):
                recording, process, adb_patch, media_patch = self.finish_case(**options)
                with adb_patch, media_patch, self.assertRaises(error):
                    recording.finish()
                self.assertTrue((Path(temporary) / 'screenrecord.log').is_file())


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
