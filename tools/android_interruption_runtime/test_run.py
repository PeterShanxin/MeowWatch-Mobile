import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch
import xml.etree.ElementTree as ET

from tools.android_install.runner import PACKAGE, RuntimeFailure
from tools.android_interruption_runtime.run import (
    FOCUS_HEADER, HELPER, LIFECYCLE_TAGS, Runner, focus_stack, lifecycle_events,
    package_uid, probe_events, require_focus, require_foreground_history, require_resumed_baseline,
    require_owned_avd,
)
from tools.android_lifecycle_runtime.run import Playback


NONCE = "a" * 32
AVD = "meowwatch_interruption_123_1"
BASH = ("C:/Program Files/Git/bin/bash.exe" if Path("C:/Program Files/Git/bin/bash.exe").is_file()
        else shutil.which("bash"))


def focus_row(package, uid, *, gain="GAIN", loss="none"):
    # Android 15 FocusRequester.dump schema, not a device capture.
    return (f"  source:android.os.BinderProxy@abc -- pack: {package} -- client: focus-client"
            f" -- gain: {gain} -- flags:  -- loss: {loss} -- notified: true -- limbofalse"
            f" -- uid: {uid} -- attr: AudioAttributes: usage=USAGE_MEDIA -- sdk:35")


def audio(*rows):
    return "AudioService state\n\n" + FOCUS_HEADER + "\n" + "\n".join(rows) + "\n\nNo external focus policy\n\n"


def event(name="requested", *, sequence=1, nonce=NONCE, pid=4321, uid=10179, result=1, **extra):
    value = dict(protocol=1, nonce=nonce, sequence=sequence, event=name, result=result,
                 gain=1, pid=pid, uid=uid, uptimeMs=1000 + sequence)
    value.update(extra)
    return "1789600000.100 4321 4321 I MWFocusProbe: " + json.dumps(value)


