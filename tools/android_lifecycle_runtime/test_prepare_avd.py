from fractions import Fraction
from pathlib import Path
import tempfile
import unittest

from tools.android_lifecycle_runtime.prepare_avd import ORIGINAL, PREPARED, prepare


class PhonePreparationTests(unittest.TestCase):
    def test_same_dp_layout_and_unrelated_settings_survive(self):
        for kind in ("lifecycle", "interruption", "network"):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                name = f"meowwatch_{kind}_123_1"
                config = root / f"{name}.avd" / "config.ini"
                config.parent.mkdir()
                before = "".join(f"{key}={value}\n" for key, value in ORIGINAL.items()) + "hw.ramSize=4096M\n"
                config.write_text(before)
                prepare(root, name, root / "evidence")
                after = dict(line.split("=", 1) for line in config.read_text().splitlines())
                for key in ("hw.lcd.width", "hw.lcd.height"):
                    self.assertEqual(int(after[key]), PREPARED[key])
                    self.assertEqual(Fraction(ORIGINAL[key], ORIGINAL["hw.lcd.density"]),
                                     Fraction(int(after[key]), int(after["hw.lcd.density"])))
                self.assertEqual(after["hw.ramSize"], "4096M")
                self.assertEqual((root / "evidence/before.ini").read_text(), before)

    def test_unknown_owner_or_ambiguous_geometry_never_changes_config(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            name = "meowwatch_lifecycle_123_1"
            config = root / f"{name}.avd" / "config.ini"
            config.parent.mkdir()
            before = "".join(f"{key}={value}\n" for key, value in ORIGINAL.items())
            for candidate, content in (("personal", before), ("../" + name, before),
                                       (name, before + "hw.lcd.width=1080\n"),
                                       (name, before.replace("420", "320"))):
                config.write_text(content)
                with self.subTest(candidate=candidate), self.assertRaises(ValueError):
                    prepare(root, candidate, root / "evidence")
                self.assertEqual(config.read_text(), content)
