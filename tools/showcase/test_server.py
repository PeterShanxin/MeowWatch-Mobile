#!/usr/bin/env python3
"""Focused unit tests for local showcase persistence and security bounds."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
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

    def test_evidence_only_mode_never_starts_adb(self) -> None:
        self.state.device_polling = False
        with mock.patch.object(server.subprocess, "run") as process:
            devices, note = self.state.list_devices()
        self.assertEqual(devices, [])
        self.assertIn("paused to reduce local load", note)
        process.assert_not_called()

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


class FrontendEvidenceTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("node"), "JavaScript contract requires Node")
    def test_captured_media_stays_local_literal_and_explicitly_selected(self) -> None:
        script = r'''
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
class Element {
  constructor(tag) {
    this.tagName = tag; this.children = []; this.events = {};
    this.options = []; this.paused = true; this.currentTime = 0;
    this.duration = 30; this.readyState = 2; this.videoWidth = 1280; this.videoHeight = 720;
  }
  set innerHTML(_) { throw new Error("Untrusted metadata must not enter HTML"); }
  append(...children) { this.children.push(...children); }
  replaceChildren(...children) { this.children = children; }
  setAttribute(name, value) { this[name] = value; }
  removeAttribute(name) { delete this[name]; }
  addEventListener(name, callback) { this.events[name] = callback; }
  pause() { this.paused = true; }
  play() { this.paused = false; return Promise.resolve(); }
  load() {}
}
const drawn = [];
const context = new Proxy({
  measureText: (text) => ({width: String(text).length * 8}),
  drawImage: (...args) => drawn.push(args[0]),
}, {get: (target, key) => key in target ? target[key] : () => {}});
const elements = new Map();
const createdTags = [];
const document = {
  getElementById: (id) => {
    if (!elements.has(id)) elements.set(id, new Element(id));
    return elements.get(id);
  },
  createElement: (tag) => { createdTags.push(tag); return new Element(tag); },
  createTextNode: (text) => ({textContent: text}),
};
const canvas = document.getElementById("stage");
canvas.getContext = () => context; canvas.width = 1280; canvas.height = 720;
const items = [
  {name: 'failed-run/<img onerror=bad>.png', kind: 'image', size: 42, modifiedAt: '2026-09-16T06:00:00.000Z'},
  {name: 'passed-run/two devices #1.mp4', kind: 'video', size: 99, modifiedAt: '2026-09-16T07:00:00.000Z'},
];
const sandbox = vm.createContext({
  URL, URLSearchParams, console, document,
  location: {search:'?token=local-test', href:'http://127.0.0.1:8765/?token=local-test', origin:'http://127.0.0.1:8765'},
  fetch: async () => ({ok: true, json: async () => ({items}), blob: async () => ({})}),
  createImageBitmap: async () => ({width: 10, height: 10, close() {}}),
});
// Evaluate definitions without starting polling, recording, or browser I/O.
const source = fs.readFileSync('tools/showcase/app.js', 'utf8');
vm.runInContext(source.split('document.getElementById("refreshEvidence").addEventListener')[0], sandbox);
(async () => {
  await vm.runInContext('loadEvidence()', sandbox);
  assert.equal(vm.runInContext('selectedEvidence', sandbox), null, 'gallery never auto-selects a passing or failed run');
  const gallery = elements.get('evidence').children;
  assert.equal(createdTags.filter((tag) => tag === 'img' || tag === 'video').length, 0,
    'the index must not allocate image or video decoders before selection');
  await vm.runInContext('loadEvidence()', sandbox);
  assert.equal(elements.get('evidence').children, gallery, 'an unchanged index keeps its existing cards');
  assert.equal(gallery[0].children[1].textContent.includes(items[0].name), true);
  assert.equal(gallery[0].children[2].textContent, 'Show on canvas');
  sandbox.imageItem = items[0];
  const imageUrl = new URL(vm.runInContext('evidenceMetadata(imageItem).url', sandbox));
  assert.equal(imageUrl.origin, 'http://127.0.0.1:8765');
  assert.equal(decodeURIComponent(imageUrl.pathname), '/evidence/' + items[0].name);
  for (const name of ['../private.png', '/absolute.png', 'a/../private.png', 'a\\private.png', 'https://elsewhere/image.png']) {
    sandbox.badItem = {...items[0], name};
    assert.throws(() => vm.runInContext('evidenceMetadata(badItem)', sandbox));
  }
  await gallery[1].children[2].events.click();
  const video = elements.get('capturedVideo');
  assert.equal(video.muted, true);
  assert.equal(video.paused, false);
  vm.runInContext('drawStage(); updateCapturedPlayback()', sandbox);
  assert.equal(drawn.at(-1), video, 'canvas receives actual HTML video frames');
  assert.match(elements.get('capturedLabel').textContent, /Captured native Android recording.*not live/);
  assert.equal(elements.get('capturedMetadata').textContent.includes(items[1].name), true);
  assert.equal(elements.get('capturedMetadata').textContent.includes(items[1].modifiedAt), true);
  assert.equal(elements.get('fullEvidence').textContent, 'Open full recording evidence');
  vm.runInContext('returnToLive()', sandbox);
  assert.equal(video.paused, true);
  assert.equal(video.src, undefined);
  assert.equal(vm.runInContext('selectedEvidence', sandbox), null);
  assert.equal(elements.get('capturedControls').hidden, true);

  // A hung local upload must not retain an unbounded stream of recording blobs.
  const requests = [];
  let finishUpload;
  const limits = [];
  sandbox.AbortSignal = {timeout: (ms) => {limits.push(ms); return AbortSignal.timeout(ms);}};
  sandbox.fakeRecorder = {state: 'recording', stops: 0, stop() {this.state = 'inactive'; this.stops++;}};
  sandbox.fetch = async (url, options) => {
    requests.push({url, options});
    if (url.includes('/chunk')) return new Promise((resolve) => {finishUpload = resolve;});
    return {ok: true};
  };
  vm.runInContext(`recordingSession = {sessionId:'owned', sessionSecret:'test'};
    recording = fakeRecorder; recordingHealthy = true;
    for (let i = 0; i < 4; i++) enqueueChunk({size: 4 * 1024 * 1024, type:'video/webm'});`, sandbox);
  await Promise.resolve();
  vm.runInContext('enqueueChunk({size: 1, type:"video/webm"})', sandbox);
  assert.equal(sandbox.fakeRecorder.stops, 1, 'queue overflow must stop the encoder');
  assert.equal(requests.filter((r) => r.url.includes('/interrupt')).length, 1);
  assert.equal(vm.runInContext('queuedChunkBytes', sandbox), 16 * 1024 * 1024);
  finishUpload({ok: true});
  await vm.runInContext('uploadChain', sandbox);
  assert.equal(requests.filter((r) => r.url.includes('/chunk')).length, 1,
    'after interruption, queued blobs are released instead of starting more requests');
  assert.equal(vm.runInContext('queuedChunks + queuedChunkBytes', sandbox), 0);
  assert.deepEqual(limits, [15000]);

  // Count is bounded even for tiny blobs, independently of the byte ceiling.
  requests.length = 0;
  sandbox.fakeRecorder.state = 'recording'; sandbox.fakeRecorder.stops = 0;
  vm.runInContext(`recordingHealthy = true;
    for (let i = 0; i < 5; i++) enqueueChunk({size: 1, type:'video/webm'});`, sandbox);
  await vm.runInContext('uploadChain', sandbox);
  assert.equal(sandbox.fakeRecorder.stops, 1);
  assert.equal(requests.filter((r) => r.url.includes('/chunk')).length, 0);
  assert.equal(vm.runInContext('queuedChunks + queuedChunkBytes', sandbox), 0);

  // Exercise exhausted timed-out attempts without waiting or browser/network I/O.
  requests.length = 0; limits.length = 0;
  sandbox.fakeRecorder.state = 'recording'; sandbox.fakeRecorder.stops = 0;
  sandbox.setTimeout = (callback) => {callback();};
  sandbox.AbortSignal = {timeout: (ms) => {limits.push(ms); return AbortSignal.abort(new Error('timeout'));}};
  sandbox.fetch = async (url, options) => {
    requests.push({url, options});
    if (url.includes('/chunk')) {options.signal.throwIfAborted();}
    return {ok: true};
  };
  vm.runInContext(`recordingHealthy = true; enqueueChunk({size: 1024, type:'video/webm'});`, sandbox);
  await vm.runInContext('uploadChain', sandbox);
  assert.equal(sandbox.fakeRecorder.stops, 1);
  assert.equal(requests.filter((r) => r.url.includes('/chunk')).length, 3);
  assert.deepEqual(limits, [15000, 15000, 15000]);
  assert.equal(vm.runInContext('queuedChunks + queuedChunkBytes', sandbox), 0);
  assert.match(elements.get('recordingBadge').textContent, /Recording interrupted/);
})().catch((error) => { console.error(error); process.exitCode = 1; });
'''
        result = subprocess.run(
            [shutil.which("node"), "-e", script],
            capture_output=True, text=True, timeout=15, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
