import http.client
import json
from pathlib import Path
import sys
import threading
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tools.production_together.coordination_server import (
    LOOPBACK_HOST,
    MAX_BODY_BYTES,
    MAX_CHECKPOINTS,
    RendezvousServer,
    RendezvousState,
)


RUN_ID = "ci-acceptance-123"
INVITE = (
    "meowwatch://join?room=quiet-otter&server=syncplay.pl&port=8995"
)


class FakeClock:
    def __init__(self) -> None:
        self.now = 100.0

    def __call__(self) -> float:
        return self.now


class CoordinationServerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.clock = FakeClock()
        self.state = RendezvousState(RUN_ID, ttl_seconds=10, clock=self.clock)
        self.server = RendezvousServer((LOOPBACK_HOST, 0), self.state)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def request(
        self,
        method: str,
        path: str,
        body: bytes | None = None,
        headers: dict[str, str] | None = None,
    ) -> tuple[int, dict[str, object]]:
        connection = http.client.HTTPConnection(
            LOOPBACK_HOST,
            self.server.server_port,
            timeout=2,
        )
        connection.request(method, path, body=body, headers=headers or {})
        response = connection.getresponse()
        payload = json.loads(response.read().decode("utf-8"))
        status = response.status
        connection.close()
        return status, payload

    def put(self, invite: str = INVITE, run_id: str = RUN_ID) -> int:
        encoded = json.dumps(
            {
                "runId": run_id,
                "invite": invite,
                "publishedAtUtc": "2026-09-16T00:00:00Z",
            }
        ).encode()
        status, _ = self.request(
            "PUT",
            f"/invite?run={run_id}",
            encoded,
            {"Content-Type": "application/json"},
        )
        return status

    def put_checkpoint(
        self,
        role: str,
        checkpoint: str,
        value: str | None = None,
        run_id: str = RUN_ID,
    ) -> int:
        encoded = json.dumps(
            {
                "runId": run_id,
                "role": role,
                "checkpoint": checkpoint,
                "value": value,
            }
        ).encode()
        status, _ = self.request(
            "PUT",
            f"/checkpoint?run={run_id}",
            encoded,
            {"Content-Type": "application/json"},
        )
        return status

    def test_stores_and_returns_one_invite_without_files(self) -> None:
        waiting, _ = self.request("GET", f"/invite?run={RUN_ID}")
        self.assertEqual(waiting, 404)

        self.assertEqual(self.put(), 200)
        status, payload = self.request("GET", f"/invite?run={RUN_ID}")

        self.assertEqual(status, 200)
        self.assertEqual(payload, {"runId": RUN_ID, "invite": INVITE})
        self.assertEqual(self.put(), 200, "identical retry must be idempotent")

    def test_rejects_cross_run_routes_and_payloads(self) -> None:
        status, _ = self.request("GET", "/invite?run=another-run")
        self.assertEqual(status, 404)

        encoded = json.dumps(
            {
                "runId": "another-run",
                "invite": INVITE,
                "publishedAtUtc": "2026-09-16T00:00:00Z",
            }
        ).encode()
        status, _ = self.request(
            "PUT",
            f"/invite?run={RUN_ID}",
            encoded,
            {"Content-Type": "application/json"},
        )
        self.assertEqual(status, 404)

    def test_rejects_oversize_malformed_and_invalid_invites(self) -> None:
        try:
            status, _ = self.request(
                "PUT",
                f"/invite?run={RUN_ID}",
                b"{}",
                {
                    "Content-Type": "application/json",
                    "Content-Length": str(MAX_BODY_BYTES + 1),
                },
            )
        except (
            ConnectionAbortedError,
            ConnectionResetError,
            http.client.RemoteDisconnected,
        ):
            # Windows may replace the 413 with a TCP reset when the server
            # intentionally closes without consuming an oversized body.
            status = None
        self.assertIn(status, (None, 413))
        waiting, _ = self.request("GET", f"/invite?run={RUN_ID}")
        self.assertEqual(waiting, 404, "an oversized request must not mutate state")

        status, _ = self.request(
            "PUT",
            f"/invite?run={RUN_ID}",
            b"not-json",
            {"Content-Type": "application/json"},
        )
        self.assertEqual(status, 400)
        self.assertEqual(self.put("https://example.com/not-an-invite"), 400)

    def test_prevents_invite_replacement(self) -> None:
        self.assertEqual(self.put(), 200)
        other = (
            "meowwatch://join?room=other-room&server=syncplay.pl&port=8995"
        )
        self.assertEqual(self.put(other), 409)

    def test_invite_expires_for_the_single_run(self) -> None:
        self.assertEqual(self.put(), 200)
        self.clock.now += 11

        status, payload = self.request("GET", f"/invite?run={RUN_ID}")

        self.assertEqual(status, 410)
        self.assertEqual(payload, {"status": "expired"})
        self.assertEqual(self.put(), 410, "an expired run cannot be reused")

    def test_checkpoint_round_trip_is_bounded_and_idempotent(self) -> None:
        self.assertEqual(
            self.put_checkpoint("host", "room-ready"),
            409,
            "checkpoints cannot precede the production invite",
        )
        self.assertEqual(self.put(), 200)
        self.assertEqual(
            self.put_checkpoint("host", "host-paused", "1234"),
            200,
        )
        self.assertEqual(
            self.put_checkpoint("host", "host-paused", "1234"),
            200,
            "identical retry must be idempotent",
        )

        status, payload = self.request(
            "GET",
            f"/checkpoint?run={RUN_ID}&role=host&checkpoint=host-paused",
        )

        self.assertEqual(status, 200)
        self.assertEqual(
            payload,
            {
                "runId": RUN_ID,
                "role": "host",
                "checkpoint": "host-paused",
                "value": "1234",
            },
        )

    def test_checkpoint_rejects_cross_run_invalid_and_replacement(self) -> None:
        self.assertEqual(self.put(), 200)
        status, _ = self.request(
            "GET",
            "/checkpoint?run=another-run&role=host&checkpoint=room-ready",
        )
        self.assertEqual(status, 404)
        self.assertEqual(
            self.put_checkpoint("host", "room-ready", run_id="another-run"),
            404,
        )
        self.assertEqual(self.put_checkpoint("observer", "room-ready"), 400)
        self.assertEqual(self.put_checkpoint("host", "ROOM READY"), 400)
        self.assertEqual(self.put_checkpoint("host", "host-paused", "1"), 200)
        self.assertEqual(self.put_checkpoint("host", "host-paused", "2"), 409)

    def test_checkpoint_limit_is_per_run(self) -> None:
        self.assertEqual(self.put(), 200)
        for index in range(MAX_CHECKPOINTS):
            self.assertEqual(
                self.put_checkpoint("host", f"step-{index}"),
                200,
            )
        self.assertEqual(self.put_checkpoint("guest", "one-too-many"), 429)

    def test_checkpoints_expire_with_invite(self) -> None:
        self.assertEqual(self.put(), 200)
        self.assertEqual(self.put_checkpoint("guest", "video-ready"), 200)
        self.clock.now += 11

        status, payload = self.request(
            "GET",
            f"/checkpoint?run={RUN_ID}&role=guest&checkpoint=video-ready",
        )

        self.assertEqual(status, 410)
        self.assertEqual(payload, {"status": "expired"})
        self.assertEqual(self.put_checkpoint("guest", "video-ready"), 410)

    def test_server_refuses_non_loopback_binding(self) -> None:
        with self.assertRaisesRegex(ValueError, "only to loopback"):
            RendezvousServer(("0.0.0.0", 0), self.state)


if __name__ == "__main__":
    unittest.main(verbosity=2)
