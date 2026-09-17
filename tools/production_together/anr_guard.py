"""Fail production Together on a native app ANR without dismissing its dialog."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
from uuid import uuid4

from tools.app_journey.system_anr_preflight import focused_anr_package
from tools.android_install.runner import PACKAGE
from tools.billing_runtime.native_dialog import UnsafeDialog


EVENT_ARGS = ('logcat', '-b', 'events', '-d', '-v', 'epoch',
              'am_proc_start:I', 'am_anr:I', '*:S')
MAX_LOG_BYTES = 8 * 1024 * 1024


class GuardFailure(RuntimeError):
    pass


def event(line: str) -> tuple[str, int, str] | None:
    # Android EventLogTags: am_anr=[user,pid,package,flags,reason],
    # am_proc_start=[user,pid,uid,process,type,component].
    match = re.search(r'\bI\s+(am_anr|am_proc_start)\s*:\s*\[([^\r\n]*)\]\s*$', line)
    if match is None:
        return None
    fields = match[2].split(',')
    index = 2 if match[1] == 'am_anr' else 3
    if len(fields) <= index or not re.fullmatch(r'[1-9][0-9]*', fields[1]):
        raise GuardFailure('malformed native ANR/process event')
    return match[1], int(fields[1]), fields[index]


class Events:
    def __init__(self, baseline: str) -> None:
        self.seen = set(baseline.splitlines())
        self.pids: set[int] = set()

    def consume(self, text: str, current_pid: int | None) -> tuple[list[str], list[str]]:
        if current_pid is not None:
            self.pids.add(current_pid)
        fresh, failures = [], []
        for line in text.splitlines():
            if line in self.seen:
                continue
            self.seen.add(line)
            fresh.append(line)
            parsed = event(line)
            if parsed is None:
                continue
            kind, pid, package = parsed
            if package != PACKAGE:
                continue
            if kind == 'am_proc_start':
                self.pids.add(pid)
            elif pid in self.pids:
                failures.append(line)
        return fresh, failures


class OwnedDriver:
    def __init__(self, command: list[str]) -> None:
        if os.name != 'posix':
            raise GuardFailure('native ANR driver guard requires POSIX process groups')
        self.process = subprocess.Popen(command, start_new_session=True)
        self.pid = self.process.pid

    def stop(self) -> None:
        # Keep the leader unreaped until the group is signalled, preventing PID
        # reuse. GNU timeout remains group leader in this newly created session.
        if self.process.returncode is not None:
            return
        try:
            if os.getpgid(self.pid) != self.pid or os.getsid(self.pid) != self.pid:
                raise GuardFailure('driver process group ownership changed; refusing signal')
            # Host-side only. A graceful flutter shutdown can force-stop the app
            # and erase the ANR dialog before native evidence is captured.
            os.killpg(self.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        self.process.wait(timeout=5)


class Guard:
    def __init__(self, adb: str, serial: str, role: str, output: Path, latch: Path,
                 after_roles: Path | None = None) -> None:
        if re.fullmatch(r'emulator-[0-9]+', serial) is None or role not in ('host', 'guest'):
            raise ValueError('guard requires an explicit emulator and host/guest role')
        self.prefix = [adb, '-s', serial]
        self.serial, self.role, self.output, self.latch = serial, role, output, latch
        self.events: Events | None = None
        self.probes = 0
        self.owns_output = False
        self.after_roles = after_roles

    def run_adb(self, *arguments: str, timeout: float) -> bytes:
        result = subprocess.run(self.prefix + list(arguments), capture_output=True,
                                timeout=timeout, check=False)
        if result.returncode:
            # pidof returns 1 when Flutter has not installed/launched the app yet.
            if arguments[:2] == ('shell', 'pidof') and result.returncode == 1 and not result.stdout.strip():
                return b''
            raise GuardFailure(f'native ANR probe command failed: {arguments[0]} exit {result.returncode}')
        if len(result.stdout) > MAX_LOG_BYTES:
            raise GuardFailure('native ANR probe exceeded its output bound')
        return result.stdout

    def latch_failure(self, reason: str) -> None:
        data = json.dumps({'role': self.role, 'serial': self.serial, 'failure': reason,
                           'observedAtUnixSeconds': time.time()}).encode()
        try:
            with self.latch.open('xb') as stream:
                stream.write(data)
        except FileExistsError:
            pass

    def start(self) -> None:
        self.output.mkdir(parents=True, exist_ok=False)
        self.owns_output = True
        if self.after_roles is None and self.latch.exists():
            raise GuardFailure('peer native ANR guard has already failed')
        if self.run_adb('shell', 'getprop', 'ro.kernel.qemu', timeout=2).strip() != b'1':
            raise GuardFailure('native ANR guard requires a verified emulator')
        if self.after_roles is None:
            baseline = self.run_adb(*EVENT_ARGS, timeout=3).decode('utf-8', errors='strict')
        else:
            prior = json.loads((self.after_roles / 'result.json').read_text(encoding='utf-8'))
            if type(prior.get('passed')) is not bool or prior.get('role') != self.role or prior.get('serial') != self.serial:
                raise GuardFailure('final native ANR check requires this role\'s original guard result')
            # A driver failure (for example a Dart assertion) does not make the
            # original native baseline unusable. Keep both verdicts separate.
            (self.output / 'prior-guard-result.json').write_text(json.dumps(prior, indent=2), encoding='utf-8')
            baseline = (self.after_roles / 'baseline-events.log').read_text(encoding='utf-8')
        (self.output / 'baseline-events.log').write_text(baseline, encoding='utf-8')
        self.events = Events(baseline)
        if self.after_roles is not None:
            for line in (self.after_roles / 'probes.jsonl').read_text(encoding='utf-8').splitlines():
                pids = json.loads(line)['knownRunPids']
                if not isinstance(pids, list) or any(type(pid) is not int or pid <= 0 for pid in pids):
                    raise GuardFailure('final native ANR check has invalid prior PIDs')
                self.events.pids.update(pids)
        self.probe(boundary='after-both-drivers' if self.after_roles else 'before-driver')

    def probe(self, *, boundary: str = 'active') -> None:
        if self.after_roles is None and self.latch.exists():
            raise GuardFailure('peer native ANR guard failed')
        # One probe has a total six-second budget, including its subprocesses.
        deadline = time.monotonic() + 6
        def read(*args: str) -> bytes:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise GuardFailure('native ANR probe exceeded six seconds')
            return self.run_adb(*args, timeout=min(3, remaining))

        raw_pid = read('shell', 'pidof', PACKAGE).strip()
        if raw_pid and re.fullmatch(rb'[1-9][0-9]*', raw_pid) is None:
            raise GuardFailure('native ANR probe found ambiguous application PIDs')
        pid = int(raw_pid) if raw_pid else None
        raw = read(*EVENT_ARGS)
        assert self.events is not None
        fresh, failures = self.events.consume(raw.decode('utf-8', errors='strict'), pid)
        # Append new original lines; the first ANR is never replaced by a tail.
        with (self.output / 'events.log').open('a', encoding='utf-8') as stream:
            stream.write(''.join(line + '\n' for line in fresh))
        self.probes += 1
        with (self.output / 'probes.jsonl').open('a', encoding='utf-8') as stream:
            stream.write(json.dumps({'phase': boundary, 'unixSeconds': time.time(),
                'pid': pid, 'knownRunPids': sorted(self.events.pids),
                'eventBytes': len(raw), 'eventSha256': hashlib.sha256(raw).hexdigest()}) + '\n')
        if failures:
            (self.output / 'first-anr.log').write_text(failures[0] + '\n', encoding='utf-8')
            raise GuardFailure('native MeowWatch ANR observed for this driver run')
        if boundary != 'active':
            window = read('shell', 'dumpsys', 'window', 'displays').decode('utf-8', errors='replace')
            (self.output / f'{boundary}-window.txt').write_text(window, encoding='utf-8')
            if focused_anr_package(window) == PACKAGE:
                raise GuardFailure('current focused window is a MeowWatch ANR dialog')

    def collect(self) -> None:
        # Failure-only diagnostics. No app stop, dialog input, root, or service
        # restart. Every command is bounded; incomplete evidence stays explicit.
        diagnostics = []
        def capture(name: str, arguments: tuple[str, ...], timeout: float) -> bool:
            try:
                result = subprocess.run(self.prefix + list(arguments), capture_output=True,
                                        timeout=timeout, check=False)
                (self.output / name).write_bytes(result.stdout)
                (self.output / (name + '.stderr')).write_bytes(result.stderr)
                diagnostics.append({'file': name, 'exitCode': result.returncode})
                return result.returncode == 0
            except subprocess.TimeoutExpired as error:
                (self.output / name).write_bytes(error.stdout or b'')
                (self.output / (name + '.stderr')).write_bytes(error.stderr or b'')
                diagnostics.append({'file': name, 'timeoutSeconds': timeout})
                return False
            except OSError as error:
                diagnostics.append({'file': name, 'failure': type(error).__name__})
                return False
        capture('failure-window.txt', ('shell', 'dumpsys', 'window', 'displays'), 3)
        capture('activity-lastanr.txt', ('shell', 'dumpsys', 'activity', 'lastanr'), 8)
        capture('failure-logcat.txt', ('logcat', '-b', 'all', '-d', '-t', '1200', '-v', 'threadtime'), 4)
        capture('failure.png', ('exec-out', 'screencap', '-p'), 4)
        remote = f'/data/local/tmp/meowwatch-anr-{uuid4().hex}.xml'
        capture('ui-dump.txt', ('shell', 'uiautomator', 'dump', '--compressed', remote), 8)
        capture('failure.xml', ('exec-out', 'cat', remote), 2)
        capture('ui-cleanup.txt', ('shell', 'rm', '-f', remote), 2)
        (self.output / 'diagnostics.json').write_text(json.dumps(diagnostics, indent=2), encoding='utf-8')

    def supervise(self, command: list[str], max_seconds: int = 570) -> int:
        driver = None
        result: dict[str, object] = {'role': self.role, 'serial': self.serial, 'passed': False,
            'mode': 'after-both-drivers' if self.after_roles else 'supervise',
            'sharedFailureLatchedAtStart': self.latch.exists()}
        try:
            self.start()
            if self.after_roles is not None:
                result['passed'] = True
                return 0
            driver = OwnedDriver(command)
            result['driverProcessGroup'] = driver.pid
            deadline = time.monotonic() + max_seconds
            while True:
                self.probe()
                status = driver.process.poll()
                if status is not None:
                    result['driverExit'] = status
                    self.probe(boundary='after-driver')
                    result['passed'] = status == 0
                    return status if status >= 0 else 1
                if time.monotonic() >= deadline:
                    raise GuardFailure('owned driver exceeded native ANR guard deadline')
                time.sleep(2)
        except (GuardFailure, UnsafeDialog, OSError, subprocess.TimeoutExpired, ValueError, KeyError) as error:
            reason = str(error) if isinstance(error, GuardFailure) else type(error).__name__
            result['failure'] = reason
            self.latch_failure(reason)
            if driver is not None:
                try:
                    driver.stop()
                except (GuardFailure, OSError, subprocess.TimeoutExpired) as stop_error:
                    result['driverStopFailure'] = str(stop_error)
            if self.owns_output:
                self.collect()
            print(f'NATIVE_TOGETHER_ANR_GUARD_FAIL: {reason}', file=sys.stderr, flush=True)
            return 1
        finally:
            if self.owns_output:
                result['probes'] = self.probes
                (self.output / 'result.json').write_text(json.dumps(result, indent=2), encoding='utf-8')


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', required=True)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--role', required=True, choices=('host', 'guest'))
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--failure-latch', type=Path, required=True)
    parser.add_argument('--after-roles', type=Path)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if bool(command) == bool(args.after_roles):
        parser.error('provide either an owned driver command after -- or --after-roles')
    def interrupted(signum, frame):
        raise GuardFailure(f'native ANR guard interrupted by signal {signum}')
    for signum in (signal.SIGINT, signal.SIGTERM):
        signal.signal(signum, interrupted)
    return Guard(args.adb, args.serial, args.role, args.output, args.failure_latch,
                 args.after_roles).supervise(command)


if __name__ == '__main__':
    raise SystemExit(main())
