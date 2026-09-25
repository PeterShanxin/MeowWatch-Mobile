from pathlib import Path
import json
import subprocess
import tempfile
import unittest

from tools.android_multi_device import prepare_sdk_packages as sdk


CONTEXT = {"GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "1", "GITHUB_SHA": "a" * 40}


def installed_sdk(root):
    for package, files in sdk.PACKAGES.items():
        folder = root.joinpath(*package.split(";"))
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "package.xml").write_text(
            f'<repository xmlns="http://schemas.android.com/repository/android/common/02">'
            f'<localPackage path="{package}"><revision><major>9</major></revision></localPackage></repository>')
        properties = "Pkg.Revision=9\n"
        if package == sdk.SYSTEM_IMAGE:
            properties += "AndroidVersion.ApiLevel=35\nSystemImage.TagId=google_apis\nSystemImage.Abi=x86_64\n"
        (folder / "source.properties").write_text(properties)
        for name in files:
            (folder / name).write_bytes(b"fixture")
    tools = root / "cmdline-tools/latest"
    (tools / "bin").mkdir(parents=True)
    (tools / "source.properties").write_text("Pkg.Revision=16.0\n")
    for name in ("sdkmanager", "avdmanager"):
        (tools / "bin" / name).write_bytes(b"fixture")


class Installer:
    def __init__(self, *, failed=False, timeout=False):
        self.calls = []
        self.failed, self.timeout = failed, timeout

    def __call__(self, command, **kwargs):
        self.calls.append(command)
        if "--version" in command:
            return subprocess.CompletedProcess(command, 0, b"16.0\n", b"XML version warning\n")
        if self.timeout:
            raise subprocess.TimeoutExpired(command, kwargs["timeout"], output=b"partial download\r", stderr=b"unfinished\n")
        return subprocess.CompletedProcess(command, int(self.failed), b"download\r\n",
                                           b"Error on ZipFile unknown archive.\n" if self.failed else b"")


class SDKPackagePreparationTests(unittest.TestCase):
    def test_install_once_then_validate_and_bind_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "sdk"; installed_sdk(root)
            output = Path(directory) / "evidence"; installer = Installer()
            result = sdk.prepare(root, output, execute=installer, context=CONTEXT)
            self.assertEqual(result["status"], "prepared", result)
            self.assertEqual(len(installer.calls), 2)
            self.assertEqual(installer.calls[1][1:], [f"--sdk_root={root.resolve()}", "--verbose",
                                                    "platform-tools", "emulator", "platforms;android-35",
                                                    "system-images;android-35;google_apis;x86_64"])
            self.assertEqual((output / "install.stdout.log").read_bytes(), b"download\r\n")
            verified = sdk.verify(root, output / "result.json", context=CONTEXT)
            self.assertEqual(verified["packages"], result["packages"])
            with self.assertRaises(FileExistsError):
                sdk.prepare(root, output, execute=installer, context=CONTEXT)
            self.assertEqual(len(installer.calls), 2)

    def test_original_zip_failure_and_uncertain_install_never_retry(self):
        for flag in ("failed", "timeout"):
            with self.subTest(flag=flag), tempfile.TemporaryDirectory() as directory:
                root = Path(directory) / "sdk"; installed_sdk(root)
                output = Path(directory) / "evidence"; installer = Installer(**{flag: True})
                result = sdk.prepare(root, output, execute=installer, context=CONTEXT)
                self.assertEqual(result["status"], "failed")
                self.assertEqual(len(installer.calls), 2)
                self.assertNotIn("packages", result)
                self.assertTrue((output / "install.stderr.log").read_bytes())
                with self.assertRaises(sdk.PreparationError):
                    sdk.verify(root, output / "result.json", context=CONTEXT)

    def test_installer_success_cannot_hide_partial_or_wrong_image(self):
        cases = [("system.img", None), ("ramdisk.img", b""),
                 ("package.xml", b'<repository><localPackage path="system-images;android-34;google_apis;x86_64"/></repository>'),
                 ("source.properties", b"Pkg.Revision=9\nAndroidVersion.ApiLevel=35\nSystemImage.TagId=google_apis_playstore\nSystemImage.Abi=x86_64\n")]
        for name, contents in cases:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory) / "sdk"; installed_sdk(root)
                target = root.joinpath(*sdk.SYSTEM_IMAGE.split(";"), name)
                if contents is None:
                    target.unlink()
                else:
                    target.write_bytes(contents)
                installer = Installer()
                result = sdk.prepare(root, Path(directory) / "evidence", execute=installer, context=CONTEXT)
                self.assertEqual(result["status"], "failed")
                self.assertEqual(len(installer.calls), 2)

    def test_receipt_rejects_new_attempt_head_root_or_changed_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "sdk"; installed_sdk(root)
            output = Path(directory) / "evidence"
            sdk.prepare(root, output, execute=Installer(), context=CONTEXT)
            receipt = output / "result.json"
            for key in CONTEXT:
                with self.subTest(key=key), self.assertRaises(sdk.PreparationError):
                    sdk.verify(root, receipt, context={**CONTEXT, key: "different"})
            other = Path(directory) / "other"; installed_sdk(other)
            with self.assertRaises(sdk.PreparationError):
                sdk.verify(other, receipt, context=CONTEXT)
            (root / "emulator/source.properties").write_text("Pkg.Revision=10\n")
            with self.assertRaises(sdk.PreparationError):
                sdk.verify(root, receipt, context=CONTEXT)

    def test_read_only_validation_does_not_require_receipt_for_existing_callers(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "sdk"; installed_sdk(root)
            result = sdk.verify(root, context={})
            self.assertEqual(result["status"], "validated")
            self.assertIsNone(result["preparationReport"])
            self.assertEqual(set(result["packages"]), set(sdk.PACKAGES))

    def test_missing_command_tools_refuses_before_install(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "sdk"; installed_sdk(root)
            (root / "cmdline-tools/latest/bin/sdkmanager").unlink()
            installer = Installer()
            result = sdk.prepare(root, Path(directory) / "evidence", execute=installer, context=CONTEXT)
            self.assertEqual(result["status"], "failed")
            self.assertEqual(installer.calls, [])
            self.assertEqual(json.loads((Path(directory) / "evidence/result.json").read_text())["status"], "failed")

    def test_missing_execution_permission_retains_failure_without_retry(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "sdk"; installed_sdk(root)
            calls = []

            def denied(command, **kwargs):
                calls.append(command)
                raise PermissionError("fixture permission denied")

            output = Path(directory) / "evidence"
            result = sdk.prepare(root, output, execute=denied, context=CONTEXT)
            self.assertEqual(result["status"], "failed")
            self.assertEqual(len(calls), 1)
            self.assertEqual(result["commands"]["version"]["error"], "PermissionError")
            self.assertIn(b"fixture permission denied", (output / "version.stderr.log").read_bytes())

    def test_image_symlink_outside_selected_sdk_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "sdk"; installed_sdk(root)
            outside = Path(directory) / "outside.img"; outside.write_bytes(b"outside")
            target = root.joinpath(*sdk.SYSTEM_IMAGE.split(";"), "system.img")
            target.unlink()
            try:
                target.symlink_to(outside)
            except OSError as error:
                self.skipTest(f"Host does not permit symlink fixtures: {error}")
            with self.assertRaises(sdk.PreparationError):
                sdk.verify(root, context={})


if __name__ == "__main__":
    unittest.main()
