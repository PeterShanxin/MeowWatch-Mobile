#!/usr/bin/env python3
"""Focused unit tests for local showcase persistence and security bounds."""

from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tools.showcase import server


class ShowcaseStateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.state = server.ShowcaseState(self.root, self.root / "missing-adb.exe", "launch-token")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_identical_chunk_replay_is_idempotent(self) -> None:
        started = self.state.start_session({"mimeType": "video/webm"}, "unit-test")
        session = self.state.authenticate_session(started["sessionId"], f"Bearer {started['sessionSecret']}")
        self.assertIsNotNone(session)
        assert session is not None
        content = b"a-realistic-webm-chunk"

        self.assertFalse(self.state.append_chunk(session, 0, content))
        self.assertTrue(self.state.append_chunk(session, 0, content))

        recording = self.state.recordings_root / started["filename"]
        self.assertEqual(recording.read_bytes(), content)
        manifest = json.loads((self.state.recordings_root / f"{started['filename']}.manifest.json").read_text())
        self.assertEqual(manifest["bytes"], len(content))
        self.assertEqual(len(manifest["chunks"]), 1)
        self.assertEqual(len(manifest["chunks"][0]["sha256"]), 64)

    def test_changed_replay_and_out_of_order_chunk_are_rejected(self) -> None:
        started = self.state.start_session({}, "unit-test")
        session = self.state.authenticate_session(started["sessionId"], f"Bearer {started['sessionSecret']}")
        assert session is not None
        self.state.append_chunk(session, 0, b"original")

        with self.assertRaisesRegex(ValueError, "replay content changed"):
            self.state.append_chunk(session, 0, b"modified")
        with self.assertRaisesRegex(ValueError, "expected chunk 1"):
            self.state.append_chunk(session, 2, b"future")

    def test_interruption_marks_unflushed_range_without_claiming_completion(self) -> None:
        started = self.state.start_session({}, "unit-test")
        session = self.state.authenticate_session(started["sessionId"], f"Bearer {started['sessionSecret']}")
        assert session is not None
        content = b"persisted"
        self.state.append_chunk(session, 0, content)
        self.state.interrupt_session(session, "page unload")

        manifest = json.loads((self.state.recordings_root / f"{started['filename']}.manifest.json").read_text())
        self.assertEqual(manifest["state"], "interrupted")
        self.assertTrue(manifest["unflushed"])
        self.assertEqual(manifest["bytes"], len(content))
        self.assertEqual(manifest["gaps"][-1]["reason"], "final MediaRecorder data was not confirmed persisted")
        self.assertTrue(self.state.append_chunk(session, 0, content), "committed replay stays idempotent after interruption")
        with self.assertRaisesRegex(ValueError, "already ended"):
            self.state.append_chunk(session, 1, b"unconfirmed")

    def test_preview_catalog_allows_only_fixed_phone_and_tablet_png_names(self) -> None:
        self.state.preview_root.mkdir(parents=True)
        valid_png = server.PNG_SIGNATURE + b"test-renderer-pixels"
        (self.state.preview_root / "phone-home.png").write_bytes(valid_png)
        (self.state.preview_root / "tablet-home.png").write_bytes(valid_png)
        (self.state.preview_root / "landscape-phone-home.png").write_bytes(valid_png)
        (self.state.preview_root / "phone-player.png").write_bytes(b"not a png")

        catalog = {entry["state"]: entry for entry in self.state.list_previews()}
        self.assertTrue(catalog["home"]["complete"])
        self.assertEqual(catalog["home"]["phone"]["name"], "phone-home.png")
        self.assertNotIn("landscape", catalog["home"])
        self.assertFalse(catalog["player"]["complete"])
        self.assertIsNone(self.state.resolve_preview("landscape-phone-home.png"))
        self.assertIsNone(self.state.resolve_preview("../phone-home.png"))
        self.assertIsNone(self.state.resolve_preview("phone-player.png"))


class SecurityBoundsTests(unittest.TestCase):
    def test_content_length_accepts_only_bounded_nonnegative_integers(self) -> None:
        self.assertEqual(server.validated_content_length(None), 0)
        self.assertEqual(server.validated_content_length(str(server.MAX_REQUEST_BYTES)), server.MAX_REQUEST_BYTES)
        for value in ("-1", "not-a-number", "1.5"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                server.validated_content_length(value)
        with self.assertRaises(OverflowError):
            server.validated_content_length(str(server.MAX_REQUEST_BYTES + 1))

    def test_adb_discovery_prefers_documented_sdk_environment(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            sdk = Path(directory)
            adb = sdk / "platform-tools" / "adb.exe"
            adb.parent.mkdir(parents=True)
            adb.write_bytes(b"")
            with mock.patch.dict(os.environ, {"ANDROID_SDK_ROOT": str(sdk)}, clear=True):
                with mock.patch.object(server.shutil, "which", return_value=None):
                    self.assertEqual(server.discover_adb(), adb)


if __name__ == "__main__":
    unittest.main(verbosity=2)
