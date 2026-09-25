#!/usr/bin/env python3
"""One-run loopback rendezvous for the production two-device acceptance test."""

from __future__ import annotations

import argparse
import json
import re
import threading
import time
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Callable, Sequence
from urllib.parse import parse_qs, urlparse


LOOPBACK_HOST = "127.0.0.1"
DEFAULT_PORT = 18766
DEFAULT_TTL_SECONDS = 600.0
MAX_BODY_BYTES = 8 * 1024
MAX_CHECKPOINTS = 64
_RUN_ID = re.compile(r"^[A-Za-z0-9._-]{1,80}$")
_ROLE = re.compile(r"^(host|guest)$")
_CHECKPOINT = re.compile(r"^[a-z0-9-]{1,48}$")


@dataclass(frozen=True)
class StoredInvite:
    value: str
    expires_at: float


class RendezvousState:
    """Thread-safe, memory-only storage for exactly one configured run."""

    def __init__(
        self,
        run_id: str,
        ttl_seconds: float = DEFAULT_TTL_SECONDS,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        if not _RUN_ID.fullmatch(run_id):
            raise ValueError("run ID must match [A-Za-z0-9._-]{1,80}")
        if not 1.0 <= ttl_seconds <= 3600.0:
            raise ValueError("TTL must be between 1 and 3600 seconds")
        self.run_id = run_id
        self.ttl_seconds = ttl_seconds
        self._clock = clock
        self._lock = threading.Lock()
        self._stored: StoredInvite | None = None
        self._checkpoints: dict[tuple[str, str], str | None] = {}
        self._expired = False

    def put(self, invite: str) -> str:
        """Store once. Retrying the identical PUT is idempotent."""
        with self._lock:
            self._expire_locked()
            if self._expired:
                return "expired"
            if self._stored is not None:
                if self._stored.value == invite:
                    return "unchanged"
                return "conflict"
            self._stored = StoredInvite(
                value=invite,
                expires_at=self._clock() + self.ttl_seconds,
            )
            return "stored"

    def get(self) -> tuple[str, str | None]:
        with self._lock:
            self._expire_locked()
            if self._expired:
                return "expired", None
            if self._stored is None:
                return "missing", None
            return "ready", self._stored.value

    def put_checkpoint(
        self,
        role: str,
        checkpoint: str,
        value: str | None,
    ) -> str:
        """Store one immutable role/checkpoint event after the invite exists."""
        with self._lock:
            self._expire_locked()
            if self._expired:
                return "expired"
            if self._stored is None:
                return "not_ready"
            key = (role, checkpoint)
            if key in self._checkpoints:
                if self._checkpoints[key] == value:
                    return "unchanged"
                return "conflict"
            if len(self._checkpoints) >= MAX_CHECKPOINTS:
                return "full"
            self._checkpoints[key] = value
            return "stored"

    def get_checkpoint(
        self,
        role: str,
        checkpoint: str,
    ) -> tuple[str, str | None]:
        with self._lock:
            self._expire_locked()
            if self._expired:
                return "expired", None
            key = (role, checkpoint)
            if key not in self._checkpoints:
                return "missing", None
            return "ready", self._checkpoints[key]

    def _expire_locked(self) -> bool:
        if self._stored is None or self._clock() < self._stored.expires_at:
            return False
        self._stored = None
        self._checkpoints.clear()
        self._expired = True
        return True


class RendezvousServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(
        self,
        address: tuple[str, int],
        state: RendezvousState,
    ) -> None:
        if address[0] != LOOPBACK_HOST:
            raise ValueError("the coordination server may bind only to loopback")
        self.state = state
        super().__init__(address, RendezvousHandler)


class RendezvousHandler(BaseHTTPRequestHandler):
    server: RendezvousServer
    protocol_version = "HTTP/1.1"

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        parsed = urlparse(self.path)
        if parsed.path == "/invite":
            if self._valid_query(parsed, set()) is None:
                return
            self._get_invite()
            return
        if parsed.path == "/checkpoint":
            query = self._valid_query(parsed, {"role", "checkpoint"})
            if query is None:
                return
            role = query["role"][0]
            checkpoint = query["checkpoint"][0]
            if not _ROLE.fullmatch(role) or not _CHECKPOINT.fullmatch(checkpoint):
                self._json(400, {"error": "invalid checkpoint query"})
                return
            self._get_checkpoint(role, checkpoint)
            return
        self._json(404, {"error": "not found"})

    def _get_invite(self) -> None:
        status, invite = self.server.state.get()
        if status == "missing":
            self._json(404, {"status": "waiting"})
            return
        if status == "expired":
            self._json(410, {"status": "expired"})
            return
        self._json(
            200,
            {"runId": self.server.state.run_id, "invite": invite},
        )

    def _get_checkpoint(self, role: str, checkpoint: str) -> None:
        status, value = self.server.state.get_checkpoint(role, checkpoint)
        if status == "missing":
            self._json(404, {"status": "waiting"})
            return
        if status == "expired":
            self._json(410, {"status": "expired"})
            return
        self._json(
            200,
            {
                "runId": self.server.state.run_id,
                "role": role,
                "checkpoint": checkpoint,
                "value": value,
            },
        )

    def do_PUT(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        self.close_connection = True
        parsed = urlparse(self.path)
        if parsed.path not in {"/invite", "/checkpoint"}:
            self._json(404, {"error": "not found"})
            return
        if self._valid_query(parsed, set()) is None:
            return
        payload = self._read_payload()
        if payload is None:
            return
        if parsed.path == "/invite":
            self._put_invite(payload)
        else:
            self._put_checkpoint(payload)

    def _read_payload(self) -> dict[str, object] | None:
        if self.headers.get("Transfer-Encoding") is not None:
            self._json(400, {"error": "chunked requests are not supported"})
            return None
        length_text = self.headers.get("Content-Length")
        try:
            length = int(length_text) if length_text is not None else -1
        except ValueError:
            length = -1
        if length < 0:
            self._json(411, {"error": "Content-Length is required"})
            return None
        if length > MAX_BODY_BYTES:
            self.close_connection = True
            self._json(413, {"error": "request body is too large"})
            return None
        if self.headers.get_content_type() != "application/json":
            self._discard(length)
            self._json(415, {"error": "Content-Type must be application/json"})
            return None

        raw = self.rfile.read(length)
        try:
            payload = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self._json(400, {"error": "malformed JSON"})
            return None
        if not isinstance(payload, dict):
            self._json(400, {"error": "invalid payload"})
            return None
        return payload

    def _put_invite(self, payload: dict[str, object]) -> None:
        if set(payload) != {
            "runId",
            "invite",
            "publishedAtUtc",
        }:
            self._json(400, {"error": "invalid payload"})
            return
        if payload.get("runId") != self.server.state.run_id:
            self._json(404, {"error": "unknown run"})
            return
        invite = payload.get("invite")
        published_at = payload.get("publishedAtUtc")
        if not isinstance(invite, str) or not _valid_invite(invite):
            self._json(400, {"error": "invalid MeowWatch invite"})
            return
        if not isinstance(published_at, str) or not 10 <= len(published_at) <= 64:
            self._json(400, {"error": "invalid publication timestamp"})
            return

        result = self.server.state.put(invite)
        if result == "expired":
            self._json(410, {"error": "run expired"})
            return
        if result == "conflict":
            self._json(409, {"error": "invite already stored for this run"})
            return
        self._json(200, {"status": result, "runId": self.server.state.run_id})

    def _put_checkpoint(self, payload: dict[str, object]) -> None:
        if set(payload) != {"runId", "role", "checkpoint", "value"}:
            self._json(400, {"error": "invalid payload"})
            return
        if payload.get("runId") != self.server.state.run_id:
            self._json(404, {"error": "unknown run"})
            return
        role = payload.get("role")
        checkpoint = payload.get("checkpoint")
        value = payload.get("value")
        if not isinstance(role, str) or not _ROLE.fullmatch(role):
            self._json(400, {"error": "invalid role"})
            return
        if not isinstance(checkpoint, str) or not _CHECKPOINT.fullmatch(checkpoint):
            self._json(400, {"error": "invalid checkpoint"})
            return
        if value is not None and (
            not isinstance(value, str)
            or len(value) > 256
            or any(ord(char) < 0x20 for char in value)
        ):
            self._json(400, {"error": "invalid checkpoint value"})
            return

        result = self.server.state.put_checkpoint(role, checkpoint, value)
        if result == "expired":
            self._json(410, {"error": "run expired"})
            return
        if result == "not_ready":
            self._json(409, {"error": "invite has not been published"})
            return
        if result == "conflict":
            self._json(409, {"error": "checkpoint already stored"})
            return
        if result == "full":
            self._json(429, {"error": "checkpoint limit reached"})
            return
        self._json(200, {"status": result, "runId": self.server.state.run_id})

    def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        self._json(405, {"error": "method not allowed"})

    def _valid_query(
        self,
        parsed: object,
        extra_keys: set[str],
    ) -> dict[str, list[str]] | None:
        if not hasattr(parsed, "query"):
            self._json(404, {"error": "not found"})
            return None
        query = parse_qs(parsed.query, keep_blank_values=True)
        if set(query) != {"run", *extra_keys}:
            self._json(404, {"error": "not found"})
            return None
        values = query["run"]
        if len(values) != 1 or values[0] != self.server.state.run_id:
            self._json(404, {"error": "unknown run"})
            return None
        if any(len(query[key]) != 1 for key in extra_keys):
            self._json(400, {"error": "invalid query"})
            return None
        return query

    def _discard(self, length: int) -> None:
        if length:
            self.rfile.read(length)

    def _json(self, status: int, payload: dict[str, object]) -> None:
        encoded = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def log_message(self, format: str, *args: object) -> None:
        # Deliberately silent: payloads include a live invitation and test state.
        return


def _valid_invite(value: str) -> bool:
    if not 1 <= len(value) <= 2048 or any(ord(char) < 0x20 for char in value):
        return False
    parsed = urlparse(value)
    if (
        parsed.scheme != "meowwatch"
        or parsed.netloc != "join"
        or parsed.params
        or parsed.fragment
    ):
        return False
    query = parse_qs(parsed.query, keep_blank_values=True)
    if set(query) != {"room", "server", "port"}:
        return False
    if any(len(values) != 1 or not values[0] for values in query.values()):
        return False
    try:
        port = int(query["port"][0])
    except ValueError:
        return False
    return 1 <= port <= 65535 and len(query["room"][0]) <= 35


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--run-id", required=True)
    result.add_argument("--port", type=int, default=DEFAULT_PORT)
    result.add_argument(
        "--ttl-seconds",
        type=float,
        default=DEFAULT_TTL_SECONDS,
    )
    return result


def main(arguments: Sequence[str] | None = None) -> int:
    args = parser().parse_args(arguments)
    state = RendezvousState(args.run_id, ttl_seconds=args.ttl_seconds)
    with RendezvousServer((LOOPBACK_HOST, args.port), state) as server:
        print(
            f"production-together rendezvous listening on "
            f"{LOOPBACK_HOST}:{server.server_port} for one run",
            flush=True,
        )
        try:
            server.serve_forever(poll_interval=0.2)
        except KeyboardInterrupt:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
