from dataclasses import replace
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch
from xml.sax.saxutils import escape

from tools.android_fullscreen_runtime.run import (
    Display, Runner, display_state, immersive_confirmation_button, recording_size, require_same_paused_player,
    require_transition, require_visible_bounds,
)
from tools.android_install.runner import PACKAGE, RuntimeFailure
from tools.android_lifecycle_runtime.run import Playback
from tools.android_native_ui.observer import OBSERVER_PACKAGE, ObserverIntegrityFailure


# Native API 35 hierarchy/window shape from phone run 35250983436, phase 07.
IMMERSIVE_XML = '''<?xml version='1.0' encoding='UTF-8' standalone='yes' ?><hierarchy>
<node index="0" text="" resource-id="" class="android.widget.FrameLayout" package="android" content-desc="" clickable="false" enabled="true" visible-to-user="true" bounds="[0,0][2400,1080]">
<node index="0" text="Viewing full screen" resource-id="android:id/immersive_cling_title" class="android.widget.TextView" package="android" content-desc="" clickable="false" enabled="true" visible-to-user="true" bounds="[606,200][1793,285]" />
<node index="1" text="To exit, swipe down from the top of your screen" resource-id="android:id/immersive_cling_description" class="android.widget.TextView" package="android" content-desc="" clickable="false" enabled="true" visible-to-user="true" bounds="[606,285][1793,373]" />
<node index="2" text="Got it" resource-id="android:id/ok" class="android.widget.Button" package="android" content-desc="" clickable="true" enabled="true" visible-to-user="true" bounds="[1611,436][1793,562]" />
</node></hierarchy>'''


def immersive_window():
    value = window(width=2400, height=1080, rotation=1, bars=False)
    return value.replace(f"mCurrentFocus=Window{{123 u0 {PACKAGE}/.MainActivity}}", f"""mCurrentFocus=Window{{2ac2226 u0 ImmersiveModeConfirmation}}
  mFocusedApp=ActivityRecord{{dd28180 u0 {PACKAGE}/.MainActivity t8}}""")


def window(*, width=1080, height=2400, rotation=0, smallest=411, bars=True):
    # Format taken from retained API 35 dumpsys window displays originals.
    return f"""WINDOW MANAGER DISPLAY CONTENTS (dumpsys window displays)
  Display: mDisplayId=0 (organized)
    init=1080x2400 420dpi base={width}x{height} 420dpi cur={width}x{height} app={width}x{height}
  overrideConfig={{1.0 310mcc260mnc [en_US] ldltr sw{smallest}dp w411dp h914dp}}
  mCurrentFocus=Window{{123 u0 {PACKAGE}/.MainActivity}}
    mCurrentAppOrientation=SCREEN_ORIENTATION_UNSPECIFIED
    mRotation={rotation} mDeferredRotationPauseCount=0
  WindowInsetsStateController
    InsetsState
      mDisplayFrame=Rect(0, 0 - {width}, {height})
        InsetsSource id=123 type=statusBars frame=[0,0][{width},80] visible={str(bars).lower()} flags=
        InsetsSource id=456 type=navigationBars frame=[0,{height-80}][{width},{height}] visible={str(bars).lower()} flags=
    Control map:
      mRequestedVisibleTypes=0
"""


def node(label, rectangle, *, clickable=False, class_name="android.view.View"):
    left, top, right, bottom = rectangle
    return (f'<node text="{escape(label)}" content-desc="" package="{PACKAGE}" '
            f'visible-to-user="true" enabled="true" clickable="{str(clickable).lower()}" '
            f'class="{class_name}" bounds="[{left},{top}][{right},{bottom}]"/>')


def fullscreen_player(position, pause_bounds):
    surface = node("Video", (0, 0, 2400, 1080), clickable=True)
    controls = "".join(node(label, (20 + index * 160, 20, 150 + index * 160, 100), clickable=True)
                       for index, label in enumerate(("Exit full screen", "Choose video", "Choose playback screen")))
    return "<hierarchy>" + surface + controls + "".join((
        node("sync-fixture.mp4", (500, 20, 800, 100)),
        node(f"0:{position:02}", (20, 900, 100, 950)),
        node("1:30", (2250, 900, 2350, 950)),
        node("timeline", (100, 850, 2200, 890), class_name="android.widget.SeekBar"),
        node("Pause together", pause_bounds, clickable=True),
    )) + "</hierarchy>"


