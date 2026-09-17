"""Strict emulator-only ANR preflight for the native app journey recorder."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys
import time
from uuid import uuid4

from tools.billing_runtime.native_dialog import (
    Adb,
    LAUNCHER_PACKAGE,
    SETUP_PACKAGE,
    UnsafeDialog,
    image_size,
    select_google_sdk_setup_anr_close,
    select_pixel_launcher_anr_close,
)


_PHASE = re.compile(r"[A-Za-z0-9_-]+")
_PACKAGE = re.compile(r"[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+")
_ALLOWED_SELECTORS = {
    LAUNCHER_PACKAGE: select_pixel_launcher_anr_close,
    SETUP_PACKAGE: select_google_sdk_setup_anr_close,
}


def focused_anr_package(window_dump: str) -> str | None:
    """Return the exact focused ANR package, rejecting ambiguous focus state."""
    focuses = re.findall(r"mCurrentFocus=([^\r\n]+)", window_dump)
    if len(focuses) != 1:
        raise UnsafeDialog("Android did not report exactly one current focus")
    if "Application Not Responding:" not in focuses[0]:
        return None
    match = re.search(r"\bApplication Not Responding: ([^\s}]+)(?:\s|})", focuses[0])
    if match is None or _PACKAGE.fullmatch(match.group(1)) is None:
        raise UnsafeDialog("Focused ANR package is missing or invalid")
    return match.group(1)


def _prefix(evidence_dir: Path, phase: str) -> Path:
    if _PHASE.fullmatch(phase) is None:
        raise ValueError("phase must contain only letters, numbers, underscores, or hyphens")
    evidence_dir.mkdir(parents=True, exist_ok=True)
    return evidence_dir / phase


def _window(adb: Adb) -> str:
    return adb.run("shell", "dumpsys", "window", "displays").decode(
        "utf-8", errors="replace"
    )


def assert_clean(adb: Adb, evidence_dir: Path, phase: str) -> None:
    """Require a non-ANR focused window without performing any device action."""
    prefix = _prefix(evidence_dir, phase)
    window = _window(adb)
    Path(f"{prefix}-window.txt").write_text(window, encoding="utf-8")
    package = focused_anr_package(window)
    if package is None:
        prefix.with_suffix(".tsv").write_text(
            f"phase\t{phase}\nstatus\tclean\nserial\t{adb.serial}\n",
            encoding="utf-8",
        )
        return
    Path(f"{prefix}-anr.png").write_bytes(adb.screenshot())
    raise UnsafeDialog(f"Recording boundary is obscured by ANR package {package}")


def recover_once(adb: Adb, evidence_dir: Path, phase: str) -> bool:
    """Optionally close one exact allowlisted ANR over the Pixel Launcher."""
    prefix = _prefix(evidence_dir, phase)
    if not adb.verified_emulator():
        raise UnsafeDialog("System ANR preflight is emulator-only")

    xml, window = adb.observe()
    Path(f"{prefix}-observed.xml").write_text(xml, encoding="utf-8")
    Path(f"{prefix}-observed-window.txt").write_text(window, encoding="utf-8")
    package = focused_anr_package(window)
    if package is None:
        prefix.with_suffix(".tsv").write_text(
            f"phase\t{phase}\nstatus\tclean\nserial\t{adb.serial}\n",
            encoding="utf-8",
        )
        return False

    png = adb.screenshot()
    Path(f"{prefix}-before.png").write_bytes(png)
    selector = _ALLOWED_SELECTORS.get(package)
    if selector is None:
        raise UnsafeDialog(f"ANR package is not allowlisted: {package}")

    # Validate the first observation before doing slower evidence collection.
    # The launcher is the only permitted underlying activity before Flutter starts.
    selector(xml, window, expected_underlying_package=LAUNCHER_PACKAGE)
    fresh_xml, fresh_window = adb.observe()
    Path(f"{prefix}-fresh.xml").write_text(fresh_xml, encoding="utf-8")
    Path(f"{prefix}-fresh-window.txt").write_text(fresh_window, encoding="utf-8")
    target = selector(
        fresh_xml,
        fresh_window,
        expected_underlying_package=LAUNCHER_PACKAGE,
    )
    width, height = image_size(png)
    if target.bounds[2] > width or target.bounds[3] > height:
        raise UnsafeDialog("System ANR close action lies outside the observed screen")

    x, y = target.center
    adb.run("shell", "input", "tap", str(x), str(y))
    time.sleep(0.5)
    after_window = _window(adb)
    Path(f"{prefix}-after-window.txt").write_text(after_window, encoding="utf-8")
    Path(f"{prefix}-after.png").write_bytes(adb.screenshot())
    remaining = focused_anr_package(after_window)
    if remaining is not None:
        raise UnsafeDialog(f"ANR remained after the single recovery action: {remaining}")
    prefix.with_suffix(".tsv").write_text(
        "".join(
            (
                f"phase\t{phase}\n",
                "status\trecovered\n",
                f"serial\t{adb.serial}\n",
                f"package\t{package}\n",
                "action\tclose_app\n",
                "recovery_count\t1\n",
            )
        ),
        encoding="utf-8",
    )
    return True


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("recover", "assert-clean"))
    parser.add_argument("--serial", required=True)
    parser.add_argument("--evidence-dir", required=True, type=Path)
    parser.add_argument("--phase", required=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    adb = Adb(
        "adb",
        args.serial,
        f"app-journey-anr-{args.phase}-{uuid4().hex}",
    )
    prefix = _prefix(args.evidence_dir, args.phase)
    status = 0
    try:
        if args.mode == "recover":
            recover_once(adb, args.evidence_dir, args.phase)
        else:
            assert_clean(adb, args.evidence_dir, args.phase)
    except Exception as error:
        Path(f"{prefix}-error.txt").write_text(f"{error}\n", encoding="utf-8")
        print(f"System ANR {args.mode} failed: {error}", file=sys.stderr)
        status = 1
    try:
        adb.cleanup()
    except Exception as error:
        Path(f"{prefix}-cleanup-error.txt").write_text(
            f"{error}\n", encoding="utf-8"
        )
        print(f"System ANR evidence cleanup failed: {error}", file=sys.stderr)
        status = 1
    return status


if __name__ == "__main__":
    raise SystemExit(main())
