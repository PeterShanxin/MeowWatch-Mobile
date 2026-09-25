"""Native ANR guard contracts; no Flutter or Android process is launched."""

import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

from tools.production_together.anr_guard import (
    EVENT_ARGS, PACKAGE, Events, Guard, GuardFailure, OwnedDriver,
)


def anr(pid=3306, package=PACKAGE, stamp='1770000015.200'):
    return f'{stamp}  902  1002 I am_anr : [0,{pid},{package},0,Input dispatching timed out]'


def started(pid=3306):
    return f'1770000010.000  902  1002 I am_proc_start: [0,{pid},10100,{PACKAGE},activity,MainActivity]'


class EventTests(unittest.TestCase):
    def test_exact_package_and_current_pid(self):
        events = Events('')
        own = anr()
        _, failures = events.consume('\n'.join((anr(package=PACKAGE + '.other'), anr(pid=999), own)), 3306)
        self.assertEqual(failures, [own])

    def test_historical_event_is_not_current_even_when_pid_reused(self):
        old = anr()
        events = Events(old)
        self.assertEqual(events.consume(old, 3306), ([], []))
        new = anr(stamp='1770000020.000')
        self.assertEqual(events.consume(old + '\n' + new, 3306)[1], [new])

    def test_fresh_start_catches_anr_after_app_process_disappears(self):
        events = Events('')
        self.assertEqual(events.consume(started() + '\n' + anr(), None)[1], [anr()])
        self.assertEqual(events.consume(started() + '\n' + anr(), None), ([], []))


class GuardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.guard = Guard('adb', 'emulator-5554', 'host', self.root / 'host', self.root / 'failed.json')

    def ready(self):
        self.guard.output.mkdir()
        self.guard.owns_output = True
        self.guard.events = Events('')

    def test_active_probe_preserves_first_event_without_ui_automation(self):
        self.ready()
        raw = (started() + '\n' + anr() + '\n' + anr(stamp='1770000020.000')).encode()
        with patch.object(self.guard, 'run_adb', side_effect=[b'3306', raw]) as adb:
            with self.assertRaisesRegex(GuardFailure, 'ANR observed'):
                self.guard.probe()
        self.assertEqual(adb.call_args_list[1].args, EVENT_ARGS)
        self.assertEqual(adb.call_count, 2)
        self.assertEqual((self.guard.output / 'first-anr.log').read_text().strip(), anr())
        self.assertIn(anr(), (self.guard.output / 'events.log').read_text())
        self.assertEqual(json.loads((self.guard.output / 'probes.jsonl').read_text())['pid'], 3306)

    def test_total_probe_budget_is_not_per_command(self):
        self.ready()
        with patch('tools.production_together.anr_guard.time.monotonic', side_effect=[0, 0, 5.5]), patch.object(
            self.guard, 'run_adb', side_effect=[b'3306', b'']
        ) as adb:
            self.guard.probe()
        self.assertEqual([call.kwargs['timeout'] for call in adb.call_args_list], [3, 0.5])

    def test_final_window_anr_fails_even_after_successful_driver(self):
        driver = Mock(pid=42)
        driver.process.poll.return_value = 0
        def probe(*, boundary='active'):
            if boundary == 'after-driver':
                raise GuardFailure('current focused window is a MeowWatch ANR dialog')
        with patch.object(self.guard, 'start', side_effect=self.ready), patch.object(self.guard, 'probe', side_effect=probe), patch.object(
            self.guard, 'collect'
        ), patch('tools.production_together.anr_guard.OwnedDriver', return_value=driver):
            self.assertEqual(self.guard.supervise(['driver']), 1)
        result = json.loads((self.guard.output / 'result.json').read_text())
        self.assertFalse(result['passed'])
        self.assertEqual(result['driverExit'], 0)

    def test_failure_latch_stops_each_roles_own_driver_before_collection(self):
        self.ready()
        driver = Mock(pid=42)
        order = []
        driver.stop.side_effect = lambda: order.append('stop')
        with patch.object(self.guard, 'start'), patch.object(self.guard, 'probe', side_effect=GuardFailure('own ANR')), patch.object(
            self.guard, 'collect', side_effect=lambda: order.append('collect')
        ), patch('tools.production_together.anr_guard.OwnedDriver', return_value=driver):
            self.assertEqual(self.guard.supervise(['driver']), 1)
        self.assertEqual(order, ['stop', 'collect'])
        self.assertEqual(json.loads(self.guard.latch.read_text())['role'], 'host')
        guest = Guard('adb', 'emulator-5556', 'guest', self.root / 'guest', self.guard.latch)
        with patch.object(guest, 'collect'), patch('tools.production_together.anr_guard.OwnedDriver') as spawn:
            self.assertEqual(guest.supervise(['driver']), 1)
        spawn.assert_not_called()
        self.assertEqual(json.loads(self.guard.latch.read_text())['role'], 'host')
        self.assertFalse(json.loads((guest.output / 'result.json').read_text())['passed'])

    def test_running_peer_observes_latch(self):
        self.ready()
        self.guard.latch_failure('guest ANR')
        with patch.object(self.guard, 'run_adb') as adb:
            with self.assertRaisesRegex(GuardFailure, 'peer'):
                self.guard.probe()
        adb.assert_not_called()

    def test_after_both_roles_uses_original_baseline_and_prior_pid(self):
        self.ready()
        old = anr(pid=2000)
        (self.guard.output / 'baseline-events.log').write_text(old)
        (self.guard.output / 'result.json').write_text(json.dumps({
            'passed': True, 'role': 'host', 'serial': 'emulator-5554'}))
        (self.guard.output / 'probes.jsonl').write_text(json.dumps({'knownRunPids': [3306]}) + '\n')
        final = Guard('adb', 'emulator-5554', 'host', self.root / 'final',
                      self.guard.latch, self.guard.output)
        # App has disappeared after an ANR in the gap between role completions.
        with patch.object(final, 'run_adb', side_effect=[b'1', b'', (old + '\n' + anr()).encode()]), patch.object(
            final, 'collect'
        ), patch('tools.production_together.anr_guard.OwnedDriver') as spawn:
            self.assertEqual(final.supervise([]), 1)
        spawn.assert_not_called()
        self.assertEqual((final.output / 'first-anr.log').read_text().strip(), anr())

    def test_start_and_successful_end_require_actual_focus(self):
        with patch.object(self.guard, 'run_adb', side_effect=[
            b'1', anr(pid=2000).encode(), b'', anr(pid=2000).encode(),
            b'mCurrentFocus=Window{abc u0 com.android.launcher3/.Launcher}',
            b'3306', started().encode(), b'3306', started().encode(),
            f'mCurrentFocus=Window{{abc u0 {PACKAGE}/.MainActivity}}'.encode(),
        ]), patch('tools.production_together.anr_guard.OwnedDriver') as spawn:
            spawn.return_value.pid = 42
            spawn.return_value.process.poll.return_value = 0
            self.assertEqual(self.guard.supervise(['driver']), 0)
        self.assertTrue(json.loads((self.guard.output / 'result.json').read_text())['passed'])
        self.assertTrue((self.guard.output / 'after-driver-window.txt').is_file())
        self.assertFalse(self.guard.latch.exists())

    def test_failed_role_replay_ignores_peer_latch_and_preserves_original_anr(self):
        self.ready()
        prior = {'passed': False, 'role': 'host', 'serial': 'emulator-5554', 'driverExit': 7}
        (self.guard.output / 'baseline-events.log').write_text('')
        (self.guard.output / 'result.json').write_text(json.dumps(prior))
        (self.guard.output / 'first-anr.log').write_text('original first ANR')
        (self.guard.output / 'probes.jsonl').write_text(json.dumps({'knownRunPids': [3306]}) + '\n')
        self.guard.latch_failure('peer already failed')
        original_latch = self.guard.latch.read_bytes()
        final = Guard('adb', 'emulator-5554', 'host', self.root / 'final',
                      self.guard.latch, self.guard.output)
        with patch.object(final, 'run_adb', side_effect=[b'1', b'3306', anr().encode()]), patch.object(final, 'collect') as collect:
            self.assertEqual(final.supervise([]), 1)
        collect.assert_called_once()
        self.assertEqual((final.output / 'first-anr.log').read_text().strip(), anr())
        self.assertEqual((self.guard.output / 'first-anr.log').read_text(), 'original first ANR')
        self.assertEqual(json.loads((final.output / 'prior-guard-result.json').read_text()), prior)
        self.assertEqual(self.guard.latch.read_bytes(), original_latch)
        self.assertTrue(json.loads((final.output / 'result.json').read_text())['sharedFailureLatchedAtStart'])

    def test_collection_timeouts_keep_partial_evidence_and_never_touch_dialog(self):
        self.ready()
        def timeout(command, **kwargs):
            raise subprocess.TimeoutExpired(command, kwargs['timeout'], output=b'partial', stderr=b'slow')
        with patch('tools.production_together.anr_guard.subprocess.run', side_effect=timeout) as run:
            self.guard.collect()
        calls = run.call_args_list
        self.assertEqual([call.kwargs['timeout'] for call in calls], [3, 8, 4, 4, 8, 2, 2])
        self.assertIn('lastanr', calls[1].args[0])
        self.assertEqual(calls[4].args[0][-1], calls[5].args[0][-1])
        self.assertEqual(calls[4].args[0][-1], calls[6].args[0][-1])
        self.assertTrue(all('input' not in call.args[0] and 'force-stop' not in call.args[0] and 'root' not in call.args[0] for call in calls))
        self.assertEqual((self.guard.output / 'activity-lastanr.txt').read_bytes(), b'partial')
        self.assertTrue(all('timeoutSeconds' in row for row in json.loads((self.guard.output / 'diagnostics.json').read_text())))

    def test_existing_evidence_is_never_overwritten(self):
        self.ready()
        (self.guard.output / 'result.json').write_text('original')
        # A separate invocation has not acquired ownership of this directory.
        guard = Guard('adb', 'emulator-5554', 'host', self.guard.output, self.guard.latch)
        with patch.object(guard, 'collect') as collect:
            self.assertEqual(guard.supervise(['driver']), 1)
        collect.assert_not_called()
        self.assertEqual((guard.output / 'result.json').read_text(), 'original')


