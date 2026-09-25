"""Reduce an owned phone acceptance AVD's pixels, preserving its dp size."""

import json
import os
from pathlib import Path
import re


ORIGINAL = {"hw.lcd.width": 1080, "hw.lcd.height": 2400, "hw.lcd.density": 420}
PREPARED = {"hw.lcd.width": 540, "hw.lcd.height": 1200, "hw.lcd.density": 210}


def prepare(home: Path, name: str, output: Path) -> None:
    if re.fullmatch(r"meowwatch_(lifecycle|interruption|network)_[0-9]+_[0-9]+", name) is None:
        raise ValueError("only a named lifecycle, interruption or network AVD may be prepared")
    root = home.resolve(strict=True)
    config = root / f"{name}.avd" / "config.ini"
    if config.resolve(strict=True) != config:
        raise ValueError("AVD config escapes its task directory")
    before = config.read_text(encoding="utf-8")
    entries = [line.partition("=") for line in before.splitlines()]
    for key, expected in ORIGINAL.items():
        if [value.strip() for candidate, separator, value in entries
                if separator and candidate.strip() == key] != [str(expected)]:
            raise ValueError(f"unexpected original phone configuration: {key}")
    output.mkdir(parents=True, exist_ok=False)
    values = {**PREPARED, "skin.name": "540x1200", "skin.path": "540x1200"}
    lines = [line for line in before.splitlines() if line.partition("=")[0].strip() not in values]
    lines.extend(f"{key}={value}" for key, value in values.items())
    after = "\n".join(lines) + "\n"
    (output / "before.ini").write_text(before, encoding="utf-8")
    config.write_text(after, encoding="utf-8")
    (output / "after.ini").write_text(after, encoding="utf-8")
    (output / "preparation.json").write_text(json.dumps({
        "avdName": name, "original": ORIGINAL, "prepared": PREPARED,
        "logicalSizeDp": [1080 * 160 / 420, 2400 * 160 / 420],
        "scope": "pre-launch framebuffer; app, timing assertions and observer deadlines unchanged",
    }, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    prepare(Path(os.environ["ANDROID_AVD_HOME"]), os.environ["PHONE_ACCEPTANCE_AVD_NAME"],
            Path("build/android-phone-acceptance-avd"))
