"""Contract tests for the opt-in Together profile recording path."""

import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools" / "android_multi_device"


@unittest.skipIf(os.name == "nt", "Bash contract tests run on Linux or WSL")
class TogetherModeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.work = Path(self.temporary.name)
        self.bin = self.work / "bin"
        self.bin.mkdir()
        self.env = os.environ.copy()
        self.env["PATH"] = f"{self.bin}{os.pathsep}{self.env['PATH']}"

    def fake(self, name: str, body: str):
        path = self.bin / name
        path.write_text("#!/usr/bin/env bash\nset -euo pipefail\n" + body)
        path.chmod(0o755)
        return path

    def run_script(self, name: str, *args: str):
        return subprocess.run(
            ["bash", str(TOOLS / name), *args],
            cwd=self.work,
            env=self.env,
            text=True,
            capture_output=True,
            timeout=30,
            check=False,
        )

    def test_build_modes_keep_role_apks_and_profile_has_no_test_store_key(self):
        self.fake(
            "flutter",
            """printf '%s\\n' "$*" >> "$FAKE_FLUTTER_LOG"
mode=debug
role=''
for arg in "$@"; do
  [[ "$arg" == --profile ]] && mode=profile
  [[ "$arg" == --dart-define=TOGETHER_ROLE=* ]] && role="${arg##*=}"
done
mkdir -p build/app/outputs/flutter-apk
printf '%s:%s\\n' "$role" "$mode" > "build/app/outputs/flutter-apk/app-$mode.apk"
""",
        )
        (self.work / "integration_test").mkdir()
        (self.work / "integration_test" / "production_together_test.dart").touch()
        self.env["FAKE_FLUTTER_LOG"] = str(self.work / "flutter.log")

        for mode in ("debug", "profile"):
            with self.subTest(mode=mode):
                output = self.work / mode
                args = [
                    "--room", "mode-test", "--target",
                    "integration_test/production_together_test.dart",
                    "--coordination-url", "http://10.0.2.2:18766/invite",
                    "--output", str(output),
                ]
                if mode == "profile":
                    args += ["--mode", mode]
                result = self.run_script("build_together_apks.sh", *args)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual((output / "host.apk").read_text(), f"host:{mode}\n")
                self.assertEqual((output / "guest.apk").read_text(), f"guest:{mode}\n")
                self.assertIn(f"mode\t{mode}\n", (output / "build-provenance.tsv").read_text())
                calls = (self.work / "flutter.log").read_text().splitlines()[-2:]
                self.assertEqual(len(calls), 2)
                for call, role in zip(calls, ("host", "guest")):
                    self.assertIn(f"--dart-define=TOGETHER_ROLE={role}", call)
                    self.assertIn(f"--{mode}", call)
                    if mode == "profile":
                        self.assertIn("--dart-define=REVENUECAT_API_KEY=", call)
                    else:
                        self.assertNotIn("--dart-define=REVENUECAT_API_KEY=", call)

    def test_ci_rejects_mode_mismatch_before_starting_devices(self):
        runtime = self.work / "build" / "android-multi-device"
        fixture = runtime / "fixture" / "sync-fixture.mp4"
        fixture.parent.mkdir(parents=True)
        fixture.write_bytes(b"fixture")
        apks = runtime / "apks"
        apks.mkdir()
        for role in ("host", "guest"):
            apk = apks / f"{role}.apk"
            apk.write_bytes(role.encode())
            relative = f"build/android-multi-device/apks/{role}.apk"
            (apks / f"{role}.apk.sha256").write_text(
                f"{hashlib.sha256(apk.read_bytes()).hexdigest()}  {relative}\n"
            )
        provenance = apks / "build-provenance.tsv"
        provenance.write_text(
            "target\tintegration_test/together_smoke_test.dart\n"
            "mode\tdebug\nroom\tmode-test\nserver\tsyncplay.pl\n"
            "host_apk\tbuild/android-multi-device/apks/host.apk\n"
            "guest_apk\tbuild/android-multi-device/apks/guest.apk\n"
            "port\t8995\nvideo_url\thttp://10.0.2.2:18765/sync-fixture.mp4\n"
        )
        result = self.run_script("ci_together.sh", "--mode", "profile")
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertIn("build mode does not match", result.stderr)
        self.assertFalse((runtime / "sessions").exists())

        profile_manifest = provenance.read_text().replace("mode\tdebug", "mode\tprofile")
        provenance.write_text(profile_manifest.replace("host.apk\n", "other.apk\n"))
        wrong_file = self.run_script("ci_together.sh", "--mode", "profile")
        self.assertEqual(wrong_file.returncode, 3, wrong_file.stderr)
        self.assertIn("selected host and guest files", wrong_file.stderr)

        provenance.write_text(profile_manifest)
        (apks / "host.apk").write_bytes(b"tampered")
        wrong_hash = self.run_script("ci_together.sh", "--mode", "profile")
        self.assertEqual(wrong_hash.returncode, 3, wrong_hash.stderr)
        self.assertIn("APK hash does not match", wrong_hash.stderr)
        self.assertFalse((runtime / "sessions").exists())

    def test_invalid_mode_is_rejected_before_any_build_or_device_work(self):
        for script in (
            "build_together_apks.sh",
            "ci_together.sh",
            "run_together_smoke.sh",
        ):
            with self.subTest(script=script):
                result = self.run_script(script, "--mode", "release")
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn("--mode must be debug or profile", result.stderr)
                missing = self.run_script(script, "--mode")
                self.assertEqual(missing.returncode, 2, missing.stderr)
                self.assertIn("--mode needs debug or profile", missing.stderr)
        self.assertFalse((self.work / "build").exists())

    def test_driver_mode_reaches_both_roles_without_changing_default(self):
        self.fake(
            "adb",
            """if [[ "${1:-}" == -s ]]; then shift 2; fi
case "$*" in
  get-state) echo device ;;
  'shell getprop sys.boot_completed') echo 1 ;;
  'shell getprop init.svc.bootanim') echo stopped ;;
  'shell settings get global device_provisioned') echo 1 ;;
  'shell settings get secure user_setup_complete') echo 1 ;;
  'shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME') echo 'com.android.launcher/.Launcher' ;;
  'shell dumpsys window displays') echo 'mCurrentFocus=Window{1 com.android.launcher/.Launcher}' ;;
esac
""",
        )
        self.fake(
            "flutter",
            """printf '%s|%s\\n' "$TOGETHER_ROLE" "$*" >> "$FAKE_FLUTTER_LOG"
echo 'VMServiceFlutterDriver: Connected to Flutter application.'
sleep 6
""",
        )
        self.env["FAKE_FLUTTER_LOG"] = str(self.work / "drive.log")
        for name in ("host.apk", "guest.apk", "driver.dart", "target.dart"):
            (self.work / name).write_bytes(b"test")
        session = self.work / "session.env"
        session.write_text(
            "PHONE_SERIAL=emulator-5554\nTABLET_SERIAL=emulator-5556\n"
            f"SESSION_DIR='{self.work}'\nADB='{self.bin / 'adb'}'\n"
        )
        for mode in ("debug", "profile"):
            with self.subTest(mode=mode):
                args = [
                    "--session", str(session),
                    "--host-apk", "host.apk", "--guest-apk", "guest.apk",
                    "--driver", "driver.dart", "--target", "target.dart",
                    "--room", "mode-test", "--output", str(self.work / mode),
                    "--driver-output", str(self.work / f"{mode}-driver"),
                ]
                if mode == "profile":
                    args += ["--mode", mode]
                result = self.run_script("run_together_smoke.sh", *args)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(
                    f"mode\t{mode}\n",
                    (self.work / mode / "command-environment.tsv").read_text(),
                )
                calls = (self.work / "drive.log").read_text().splitlines()[-2:]
                self.assertEqual({call.split("|", 1)[0] for call in calls}, {"host", "guest"})
                for call in calls:
                    self.assertEqual("--profile" in call, mode == "profile")


if __name__ == "__main__":
    unittest.main()
