from pathlib import Path
from contextlib import redirect_stdout
import io
import tempfile
import unittest
from xml.sax.saxutils import escape

from tools.android_install.runner import PACKAGE, RuntimeFailure
from tools.android_lifecycle_runtime.run import (
    FIXTURE_NAME, Playback, Runner, button, history_card, history_swipe, main,
    parse_time, playback, require_background_pause, require_paused_stability,
    require_playing_advance, require_restored_position,
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
