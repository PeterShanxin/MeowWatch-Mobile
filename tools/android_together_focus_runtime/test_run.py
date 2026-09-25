"""Mocked receipt checks; device acceptance only occurs in hosted Android CI."""

from __future__ import annotations

import copy
from http.client import HTTPConnection
import json
import threading
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from unittest.mock import Mock, patch

from tools.android_install.runner import PACKAGE, RuntimeFailure
from tools.android_interruption_runtime.run import HELPER, FOCUS_HEADER, require_focus
from tools.android_lifecycle_runtime.prepare_avd import ORIGINAL, prepare
from tools.android_multi_device.device_readiness import MeasurementError
from tools.android_multi_device.prepare_sdk_setup import LAUNCHER_HOME
from tools.android_together_focus_runtime.run import (
    AVD_NAME, STAGES, FocusSession, StageServer, await_boot_ready, require_prelaunch_home, validate_journey,
)


def snapshot(*, playing: bool, paused: bool, position: int) -> dict:
    return {"nativeReady": True, "nativePlaying": playing, "nativeBuffering": False,
            "nativePositionMs": position, "nativeDurationMs": 180000, "nativeError": None,
            "peerPaused": paused, "peerPositionMs": position, "peerSetter": "Focus Host"}


def receipt() -> tuple[dict, list[dict]]:
    stages = [{"stage": name, "completed": True, "event": {"protocol": 2}} for name in STAGES]
    stages[0].update(deviceElapsedRealtimeMs=100000, appPid="1234", appForegroundBeforePeerPlay=True)
    stages[1].update(appPid="1234", autoReleaseMs=350, limitMs=3000,
                     fromPrePeerPlayMarkerToReleaseMs=1230, nativeUi={"playing": False},
                     appOwnedFocusAfterPeerPlay=True,
                     request={"event": "requested", "result": 1, "gain": 2,
                              "requestStartedElapsedRealtimeMs": 100800, "elapsedRealtimeMs": 100830},
                     release={"event": "released", "result": 1, "gain": 2,
                              "elapsedRealtimeMs": 101230})
    cases = []
    for index, mode in enumerate(("permanent", "transient")):
        start = 5000 + index * 10000
        cases.append({"mode": mode, "settledPlaying": {"continuousPlayingMs": 4100,
                      "nativeAdvanceMs": 3600, "peerUnpausedThroughout": True},
                      "noAutoplayMonitor": {"monitoredMs": 9000, "nativeEvents": 2,
                      "roomEvents": 8, "forbiddenPlayEvents": []},
                      "before": snapshot(playing=True, paused=False, position=start),
                      "paused": snapshot(playing=False, paused=True, position=start + 900),
                      "held": snapshot(playing=False, paused=True, position=start + 900),
                      "afterRelease": snapshot(playing=False, paused=True, position=start + 900),
                      "explicitReplay": snapshot(playing=True, paused=False, position=start + 2000),
                      "acquire": stages[index * 2 + 2], "release": stages[index * 2 + 3],
                      "testSidePauseDuringInterruption": False})
    early = {"peerName": "Focus Protocol Peer", "tlsPeerPlay": True,
             "ready": stages[0], "acquire": stages[1], "testSidePauseDuringInterruption": False,
             "before": {**snapshot(playing=True, paused=False, position=3000), "peerSetter": "Focus Protocol Peer"},
             "paused": snapshot(playing=False, paused=True, position=3100),
             "afterRelease": snapshot(playing=False, paused=True, position=3100),
             "explicitReplay": snapshot(playing=True, paused=False, position=3900),
             "noAutoplayMonitor": {"monitoredMs": 4300, "nativeEvents": 3,
                                   "sawNativePause": True, "sawRoomPause": True,
                                   "firstNativePauseElapsedMs": 300,
                                   "forbiddenNativePlayEvents": [], "forbiddenRoomPlayEvents": []}}
    return {"togetherFocus": {"result": "passed", "peerCompletedTlsHello": True,
                               "earlyShort": early, "cases": cases}}, stages


