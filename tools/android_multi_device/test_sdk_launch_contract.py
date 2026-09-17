"""Exercise the launcher's real SDK verification block without Android tools."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
BASH = ("C:/Program Files/Git/bin/bash.exe" if os.name == "nt"
        and Path("C:/Program Files/Git/bin/bash.exe").is_file() else shutil.which("bash"))


@unittest.skipUnless(BASH, "Bash is required for the launch contract")
class SDKLaunchContractTests(unittest.TestCase):
    def test_failed_validation_stops_before_emulator_and_preserves_quoted_receipt(self):
        source = (ROOT / "tools/android_multi_device/launch_two_avds.sh").read_text(encoding="utf-8")
        start = "system_image='system-images;android-35;google_apis;x86_64'\n"
        self.assertEqual(source.count(start), 1)
        block = start + source.split(start, 1)[1].split('device_list=', 1)[0]
        for receipt in ("", "receipt with spaces/result.json"):
            for exit_code in (0, 19):
                with self.subTest(receipt=receipt, exit_code=exit_code), tempfile.TemporaryDirectory() as directory:
                    root = Path(directory)
                    script = root / "launch-contract.sh"
                    script.write_text('''#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
session_dir="$PWD"
sdk_root="sdk with spaces"
emulator=fixture_emulator
python3() { printf '%s\\n' "$@" > arguments.txt; return "$VALIDATION_EXIT"; }
fixture_emulator() { printf '%s\\n' "$@" > emulator-called.txt; }
''' + block, encoding="utf-8", newline="\n")
                    result = subprocess.run([BASH, script.as_posix()], cwd=root, capture_output=True,
                                            text=True, timeout=10, env={**os.environ,
                                                "MEOWWATCH_ANDROID_SDK_PREPARATION": receipt,
                                                "VALIDATION_EXIT": str(exit_code)})
                    self.assertEqual(result.returncode, exit_code, result.stderr)
                    expected = ["-m", "tools.android_multi_device.prepare_sdk_packages", "verify",
                                "--sdk-root", "sdk with spaces"]
                    if receipt:
                        expected += ["--preparation-report", receipt]
                    self.assertEqual((root / "arguments.txt").read_text().splitlines(), expected)
                    self.assertEqual((root / "emulator-called.txt").exists(), exit_code == 0)


if __name__ == "__main__":
    unittest.main()
