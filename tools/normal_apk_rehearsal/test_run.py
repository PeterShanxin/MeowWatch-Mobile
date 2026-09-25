"""Small parser contracts for the visible invitation and native controls."""

import unittest

from tools.android_install.runner import PACKAGE, RuntimeFailure
from tools.normal_apk_rehearsal.run import (
    history_context, unique_seekbar, unique_text_field, visible_code,
)


def tree(*nodes: str) -> str:
    return '<hierarchy>' + ''.join(nodes) + '</hierarchy>'


def node(label: str, *, kind: str = 'android.widget.TextView') -> str:
    return (f'<node package="{PACKAGE}" enabled="true" '
            f'visible-to-user="true" class="{kind}" text="{label}" '
            'bounds="[0,0][200,80]"/>')


class VisibleUiContract(unittest.TestCase):
    def test_visible_bare_invite(self):
        xml = tree(node('QR invite to sleepy-otter-stars'), node('sleepy-otter-stars'))
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

    def test_history_requires_fixture_and_saved_room_position(self):
        xml = tree(node('Continue Watching'), node('sync-fixture.mp4'),
                   node('Room sleepy-otter-stars · 0:12 of 1:30'))
        self.assertTrue(history_context(xml, 'Room sleepy-otter-stars'))
        with self.assertRaises(RuntimeFailure):
            history_context(tree(node('Recent rooms'), node('Room sleepy-otter-stars')),
                            'Room sleepy-otter-stars')


if __name__ == '__main__':
    unittest.main()
