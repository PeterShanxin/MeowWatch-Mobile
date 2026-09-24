from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from tools.android_install.runner import RuntimeFailure
from tools.android_network_runtime.fixture_proof import prepare, release_owned_server, validate_spans


class FixtureProofTests(unittest.TestCase):
    def test_release_requires_owned_pid_and_server_ack_before_radio_restore(self):
        proof = {"maxBodyOffset": 900, "bodyBytesPerSecond": 262144}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / "server.env"
            state.write_text("SERVER_PID=123\nSERVER_PORT=18765\nSERVER_START_TICKS=456\n"
                             "MAX_BODY_OFFSET=900\nBODY_BYTES_PER_SECOND=262144\n")
            log = root / "http-server.log"
            log.write_text('{"event":"ready"}\n')
            receipt = {"event": "body_cap_released", "at_utc": "2026-09-25T00:00:00Z",
                       "pid": 123, "max_body_offset": 900,
                       "body_bytes_per_second": 262144}
            def acknowledge(pid, signum):
                self.assertEqual(pid, 123)
                log.write_text(log.read_text() + json.dumps(receipt) + "\n")
            with patch("tools.android_network_runtime.fixture_proof.process_identity",
                       return_value="456") as identity, \
                    patch("tools.android_network_runtime.fixture_proof.signal.SIGUSR1",
                          10, create=True), \
                    patch("tools.android_network_runtime.fixture_proof.os.kill",
                          side_effect=acknowledge) as signal:
                self.assertEqual(release_owned_server(state, log, proof, fixture_dir=root), receipt)
                self.assertTrue(identity.called)
                signal.assert_called_once()
            log.write_text('{"event":"ready"}\n')
            with patch("tools.android_network_runtime.fixture_proof.process_identity",
                       return_value=None), \
                    patch("tools.android_network_runtime.fixture_proof.os.kill") as signal:
                with self.assertRaisesRegex(RuntimeFailure, "birth token"):
                    release_owned_server(state, log, proof, fixture_dir=root)
                signal.assert_not_called()

    def test_real_packet_position_must_follow_cap(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = root / "sync-fixture.mp4"
            fixture.write_bytes(b"x" * 1000)
            packets = {"packets": [
                {"pts_time": "76.0", "pos": "800", "flags": "K_"},
                {"pts_time": "84.0", "pos": "920", "flags": "K_"},
            ]}
            response = subprocess.CompletedProcess([], 0, json.dumps(packets), "")
            with patch("tools.android_network_runtime.fixture_proof.subprocess.run", return_value=response):
                proof = prepare(fixture, root / "proof.json")
            self.assertEqual(proof["maxBodyOffset"], 900)
            self.assertEqual(proof["keyframeOffset"], 920)
            self.assertEqual(json.loads((root / "proof.json").read_text()), proof)
            packets["packets"][-1]["pos"] = "890"
            response.stdout = json.dumps(packets)
            with patch("tools.android_network_runtime.fixture_proof.subprocess.run", return_value=response), \
                    self.assertRaisesRegex(RuntimeFailure, "beyond the byte cap"):
                prepare(fixture, root / "proof.json")

    def test_actual_served_spans_must_stay_below_cap_for_two_requests(self):
        proof = {"maxBodyOffset": 900, "keyframeOffset": 920, "fixtureSize": 1000,
                 "seekMs": 85000, "bodyBytesPerSecond": 262144}
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "http-server.log"
            spans = [{"event": "ready", "max_body_offset": 900,
                      "body_bytes_per_second": 262144},
                     {"event": "body_response", "asset": "sync-fixture.mp4", "status": 200,
                      "first": 0, "last": 999, "client_port": 1},
                     {"event": "body_response", "asset": "sync-fixture.mp4", "status": 206,
                      "first": 400, "last": 999, "client_port": 2},
                     {"event": "body_span", "asset": "sync-fixture.mp4",
                      "first": 0, "last": 700, "client_port": 1},
                     {"event": "body_span", "asset": "sync-fixture.mp4",
                      "first": 400, "last": 899, "client_port": 2}]
            log.write_text("\n".join(map(json.dumps, spans)) + "\n")
            self.assertEqual(validate_spans(log, proof)["highestServedOffset"], 899)
            spans[-1]["last"] = 900
            log.write_text("\n".join(map(json.dumps, spans)) + "\n")
            with self.assertRaisesRegex(RuntimeFailure, "uncapped"):
                validate_spans(log, proof)
            spans[-1]["last"] = 899
            spans.append({"event": "body_cap_wait", "next_offset": 900})
            log.write_text("\n".join(map(json.dumps, spans)) + "\n")
            with self.assertRaisesRegex(RuntimeFailure, "artificial byte cap"):
                validate_spans(log, proof)
