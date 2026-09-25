from fractions import Fraction
from pathlib import Path
import tempfile
import unittest

from tools.android_fullscreen_runtime.prepare_avd import ORIGINAL, PREPARED, prepare


class AvdPreparationTests(unittest.TestCase):
    def config(self, root, role="tablet", content=None):
        name = f"meowwatch_fullscreen_{role}_123_1"
        config = root / f"{name}.avd" / "config.ini"
        config.parent.mkdir()
        config.write_text(content or "hw.lcd.width=2560\nhw.lcd.height=1600\nhw.lcd.density=320\n"
                          "hw.ramSize=4096M\nskin.name=pixel_tablet\nskin.path=old-skin\n", encoding="utf-8")
        return name, config

    def test_tablet_preserves_exact_layout_and_unrelated_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            name, config = self.config(root)
            before = config.read_text()
            prepare(root, name, "tablet", root / "evidence")
            after = dict(line.split("=", 1) for line in config.read_text().splitlines())
            for key in ("hw.lcd.width", "hw.lcd.height"):
                self.assertEqual(Fraction(ORIGINAL[key], ORIGINAL["hw.lcd.density"]),
                                 Fraction(int(after[key]), int(after["hw.lcd.density"])))
                self.assertEqual(int(after[key]), PREPARED[key])
            self.assertEqual(after["hw.ramSize"], "4096M")
            self.assertEqual(after["skin.name"], "1280x800")
            self.assertEqual(after["skin.path"], "1280x800")
            self.assertEqual((root / "evidence/before.ini").read_text(), before)
            self.assertEqual((root / "evidence/after.ini").read_text(), config.read_text())

    def test_phone_configuration_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            name, config = self.config(root, "phone", "hw.lcd.width=1080\n")
            before = config.read_bytes()
            prepare(root, name, "phone", root / "evidence")
            self.assertEqual(config.read_bytes(), before)

    def test_unknown_or_mismatched_avd_and_unexpected_geometry_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            name, config = self.config(root, content="hw.lcd.width=1920\n")
            before = config.read_bytes()
            for candidate, role in (("personal", "tablet"), (name, "phone"),
                                    ("../" + name, "tablet"), (name, "tablet")):
                with self.subTest(candidate=candidate), self.assertRaises(ValueError):
                    prepare(root, candidate, role, root / "evidence")
                self.assertEqual(config.read_bytes(), before)