class InsetsTests(unittest.TestCase):
    def test_actual_bar_sources_are_read_instead_of_requested_flags(self):
        state = display_state(window())
        self.assertTrue(state.status_bar_visible)
        self.assertTrue(state.navigation_bar_visible)
        self.assertEqual((state.width, state.height, state.rotation), (1080, 2400, 0))
        with self.assertRaises(RuntimeFailure):
            require_transition(state, state, "phone", fullscreen=True)

    def test_missing_duplicate_or_foreign_display_evidence_fails_closed(self):
        text = window()
        bad = [text.replace("type=statusBars", "type=tappableElement"),
               text.replace("visible=true", "requestedVisible=false"),
               text.replace("cur=1080x2400", "cur=2400x1080"),
               text + "  Display: mDisplayId=1\n",
               text.replace(PACKAGE, "com.other.application"),
               text.replace("    Control map:", "        InsetsSource id=789 type=statusBars visible=true\n    Control map:")]
        for value in bad:
            with self.subTest(value=value[-80:]), self.assertRaises(RuntimeFailure):
                display_state(value)

    def test_phone_enters_landscape_and_restores_original_orientation(self):
        before = display_state(window())
        full = display_state(window(width=2400, height=1080, rotation=1, bars=False))
        require_transition(before, full, "phone", fullscreen=True)
        require_transition(before, before, "phone", fullscreen=False)
        for wrong in (replace(full, width=1080, height=2400), replace(full, rotation=0),
                      replace(full, status_bar_visible=True), replace(full, navigation_bar_visible=True)):
            with self.subTest(wrong=wrong), self.assertRaises(RuntimeFailure):
                require_transition(before, wrong, "phone", fullscreen=True)
        with self.assertRaises(RuntimeFailure):
            require_transition(before, replace(before, app_orientation="SCREEN_ORIENTATION_SENSOR_LANDSCAPE"),
                               "phone", fullscreen=False)

    def test_tablet_preserves_orientation_in_both_directions(self):
        before = display_state(window(width=2560, height=1600, smallest=800))
        full = replace(before, status_bar_visible=False, navigation_bar_visible=False)
        require_transition(before, full, "tablet", fullscreen=True)
        require_transition(before, before, "tablet", fullscreen=False)
        with self.assertRaises(RuntimeFailure):
            require_transition(before, replace(full, width=1600, height=2560, rotation=1), "tablet", fullscreen=True)
        with self.assertRaises(RuntimeFailure):
            require_transition(before, full, "phone", fullscreen=True)

    def test_cropped_geometry_is_not_accepted_as_fullscreen(self):
        baseline = display_state(window())
        cropped = Display(2200, 1080, 1, 411, baseline.app_orientation, False, False)
        with self.assertRaises(RuntimeFailure):
            require_transition(baseline, cropped, "phone", fullscreen=True)


class SurfaceTests(unittest.TestCase):
    def setUp(self):
        self.state = display_state(window(width=2400, height=1080, rotation=1, bars=False))
        self.surface = node("Video", (0, 0, 2400, 1080), clickable=True)
        self.controls = "".join(node(label, (20 + index * 160, 20, 150 + index * 160, 100), clickable=True)
                                for index, label in enumerate(("Exit full screen", "Choose video", "Choose playback screen")))

    def test_full_surface_and_controls_fit_original_native_display(self):
        require_visible_bounds(f"<hierarchy>{self.surface}{self.controls}</hierarchy>", self.state,
                               fullscreen=True, controls=True)
        require_visible_bounds(f"<hierarchy>{self.surface}</hierarchy>", self.state,
                               fullscreen=True, controls=False)

    def test_hidden_controls_cannot_still_expose_transport_or_exit(self):
        for extra in (self.controls, node("Pause together", (10, 10, 100, 100), clickable=True)):
            with self.assertRaises(RuntimeFailure):
                require_visible_bounds(f"<hierarchy>{self.surface}{extra}</hierarchy>", self.state,
                                       fullscreen=True, controls=False)

    def test_cropped_surface_and_overflowing_action_are_rejected(self):
        for value in (node("Video", (0, 0, 2300, 1080)),
                      self.surface + node("outside", (2300, 20, 2450, 100), clickable=True)):
            with self.assertRaises(RuntimeFailure):
                require_visible_bounds(f"<hierarchy>{value}</hierarchy>", self.state,
                                       fullscreen=True, controls=False)

    def test_rotated_recording_uses_current_display_aspect(self):
        self.assertEqual(recording_size(self.state), (960, 432))
        portrait = display_state(window())
        self.assertEqual(recording_size(portrait), (432, 960))
        self.assertNotEqual(recording_size(self.state), recording_size(portrait))

    def test_first_back_requires_same_process_media_and_paused_position(self):
        paused = Playback(12, 90, False)
        require_same_paused_player(paused, Playback(13, 90, False), "123", "123")
        for other, pid in ((Playback(12, 90, False), "456"), (Playback(0, 90, False), "123"),
                           (Playback(12, 90, True), "123"), (Playback(12, 120, False), "123")):
            with self.assertRaises(RuntimeFailure):
                require_same_paused_player(paused, other, "123", pid)


