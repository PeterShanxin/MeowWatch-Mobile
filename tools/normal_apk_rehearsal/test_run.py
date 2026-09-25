"""Small parser contracts for the visible invitation and native controls."""

import unittest
from xml.sax.saxutils import escape

from tools.android_install.runner import PACKAGE, RuntimeFailure
from tools.android_lifecycle_runtime.run import button
from tools.normal_apk_rehearsal.run import (
    FIXTURE_URL, entered_text_field, focused_text_field, history_context,
    join_sheet_ready, media_link_ready,
    rehearsed_playback, timeline_tap, unique_seekbar, unique_text_field,
    visible_chat_receipt, visible_code,
)


def tree(*nodes: str) -> str:
    return '<hierarchy>' + ''.join(nodes) + '</hierarchy>'


def node(label: str, *, kind: str = 'android.widget.TextView', clickable: bool = False,
         focused: bool = False) -> str:
    label = escape(label, {'"': '&quot;'}).replace('\n', '&#10;')
    return (f'<node package="{PACKAGE}" enabled="true" '
            f'visible-to-user="true" class="{kind}" text="{label}" '
            f'clickable="{str(clickable).lower()}" focused="{str(focused).lower()}" '
            'bounds="[0,0][200,80]"/>')


class VisibleUiContract(unittest.TestCase):
    def test_visible_bare_invite(self):
        xml = tree(node('QR invite to sleepy-otter-stars'), node('sleepy-otter-stars'))
        self.assertEqual(visible_code(xml), 'sleepy-otter-stars')

    def test_visible_qr_description_from_native_observer(self):
        xml = tree(node('QR invite to sleepy-otter-stars\nqr code'),
                   node('sleepy-otter-stars'))
        self.assertEqual(visible_code(xml), 'sleepy-otter-stars')

    def test_visible_endpoint_invite(self):
        xml = tree(node('QR invite to sleepy-otter-stars'),
                   node('sleepy-otter-stars@syncplay.pl:8995'))
        self.assertEqual(visible_code(xml), 'sleepy-otter-stars@syncplay.pl:8995')

    def test_ambiguous_visible_invite_fails(self):
        xml = tree(node('QR invite to sleepy-otter-stars'),
                   node('sleepy-otter-stars'), node('sleepy-otter-stars'))
        with self.assertRaises(RuntimeFailure):
            visible_code(xml)

    def test_unique_text_field_and_timeline(self):
        xml = tree(node('', kind='android.widget.EditText'),
                   node('', kind='android.widget.SeekBar'))
        self.assertEqual(unique_text_field(xml).get('class'), 'android.widget.EditText')
        self.assertEqual(unique_seekbar(xml).get('class'), 'android.widget.SeekBar')

    def test_seek_uses_visible_track_labels_when_native_seekbar_bounds_are_thumb_only(self):
        xml = tree(
            f'<node package="{PACKAGE}" class="android.widget.SeekBar" '
            'content-desc="0:30" bounds="[307,588][355,636]"/>',
            f'<node package="{PACKAGE}" class="android.view.View" '
            'content-desc="0:30" bounds="[20,636][48,652]"/>',
            f'<node package="{PACKAGE}" class="android.view.View" '
            'content-desc="1:30" bounds="[895,636][919,652]"/>',
        )
        self.assertEqual(timeline_tap(xml, .60), (556, 612))
        with self.assertRaises(RuntimeFailure):
            timeline_tap(xml.replace('bounds="[895,636][919,652]"',
                                     'bounds="[50,636][74,652]"'), .60)

    def test_history_requires_fixture_and_saved_room_position(self):
        xml = tree(node('Continue Watching'), node('sync-fixture.mp4'),
                   node('Room sleepy-otter-stars · 0:12 of 1:30'))
        self.assertTrue(history_context(xml, 'Room sleepy-otter-stars'))
        with self.assertRaises(RuntimeFailure):
            history_context(tree(node('Recent rooms'), node('Room sleepy-otter-stars')),
                            'Room sleepy-otter-stars')

    def test_join_sheet_uses_visible_field_not_floating_label(self):
        xml = tree(node('Join their movie night'),
                   node('', kind='android.widget.EditText', clickable=True),
                   node('Join room', kind='android.widget.Button', clickable=True))
        self.assertTrue(join_sheet_ready(xml))
        with self.assertRaises(RuntimeFailure):
            join_sheet_ready(tree(node('', kind='android.widget.EditText', clickable=True),
                                  node('Join room', kind='android.widget.Button', clickable=True)))

    def test_media_link_requires_visible_submit_and_entered_fixture(self):
        ready = tree(node('Choose what to watch'),
                     node(FIXTURE_URL, kind='android.widget.EditText', clickable=True),
                     node('Use this link', kind='android.widget.Button', clickable=True))
        self.assertTrue(media_link_ready(ready))
        with self.assertRaises(RuntimeFailure):
            media_link_ready(tree(node('Choose what to watch'),
                                  node(FIXTURE_URL, kind='android.widget.EditText', clickable=True)))

    def test_text_entry_waits_for_native_focus(self):
        self.assertTrue(focused_text_field(tree(node('', kind='android.widget.EditText',
                                                 clickable=True, focused=True))))
        with self.assertRaises(RuntimeFailure):
            focused_text_field(tree(node('', kind='android.widget.EditText', clickable=True)))

    def test_text_entry_requires_exact_visible_value(self):
        expected = 'quiet-lark-pokes-kindly-daisy'
        self.assertTrue(entered_text_field(
            tree(node(expected, kind='android.widget.EditText', focused=True)), expected))
        with self.assertRaises(RuntimeFailure):
            entered_text_field(
                tree(node('g' + expected, kind='android.widget.EditText', focused=True)),
                expected)

    def test_chat_receipt_matches_complete_message_in_visible_sender_bubble(self):
        # Extracted semantics shape from tablet failure XML in run 36126715801.
        bubble = (f'<node package="{PACKAGE}" enabled="true" visible-to-user="true" '
                  'class="android.view.View" text="" '
                  'content-desc="AmberOtter&#10;HelloFromPhone" '
                  'bounds="[960,570][1260,644]"/>')
        self.assertTrue(visible_chat_receipt(tree(bubble), 'HelloFromPhone'))
        self.assertTrue(visible_chat_receipt(
            tree(node('HelloFromTablet', kind='android.view.View')), 'HelloFromTablet'))
        for wrong in ('AmberOtter\nHelloFromPhoneAgain',
                      'AmberOtter\nxHelloFromPhone',
                      'AmberOtter\nHelloFromPhone\nmore'):
            with self.subTest(wrong=wrong), self.assertRaises(RuntimeFailure):
                visible_chat_receipt(
                    tree(node(wrong, kind='android.view.View')), 'HelloFromPhone')
        with self.assertRaises(RuntimeFailure):
            visible_chat_receipt(
                tree(node('HelloFromPhone', kind='android.widget.EditText')),
                'HelloFromPhone')

    def test_reaction_picker_exposes_clickable_emoji_below_semantics_label(self):
        # Native picker hierarchy from run 36128627853: the label is not clickable.
        xml = tree(node('React ❤️', kind='android.widget.Button'),
                   node('❤️', kind='android.widget.Button', clickable=True))
        self.assertEqual(button(xml, '❤️').get('clickable'), 'true')
        with self.assertRaises(RuntimeFailure):
            button(xml, 'React ❤️')

    def test_local_mode_home_action_has_complete_merged_label(self):
        # Phone home hierarchy from run 36128627853.
        label = 'Local Player Mode\nWatch on this device without starting a room.'
        xml = tree(node(label, kind='android.view.View', clickable=True))
        self.assertEqual(button(xml, label).get('clickable'), 'true')
        with self.assertRaises(RuntimeFailure):
            button(xml, 'Local Player Mode')

    def test_tablet_player_uses_submitted_url_and_visible_ninety_second_timeline(self):
        landscape = tree(node('Together in this room'),
                         node('0:00'), node('1:30'),
                         node('', kind='android.widget.SeekBar', clickable=True),
                         node('Play', kind='android.widget.Button', clickable=True))
        state = rehearsed_playback(landscape, direct_fixture_submitted=True)
        self.assertEqual((state.position_seconds, state.duration_seconds, state.playing),
                         (0, 90, False))
        with self.assertRaises(RuntimeFailure):
            rehearsed_playback(landscape, direct_fixture_submitted=False)
        with self.assertRaises(RuntimeFailure):
            rehearsed_playback(landscape.replace('1:30', '1:00'), direct_fixture_submitted=True)


if __name__ == '__main__':
    unittest.main()