class FocusEvidenceTests(unittest.TestCase):
    def test_android_15_dump_requires_actual_top_owner_not_historical_text(self):
        raw = audio(focus_row(PACKAGE, 10178, loss="LOSS"), focus_row(HELPER, 10179))
        self.assertEqual(require_focus(raw, HELPER, 10179)[-1]["uid"], 10179)
        for changed in (raw.replace("uid: 10179", "uid: 10180"),
                        raw.replace("gain: GAIN --", "gain: GAIN_TRANSIENT --"),
                        raw.replace("loss: none", "loss: LOSS"),
                        audio(focus_row(HELPER, 10179), focus_row(PACKAGE, 10178)),
                        audio() + "historical requestAudioFocus " + HELPER,
                        audio(focus_row(HELPER, 10179), focus_row(HELPER, 10179)),
                        raw + "\n" + FOCUS_HEADER):
            with self.subTest(changed=changed), self.assertRaises(RuntimeFailure):
                require_focus(changed, HELPER, 10179)

    def test_empty_stack_is_distinct_from_missing_or_unrecognized_stack(self):
        self.assertEqual(focus_stack(audio()), [])
        for raw in ("", "AudioFocusEvent " + HELPER, FOCUS_HEADER + "\nunknown owner\n\n"):
            with self.subTest(raw=raw), self.assertRaises(RuntimeFailure):
                focus_stack(raw)

    def test_package_identity_requires_exact_single_user_zero_package(self):
        self.assertEqual(package_uid(f"package:{HELPER} uid:10179\n", HELPER), 10179)
        for value in (f"package:{HELPER}.other uid:10179", f"package:{HELPER} uid:110179",
                      f"package:{HELPER} uid:10179,110179", f"package:{HELPER} uid:root",
                      f"package:{HELPER} uid:10179\npackage:other uid:10001"):
            with self.assertRaises(RuntimeFailure):
                package_uid(value, HELPER)

    def test_focus_results_bind_nonce_log_pid_uid_sequence_and_device_time(self):
        raw = event(nonce="b" * 32) + "\n" + event() + "\n" + event("released", sequence=2)
        self.assertEqual([row["event"] for row in probe_events(raw, NONCE, 10179, 4321)], ["requested", "released"])
        for raw in (event(pid=123), event(uid=10180), event(sequence=2), event(gain=2),
                    event(protocol=2), event(uptimeMs=0), event(result=0),
                    event("watchdog-expired"), event("focus-change", result=-1),
                    event() + "\n" + event("released", sequence=2, uptimeMs=999),
                    "MWFocusProbe: " + event().split(": ", 1)[-1], event(unexpected=True)):
            with self.subTest(raw=raw), self.assertRaises(RuntimeFailure):
                probe_events(raw, NONCE, 10179, 4321)

    def test_background_events_or_lost_history_cannot_count_as_focus_acceptance(self):
        previous = [f"1789600000.000 100 101 I wm_on_paused_called: [1,{PACKAGE}.MainActivity,old]"]
        raw = "--------- beginning of events\n" + previous[0]
        self.assertEqual(lifecycle_events(raw), previous)
        require_foreground_history(previous, lifecycle_events(raw))
        other = raw + "\n1789600001.000 100 101 I wm_pause_activity: [0,other.package/.Activity]"
        require_foreground_history(previous, lifecycle_events(other))
        for changed in ([], previous + [previous[0].replace("old", "pause")]):
            with self.assertRaises(RuntimeFailure):
                require_foreground_history(previous, changed)
        for package, tag in ((PACKAGE, "am_anr"), (HELPER, "am_crash")):
            with self.assertRaises(RuntimeFailure):
                require_foreground_history(previous, lifecycle_events(
                    raw + f"\n1789600001.000 100 101 I {tag}: [0,4321,{package},reason]"))
        with self.assertRaises(RuntimeFailure):
            lifecycle_events("unparsed log " + PACKAGE)
        self.assertIn("wm_on_paused_called", LIFECYCLE_TAGS)
        self.assertIn("wm_on_stop_called", LIFECYCLE_TAGS)

    def test_helper_has_no_activity_instrumentation_network_or_open_command_receiver(self):
        root = ET.parse(Path(__file__).with_name("helper") / "AndroidManifest.xml").getroot()
        android = "{http://schemas.android.com/apk/res/android}"
        self.assertEqual(root.find("uses-sdk").get(android + "targetSdkVersion"), "35")
        application = root.find("application")
        self.assertEqual(application.get(android + "testOnly"), "true")
        self.assertEqual(application.get(android + "allowBackup"), "false")
        self.assertEqual([node.tag for node in application], ["service"])
        service = application.find("service")
        self.assertEqual(service.get(android + "permission"), "android.permission.DUMP")
        self.assertEqual(service.get(android + "foregroundServiceType"), "mediaPlayback")
        self.assertIsNone(root.find("instrumentation"))
        permissions = {node.get(android + "name") for node in root.findall("uses-permission")}
        self.assertNotIn("android.permission.INTERNET", permissions)

    def test_current_app_resume_callback_proves_lifecycle_logging_is_available(self):
        row = f"1789600000.000 4444 4444 I wm_on_resume_called: [1,{PACKAGE}.MainActivity,RESUME_ACTIVITY,0]"
        require_resumed_baseline([row], "4444")
        for history in ([], [row.replace("4444", "5555")],
                        [row.replace("wm_on_resume_called", "wm_on_paused_called")],
                        [row.replace(PACKAGE + ".MainActivity", "other.package.Activity")]):
            with self.subTest(history=history), self.assertRaisesRegex(RuntimeFailure, "resume callback"):
                require_resumed_baseline(history, "4444")
        self.assertIn("wm_on_resume_called", LIFECYCLE_TAGS)


