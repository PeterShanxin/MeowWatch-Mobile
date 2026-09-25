#!/usr/bin/env python3
"""Loopback-only MP4 fixture server with byte ranges and bounded diagnostics."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import signal
import stat
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import TextIO
from urllib.parse import urlsplit


HOST = "127.0.0.1"
ASSETS = ("sync-fixture.mp4", "Bee.mp4")
MAX_LOG_RECORDS = 4096
_RANGE = re.compile(r"bytes=(\d{0,20})-(\d{0,20})", re.IGNORECASE)


def byte_range(value: str, size: int) -> tuple[int, int]:
    """Return inclusive bounds; reject malformed, multiple or unsatisfied ranges."""
    match = _RANGE.fullmatch(value.strip()) if len(value) <= 80 else None
    if match is None or not any(match.groups()):
        raise ValueError("invalid byte range")
    first, last = match.groups()
    if not first:
        suffix = int(last)
        if suffix <= 0:
            raise ValueError("empty suffix range")
        return max(0, size - suffix), size - 1
    start = int(first)
    end = min(int(last), size - 1) if last else size - 1
    if start >= size or end < start:
        raise ValueError("unsatisfied byte range")
    return start, end


def fixture_path(directory: Path, name: str) -> Path:
    path = directory / name
    # Only fixed names in the owned directory are ever translated to a file.
    if name not in ASSETS or path.is_symlink() or path.resolve().parent != directory:
        raise ValueError("fixture must be a regular file in the owned directory")
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError("fixture is missing or empty")
    return path


class FixtureServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(
        self,
        directory: Path,
        port: int,
        *,
        log: TextIO = sys.stdout,
        max_log_records: int = MAX_LOG_RECORDS,
        max_body_offset: int = 0,
        body_bytes_per_second: int = 0,
    ) -> None:
        self.directory = directory.resolve(strict=True)
        fixture_path(self.directory, ASSETS[0])
        if (self.directory / ASSETS[1]).exists() or (self.directory / ASSETS[1]).is_symlink():
            fixture_path(self.directory, ASSETS[1])
        self.log = log
        self.max_log_records = max_log_records
        self._log_count = 0
        self._log_lock = threading.Lock()
        self.max_body_offset = max_body_offset
        self.body_bytes_per_second = body_bytes_per_second
        self.body_cap_released = threading.Event()
        if (max_body_offset == 0) != (body_bytes_per_second == 0):
            raise ValueError("fixture byte cap and pacing must be enabled together")
        if max_body_offset and not 0 < max_body_offset < fixture_path(self.directory, ASSETS[0]).stat().st_size:
            raise ValueError("fixture byte cap must be within the media body")
        super().__init__((HOST, port), FixtureHandler)

    def record(self, row: dict) -> None:
        # Capture the event before waiting for the log lock: a cap wait that
        # happened before the offline boundary must not appear later in time.
        row = {**row, "at_monotonic": time.monotonic()}
        with self._log_lock:
            if self._log_count < self.max_log_records:
                print(json.dumps(row, separators=(",", ":")), file=self.log, flush=True)
            elif self._log_count == self.max_log_records:
                print(json.dumps({"event": "request_log_limit", "limit": self.max_log_records}),
                      file=self.log, flush=True)
            self._log_count += 1


class FixtureHandler(BaseHTTPRequestHandler):
    server: FixtureServer
    protocol_version = "HTTP/1.0"
    server_version = "MeowWatchFixture/1"
    sys_version = ""

    def handle_one_request(self) -> None:
        started = time.monotonic()
        utc = datetime.now(timezone.utc).isoformat()
        self._status = 0
        self._asset = "unmatched"
        self._range = "none"
        self._written = 0
        self._outcome = "complete"
        try:
            super().handle_one_request()
        except (BrokenPipeError, ConnectionResetError):
            self._outcome = "cancelled"
            self.close_connection = True
        except TimeoutError:
            self._outcome = "timeout"
            self.close_connection = True
        finally:
            if self._status or self._outcome == "timeout":
                self.server.record({
                    "event": "request", "at_utc": utc,
                    "method": self.command if getattr(self, "command", None) in ("GET", "HEAD") else "other",
                    "asset": self._asset, "range": self._range,
                    "status": self._status, "bytes": self._written,
                    "elapsed_ms": round((time.monotonic() - started) * 1000, 3),
                    "client_port": self.client_address[1], "outcome": self._outcome,
                })

    def log_message(self, format: str, *args: object) -> None:
        # BaseHTTP logging includes arbitrary URLs/header values. The bounded
        # record above deliberately retains only allowlisted request fields.
        pass

    def log_error(self, format: str, *args: object) -> None:
        # BaseHTTPRequestHandler catches read/header timeouts internally. Keep
        # their classification without exposing its raw error or request text.
        if any(isinstance(arg, TimeoutError) for arg in args):
            self._outcome = "timeout"

    def send_response(self, code: int, message: str | None = None) -> None:
        self._status = code
        super().send_response(code, message)

    def send_error(self, code: int, message: str | None = None,
                   explain: str | None = None) -> None:
        self._empty(code)

    def _empty(self, status: int, *, size: int | None = None) -> None:
        self.send_response(status)
        self.send_header("Content-Length", "0")
        if size is not None:
            self.send_header("Content-Range", f"bytes */{size}")
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802 - native HTTP handler API
        self._serve(head=False)

    def do_HEAD(self) -> None:  # noqa: N802
        self._serve(head=True)

    def _serve(self, *, head: bool) -> None:
        try:
            parsed = urlsplit(self.path)
        except ValueError:
            self._empty(404)
            return
        if parsed.scheme or parsed.netloc or parsed.fragment or parsed.path not in (
            "/sync-fixture.mp4", "/Bee.mp4"
        ):
            self._empty(404)
            return
        self._asset = parsed.path[1:]
        try:
            path = fixture_path(self.server.directory, self._asset)
            descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_BINARY", 0)
                                 | getattr(os, "O_NOFOLLOW", 0))
        except (OSError, ValueError):
            self._empty(404)
            return
        with os.fdopen(descriptor, "rb") as media:
            metadata = os.fstat(media.fileno())
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_size <= 0:
                self._empty(404)
                return
            size = metadata.st_size
            start, end = 0, size - 1
            status = 200
            values = self.headers.get_all("Range", [])
            modified = self.date_time_string(metadata.st_mtime)
            if_range = self.headers.get("If-Range")
            if values and if_range is not None and (
                if_range != modified or time.time() - metadata.st_mtime < 60
            ):
                # No ETag is advertised. A date can authorize a partial body
                # only when it matches our Last-Modified and is a strong validator.
                self._range = "ignored-if-range"
                values = []
            if (len(values) == 1 and "=" in values[0]
                    and values[0].split("=", 1)[0].strip().lower() != "bytes"):
                self._range = "ignored-unit"
                values = []
            # RFC 9110: Range applies to GET; HEAD returns full-object metadata.
            if values and not head:
                try:
                    if len(values) != 1:
                        raise ValueError("multiple Range fields")
                    start, end = byte_range(values[0], size)
                except ValueError:
                    self._range = "invalid"
                    self._empty(416, size=size)
                    return
                status = 206
                self._range = f"bytes={start}-{end}"
            elif values:
                self._range = "ignored-for-head"
            self.send_response(status)
            self.send_header("Content-Type", "video/mp4")
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Length", str(end - start + 1))
            self.send_header("Last-Modified", modified)
            if status == 206:
                self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
            self.end_headers()
            if head:
                return
            if self.server.max_body_offset:
                self.server.record({"event": "body_response", "asset": self._asset,
                                    "status": status, "range": self._range,
                                    "first": start, "last": end,
                                    "client_port": self.client_address[1]})
            media.seek(start)
            remaining = end - start + 1
            offset = start
            paced_started = time.monotonic()
            paced_bytes = 0
            try:
                while remaining:
                    cap = (0 if self.server.body_cap_released.is_set()
                           else self.server.max_body_offset)
                    if cap and offset >= cap:
                        self.server.record({"event": "body_cap_wait", "asset": self._asset,
                                            "next_offset": offset, "client_port": self.client_address[1]})
                        # Keep the HTTP response open. Truncating it before the
                        # radio outage would turn this into a server EOF test.
                        if not self.server.body_cap_released.wait(120):
                            self._outcome = "body_cap_timeout"
                            break
                        continue
                    length = min(64 * 1024, remaining, cap - offset if cap else remaining)
                    chunk = media.read(length)
                    if not chunk:
                        raise OSError("fixture truncated during response")
                    if cap:
                        # An initial buffer is delivered promptly. Subsequent
                        # prefetch is paced so the cap is reached after the
                        # healthy playback proof, while every byte remains real.
                        paced_bytes += len(chunk)
                        delay = max(0.0, (paced_bytes - 8 * 1024 * 1024)
                                    / self.server.body_bytes_per_second
                                    - (time.monotonic() - paced_started))
                        if delay:
                            time.sleep(delay)
                    self.wfile.write(chunk)
                    self._written += len(chunk)
                    if cap:
                        self.server.record({"event": "body_span", "asset": self._asset,
                                            "first": offset, "last": offset + len(chunk) - 1,
                                            "client_port": self.client_address[1]})
                    offset += len(chunk)
                    remaining -= len(chunk)
            except (BrokenPipeError, ConnectionResetError):
                self._outcome = "cancelled"
            except TimeoutError:
                self._outcome = "timeout"
            except OSError:
                self._outcome = "io_error"
            # bytes is completed socket writes, not an acknowledgement that
            # the remote decoder consumed every byte; cancelled writes may be partial.


def process_identity(pid: int, directory: Path, port: int,
                     *, proc: Path = Path("/proc"), parent_pid: int | None = None) -> str | None:
    """Linux PID birth token, only when the complete server command still matches."""
    try:
        raw = (proc / str(pid) / "cmdline").read_bytes()
        args = [os.fsdecode(item) for item in raw.rstrip(b"\0").split(b"\0")]
        expected = [str(Path(__file__).resolve()), "--directory", str(directory.resolve()),
                    "--port", str(port)]
        if (len(args) != 6 or args[1:] != expected
                or re.fullmatch(r"python(?:3(?:\.\d+)?)?", Path(args[0]).name) is None):
            return None
        fields = (proc / str(pid) / "stat").read_text().rpartition(") ")[2].split()
        if len(fields) < 20 or fields[0] == "Z" or not fields[19].isdigit():
            return None
        if parent_pid is not None and fields[1] != str(parent_pid):
            return None
        return fields[19]
    except (OSError, ValueError):
        return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--owner-pid", type=int)
    parser.add_argument("--start-ticks")
    parser.add_argument("--parent-pid", type=int)
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535:
        parser.error("port must be between 1024 and 65535")
    if args.owner_pid is not None:
        if args.owner_pid <= 1:
            return 3
        token = process_identity(args.owner_pid, args.directory, args.port,
                                 parent_pid=args.parent_pid)
        if token is None or (args.start_ticks is not None and token != args.start_ticks):
            return 3
        if args.start_ticks is None:
            print(token)
        return 0
    if args.start_ticks is not None or args.parent_pid is not None:
        parser.error("start-ticks and parent-pid require owner-pid")
    try:
        max_body_offset = int(os.environ.get("NETWORK_FIXTURE_MAX_BODY_OFFSET", "0"))
        body_bytes_per_second = int(os.environ.get("NETWORK_FIXTURE_BODY_BYTES_PER_SECOND", "0"))
        if max_body_offset < 0 or body_bytes_per_second < 0:
            raise ValueError("fixture pacing values must be nonnegative")
        server = FixtureServer(args.directory, args.port,
                               max_body_offset=max_body_offset,
                               body_bytes_per_second=body_bytes_per_second)
    except (OSError, ValueError):
        print("Fixture server could not bind or validate the prepared media.", file=sys.stderr)
        return 2

    def stop(signum: int, frame: object) -> None:
        raise KeyboardInterrupt

    def release_body_cap(signum: int, frame: object) -> None:
        if not server.max_body_offset or server.body_cap_released.is_set():
            return
        server.body_cap_released.set()
        server.record({"event": "body_cap_released", "at_utc": datetime.now(timezone.utc).isoformat(),
                       "pid": os.getpid(), "max_body_offset": server.max_body_offset,
                       "body_bytes_per_second": server.body_bytes_per_second})

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)
    if server.max_body_offset:
        signal.signal(signal.SIGUSR1, release_body_cap)
    server.record({"event": "ready", "pid": os.getpid(), "port": args.port,
                   "max_body_offset": server.max_body_offset,
                   "body_bytes_per_second": server.body_bytes_per_second})
    try:
        server.serve_forever(poll_interval=0.1)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
