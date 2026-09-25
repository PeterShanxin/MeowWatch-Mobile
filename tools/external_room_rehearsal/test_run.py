"""Pure validation and native UI receipt parser contracts."""

import unittest
from xml.sax.saxutils import escape

from tools.android_install.runner import RuntimeFailure
from tools.external_room_rehearsal.run import message, receipt, sample_player, validate_room


PACKAGE = "com.meowwatch.meowwatch_mobile"


def xml(*items: tuple[str, str, str]) -> str:
    nodes = "".join(
        f'<node package="{PACKAGE}" class="{kind}" text="{escape(value).replace(chr(10), "&#10;")}" '
        f'content-desc="" clickable="{clickable}" />'
        for kind, value, clickable in items
    )
    return f"<hierarchy>{nodes}</hierarchy>"


class ExternalRoomContracts(unittest.TestCase):
    def test_only_short_ascii_room_codes_are_accepted(self):
        self.assertEqual(validate_room("mw-cloud-123"), "mw-cloud-123")
        for bad in ("ab", "a" * 37, "a b", "a@syncplay.pl", "房间", "a/b", "a\nxyz"):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                validate_room(bad)

    def test_handshake_changes_with_room_and_stage(self):
        self.assertRegex(message("mw-cloud-123", "READY"), r"^MWG-[0-9a-f]{8}-READY$")
        self.assertNotEqual(message("mw-cloud-123", "READY"), message("mw-cloud-124", "READY"))
        with self.assertRaises(ValueError):
            message("mw-cloud-123", "ARBITRARY")

    def test_receipt_requires_complete_visible_message_not_composer_or_substring(self):
        expected = message("mw-cloud-123", "DESKTOP_READY")
        tree = xml(("android.widget.EditText", expected, "true"),
                   ("android.widget.TextView", f"other\n{expected}-OLD", "false"))
        with self.assertRaises(RuntimeFailure):
            receipt(tree, expected)
        self.assertTrue(receipt(xml(("android.widget.TextView", f"desktop\n{expected}", "false")), expected))

    def test_sample_player_requires_real_title_timeline_and_duration(self):
        good = xml(("android.widget.TextView", "movie.mp4", "false"),
                   ("android.widget.SeekBar", "", "true"),
                   ("android.widget.TextView", "3:12", "false"),
                   ("android.widget.TextView", "9:56", "false"),
                   ("android.widget.Button", "Pause", "true"))
        self.assertEqual(sample_player(good, True).position_seconds, 192)
        with self.assertRaises(RuntimeFailure):
            sample_player(good.replace("9:56", "0:52"), True)


if __name__ == "__main__":
    unittest.main()