class FlowTests(unittest.TestCase):
    def target(self, directory):
        root = Path(directory)
        apk, fixture, helper = root / "app.apk", root / "sync-fixture.mp4", root / "helper.apk"
        for path in (apk, fixture, helper):
            path.write_bytes(b"fixture")
        return Runner("emulator-5554", apk, fixture, root / "evidence", avd_name=AVD, helper_apk=helper)

    def test_acceptance_requires_pause_stability_release_and_manual_replay(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.target(directory)
            events = []
            runner.prepare = Mock(return_value={})
            runner.start_recording = lambda: events.append("record-start")
            runner.finish_recording = lambda **kwargs: events.append("record-finish")
            runner.load_fixture = Mock()
            runner.pid = Mock(return_value="4444")
            runner.foreground = lambda phase: events.append("foreground:" + phase)
            runner.focus = lambda phase, owner: events.append("focus:" + str(owner))
            runner.command = lambda action: events.append(action)
            runner.tap = lambda node: events.append("tap:" + node.get("content-desc"))
            xml = (f'<hierarchy><node package="{PACKAGE}" content-desc="Local mode"/>'
                   f'<node package="{PACKAGE}" content-desc="Play" clickable="true"/></hierarchy>')
            samples = [(0, False), (2, True), (5, True), (6, True), (8, False), (8, False),
                       (8, False), (8, False), (8, True), (11, True)]
            runner.sample = Mock(side_effect=[(xml, Playback(position, 90, playing)) for position, playing in samples])
            with patch("tools.android_interruption_runtime.run.time.sleep"):
                report = runner.run()
            self.assertTrue(report["completed"])
            self.assertEqual(events.count("tap:Play"), 2)
            self.assertLess(events.index("acquire"), events.index("focus:" + HELPER))
            self.assertLess(events.index("release"), events.index("focus:None"))
            self.assertEqual(report["replayAdvanceSeconds"], 3)
            self.assertIn("no GSM call", report["scope"])
            self.assertIn("quota", report["scope"])

    def test_foreground_pid_change_fails_before_audio_observation_can_mask_it(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.target(directory)
            runner.expected_pid = "4444"
            runner.pid = Mock(return_value="5555")
            runner.raw = Mock()
            with self.assertRaisesRegex(RuntimeFailure, "PID"):
                runner.foreground("same-app")
            runner.raw.assert_not_called()

    def test_granted_helper_event_requires_the_current_live_process(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.target(directory)
            runner.nonce, runner.helper_uid = NONCE, 10179
            runner.raw = Mock(side_effect=["Starting service: Intent { test }", event()])
            runner.adb.run = Mock(return_value=subprocess.CompletedProcess([], 0, b"9999\n"))
            with self.assertRaisesRegex(RuntimeFailure, "current helper process"):
                runner.command("acquire")
            self.assertTrue(runner.focus_requested)
            self.assertIsNone(runner.helper_pid)

    def test_acquire_release_uses_only_the_owned_service_and_same_nonce(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.target(directory)
            runner.nonce, runner.helper_uid = NONCE, 10179
            runner.raw = Mock(side_effect=["Starting service: Intent { test }", event(),
                                           "Starting service: Intent { test }", event() + "\n" + event("released", sequence=2)])
            runner.adb.run = Mock(return_value=subprocess.CompletedProcess([], 0, b"4321\n"))
            runner.command("acquire")
            runner.command("release")
            self.assertTrue(runner.focus_released)
            self.assertEqual(runner.helper_pid, 4321)
            calls = runner.raw.call_args_list
            for index, command, action in ((0, "start-foreground-service", "acquire"), (2, "startservice", "release")):
                self.assertEqual(calls[index].args[2:], ("shell", "am", command, "--user", "0", "-n",
                    HELPER + "/.FocusService", "-a", action, "--es", "nonce", NONCE))

    def test_denied_focus_service_is_not_retried_or_reported_as_granted(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.target(directory)
            runner.nonce, runner.helper_uid = NONCE, 10179
            runner.raw = Mock(return_value="Error: background service start not allowed")
            with self.assertRaisesRegex(RuntimeFailure, "did not accept"):
                runner.command("acquire")
            runner.raw.assert_called_once()
            self.assertIsNone(runner.helper_pid)

    def test_helper_release_must_remove_current_focus_owner(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.target(directory)
            runner.raw = Mock(return_value=audio(focus_row(HELPER, 10179)))
            runner.foreground = Mock()
            with self.assertRaisesRegex(RuntimeFailure, "remained"):
                runner.focus("after-release", None)
            self.assertEqual(runner.checks, [])
            runner.foreground.assert_not_called()

    def test_cleanup_without_owned_helper_never_stops_or_removes_it(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.target(directory)
            runner.adb.run = Mock()
            with patch("tools.android_lifecycle_runtime.run.Runner.cleanup"):
                runner.cleanup()
            runner.adb.run.assert_not_called()

    def test_uncertain_release_still_removes_owned_helper_and_fails_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.target(directory)
            runner.owns_helper = runner.focus_requested = True
            runner.command = Mock(side_effect=RuntimeFailure("unknown release"))
            runner.adb.run = Mock(side_effect=[subprocess.CompletedProcess([], 0, b""),
                                              subprocess.CompletedProcess([], 0, b"Success\n"),
                                              subprocess.CompletedProcess([], 1, b"")])
            with patch("tools.android_lifecycle_runtime.run.Runner.cleanup") as base, \
                    patch("tools.android_interruption_runtime.run.require_owned_avd") as guard:
                with self.assertRaisesRegex(RuntimeFailure, "uncertain"):
                    runner.cleanup()
            guard.assert_called_once_with(runner.adb, AVD)
            self.assertFalse(runner.owns_helper)
            self.assertEqual(runner.adb.run.call_args_list[0].args, ("shell", "am", "force-stop", HELPER))
            self.assertEqual(runner.adb.run.call_args_list[1].args, ("uninstall", HELPER))
            base.assert_called_once()


class OwnershipTests(unittest.TestCase):
    def adb(self):
        adb = Mock(serial="emulator-5554")
        properties = {("emu", "avd", "name"): (AVD + "\nOK\n").encode(),
                      ("shell", "getprop", "ro.kernel.qemu"): b"1",
                      ("shell", "getprop", "ro.build.version.sdk"): b"35",
                      ("shell", "getprop", "ro.product.cpu.abi"): b"x86_64"}
        adb.run.side_effect = lambda *args, **kwargs: subprocess.CompletedProcess(args, 0, properties[args], b"")
        return adb, properties

    def test_only_exact_named_task_avd_can_pass_before_device_mutations(self):
        adb, _ = self.adb()
        require_owned_avd(adb, AVD)
        for command, value in ((('emu', 'avd', 'name'), b'personal_pixel\nOK\n'),
                               (('emu', 'avd', 'name'), (AVD + '\nother\nOK\n').encode()),
                               (('shell', 'getprop', 'ro.kernel.qemu'), b'0'),
                               (('shell', 'getprop', 'ro.build.version.sdk'), b'34'),
                               (('shell', 'getprop', 'ro.product.cpu.abi'), b'arm64-v8a')):
            with self.subTest(command=command, value=value):
                adb, properties = self.adb()
                properties[command] = value
                with self.assertRaises(RuntimeFailure):
                    require_owned_avd(adb, AVD)
        for name in ('pixel_6', 'test', 'meowwatch_interruption_x; unsafe', '../avd'):
            adb, _ = self.adb()
            with self.subTest(name=name), self.assertRaises(RuntimeFailure):
                require_owned_avd(adb, name)
            adb.run.assert_not_called()
        adb, _ = self.adb()
        adb.serial = "R58physical"
        with self.assertRaises(RuntimeFailure):
            require_owned_avd(adb, AVD)
        adb.run.assert_not_called()

    def test_wrong_avd_never_reaches_inherited_app_uninstall_or_install(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = FlowTests().target(directory)
            runner.adb, properties = self.adb()
            properties[('emu', 'avd', 'name')] = b'personal_pixel\nOK\n'
            with patch("tools.android_lifecycle_runtime.run.Runner.prepare") as prepare:
                with self.assertRaisesRegex(RuntimeFailure, "not the named"):
                    runner.prepare()
            prepare.assert_not_called()
            self.assertFalse(runner.cleanup_authorized)
            self.assertFalse(runner.owns_helper)

    def test_cleanup_revalidates_avd_before_any_owned_resource_mutation(self):
        for resource in ("helper", "app", "observer", "recording"):
            with self.subTest(resource=resource), tempfile.TemporaryDirectory() as directory:
                runner = FlowTests().target(directory)
                runner.owns_helper = resource == "helper"
                runner.cleanup_authorized = resource == "app"
                runner.observer.owns_package = resource == "observer"
                runner.recording = Mock() if resource == "recording" else None
                runner.adb, properties = self.adb()
                properties[('emu', 'avd', 'name')] = b'replacement_pixel\nOK\n'
                runner.command = Mock()
                with patch("tools.android_lifecycle_runtime.run.Runner.cleanup") as cleanup:
                    with self.assertRaisesRegex(RuntimeFailure, "not the named"):
                        runner.cleanup()
                cleanup.assert_not_called()
                runner.command.assert_not_called()
                self.assertEqual([call.args for call in runner.adb.run.call_args_list], [('emu', 'avd', 'name')])


@unittest.skipUnless(BASH, "Bash is required to exercise the actual CI wrapper")
class FixtureServerOwnershipTests(unittest.TestCase):
    def run_ci(self, root, *, existing=False, runtime_status=0, stop_status=0):
        root = Path(root)
        scripts = root / "tools/android_multi_device"
        scripts.mkdir(parents=True)
        state = root / "build/android-interruption-server"
        state.mkdir(parents=True)
        if existing:
            (state / "server.env").write_text("PREEXISTING_SERVER=1\n", encoding="utf-8")
        (scripts / "start_fixture_server.sh").write_text(
            '#!/usr/bin/env bash\nset -euo pipefail\n'
            'printf "start\\n" >> calls.log\n'
            'if [[ -f build/android-interruption-server/server.env ]]; then exit 3; fi\n'
            'printf "OWNED_SERVER=1\\n" > build/android-interruption-server/server.env\n', encoding="utf-8")
        (scripts / "stop_fixture_server.sh").write_text(
            '#!/usr/bin/env bash\nprintf "stop\\n" >> calls.log\n'
            'exit "$TEST_STOP_STATUS"\n', encoding="utf-8")
        binary = root / "bin"
        binary.mkdir()
        timeout = binary / "timeout"
        timeout.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$@" > runner-arguments.log\n'
                           'exit "$TEST_RUNTIME_STATUS"\n', encoding="utf-8")
        timeout.chmod(0o755)
        script = root / "ci.sh"
        script.write_bytes(Path(__file__).with_name("ci.sh").read_bytes())
        env = {**os.environ, "INTERRUPTION_AVD_NAME": AVD,
               "TEST_RUNTIME_STATUS": str(runtime_status), "TEST_STOP_STATUS": str(stop_status)}
        # Set PATH inside Bash so Git Bash and Linux resolve the same task-local
        # timeout stub. Neither the helper APK nor a real server is launched.
        result = subprocess.run([BASH, "-c", 'PATH="$PWD/bin:$PATH" bash ci.sh'], cwd=root,
                                env=env, capture_output=True, timeout=15)
        return result, (root / "calls.log").read_text(encoding="utf-8").splitlines()

    def test_preexisting_server_state_start_failure_never_calls_stop(self):
        with tempfile.TemporaryDirectory() as directory:
            result, calls = self.run_ci(directory, existing=True)
            self.assertEqual(result.returncode, 3, result.stderr.decode())
            self.assertEqual(calls, ["start"])
            self.assertFalse((Path(directory) / "runner-arguments.log").exists())
            self.assertEqual((Path(directory) / "build/android-interruption-server/server.env").read_text(),
                             "PREEXISTING_SERVER=1\n")

    def test_only_successfully_started_server_is_cleaned_after_pass_or_failure(self):
        for status in (0, 7):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as directory:
                result, calls = self.run_ci(directory, runtime_status=status)
                self.assertEqual(result.returncode, status, result.stderr.decode())
                self.assertEqual(calls, ["start", "stop"])
                arguments = (Path(directory) / "runner-arguments.log").read_text().splitlines()
                self.assertEqual(arguments[arguments.index("--avd-name") + 1], AVD)

    def test_owned_server_cleanup_failure_prevents_a_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            result, calls = self.run_ci(directory, stop_status=2)
            self.assertEqual(result.returncode, 1, result.stderr.decode())
            self.assertEqual(calls, ["start", "stop"])


if __name__ == "__main__":
    unittest.main()
