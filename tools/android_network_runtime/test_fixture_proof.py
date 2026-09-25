from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from tools.android_install.runner import RuntimeFailure
from tools.android_network_runtime.fixture_proof import (
    PACE_BYTES_PER_SECOND, prepare, release_owned_server, validate_spans,
)


class FixtureProofTests(unittest.TestCase):
    def test_release_requires_owned_pid_and_server_ack_before_radio_restore(self):
        proof = {"maxBodyOffset": 900, "bodyBytesPerSecond": PACE_BYTES_PER_SECOND}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / "server.env"
            state.write_text("SERVER_PID=123\nSERVER_PORT=18765\nSERVER_START_TICKS=456\n"
                             f"MAX_BODY_OFFSET=900\nBODY_BYTES_PER_SECOND={PACE_BYTES_PER_SECOND}\n")
            log = root / "http-server.log"
            log.write_text('{"event":"ready"}\n')
            receipt = {"event": "body_cap_released", "at_utc": "2026-09-25T00:00:00Z",
                       "pid": 123, "max_body_offset": 900,
                       "body_bytes_per_second": PACE_BYTES_PER_SECOND}
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
            log.write_text('{"event":"ready"}\n' + json.dumps(receipt) + "\n")
            with patch("tools.android_network_runtime.fixture_proof.process_identity",
                       return_value="456"), \
                    patch("tools.android_network_runtime.fixture_proof.os.kill") as signal, \
                    self.assertRaisesRegex(RuntimeFailure, "released before offline proof"):
                release_owned_server(state, log, proof, fixture_dir=root)
            signal.assert_not_called()
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
                 "seekMs": 85000, "bodyBytesPerSecond": PACE_BYTES_PER_SECOND}
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "http-server.log"
            spans = [{"event": "ready", "max_body_offset": 900,
                      "body_bytes_per_second": PACE_BYTES_PER_SECOND},
                     {"event": "body_response", "asset": "sync-fixture.mp4", "status": 200,
                      "first": 0, "last": 999, "client_port": 1, "at_monotonic": 1.0},
                     {"event": "body_response", "asset": "sync-fixture.mp4", "status": 206,
                      "first": 400, "last": 999, "client_port": 2, "at_monotonic": 2.0},
                     {"event": "body_span", "asset": "sync-fixture.mp4",
                      "first": 0, "last": 700, "client_port": 1, "at_monotonic": 3.0},
                     {"event": "body_span", "asset": "sync-fixture.mp4",
                      "first": 400, "last": 899, "client_port": 2, "at_monotonic": 4.0}]
            log.write_text("\n".join(map(json.dumps, spans)) + "\n")
            self.assertEqual(validate_spans(log, proof, 5.0)["highestServedOffset"], 899)
            spans[-1]["last"] = 900
            log.write_text("\n".join(map(json.dumps, spans)) + "\n")
            with self.assertRaisesRegex(RuntimeFailure, "uncapped"):
                validate_spans(log, proof, 5.0)
            spans[-1]["last"] = 899
            spans.append({"event": "body_cap_wait", "asset": "sync-fixture.mp4",
                          "next_offset": 900, "client_port": 2, "at_monotonic": 5.0})
            log.write_text("\n".join(map(json.dumps, spans)) + "\n")
            with self.assertRaisesRegex(RuntimeFailure, "artificial byte cap"):
                validate_spans(log, proof, 5.0)
            spans[-1]["at_monotonic"] = 5.1
            log.write_text("\n".join(map(json.dumps, spans)) + "\n")
            self.assertEqual(validate_spans(log, proof, 5.0)["postProofCapWaitCount"], 1)
            log.write_text("\n".join(map(json.dumps, spans[:-1])) + "\n")
            self.assertEqual(validate_spans(log, proof, 5.0)["postProofCapWaitCount"], 0)
            # A receipt flushed after the first check still keeps its earlier
            # event time, so the final check rejects the premature wait.
            spans[-1]["at_monotonic"] = 4.5
            with log.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(spans[-1]) + "\n")
            with self.assertRaisesRegex(RuntimeFailure, "before offline proof"):
                validate_spans(log, proof, 5.0)
            spans[-1]["at_monotonic"] = 5.1
            log.write_text("\n".join(map(json.dumps, spans)) + "\n")
            for bad in (None, float("nan"), float("inf"), 0, True):
                with self.subTest(boundary=bad), self.assertRaisesRegex(RuntimeFailure, "boundary"):
                    validate_spans(log, proof, bad)
            with patch("tools.android_network_runtime.fixture_proof.time.monotonic",
                       return_value=20.0), \
                    self.assertRaisesRegex(RuntimeFailure, "boundary"):
                validate_spans(log, proof, 21.0)
            for bad in (None, float("nan"), float("inf"), 3.5):
                changed = [row.copy() for row in spans]
                changed[-1]["at_monotonic"] = bad
                log.write_text("\n".join(map(json.dumps, changed)) + "\n")
                with self.subTest(clock=bad), self.assertRaisesRegex(RuntimeFailure, "timestamp"):
                    validate_spans(log, proof, 5.0)
            changed = [row.copy() for row in spans]
            changed[-1]["at_monotonic"] = 21.0
            log.write_text("\n".join(map(json.dumps, changed)) + "\n")
            with patch("tools.android_network_runtime.fixture_proof.time.monotonic",
                       return_value=20.0), \
                    self.assertRaisesRegex(RuntimeFailure, "timestamp"):
                validate_spans(log, proof, 5.0)
            for index in (1, 3):
                changed = [row.copy() for row in spans]
                changed[index].pop("at_monotonic")
                log.write_text("\n".join(map(json.dumps, changed)) + "\n")
                with self.subTest(event=changed[index]["event"]), \
                        self.assertRaisesRegex(RuntimeFailure, "timestamp"):
                    validate_spans(log, proof, 5.0)

    def test_interleaved_request_threads_need_only_per_port_clock_order(self):
        proof = {"maxBodyOffset": 900, "keyframeOffset": 920, "fixtureSize": 1000,
                 "seekMs": 85000, "bodyBytesPerSecond": PACE_BYTES_PER_SECOND}
        rows = [
            {"event": "ready", "max_body_offset": 900,
             "body_bytes_per_second": PACE_BYTES_PER_SECOND},
            {"event": "body_response", "asset": "sync-fixture.mp4", "status": 200,
             "first": 0, "last": 999, "client_port": 1, "at_monotonic": 10.0},
            {"event": "body_response", "asset": "sync-fixture.mp4", "status": 206,
             "first": 400, "last": 999, "client_port": 2, "at_monotonic": 11.0},
            {"event": "body_span", "asset": "sync-fixture.mp4", "first": 400,
             "last": 800, "client_port": 2, "at_monotonic": 12.0},
            {"event": "body_span", "asset": "sync-fixture.mp4", "first": 0,
             "last": 700, "client_port": 1, "at_monotonic": 10.5},
        ]
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "http-server.log"
            log.write_text("\n".join(map(json.dumps, rows)) + "\n")
            self.assertEqual(validate_spans(log, proof, 13.0)["requestPorts"], 2)