class OwnedProcessTests(unittest.TestCase):
    def test_driver_is_created_in_its_own_session(self):
        process = Mock(pid=4242)
        with patch('tools.production_together.anr_guard.subprocess.Popen', return_value=process) as spawn:
            with patch.object(os, 'name', 'posix'):
                driver = OwnedDriver(['timeout', '540s', 'flutter', 'drive'])
        self.assertEqual(driver.pid, 4242)
        spawn.assert_called_once_with(['timeout', '540s', 'flutter', 'drive'], start_new_session=True)

    def driver(self):
        driver = object.__new__(OwnedDriver)
        driver.pid = 4242
        driver.process = Mock(returncode=None)
        return driver

    def test_stop_only_exact_created_session_and_group(self):
        driver = self.driver()
        with patch.object(os, 'getpgid', return_value=4242, create=True), patch.object(os, 'getsid', return_value=4242, create=True), patch.object(os, 'killpg', create=True) as kill, patch.object(signal, 'SIGKILL', 9, create=True):
            driver.stop()
        kill.assert_called_once_with(4242, 9)
        driver.process.wait.assert_called_once_with(timeout=5)

    def test_changed_group_is_not_signalled(self):
        driver = self.driver()
        with patch.object(os, 'getpgid', return_value=4243, create=True), patch.object(os, 'killpg', create=True) as kill:
            with self.assertRaisesRegex(GuardFailure, 'ownership changed'):
                driver.stop()
        kill.assert_not_called()

    def test_reaped_driver_pid_is_not_reused_for_signal(self):
        driver = self.driver()
        driver.process.returncode = 0
        with patch.object(os, 'getpgid', create=True) as group, patch.object(os, 'killpg', create=True) as kill:
            driver.stop()
        group.assert_not_called()
        kill.assert_not_called()


if __name__ == '__main__':
    unittest.main()
