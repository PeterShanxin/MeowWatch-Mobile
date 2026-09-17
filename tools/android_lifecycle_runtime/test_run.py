from pathlib import Path
from contextlib import redirect_stdout
import io
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from xml.sax.saxutils import escape

from tools.android_install.runner import PACKAGE, RuntimeFailure
from tools.android_lifecycle_runtime.run import (
    FIXTURE_NAME, Playback, Runner, button, history_card, history_swipe, main,
    parse_time, playback, require_background_pause, require_paused_stability,
    require_playing_advance, require_restored_position, timed_out_observation,
)


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


class LifecycleRuntimeTests(unittest.TestCase):
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
            runner.last_xml = player("0:03", "Pause")
            dump_commands = []

            def native_command(command, **_kwargs):
                arguments = command[3:]
                if arguments[:3] == ["shell", "uiautomator", "dump"]:
                    dump_commands.append(command)
                    if len(dump_commands) == 1:
                        raise subprocess.TimeoutExpired(command, 10)
                    return subprocess.CompletedProcess(command, 0, b"UI hierarchy dumped", b"")
                if arguments[:2] == ["exec-out", "cat"]:
                    return subprocess.CompletedProcess(command, 0, player("0:20", "Pause").encode(), b"")
                if arguments[:4] == ["shell", "dumpsys", "window", "displays"]:
                    window = f"mCurrentFocus=Window{{abc {PACKAGE}/.MainActivity}}\n".encode()
                    return subprocess.CompletedProcess(command, 0, window, b"")
                self.fail(f"Unexpected observation command: {arguments[:3]}")

            with patch("tools.android_install.runner.subprocess.run", side_effect=native_command), patch(
                "tools.android_lifecycle_runtime.run.time.sleep",
            ):
                xml, state = runner.sample("04-advanced", playing=True, screenshot=False)

            self.assertEqual(state, Playback(20, 90, True))
            self.assertEqual(xml, player("0:20", "Pause"))
            self.assertEqual(len(dump_commands), 2)
            self.assertNotEqual(dump_commands[0][-1], dump_commands[1][-1])
            self.assertEqual([item["position_seconds"] for item in runner.samples], [20])
            self.assertEqual(runner.observation_timeouts[0]["operation"], "UIAutomator hierarchy dump")
            self.assertEqual(runner.observation_timeouts[0]["phase"], "04-advanced")
            self.assertEqual(runner.last_observation["phase"], "04-advanced")

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