class OwnershipTests(unittest.TestCase):
    def runner(self, directory):
        apk, fixture = directory / "app.apk", directory / "sync-fixture.mp4"
        apk.write_bytes(b"apk")
        fixture.write_bytes(b"fixture")
        return Runner("emulator-5554", "meowwatch_fullscreen_phone_123_1", "phone",
                      apk, fixture, directory / "output")

    def test_unowned_avd_is_rejected_before_install_or_any_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.runner(Path(directory))
            runner.adb.run = Mock(return_value=subprocess.CompletedProcess([], 0, b"personal_avd\nOK\n", b""))
            with patch.object(runner, "prepare") as prepare, self.assertRaises(RuntimeFailure):
                runner.run()
            prepare.assert_not_called()
            self.assertEqual(runner.adb.run.call_args_list[0].args, ("emu", "avd", "name"))

    def test_rotation_is_rejected_if_a_screen_recorder_survives(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.runner(Path(directory))
            runner.adb.run = Mock(return_value=subprocess.CompletedProcess([], 0, b"987", b""))
            with patch.object(runner, "finish_recording") as finish, self.assertRaises(RuntimeFailure):
                runner.stop_for_rotation("last-observation")
            finish.assert_called_once_with(required_phase="last-observation")
            self.assertFalse(any(call.args[:3] == ("shell", "input", "tap") for call in runner.adb.run.call_args_list))

    def test_cannot_start_a_second_recorder_over_existing_segment(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.runner(Path(directory))
            runner.recording = Mock()
            with self.assertRaises(RuntimeFailure):
                runner.start_recording()

    def test_startup_native_input_uses_remaining_deadline_and_never_retries_uncertain_input(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.runner(Path(directory))
            runner.adb.run = Mock()
            with patch("tools.android_fullscreen_runtime.run.time.monotonic", return_value=20):
                with self.assertRaisesRegex(RuntimeFailure, "no input sent"):
                    runner.recording_input(20, "keyevent", "KEYCODE_BACK")
            runner.adb.run.assert_not_called()
            runner.adb.run.side_effect = subprocess.TimeoutExpired("input", 0.5)
            with patch("tools.android_fullscreen_runtime.run.time.monotonic", return_value=19.5):
                with self.assertRaises(subprocess.TimeoutExpired):
                    runner.recording_input(20, "tap", "50", "60")
            runner.adb.run.assert_called_once_with("shell", "input", "tap", "50", "60", timeout=0.5)

    def test_three_segments_dispatch_only_existing_actions_and_preserve_paused_entry_proof(self):
        for changed_entry in (False, True):
            with self.subTest(changed_entry=changed_entry), tempfile.TemporaryDirectory() as directory:
                runner = self.runner(Path(directory))
                runner.output.mkdir()
                runner.require_owned_avd = Mock()
                runner.prepare = Mock(return_value={"application": {}})
                runner.load_fixture = Mock()
                runner.pid = Mock(return_value="123")
                runner.require_entry_pid = Mock()
                normal = display_state(window())
                full = display_state(window(width=2400, height=1080, rotation=1, bars=False))
                runner.last_window = window()
                events, startup_inputs, first_observations = [], [], []
                in_startup = [False]
                normal_xml = "<hierarchy>" + node("Play", (100, 100, 200, 200), clickable=True) + node(
                    "Enter full screen", (300, 100, 400, 200), clickable=True) + "</hierarchy>"
                playing_xml = normal_xml.replace('text="Play"', 'text="Pause"')
                full_xml = fullscreen_player(8, (100, 700, 180, 780)).replace("Pause together", "Play together")
                home_xml = "<hierarchy>" + node("Start a room", (100, 100, 300, 200), clickable=True) + "</hierarchy>"
                samples = {
                    "02-loaded-paused": (normal_xml, Playback(0, 90, False)),
                    "03-normal-playing": (playing_xml, Playback(2, 90, True)),
                    "04-normal-advanced": (playing_xml, Playback(6, 90, True)),
                    "06-fresh-entry-control": (normal_xml, Playback(8, 90, False)),
                    "12-before-system-back": (full_xml, Playback(12, 90, False)),
                }
                def sample(phase, **_kwargs):
                    runner.phase = phase
                    events.append(phase)
                    return samples[phase]
                runner.sample = Mock(side_effect=sample)
                def system_sample(phase, _baseline, **kwargs):
                    runner.phase = phase
                    events.append(phase)
                    state = full if kwargs["fullscreen"] else normal
                    runner.last_window = window(width=state.width, height=state.height, rotation=state.rotation,
                                                bars=state.status_bar_visible)
                    position = 8 if phase in ("05-before-fullscreen", "07-entered-fullscreen") else 12
                    if changed_entry and phase == "07-entered-fullscreen":
                        position = 0
                    return (full_xml if kwargs["fullscreen"] else normal_xml), state, Playback(position, 90, False)
                runner.system_sample = Mock(side_effect=system_sample)
                runner.evidence = Mock(side_effect=lambda phase, *_: events.append(phase))
                def idle(_baseline):
                    runner.phase = "08-controls-idle-visual-review"
                    events.append(runner.phase)
                    runner.controls_auto_hide_review = {"status": "pending", "visualReviewRequired": True}
                runner.capture_controls_idle_window = Mock(side_effect=idle)
                runner.center_tap = Mock(side_effect=lambda *_: events.append("center-tap"))
                runner.pause_after_fullscreen_advance = Mock(side_effect=lambda *_: events.append("09-native-advance") or 2)
                def wait(phase, check, **_kwargs):
                    runner.phase = phase
                    events.append(phase)
                    runner.last_window = window()
                    return home_xml, check(home_xml)
                runner.wait = Mock(side_effect=wait)
                def command(*arguments, **kwargs):
                    if arguments == ("shell", "dumpsys", "window", "displays"):
                        return subprocess.CompletedProcess([], 0, runner.last_window.encode(), b"")
                    if arguments[:2] == ("shell", "input") and in_startup[0]:
                        startup_inputs.append((runner.recording.metadata["startupActionName"], arguments[2:]))
                        self.assertEqual(kwargs["timeout"], 3)
                    return subprocess.CompletedProcess([], 0, b"", b"")
                runner.adb.run = Mock(side_effect=command)
                def make_recording(_adb, _output, index, _size):
                    recording = Mock()
                    recording.metadata = {"status": "not-started"}
                    def start(*, startup_action):
                        self.assertIsNotNone(startup_action)
                        events.append(f"owned-{index}")
                        in_startup[0] = True
                        try:
                            startup_action(20)
                        finally:
                            in_startup[0] = False
                        events.append(f"ready-{index}")
                        recording.metadata.update({"status": "recording", "startedAtMonotonic": index})
                    recording.start.side_effect = start
                    recording.finish.side_effect = lambda **_: recording.metadata.update(
                        {"status": "verified", "stopRequestedAtMonotonic": index + 0.5})
                    recording.observe_startup_result.side_effect = lambda phase: first_observations.append(phase)
                    return recording
                process = Mock()
                process.poll.return_value = None
                with patch("tools.android_fullscreen_runtime.run.LifecycleRecording", side_effect=make_recording), patch(
                    "tools.android_fullscreen_runtime.run.subprocess.Popen", return_value=process,
                ), patch("tools.android_fullscreen_runtime.run.verify_build_mode", return_value=False), patch(
                    "tools.android_fullscreen_runtime.run.time.monotonic", return_value=0,
                ), patch("tools.android_fullscreen_runtime.run.time.sleep"):
                    try:
                        if changed_entry:
                            with self.assertRaisesRegex(RuntimeFailure, "paused playback advanced"):
                                runner.run()
                        else:
                            report = runner.run()
                            self.assertTrue(report["completed"])
                            self.assertTrue(report["controlsAutoHideVisualReviewRequired"])
                            self.assertEqual(report["controlsAutoHideReview"]["status"], "pending")
                            self.assertNotIn("controlsAutoHiddenDuringPlayback", report)
                            self.assertNotIn("controlsShownByNativeTap", report)
                    finally:
                        if runner.log_file is not None:
                            runner.log_file.close()
                names = [name for name, _ in startup_inputs]
                if changed_entry:
                    self.assertEqual(names, ["normal-play"])
                    self.assertNotIn("owned-2", events)
                else:
                    self.assertEqual(names, ["normal-play", "fullscreen-play", "return-home"])
                    self.assertEqual(startup_inputs[-1][1], ("keyevent", "KEYCODE_BACK"))
                    self.assertEqual(first_observations, ["03-normal-playing", "08-controls-idle-visual-review", "15-normal-return-home"])
                    self.assertLess(events.index("ready-1"), events.index("03-normal-playing"))
                    self.assertLess(events.index("07-entered-fullscreen"), events.index("owned-2"))
                    self.assertLess(events.index("ready-2"), events.index("08-controls-idle-visual-review"))
                    self.assertLess(events.index("08-controls-idle-visual-review"), events.index("center-tap"))
                    self.assertLess(events.index("center-tap"), events.index("09-native-advance"))
                    self.assertLess(events.index("14-normal-player-restored"), events.index("owned-3"))
                    self.assertLess(events.index("ready-3"), events.index("15-normal-return-home"))

    def test_fast_observer_waits_for_actual_advance_before_tapping_fresh_pause(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.runner(Path(directory))
            runner.output.mkdir()
            full = display_state(window(width=2400, height=1080, rotation=1, bars=False))
            positions = [10, 11, 12]
            snapshots = [fullscreen_player(position, (position * 10, 700, position * 10 + 80, 780))
                         for position in positions]
            runner.observe = Mock(side_effect=snapshots)
            runner.tap = Mock()
            with patch("tools.android_lifecycle_runtime.run.time.sleep"):
                advanced = runner.pause_after_fullscreen_advance(full, Playback(10, 90, False))
            self.assertEqual(advanced, 2)
            self.assertEqual(runner.observe.call_count, 3)
            runner.tap.assert_called_once()
            self.assertEqual(runner.tap.call_args.args[0].get("bounds"), "[120,700][200,780]")

    def test_elapsed_deadline_cannot_replace_native_advancement_or_send_pause(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.runner(Path(directory))
            runner.output.mkdir()
            full = display_state(window(width=2400, height=1080, rotation=1, bars=False))
            runner.observe = Mock(return_value=fullscreen_player(10, (100, 700, 180, 780)))
            runner.tap = Mock()
            clock = [0]
            with patch("tools.android_lifecycle_runtime.run.time.sleep", side_effect=lambda _: clock.__setitem__(0, 11)), \
                    patch("tools.android_lifecycle_runtime.run.time.monotonic", side_effect=lambda: clock[0]), \
                    self.assertRaisesRegex(RuntimeFailure, "has not advanced"):
                runner.pause_after_fullscreen_advance(full, Playback(10, 90, False))
            runner.tap.assert_not_called()


class IdleVisualEvidenceTests(unittest.TestCase):
    def runner(self, directory):
        runner = OwnershipTests().runner(directory)
        runner.output.mkdir()
        runner.require_owned_avd = Mock()
        runner.fullscreen_entry_pid = "123"
        runner.pid = Mock(return_value="123")
        runner.observer.owns_package = runner.observer.installed = True
        runner.recording = Mock(metadata={"status": "recording", "file": "native/lifecycle-02.mp4"})
        runner.observe = Mock(side_effect=AssertionError("idle window must not query a hierarchy"))
        runner.observer.observe = Mock(side_effect=AssertionError("idle window must not query accessibility"))
        runner.adb.observe = Mock(side_effect=AssertionError("idle window must not use UIAutomator"))
        png = b"\x89PNG\r\n\x1a\n" + b"\0\0\0\rIHDR" + (2400).to_bytes(4, "big") + (1080).to_bytes(4, "big")
        runner.adb.screenshot = Mock(side_effect=[png + b"before-original", png + b"after-original"])
        self.uptimes = iter((b"100.00 0.00", b"104.50 0.00"))
        def command(*args, **kwargs):
            if args == ("shell", "pidof", OBSERVER_PACKAGE):
                return subprocess.CompletedProcess([], 1, b"", b"")
            if args == ("shell", "settings", "get", "secure", "accessibility_enabled"):
                return subprocess.CompletedProcess([], 0, b"0\n", b"")
            if args == ("shell", "dumpsys", "window", "displays"):
                return subprocess.CompletedProcess([], 0, window(width=2400, height=1080, rotation=1, bars=False).encode(), b"")
            if args == ("exec-out", "cat", "/proc/uptime"):
                return subprocess.CompletedProcess([], 0, next(self.uptimes), b"")
            self.assertEqual(args, ("shell", "am", "force-stop", OBSERVER_PACKAGE))
            return subprocess.CompletedProcess([], 0, b"", b"")
        runner.adb.run = Mock(side_effect=command)
        return runner

    def test_original_images_and_device_interval_are_retained_without_tree_or_pass_claim(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.runner(Path(directory))
            with patch("tools.android_fullscreen_runtime.run.time.sleep") as sleep:
                runner.capture_controls_idle_window(display_state(window()))
            sleep.assert_called_once_with(4)
            runner.observe.assert_not_called()
            runner.observer.observe.assert_not_called()
            runner.adb.observe.assert_not_called()
            receipt = runner.controls_auto_hide_review
            self.assertEqual(receipt["status"], "pending")
            self.assertTrue(receipt["visualReviewRequired"])
            self.assertTrue(receipt["evidenceCaptured"])
            self.assertEqual(receipt["quietDeviceSeconds"], 4.5)
            self.assertEqual(receipt["recordingFile"], "native/lifecycle-02.mp4")
            self.assertEqual(len(receipt["screenshots"]), 2)
            for suffix, ending in ((".before", b"before-original"), ("", b"after-original")):
                prefix = runner.output / f"08-controls-idle-visual-review{suffix}"
                self.assertTrue(Path(str(prefix) + ".png").read_bytes().endswith(ending))
                self.assertTrue(Path(str(prefix) + ".window.txt").is_file())
                self.assertTrue(Path(str(prefix) + ".after-screenshot.window.txt").is_file())
            self.assertFalse(list(runner.output.glob("*.xml")))

    def test_unowned_helper_or_missing_recording_cannot_be_stopped(self):
        for bad in ("ownership", "installed", "recording"):
            with self.subTest(bad=bad), tempfile.TemporaryDirectory() as directory:
                runner = self.runner(Path(directory))
                if bad == "ownership":
                    runner.observer.owns_package = False
                elif bad == "installed":
                    runner.observer.installed = False
                else:
                    runner.recording = None
                with self.assertRaises(RuntimeFailure):
                    runner.capture_controls_idle_window(display_state(window()))
                runner.adb.run.assert_not_called()
                runner.adb.screenshot.assert_not_called()

    def test_disconnect_requires_no_helper_and_disabled_accessibility_and_valid_evidence(self):
        for pid, code, enabled, expected in ((b"", 1, b"0", True), (b"123", 0, b"0", False),
                                            (b"", 1, b"1", False), (b"", 1, b"null", None),
                                            (b"", 2, b"0", None)):
            with self.subTest(pid=pid, enabled=enabled), tempfile.TemporaryDirectory() as directory:
                runner = self.runner(Path(directory))
                runner.adb.run.side_effect = [subprocess.CompletedProcess([], code, pid, b""),
                                             subprocess.CompletedProcess([], 0, enabled, b"")]
                with patch("tools.android_fullscreen_runtime.run.time.monotonic", return_value=0):
                    if expected is None:
                        with self.assertRaisesRegex(RuntimeFailure, "missing or invalid"):
                            runner.observer_disconnected(5)
                    else:
                        self.assertIs(runner.observer_disconnected(5), expected)

    def test_disconnect_deadline_and_reconnection_do_not_produce_visual_evidence_success(self):
        for case in ("deadline", "reconnect"):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as directory:
                runner = self.runner(Path(directory))
                runner.observer_disconnected = Mock(side_effect=[False] if case == "deadline" else [True, False])
                clock = [0, 6] if case == "deadline" else [0, 0, 0, 5]
                with patch("tools.android_fullscreen_runtime.run.time.monotonic", side_effect=clock), \
                        patch("tools.android_fullscreen_runtime.run.time.sleep"), self.assertRaises(RuntimeFailure):
                    runner.capture_controls_idle_window(display_state(window()))
                self.assertNotIn("evidenceCaptured", runner.controls_auto_hide_review)
                self.assertEqual(runner.controls_auto_hide_review["status"], "pending")
                self.assertEqual(runner.adb.screenshot.call_count, 0 if case == "deadline" else 1)

    def test_short_device_interval_changed_process_or_changed_insets_fail_closed(self):
        for case in ("short-clock", "process", "insets", "image-size"):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as directory:
                runner = self.runner(Path(directory))
                if case == "short-clock":
                    self.uptimes = iter((b"100 0", b"103.99 0"))
                elif case == "process":
                    runner.pid.side_effect = ["123", "456"]
                elif case == "insets":
                    with_insets = window(width=2400, height=1080, rotation=1, bars=True).encode()
                    original = runner.adb.run.side_effect
                    runner.adb.run.side_effect = lambda *args, **kwargs: subprocess.CompletedProcess([], 0, with_insets, b"") if args == (
                        "shell", "dumpsys", "window", "displays") else original(*args, **kwargs)
                else:
                    runner.adb.screenshot.side_effect = [b"\x89PNG\r\n\x1a\n" + b"\0\0\0\rIHDR"
                                                         + (1080).to_bytes(4, "big") + (2400).to_bytes(4, "big")]
                with patch("tools.android_fullscreen_runtime.run.time.sleep"), self.assertRaises(RuntimeFailure):
                    runner.capture_controls_idle_window(display_state(window()))
                self.assertNotIn("evidenceCaptured", runner.controls_auto_hide_review)


class ImmersiveConfirmationTests(unittest.TestCase):
    def runner(self, directory):
        runner = OwnershipTests().runner(directory)
        runner.output.mkdir()
        runner.phase = "07-entered-fullscreen"
        runner.fullscreen_entry_pid = "123"
        runner.pid = Mock(return_value="123")
        runner.require_owned_avd = Mock()
        runner.adb.screenshot = Mock(return_value=(b"\x89PNG\r\n\x1a\n" + b"\0\0\0\rIHDR"
                                                 + (2400).to_bytes(4, "big") + (1080).to_bytes(4, "big")))
        runner.adb.run = Mock(return_value=subprocess.CompletedProcess([], 0, immersive_window().encode(), b""))
        runner.adb.observe = Mock(return_value=(IMMERSIVE_XML, immersive_window()))
        runner.observer.observe = Mock(return_value=("<hierarchy/>", window(width=2400, height=1080, bars=False)))
        runner.tap = Mock()
        return runner

    def test_exact_native_tip_is_selected_with_uiautomator_visibility_format(self):
        for xml in (IMMERSIVE_XML, IMMERSIVE_XML.replace(' visible-to-user="true"', "")):
            target = immersive_confirmation_button(xml, immersive_window())
            self.assertEqual(target.get("resource-id"), "android:id/ok")
            self.assertEqual(target.get("bounds"), "[1611,436][1793,562]")

    def test_foreign_ambiguous_or_similarly_named_focused_windows_are_rejected(self):
        original = immersive_window()
        cases = [window(), original.replace("ImmersiveModeConfirmation", "ImmersiveModeConfirmationFake"),
                 original.replace("ImmersiveModeConfirmation", f"Application Not Responding: {PACKAGE}"),
                 original.replace(PACKAGE, "com.other.app"), original.replace("/.MainActivity t8", "/.OtherActivity t8"),
                 original + "mCurrentFocus=Window{def u0 ImmersiveModeConfirmation}\n",
                 original + f"mFocusedApp=ActivityRecord{{abc u0 {PACKAGE}/.MainActivity t9}}\n"]
        for value in cases:
            with self.subTest(window=value[-120:]), self.assertRaises(RuntimeFailure):
                immersive_confirmation_button(IMMERSIVE_XML, value)

    def test_missing_hidden_disabled_duplicate_or_offscreen_system_content_is_rejected(self):
        button = IMMERSIVE_XML[IMMERSIVE_XML.index('<node index="2"'):IMMERSIVE_XML.index("</node>")]
        cases = ["<broken", IMMERSIVE_XML.replace("Viewing full screen", "Other tip"),
                 IMMERSIVE_XML.replace("To exit, swipe down from the top of your screen", "Permission needed"),
                 IMMERSIVE_XML.replace("Got it", "Allow"),
                 IMMERSIVE_XML.replace("immersive_cling_description", "other_description"),
                 IMMERSIVE_XML.replace('enabled="true"', 'enabled="false"'),
                 IMMERSIVE_XML.replace('visible-to-user="true"', 'visible-to-user="false"'),
                 IMMERSIVE_XML.replace('package="android"', f'package="{PACKAGE}"'),
                 IMMERSIVE_XML.replace('class="android.widget.Button"', 'class="android.widget.TextView"'),
                 IMMERSIVE_XML.replace("[1611,436][1793,562]", "[1611,436][2500,562]"),
                 IMMERSIVE_XML.replace("[1611,436][1793,562]", "[1611,436][1611,562]"),
                 IMMERSIVE_XML.replace("</node>", button + "</node>"),
                 IMMERSIVE_XML.replace("</node>", button.replace("android:id/ok", "android:id/other") + "</node>")]
        for index, value in enumerate(cases):
            with self.subTest(case=index), self.assertRaises(RuntimeFailure):
                immersive_confirmation_button(value, immersive_window())

    def test_tap_uses_fresh_bounds_after_retaining_originals_and_then_native_app_observation(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.runner(Path(directory))
            fresh = IMMERSIVE_XML.replace("[1611,436][1793,562]", "[1511,436][1693,562]")
            runner.adb.observe.side_effect = [(IMMERSIVE_XML, immersive_window()), (fresh, immersive_window())]
            def tap(target, *, deadline=None):
                self.assertEqual(target.get("bounds"), "[1511,436][1693,562]")
                self.assertEqual((runner.output / "07-immersive-confirmation.xml").read_text(), IMMERSIVE_XML)
                self.assertEqual((runner.output / "07-immersive-confirmation.fresh.xml").read_text(), fresh)
                self.assertTrue((runner.output / "07-immersive-confirmation.png").is_file())
                self.assertEqual((runner.output / "07-immersive-confirmation.fresh.window.txt").read_text(), immersive_window())
                self.assertEqual(runner.pid.call_count, 3)
            runner.tap.side_effect = tap
            self.assertEqual(runner.observe(), "<hierarchy/>")
            runner.require_owned_avd.assert_called_once()
            runner.tap.assert_called_once()
            runner.observer.observe.assert_called_once()
            self.assertEqual(runner.immersive_confirmations[0]["status"], "acknowledged")
            # An animation tail or recurring tip never authorizes a second tap.
            runner.observe()
            self.assertEqual(runner.tap.call_count, 1)
            self.assertEqual(runner.adb.observe.call_count, 2)

    def test_normal_app_focus_never_uses_system_dialog_uiautomator_path(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.runner(Path(directory))
            runner.adb.run.return_value.stdout = (window() + "inactive Window{abc ImmersiveModeConfirmation}\n").encode()
            runner.observe()
            runner.adb.observe.assert_not_called()
            runner.tap.assert_not_called()
            runner.observer.observe.assert_called_once()

    def test_first_entry_forwards_one_deadline_to_both_observers_and_tap(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.runner(Path(directory))
            with patch("tools.android_fullscreen_runtime.run.time.monotonic", return_value=10):
                self.assertEqual(runner.observe(deadline=15), "<hierarchy/>")
            self.assertEqual(runner.adb.observe.call_count, 2)
            self.assertTrue(all(call.kwargs == {"deadline": 15} for call in runner.adb.observe.call_args_list))
            runner.observer.observe.assert_called_once_with(deadline=15)
            runner.adb.screenshot.assert_called_once_with(timeout=5)
            self.assertEqual(runner.tap.call_args.kwargs, {"deadline": 15})
            self.assertEqual(runner.adb.run.call_args.kwargs["timeout"], 5)

    def test_expired_entry_deadline_never_reads_or_taps(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.runner(Path(directory))
            with patch("tools.android_fullscreen_runtime.run.time.monotonic", return_value=15), \
                    self.assertRaises(ObserverIntegrityFailure):
                runner.observe(deadline=15)
            runner.adb.run.assert_not_called()
            runner.adb.observe.assert_not_called()
            runner.observer.observe.assert_not_called()
            runner.tap.assert_not_called()

    def test_late_fresh_system_tip_cannot_authorize_tap(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.runner(Path(directory))
            clock = [10]
            def late_tip(**kwargs):
                clock[0] = 15
                return IMMERSIVE_XML, immersive_window()
            runner.adb.observe.side_effect = late_tip
            with patch("tools.android_fullscreen_runtime.run.time.monotonic", side_effect=lambda: clock[0]), \
                    self.assertRaises(ObserverIntegrityFailure):
                runner.acknowledge_immersive_confirmation(IMMERSIVE_XML, immersive_window(), deadline=15)
            runner.tap.assert_not_called()
            self.assertEqual(runner.immersive_confirmations, [])

    def test_late_native_app_result_never_acknowledges_or_returns_entry(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.runner(Path(directory))
            clock = [10]
            def late_app(**kwargs):
                clock[0] = 15
                return "<hierarchy/>", window(width=2400, height=1080, bars=False)
            runner.observer.observe.side_effect = late_app
            with patch("tools.android_fullscreen_runtime.run.time.monotonic", side_effect=lambda: clock[0]), \
                    self.assertRaises(ObserverIntegrityFailure):
                runner.observe(deadline=15)
            runner.tap.assert_called_once()
            self.assertEqual(runner.immersive_confirmations[0]["status"], "tap-sent")

    def test_system_tip_is_never_accepted_as_fresh_fullscreen_app_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.runner(Path(directory))
            runner.observer.observe.return_value = (IMMERSIVE_XML, immersive_window())
            with self.assertRaisesRegex(RuntimeFailure, "not the focused Android package"):
                runner.observe()
            self.assertEqual(runner.immersive_confirmations[0]["status"], "tap-sent")
            with self.assertRaises(RuntimeFailure):
                display_state(immersive_window())
            runner.tap.assert_called_once()
            runner.observer.observe.assert_called_once()

    def test_other_phases_and_repeated_acknowledgement_never_tap(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.runner(Path(directory))
            for phase in ("01-fixture-review", "08-controls-auto-hidden", "13-back-exits-fullscreen"):
                runner.phase = phase
                runner.observe()
                with self.assertRaises(ObserverIntegrityFailure):
                    runner.acknowledge_immersive_confirmation(IMMERSIVE_XML, immersive_window())
            runner.phase = "07-entered-fullscreen"
            runner.immersive_confirmations.append({"status": "tap-sent"})
            with self.assertRaises(ObserverIntegrityFailure):
                runner.acknowledge_immersive_confirmation(IMMERSIVE_XML, immersive_window())
            runner.tap.assert_not_called()
            runner.adb.observe.assert_not_called()

    def test_changed_fresh_focus_or_content_and_unverified_avd_never_tap(self):
        for case in ("focus", "content", "geometry", "ownership"):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as directory:
                runner = self.runner(Path(directory))
                if case == "ownership":
                    runner.require_owned_avd.side_effect = RuntimeFailure("unowned AVD")
                else:
                    fresh_xml = IMMERSIVE_XML.replace("Got it", "Allow") if case == "content" else IMMERSIVE_XML
                    fresh_window = window() if case == "focus" else immersive_window()
                    if case == "geometry":
                        fresh_window = fresh_window.replace("cur=2400x1080", "cur=2500x1080")
                    runner.adb.observe.return_value = (fresh_xml, fresh_window)
                with self.assertRaises(RuntimeFailure):
                    runner.acknowledge_immersive_confirmation(IMMERSIVE_XML, immersive_window())
                runner.tap.assert_not_called()

    def test_changed_process_before_or_after_tap_is_a_hard_failure(self):
        for pids, taps in ((["456"], 0), (["123", "456"], 0), (["123", "123", "456"], 1)):
            with self.subTest(pids=pids), tempfile.TemporaryDirectory() as directory:
                runner = self.runner(Path(directory))
                runner.pid.side_effect = pids
                with self.assertRaises(ObserverIntegrityFailure):
                    runner.acknowledge_immersive_confirmation(IMMERSIVE_XML, immersive_window())
                self.assertEqual(runner.tap.call_count, taps)

    def test_uncertain_tap_is_retained_and_cannot_be_retried(self):
        with tempfile.TemporaryDirectory() as directory:
            runner = self.runner(Path(directory))
            runner.tap.side_effect = subprocess.TimeoutExpired("adb input tap", 25)
            with self.assertRaises(ObserverIntegrityFailure):
                runner.acknowledge_immersive_confirmation(IMMERSIVE_XML, immersive_window())
            self.assertEqual(runner.immersive_confirmations[0]["status"], "uncertain")
            with self.assertRaises(ObserverIntegrityFailure):
                runner.acknowledge_immersive_confirmation(IMMERSIVE_XML, immersive_window())
            runner.tap.assert_called_once()


if __name__ == "__main__":
    unittest.main()
