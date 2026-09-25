import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import prepare


ORIGINAL = b"alpha\nkeep a\n\nbeta\nkeep b\n"
EXPECTED = b"alpha\nnew a\nkeep a\n\nbeta\nnew b\nkeep b\n"
PATCH = b"""--- a/object.dart
+++ b/object.dart
@@ -1,2 +1,3 @@
 alpha
+new a
 keep a
@@ -4,2 +5,3 @@
 beta
+new b
 keep b
"""


class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.runner = self.root / "runner"
        self.runner.mkdir()
        self.source = self.root / "source-sdk"
        (self.source / prepare.OBJECT).parent.mkdir(parents=True)
        (self.source / prepare.OBJECT).write_bytes(ORIGINAL)
        (self.source / prepare.VERSION).parent.mkdir(parents=True)
        (self.source / prepare.VERSION).write_text(json.dumps({
            "frameworkVersion": "3.44.0",
            "frameworkRevision": prepare.FRAMEWORK_REVISION,
        }), encoding="utf-8")
        self.patch_dir = self.root / "patch"
        self.patch_dir.mkdir()
        (self.patch_dir / "object.dart.upstream.patch").write_bytes(PATCH)
        self.output = self.runner / "candidate"
        self.env = {
            "GITHUB_ACTIONS": "true",
            "RUNNER_ENVIRONMENT": "github-hosted",
            "RUNNER_TEMP": str(self.runner),
        }
        hashes = {}
        for ending in (b"\n", b"\r\n"):
            before = ORIGINAL.replace(b"\n", ending)
            after = EXPECTED.replace(b"\n", ending)
            hashes[prepare.sha256(before)] = prepare.sha256(after)
        for mocked in (
            patch.object(prepare, "HERE", self.patch_dir),
            patch.object(prepare, "PATCH_SHA256", prepare.sha256(PATCH)),
            patch.object(prepare, "SOURCE_HASHES", hashes),
        ):
            mocked.start()
            self.addCleanup(mocked.stop)

    def run_prepare(self, *, check=False, env=None):
        report = {}
        prepare.prepare(self.source, self.output, check=check, report=report,
                        env=self.env if env is None else env)
        return report

    def test_exact_transform_preserves_lf_and_crlf(self):
        for ending in (b"\n", b"\r\n"):
            with self.subTest(ending=ending):
                self.assertEqual(prepare.apply_fixed_patch(ORIGINAL.replace(b"\n", ending)),
                                 EXPECTED.replace(b"\n", ending))

    def test_modified_or_already_patched_source_is_rejected(self):
        for data in (ORIGINAL + b"changed\n", EXPECTED):
            with self.subTest(data=data), self.assertRaisesRegex(prepare.Refused, "unmodified"):
                prepare.apply_fixed_patch(data)

    def test_altered_patch_is_rejected(self):
        (self.patch_dir / "object.dart.upstream.patch").write_bytes(PATCH + b"changed\n")
        with self.assertRaisesRegex(prepare.Refused, "patch hash"):
            prepare.apply_fixed_patch(ORIGINAL)

    def test_unexpected_output_hash_is_rejected(self):
        with patch.object(prepare, "SOURCE_HASHES", {prepare.sha256(ORIGINAL): "bad"}):
            with self.assertRaisesRegex(prepare.Refused, "output hash"):
                prepare.apply_fixed_patch(ORIGINAL)

    def test_check_mode_does_not_copy_or_mutate_without_ci(self):
        with patch.object(prepare.shutil, "copytree") as copy:
            report = self.run_prepare(check=True, env={})
        copy.assert_not_called()
        self.assertFalse(self.output.exists())
        self.assertEqual((self.source / prepare.OBJECT).read_bytes(), ORIGINAL)
        self.assertEqual(report["status"], "checked-only-no-sdk-written")

    def test_ci_copy_is_independent_and_source_is_unchanged(self):
        report = self.run_prepare()
        self.assertEqual((self.output / prepare.OBJECT).read_bytes(), EXPECTED)
        self.assertEqual((self.source / prepare.OBJECT).read_bytes(), ORIGINAL)
        self.assertFalse(os.path.samefile(self.source / prepare.OBJECT, self.output / prepare.OBJECT))
        self.assertEqual(report["sourceObjectSha256Before"], report["sourceObjectSha256After"])
        self.assertEqual(report["status"], "candidate-prepared-not-native-validated")

    def test_local_or_self_hosted_mutation_is_rejected(self):
        for env in ({}, {**self.env, "RUNNER_ENVIRONMENT": "self-hosted"}):
            with self.subTest(env=env), self.assertRaisesRegex(prepare.Refused, "GitHub-hosted"):
                self.run_prepare(env=env)
        self.assertFalse(self.output.exists())

    def test_missing_runner_temp_is_rejected(self):
        with self.assertRaisesRegex(prepare.Refused, "RUNNER_TEMP"):
            self.run_prepare(env={k: v for k, v in self.env.items() if k != "RUNNER_TEMP"})

    def test_temp_root_and_outside_output_are_rejected(self):
        for destination in (self.runner, self.root / "elsewhere"):
            with self.subTest(destination=destination), self.assertRaisesRegex(prepare.Refused, "strictly inside"):
                prepare.validate_destination(self.source, destination, self.env)

    def test_existing_output_is_not_overwritten(self):
        self.output.mkdir()
        marker = self.output / "keep"
        marker.write_text("retained", encoding="utf-8")
        with self.assertRaisesRegex(prepare.Refused, "already exists"):
            self.run_prepare()
        self.assertEqual(marker.read_text(encoding="utf-8"), "retained")

    def test_source_containing_output_is_rejected(self):
        with self.assertRaisesRegex(prepare.Refused, "overlap"):
            prepare.validate_destination(self.runner, self.output, self.env)

    def test_relative_source_is_rejected(self):
        with self.assertRaisesRegex(prepare.Refused, "absolute"):
            prepare.prepare(Path("source"), self.output, check=True, report={}, env={})

    def test_wrong_sdk_revision_rejected_before_copy(self):
        (self.source / prepare.VERSION).write_text('{"frameworkVersion":"3.44.0","frameworkRevision":"wrong"}')
        with self.assertRaisesRegex(prepare.Refused, "revision"):
            self.run_prepare()
        self.assertFalse(self.output.exists())

    def test_copy_failure_preserves_source_and_records_after_hash(self):
        report = {}
        with patch.object(prepare.shutil, "copytree", side_effect=OSError("disk full")):
            with self.assertRaisesRegex(OSError, "disk full"):
                prepare.prepare(self.source, self.output, check=False, report=report, env=self.env)
        self.assertEqual(report["sourceObjectSha256Before"], report["sourceObjectSha256After"])

    def test_hard_link_copy_is_rejected_without_writing_shared_file(self):
        def hard_link_copy(source, output, **kwargs):
            (output / prepare.OBJECT).parent.mkdir(parents=True)
            os.link(source / prepare.OBJECT, output / prepare.OBJECT)
        with patch.object(prepare.shutil, "copytree", side_effect=hard_link_copy):
            with self.assertRaisesRegex(prepare.Refused, "independent"):
                self.run_prepare()
        self.assertEqual((self.source / prepare.OBJECT).read_bytes(), ORIGINAL)

    def test_main_failure_still_writes_refusal_provenance(self):
        report = self.root / "artifacts" / "preparation.json"
        with patch.dict(os.environ, {}, clear=True):
            code = prepare.main(["--source-sdk", str(self.source), "--output-sdk",
                                 str(self.output), "--report", str(report)])
        self.assertEqual(code, 1)
        result = json.loads(report.read_text(encoding="utf-8"))
        self.assertEqual(result["status"], "refused-or-failed")
        self.assertFalse(result["nativeGeometryFixProven"])
        self.assertFalse(self.output.exists())

    def test_report_cannot_overwrite_a_source_sdk_file(self):
        with self.assertRaises(SystemExit) as error:
            prepare.main(["--check", "--source-sdk", str(self.source),
                          "--report", str(self.source / prepare.OBJECT)])
        self.assertEqual(error.exception.code, 2)
        self.assertEqual((self.source / prepare.OBJECT).read_bytes(), ORIGINAL)

    def test_changed_source_during_copy_is_detected(self):
        real_copy = prepare.shutil.copytree
        def changing_copy(source, output, *args, **kwargs):
            real_copy(source, output, *args, **kwargs)
            if Path(source) == self.source:
                (self.source / prepare.OBJECT).write_bytes(b"concurrent change")
        with patch.object(prepare.shutil, "copytree", side_effect=changing_copy):
            with self.assertRaisesRegex(prepare.Refused, "Cached source SDK changed"):
                self.run_prepare()


if __name__ == "__main__":
    unittest.main()
