"""Execute the real wrapper's post-driver tail with fake native guard commands."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
BASH = ('C:/Program Files/Git/bin/bash.exe' if os.name == 'nt'
        and Path('C:/Program Files/Git/bin/bash.exe').is_file() else shutil.which('bash'))


@unittest.skipUnless(BASH, 'Bash is required to exercise the production wrapper')
class WrapperTests(unittest.TestCase):
    def run_tail(self, guest_exit, host_final, guest_final, production=True):
        source = (ROOT / 'tools/android_multi_device/run_together_smoke.sh').read_text(encoding='utf-8')
        marker = '\nset +e\nwait "$host_drive_pid"\n'
        self.assertEqual(source.count(marker), 1)
        tail = marker + source.split(marker, 1)[1]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / 'finish.sh'
            script.write_text('''#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
output_dir="$PWD"
host_output="$PWD/host"
guest_output="$PWD/guest"
host_driver_output="$PWD/host-driver"
guest_driver_output="$PWD/guest-driver"
mkdir -p "$host_output" "$guest_output" "$host_driver_output" "$guest_driver_output"
PHONE_SERIAL=emulator-5554
TABLET_SERIAL=emulator-5556
ADB=unused-adb
target="$TEST_TARGET"
python3() {
  [[ "$1" == -m && "$2" == tools.production_together.anr_guard ]] || return 97
  local role=''
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == --role ]]; then role="$2"; fi
    shift
  done
  printf 'final-%s\\n' "$role" >> calls.txt
  if [[ "$role" == host ]]; then return "$HOST_FINAL"; fi
  if [[ "$role" == guest ]]; then return "$GUEST_FINAL"; fi
  return 98
}
capture_device_diagnostics() { printf 'diagnostics-%s\\n' "$1" >> calls.txt; }
(printf '0\\n' > "$host_output/exit-code.txt"; printf 'host-done\\n' >> calls.txt) &
host_drive_pid=$!
(sleep 0.1; printf '%s\\n' "$GUEST_EXIT" > "$guest_output/exit-code.txt"; printf 'guest-done\\n' >> calls.txt) &
guest_drive_pid=$!
''' + tail, encoding='utf-8', newline='\n')
            result = subprocess.run([BASH, script.as_posix()], capture_output=True, text=True, timeout=10,
                env={**os.environ, 'GUEST_EXIT': str(guest_exit), 'HOST_FINAL': str(host_final),
                     'GUEST_FINAL': str(guest_final), 'TEST_TARGET':
                     'integration_test/production_together_test.dart' if production else 'integration_test/together_test.dart'})
            calls = (root / 'calls.txt').read_text().splitlines()
            statuses = {role: (root / role / 'exit-code.txt').read_text().strip() for role in ('host', 'guest')}
            summary = (root / 'native-anr-exits.tsv').read_text() if production else None
            if production:
                self.assertEqual((root / 'host/native-anr-final-exit-code.txt').read_text().strip(), str(host_final))
                self.assertEqual((root / 'guest/native-anr-final-exit-code.txt').read_text().strip(), str(guest_final))
            return result, calls, statuses, summary

    def assert_both_final_checks_follow_both_drivers(self, calls):
        self.assertLess(calls.index('host-done'), calls.index('final-host'))
        self.assertLess(calls.index('guest-done'), calls.index('final-host'))
        self.assertLess(calls.index('final-host'), calls.index('final-guest'))

    def test_guest_assertion_failure_does_not_skip_hosts_late_anr(self):
        result, calls, statuses, summary = self.run_tail(guest_exit=7, host_final=1, guest_final=0)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assert_both_final_checks_follow_both_drivers(calls)
        self.assertEqual(statuses, {'host': '0', 'guest': '7'})
        self.assertEqual(summary, 'role\tdriverExit\tfinalGuardExit\nhost\t0\t1\nguest\t7\t0\n')

    def test_first_final_failure_still_runs_the_other_final_guard(self):
        result, calls, statuses, summary = self.run_tail(guest_exit=0, host_final=1, guest_final=2)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assert_both_final_checks_follow_both_drivers(calls)
        self.assertEqual(statuses, {'host': '0', 'guest': '0'})
        self.assertIn('guest\t0\t2\n', summary)

    def test_all_four_statuses_must_pass(self):
        result, calls, _, _ = self.run_tail(guest_exit=0, host_final=0, guest_final=0)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_both_final_checks_follow_both_drivers(calls)
        self.assertFalse(any(call.startswith('diagnostics-') for call in calls))

    def test_nonproduction_has_no_native_final_commands(self):
        result, calls, _, _ = self.run_tail(guest_exit=0, host_final=1, guest_final=1, production=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(call.startswith('final-') for call in calls))


if __name__ == '__main__':
    unittest.main()
