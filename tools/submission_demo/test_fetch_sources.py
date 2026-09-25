import copy
import unittest

from tools.submission_demo.fetch_sources import validate_downloads, verify_run


class SourceProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.pin = {"run": "123456789", "artifact": "native-original-1", "commit": "a" * 40}
        self.manifest = {"schema_version": 1, "artifacts": [self.pin]}
        self.edl = {
            "purpose": "submission-edit",
            "sources": {"phone": {"path": "sources/123456789/native-original-1/phone.mp4",
                                  "run": "123456789", "commit": "a" * 40, "kind": "native-recording"}},
            "timelines": {"pair": {"path": "sources/123456789/native-original-1/timing.json"}},
        }
        self.receipt = {"databaseId": 123456789, "headSha": "a" * 40, "conclusion": "success"}

    def test_exact_artifact_and_remote_commit_are_accepted(self):
        self.assertEqual(validate_downloads(self.edl, self.manifest), [self.pin])
        verify_run(self.receipt, self.pin)

    def test_path_cannot_escape_or_select_a_different_artifact(self):
        for path in ("../outside.mp4", "/tmp/file.mp4", "C:/private/file.mp4",
                     "sources\\123456789\\native-original-1\\phone.mp4",
                     "sources/123456789/native-original-1/../file.mp4",
                     "sources/987654321/native-original-1/file.mp4"):
            with self.subTest(path=path):
                edl = copy.deepcopy(self.edl)
                edl["sources"]["phone"]["path"] = path
                with self.assertRaises(ValueError):
                    validate_downloads(edl, self.manifest)

    def test_success_from_a_different_build_is_rejected(self):
        for field, value in (("databaseId", 987654321), ("headSha", "b" * 40),
                             ("conclusion", "failure"), ("conclusion", None)):
            with self.subTest(field=field, value=value):
                with self.assertRaises(ValueError):
                    verify_run({**self.receipt, field: value}, self.pin)

    def test_metadata_cannot_launder_another_build_or_synthetic_source(self):
        for field, value in (("run", "987654321"), ("commit", "b" * 40),
                             ("kind", "synthetic-fixture")):
            with self.subTest(field=field):
                edl = copy.deepcopy(self.edl)
                edl["sources"]["phone"][field] = value
                with self.assertRaises(ValueError):
                    validate_downloads(edl, self.manifest)

    def test_wildcards_duplicate_and_unused_artifacts_are_rejected(self):
        for artifacts in ([{**self.pin, "artifact": "native-*"}],
                          [self.pin, self.pin],
                          [self.pin, {**self.pin, "artifact": "unused-2"}]):
            with self.assertRaises(ValueError):
                validate_downloads(self.edl, {"schema_version": 1, "artifacts": artifacts})

    def test_timing_evidence_cannot_come_from_an_unpinned_run(self):
        self.edl["timelines"]["pair"]["path"] = "sources/999999999/native-original-1/timing.json"
        with self.assertRaises(ValueError):
            validate_downloads(self.edl, self.manifest)


if __name__ == "__main__":
    unittest.main()