class ReceiptTests(unittest.TestCase):
    def test_cold_fallback_home_waits_for_provisioned_launcher(self):
        avd = "meowwatch_interruption_36092741332_1"
        cold = {"verifiedAvd": avd, "appInstalled": False, "bootCompleted": "1",
                "provisioned": "0", "userSetupComplete": "0", "eligible": False,
                "resolvedHome": "com.google.android.googlesdksetup/com.google.android.googlesdksetup.DefaultActivity",
                "homeFocused": False, "anrWindow": None}
        ready = {**cold, "provisioned": "1", "userSetupComplete": "1",
                 "resolvedHome": LAUNCHER_HOME, "homeFocused": True}
        now = [0.0]
        observer = Mock()
        observer.snapshot.side_effect = [cold, ready]
        with TemporaryDirectory() as directory, patch(
                "tools.android_together_focus_runtime.run.Preparation", return_value=observer):
            output = Path(directory) / "boot"
            result = await_boot_ready("adb", "emulator-5554", avd, output,
                                      clock=lambda: now[0], sleep=lambda delay: now.__setitem__(0, now[0] + delay))
            self.assertEqual(result["status"], "home-ready")
            self.assertEqual(result["observations"], 2)
            self.assertEqual([call.args[2] for call in observer.snapshot.call_args_list],
                             ["boot-readiness-00", "boot-readiness-01"])
            self.assertEqual(json.loads((output / "result.json").read_text())["lastState"], ready)

    def test_cold_home_deadline_does_not_admit_unfinished_provisioning(self):
        avd = "meowwatch_interruption_123_1"
        cold = {"verifiedAvd": avd, "appInstalled": False, "bootCompleted": "1",
                "provisioned": "0", "userSetupComplete": "0", "eligible": False,
                "resolvedHome": "com.android.settings/.FallbackHome", "homeFocused": False,
                "anrWindow": None}
        now = [0.0]
        observer = Mock()
        observer.snapshot.return_value = cold
        with TemporaryDirectory() as directory, patch(
                "tools.android_together_focus_runtime.run.Preparation", return_value=observer):
            output = Path(directory) / "boot"
            with self.assertRaisesRegex(RuntimeFailure, "within 5 seconds"):
                await_boot_ready("adb", "emulator-5554", avd, output, budget_seconds=5,
                                 clock=lambda: now[0], sleep=lambda delay: now.__setitem__(0, now[0] + delay))
            self.assertEqual(observer.snapshot.call_count, 3)
            self.assertEqual(json.loads((output / "result.json").read_text())["status"], "failed")

    def test_cold_home_identity_install_and_measurement_fail_without_retry(self):
        avd = "meowwatch_interruption_123_1"
        ready = {"verifiedAvd": avd, "appInstalled": False, "bootCompleted": "1",
                 "provisioned": "1", "userSetupComplete": "1", "eligible": False,
                 "resolvedHome": LAUNCHER_HOME, "homeFocused": True, "anrWindow": None}
        for state, error in (({**ready, "verifiedAvd": "other"}, RuntimeFailure),
                             ({**ready, "appInstalled": True}, RuntimeFailure),
                             (MeasurementError("invalid focused window"), MeasurementError)):
            with self.subTest(state=state), TemporaryDirectory() as directory:
                observer = Mock()
                observer.snapshot.side_effect = [state] if isinstance(state, Exception) else None
                if not isinstance(state, Exception):
                    observer.snapshot.return_value = state
                with patch("tools.android_together_focus_runtime.run.Preparation", return_value=observer):
                    with self.assertRaises(error):
                        await_boot_ready("adb", "emulator-5554", avd, Path(directory) / "boot",
                                         clock=lambda: 0, sleep=lambda _: self.fail("unexpected retry"))
                self.assertEqual(observer.snapshot.call_count, 1)

    def test_provisioned_system_anr_goes_to_existing_preparation(self):
        avd = "meowwatch_interruption_123_1"
        eligible = {"verifiedAvd": avd, "appInstalled": False, "bootCompleted": "1",
                    "provisioned": "1", "userSetupComplete": "1", "eligible": True,
                    "resolvedHome": LAUNCHER_HOME, "homeFocused": False, "anrWindow": "abc"}
        observer = Mock()
        observer.snapshot.return_value = eligible
        with TemporaryDirectory() as directory, patch(
                "tools.android_together_focus_runtime.run.Preparation", return_value=observer):
            result = await_boot_ready("adb", "emulator-5554", avd, Path(directory) / "boot", clock=lambda: 0)
            self.assertEqual(result["status"], "eligible-system-anr")
            self.assertEqual(observer.snapshot.call_count, 1)

    def test_ready_home_observed_after_deadline_is_rejected(self):
        avd = "meowwatch_interruption_123_1"
        now = [0.0]
        observer = Mock()

        def late_snapshot(*args):
            now[0] = 60.1
            return {"verifiedAvd": avd, "appInstalled": False, "bootCompleted": "1",
                    "provisioned": "1", "userSetupComplete": "1", "eligible": False,
                    "resolvedHome": LAUNCHER_HOME, "homeFocused": True, "anrWindow": None}

        observer.snapshot.side_effect = late_snapshot
        with TemporaryDirectory() as directory, patch(
                "tools.android_together_focus_runtime.run.Preparation", return_value=observer):
            with self.assertRaisesRegex(RuntimeFailure, "exceeded its deadline"):
                await_boot_ready("adb", "emulator-5554", avd, Path(directory) / "boot",
                                 clock=lambda: now[0])
            self.assertEqual(observer.snapshot.call_count, 1)

    def test_prelaunch_requires_same_ready_home_and_anr_history(self):
        serial = "emulator-5554"
        avd = "meowwatch_interruption_36088605515_1"
        baseline = {"verifiedAvd": avd, "homeFocused": True, "anrWindow": None,
                    "anrEvents": ["historical setup ANR"], "resolvedHome": "com.google.android.apps.nexuslauncher/.NexusLauncherActivity",
                    "bootCompleted": "1", "provisioned": "1", "userSetupComplete": "1", "appInstalled": False}
        report = {"status": "prepared", "devices": {serial: {"status": "not-needed", "before": baseline}}}
        self.assertTrue(require_prelaunch_home(report, baseline, serial, avd)["freshHomeFocused"])
        recovered = {"status": "prepared", "devices": {serial: {"status": "recovered-once",
                                                              "before": {**baseline, "homeFocused": False},
                                                              "after": baseline}}}
        self.assertTrue(require_prelaunch_home(recovered, baseline, serial, avd)["freshHomeFocused"])
        for change in ({"homeFocused": False}, {"anrWindow": "dialog"},
                       {"anrEvents": [*baseline["anrEvents"], "new launcher ANR"]},
                       {"verifiedAvd": "another-avd"}, {"appInstalled": True},
                       {"provisioned": "0"}):
            with self.subTest(change=change), self.assertRaises(RuntimeFailure):
                require_prelaunch_home(report, {**baseline, **change}, serial, avd)

    def test_stage_failure_retains_read_only_native_diagnostics(self):
        class DiagnosticAdb:
            serial = "emulator-5554"
            calls = []

            def run(self, *args, **kwargs):
                self.calls.append(args)
                return SimpleNamespace(returncode=0, stdout=b"native diagnostic\n", stderr=b"")

        with TemporaryDirectory() as directory:
            adb = DiagnosticAdb()
            session = FocusSession(adb, "meowwatch_interruption_123_1", Path(directory),
                                   Path("unused-helper.apk"), Path("unused-observer.apk"))
            session.app_pid = "3301"
            result = session.capture_failure_diagnostics("early-short-ready")
            self.assertEqual(result["appPid"], "3301")
            self.assertEqual(set(result["commands"]), {"window", "anr-events", "lifecycle-events",
                                                       "launcher-process", "home-resolution"})
            self.assertEqual(len(adb.calls), 5)
            self.assertTrue(all(command[0] in ("shell", "logcat") for command in adb.calls))
            self.assertEqual((Path(directory) / "early-short-ready-failure-anr-events.txt").read_text(),
                             "native diagnostic\n")

    def test_focus_avd_is_preparable_and_exactly_owned(self):
        name = "meowwatch_interruption_36079974766_1"
        self.assertIsNotNone(AVD_NAME.fullmatch(name))
        for other in ("meowwatch_together_focus_36079974766_1",
                      "meowwatch_interruption_other_1", "meowwatch_interruption_123_1/../other"):
            with self.subTest(other=other):
                self.assertIsNone(AVD_NAME.fullmatch(other))

        with TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / f"{name}.avd" / "config.ini"
            config.parent.mkdir()
            config.write_text("".join(f"{key}={value}\n" for key, value in ORIGINAL.items()))
            prepare(root, name, root / "preparation")
            self.assertEqual(json.loads((root / "preparation/preparation.json").read_text())["avdName"], name)

    def test_streamed_helper_install_is_confirmed_on_owned_avd(self):
        name = "meowwatch_interruption_36079974766_1"

        class Adb:
            serial = "emulator-5554"

            def run(self, *args, **kwargs):
                if args == ("emu", "avd", "name"):
                    return SimpleNamespace(stdout=(name + "\nOK\n").encode())
                if args[:3] == ("shell", "getprop", "ro.kernel.qemu"):
                    return SimpleNamespace(stdout=b"1\n")
                if args[:3] == ("shell", "getprop", "ro.build.version.sdk"):
                    return SimpleNamespace(stdout=b"35\n")
                if args[:3] == ("shell", "getprop", "ro.product.cpu.abi"):
                    return SimpleNamespace(stdout=b"x86_64\n")
                if args[:3] == ("shell", "pm", "path"):
                    return SimpleNamespace(stdout=b"")
                if args[:1] == ("install",):
                    return SimpleNamespace(stdout=b"Performing Streamed Install\nSuccess\n")
                if args[:4] == ("shell", "pm", "list", "packages"):
                    return SimpleNamespace(stdout=f"package:{HELPER} uid:10179\n".encode())
                if args == ("shell", "getprop", "ro.product.model"):
                    return SimpleNamespace(stdout=b"Pixel 6\n")
                raise AssertionError(f"unexpected adb command: {args}")

        with TemporaryDirectory() as directory:
            apk = Path(directory) / "focus.apk"
            apk.write_bytes(b"mock apk")
            session = FocusSession(Adb(), name, Path(directory), apk, Path("unused-observer.apk"))
            session.observer.install = Mock(return_value={"installed": True})
            self.assertEqual(session.prepare()["avdName"], name)
            self.assertEqual(session.helper_uid, 10179)

    def test_permanent_focus_accepts_original_api35_helper_only_stack(self):
        def row(package, uid, loss):
            return (f"source:android.os.BinderProxy@abc -- pack: {package} -- gain: GAIN"
                    f" -- loss: {loss} -- uid: {uid}")

        before = FOCUS_HEADER + "\n" + row(PACKAGE, 10178, "none") + "\n\n"
        after = FOCUS_HEADER + "\n" + row(HELPER, 10179, "none") + "\n\n"
        self.assertEqual(require_focus(before, PACKAGE, 10178)[-1]["package"], PACKAGE)
        self.assertEqual(require_focus(after, HELPER, 10179)[-1]["package"], HELPER)
        for changed in (after.replace("uid: 10179", "uid: 10180"),
                        after.replace("loss: none", "loss: LOSS"),
                        after + FOCUS_HEADER):
            with self.assertRaises(RuntimeFailure):
                require_focus(changed, HELPER, 10179)

    def test_requires_two_actual_play_pause_no_autoplay_and_replay_cycles(self):
        value, stages = receipt()
        self.assertEqual(len(validate_journey(value, stages)["cases"]), 2)
        mutations = [
            lambda x: x["togetherFocus"].update(peerCompletedTlsHello=False),
            lambda x: x["togetherFocus"]["cases"][0].update(testSidePauseDuringInterruption=True),
            lambda x: x["togetherFocus"]["cases"][1]["settledPlaying"].update(continuousPlayingMs=500),
            lambda x: x["togetherFocus"]["cases"][0]["noAutoplayMonitor"].update(
                forbiddenPlayEvents=[{"source": "nativePlayer", "elapsedMs": 500}]),
            lambda x: x["togetherFocus"]["cases"][0]["paused"].update(peerPaused=False),
            lambda x: x["togetherFocus"]["cases"][0]["held"].update(nativePlaying=True),
            lambda x: x["togetherFocus"]["cases"][1]["afterRelease"].update(nativePlaying=True),
            lambda x: x["togetherFocus"]["cases"][1]["explicitReplay"].update(peerPaused=True),
            lambda x: x["togetherFocus"]["cases"][0]["explicitReplay"].update(nativePositionMs=5600),
            lambda x: x["togetherFocus"]["cases"][0]["before"].update(nativeError="decoder failed"),
            lambda x: x["togetherFocus"]["cases"][1].update(acquire=stages[0]),
            lambda x: x["togetherFocus"]["earlyShort"].update(tlsPeerPlay=False),
            lambda x: x["togetherFocus"]["earlyShort"]["noAutoplayMonitor"].update(
                forbiddenNativePlayEvents=[{"elapsedMs": 500}]),
            lambda x: x["togetherFocus"]["earlyShort"]["noAutoplayMonitor"].update(
                forbiddenRoomPlayEvents=[{"elapsedMs": 900}]),
            lambda x: x["togetherFocus"]["earlyShort"]["before"].update(peerSetter="Focus Host"),
        ]
        for mutate in mutations:
            changed = copy.deepcopy(value)
            mutate(changed)
            with self.subTest(mutate=mutate), self.assertRaises(RuntimeFailure):
                validate_journey(changed, stages)
        for invalid_stages in ([], list(reversed(stages)), stages[:-1]):
            with self.assertRaises(RuntimeFailure):
                validate_journey(value, invalid_stages)
        for changed_value in (100801, 101231):
            changed = copy.deepcopy(stages)
            changed[0]["deviceElapsedRealtimeMs"] = changed_value
            changed_value_report = copy.deepcopy(value)
            changed_value_report["togetherFocus"]["earlyShort"]["ready"] = changed[0]
            with self.assertRaises(RuntimeFailure):
                validate_journey(changed_value_report, changed)
        for offset in (3000, 5000):
            changed = copy.deepcopy(stages)
            changed[1]["release"]["elapsedRealtimeMs"] = 100000 + offset
            changed[1]["fromPrePeerPlayMarkerToReleaseMs"] = offset
            changed_value_report = copy.deepcopy(value)
            changed_value_report["togetherFocus"]["earlyShort"]["acquire"] = changed[1]
            with self.assertRaises(RuntimeFailure):
                validate_journey(changed_value_report, changed)

    def test_short_helper_command_requests_native_auto_release_without_host_release(self):
        class NoAdb:
            serial = "emulator-5554"

            def run(self, *args, **kwargs):
                raise AssertionError("short command should not poll process after auto-release")

        session = FocusSession(NoAdb(), "meowwatch_interruption_123_1", Path("unused"),
                               Path("unused-helper.apk"), Path("unused-observer.apk"))
        session.nonce = "a" * 32
        session.gain = 2
        requested = {"event": "requested", "pid": 901}
        released = {"event": "released", "pid": 901}
        captured = []
        session.raw = lambda stage, name, *command: (captured.append(command) or "Starting service: Intent {}")
        session._events = lambda stage: [requested, released]
        self.assertEqual(session._command("early-short-acquire", "acquire", early_short=True), released)
        self.assertEqual(session.events, [requested, released])
        self.assertEqual(captured[0][-6:], ("--es", "mode", "transient", "--ei", "autoReleaseMs", "350"))

    def test_bridge_rejects_out_of_order_and_repeated_native_commands(self):
        class Session:
            completed = []

            def stage(self, name):
                if name != STAGES[len(self.completed)]:
                    raise RuntimeFailure("out of order")
                row = {"stage": name, "completed": True}
                self.completed.append(row)
                return row

        server = StageServer(Session(), 0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            def post(name, body=None):
                connection = HTTPConnection("127.0.0.1", server.server_address[1], timeout=3)
                connection.request("POST", "/" + name, json.dumps(body if body is not None else {"stage": name}),
                                   {"Content-Type": "application/json"})
                response = connection.getresponse()
                result = response.status, json.loads(response.read())
                connection.close()
                return result

            self.assertEqual(post("transient-acquire")[0], 500)
            self.assertEqual(post("permanent-acquire")[0], 409)
        finally:
            server.shutdown()
            server.server_close()

    def test_helper_uninstall_failure_still_attempts_owned_observer_cleanup(self):
        class Adb:
            serial = "emulator-5554"

            def run(self, *args, **kwargs):
                if args == ("emu", "avd", "name"):
                    return SimpleNamespace(stdout=b"meowwatch_interruption_123_1\nOK\n")
                if args[:1] == ("uninstall",):
                    return SimpleNamespace(stdout=b"Failure\n")
                return SimpleNamespace(stdout=b"")

        with TemporaryDirectory() as directory:
            session = FocusSession(Adb(), "meowwatch_interruption_123_1", Path(directory),
                                   Path("unused-helper.apk"), Path("unused-observer.apk"))
            session.helper_owned = True
            session.observer.cleanup = Mock()
            with self.assertRaisesRegex(RuntimeFailure, "helper uninstall"):
                session.cleanup()
            session.observer.cleanup.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
