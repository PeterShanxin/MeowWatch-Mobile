"""Reduce the dedicated tablet framebuffer while preserving its exact dp layout."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re


ORIGINAL = {"hw.lcd.width": 2560, "hw.lcd.height": 1600, "hw.lcd.density": 320}
PREPARED = {"hw.lcd.width": 1280, "hw.lcd.height": 800, "hw.lcd.density": 160}


def prepare(home: Path, name: str, form_factor: str, output: Path) -> None:
    if form_factor not in {"phone", "tablet"} or re.fullmatch(
            rf"meowwatch_fullscreen_{form_factor}_[0-9]+_[0-9]+", name) is None:
        raise ValueError("only a named fullscreen workflow AVD may be prepared")
    root = home.resolve(strict=True)
    config = root / f"{name}.avd" / "config.ini"
    if config.resolve(strict=True) != config:
        raise ValueError("fullscreen AVD config escapes its task directory")
    before = config.read_text(encoding="utf-8")
    output.mkdir(parents=True, exist_ok=False)
    (output / "before.ini").write_text(before, encoding="utf-8")
    if form_factor == "tablet":
        entries = [line.partition("=") for line in before.splitlines()]
        for key, expected in ORIGINAL.items():
            actual = [value.strip() for candidate, separator, value in entries
                      if separator and candidate.strip() == key]
            if actual != [str(expected)]:
                raise ValueError(f"unexpected original tablet configuration: {key}")
        values = {**PREPARED, "skin.name": "1280x800", "skin.path": "1280x800"}
        lines = [line for line in before.splitlines()
                 if line.partition("=")[0].strip() not in values]
        lines.extend(f"{key}={value}" for key, value in values.items())
        config.write_text("\n".join(lines) + "\n", encoding="utf-8")
    (output / "after.ini").write_text(config.read_text(encoding="utf-8"), encoding="utf-8")
    (output / "preparation.json").write_text(json.dumps({
        "avdName": name, "formFactor": form_factor,
        "changed": form_factor == "tablet",
        "original": ORIGINAL if form_factor == "tablet" else None,
        "prepared": PREPARED if form_factor == "tablet" else None,
        "tabletLogicalSizeDp": [1280, 800] if form_factor == "tablet" else None,
        "scope": "pre-launch framebuffer; native playback and observer deadlines unchanged",
    }, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    prepare(Path(os.environ["ANDROID_AVD_HOME"]), os.environ["FULLSCREEN_AVD_NAME"],
            os.environ["FULLSCREEN_FORM_FACTOR"], Path("build/android-fullscreen-avd"))
