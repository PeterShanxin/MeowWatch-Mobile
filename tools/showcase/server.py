#!/usr/bin/env python3
"""Local-only MeowWatch Android frame viewer and browser-canvas recorder."""

from __future__ import annotations

import argparse
import hashlib
import json
import mimetypes
import os
import secrets
import shutil
import subprocess
import threading
import time
import urllib.parse
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


GAP_AFTER_SECONDS = 15
MAX_REQUEST_BYTES = 16 * 1024 * 1024
PREVIEW_STATES = ("home", "onboarding", "player")
PREVIEW_VARIANTS = ("phone", "tablet")
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def discover_adb() -> Path:
    """Find adb from documented Android SDK locations, then PATH."""
    candidates: list[Path] = []
    for variable in ("ANDROID_SDK_ROOT", "ANDROID_HOME"):
        value = os.environ.get(variable)
        if value:
            candidates.append(Path(value) / "platform-tools" / "adb.exe")
    local_app_data = os.environ.get("LOCALAPPDATA")
    if local_app_data:
        candidates.append(Path(local_app_data) / "Android" / "Sdk" / "platform-tools" / "adb.exe")
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    on_path = shutil.which("adb")
    if on_path:
        return Path(on_path)
    return candidates[0] if candidates else Path("adb")


def validated_content_length(raw_value: str | None) -> int:
    try:
        length = int(raw_value or "0")
    except ValueError as error:
        raise ValueError("invalid Content-Length") from error
    if length < 0:
        raise ValueError("negative Content-Length")
    if length > MAX_REQUEST_BYTES:
        raise OverflowError("request body exceeds the local showcase limit")
    return length


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(value, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, path)


class ShowcaseState:
    def __init__(self, root: Path, adb: Path, token: str, *, device_polling: bool = True) -> None:
        self.root = root.resolve()
        self.web_root = (self.root / "tools" / "showcase").resolve()
        self.local_root = (self.root / ".local" / "showcase").resolve()
        self.evidence_root = (self.local_root / "evidence").resolve()
        self.recordings_root = (self.local_root / "recordings").resolve()
        self.preview_root = (self.root / ".local" / "visual-review").resolve()
        self.status_path = self.local_root / "status.json"
        self.adb = adb
        self.device_polling = device_polling
        self.token = token
        self.origin = ""
        self.lock = threading.RLock()
        self.sessions: dict[str, dict[str, object]] = {}
        self.evidence_root.mkdir(parents=True, exist_ok=True)
        self.recordings_root.mkdir(parents=True, exist_ok=True)
        self._recover_interrupted_manifests()

    @staticmethod
    def allowed_preview_names() -> set[str]:
        return {f"{variant}-{state}.png" for state in PREVIEW_STATES for variant in PREVIEW_VARIANTS}

    def resolve_preview(self, name: str) -> Path | None:
        if name not in self.allowed_preview_names():
            return None
        candidate = (self.preview_root / name).resolve()
        if candidate.parent != self.preview_root or not candidate.is_file():
            return None
        try:
            with candidate.open("rb") as handle:
                if handle.read(len(PNG_SIGNATURE)) != PNG_SIGNATURE:
                    return None
        except OSError:
            return None
        return candidate

    def list_previews(self) -> list[dict[str, object]]:
        states: list[dict[str, object]] = []
        for state in PREVIEW_STATES:
            variants: dict[str, object] = {}
            for variant in PREVIEW_VARIANTS:
                name = f"{variant}-{state}.png"
                path = self.resolve_preview(name)
                if path is None:
                    continue
                try:
                    stat = path.stat()
                except OSError:
                    continue
                variants[variant] = {
                    "name": name,
                    "size": stat.st_size,
                    "modifiedAt": datetime.fromtimestamp(stat.st_mtime, timezone.utc)
                    .isoformat(timespec="milliseconds")
                    .replace("+00:00", "Z"),
                }
            states.append({"state": state, "complete": all(variant in variants for variant in PREVIEW_VARIANTS), **variants})
        return states

    def _recover_interrupted_manifests(self) -> None:
        recovered_at = utc_now()
        for manifest_path in self.recordings_root.glob("*.manifest.json"):
            try:
                manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            if manifest.get("endedAt") is not None or manifest.get("state") not in {"recording", "gap"}:
                continue
            gaps = manifest.setdefault("gaps", [])
            if not gaps or gaps[-1].get("endedAt") is not None:
                gaps.append(
                    {
                        "startedAt": manifest.get("lastSeenAt", recovered_at),
                        "endedAt": recovered_at,
                        "reason": "showcase server stopped before browser session ended",
                    }
                )
            else:
                gaps[-1]["endedAt"] = recovered_at
            manifest["state"] = "interrupted"
            manifest["endedAt"] = recovered_at
            manifest["endReason"] = "recovered after showcase server restart"
            manifest["unflushed"] = True
            manifest["unflushedAt"] = recovered_at
            write_json(manifest_path, manifest)

    def list_devices(self) -> tuple[list[dict[str, str]], str | None]:
        if not self.device_polling:
            return [], "Live device polling paused to reduce local load; captured evidence remains available."
        if not self.adb.is_file():
            return [], f"ADB not found at {self.adb}"
        try:
            devices = subprocess.run(
                [str(self.adb), "devices", "-l"],
                capture_output=True,
                timeout=5,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            return [], f"ADB unavailable: {error}"
        if devices.returncode != 0:
            detail = devices.stderr.decode("utf-8", errors="replace").strip()
            return [], detail or "ADB device enumeration failed"
        connected: list[dict[str, str]] = []
        for line in devices.stdout.decode("utf-8", errors="replace").splitlines()[1:]:
            fields = line.strip().split()
            if len(fields) < 2 or fields[1] != "device":
                continue
            properties = dict(field.split(":", 1) for field in fields[2:] if ":" in field)
            serial = fields[0]
            model = properties.get("model", "Android").replace("_", " ")
            source = "Emulator" if serial.startswith("emulator-") else "Physical device"
            connected.append({"serial": serial, "model": model, "source": source, "label": f"{model} · {source}"})
        return connected, None

    def capture_frame(self, serial: str | None = None) -> tuple[bytes | None, str]:
        connected, error = self.list_devices()
        if error:
            return None, error
        if not connected:
            return None, "Waiting for Android device"
        selected = next((device for device in connected if device["serial"] == serial), None) if serial else connected[0]
        if selected is None:
            return None, "Requested Android device is not connected"
        command = [str(self.adb), "-s", selected["serial"], "exec-out", "screencap", "-p"]
        try:
            capture = subprocess.run(command, capture_output=True, timeout=8, check=False)
        except (OSError, subprocess.TimeoutExpired) as error:
            return None, f"Android frame capture failed: {error}"
        if capture.returncode != 0 or not capture.stdout.startswith(b"\x89PNG\r\n\x1a\n"):
            detail = capture.stderr.decode("utf-8", errors="replace").strip()
            return None, detail or "Android frame capture returned no PNG"
        return capture.stdout, f"{selected['label']} ({selected['serial']})"

    def list_evidence(self) -> list[dict[str, object]]:
        items: list[dict[str, object]] = []
        for path in sorted(self.evidence_root.rglob("*"), key=lambda item: item.stat().st_mtime, reverse=True):
            if not path.is_file():
                continue
            relative = path.relative_to(self.evidence_root).as_posix()
            mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
            if not (mime.startswith("image/") or mime.startswith("video/")):
                continue
            items.append(
                {
                    "name": relative,
                    "kind": "video" if mime.startswith("video/") else "image",
                    "mime": mime,
                    "size": path.stat().st_size,
                    "modifiedAt": datetime.fromtimestamp(path.stat().st_mtime, timezone.utc)
                    .isoformat(timespec="milliseconds")
                    .replace("+00:00", "Z"),
                }
            )
        return items

    def start_session(self, payload: dict[str, object], client: str) -> dict[str, str]:
        session_id = secrets.token_hex(12)
        session_secret = secrets.token_urlsafe(32)
        now = utc_now()
        mime_type = str(payload.get("mimeType") or "video/webm")[:120]
        extension = ".webm" if "webm" in mime_type else ".bin"
        filename = f"{now[:10]}_{now[11:19].replace(':', '-')}_{session_id}{extension}"
        manifest_path = self.recordings_root / f"{filename}.manifest.json"
        session = {
            "id": session_id,
            "secret": session_secret,
            "filename": filename,
            "manifest_path": manifest_path,
            "startedAt": now,
            "lastSeenAt": now,
            "last_seen_monotonic": time.monotonic(),
            "endedAt": None,
            "state": "recording",
            "client": client,
            "mimeType": mime_type,
            "canvasFps": payload.get("canvasFps"),
            "requestedBitsPerSecond": payload.get("requestedBitsPerSecond"),
            "chunks": [],
            "gaps": [],
            "active_gap": None,
            "bytes": 0,
            "unflushed": False,
        }
        with self.lock:
            self.sessions[session_id] = session
            self._persist_manifest(session)
        return {"sessionId": session_id, "sessionSecret": session_secret, "filename": filename}

    def authenticate_session(self, session_id: str, authorization: str | None) -> dict[str, object] | None:
        with self.lock:
            session = self.sessions.get(session_id)
            if not session:
                return None
            expected = f"Bearer {session['secret']}"
            if not authorization or not secrets.compare_digest(authorization, expected):
                return None
            return session

    def append_chunk(self, session: dict[str, object], sequence: int, content: bytes) -> bool:
        if not content:
            raise ValueError("empty recording chunk")
        if sequence < 0:
            raise ValueError("negative chunk sequence")
        filename = str(session["filename"])
        target = self.recordings_root / filename
        digest = hashlib.sha256(content).hexdigest()
        with self.lock:
            chunks = session["chunks"]
            assert isinstance(chunks, list)
            expected = len(chunks)
            if sequence < expected:
                previous = chunks[sequence]
                if not isinstance(previous, dict):
                    raise ValueError("invalid stored chunk metadata")
                if previous.get("bytes") == len(content) and previous.get("sha256") == digest:
                    return True
                raise ValueError(f"chunk {sequence} replay content changed")
            if sequence > expected:
                raise ValueError(f"expected chunk {expected}, received {sequence}")
            if session.get("endedAt") is not None:
                raise ValueError("recording session already ended")
            expected_size = int(session["bytes"])
            actual_size = target.stat().st_size if target.exists() else 0
            if actual_size != expected_size:
                raise ValueError(f"recording size mismatch: manifest {expected_size}, file {actual_size}")
            with target.open("ab") as handle:
                handle.write(content)
                handle.flush()
                os.fsync(handle.fileno())
            now = utc_now()
            chunks.append({"sequence": sequence, "receivedAt": now, "bytes": len(content), "sha256": digest})
            session["bytes"] = int(session["bytes"]) + len(content)
            session["lastSeenAt"] = now
            session["last_seen_monotonic"] = time.monotonic()
            self._close_gap(session, now)
            self._persist_manifest(session)
            return False

    def heartbeat(self, session: dict[str, object]) -> None:
        with self.lock:
            if session.get("endedAt") is not None:
                return
            now = utc_now()
            session["lastSeenAt"] = now
            session["last_seen_monotonic"] = time.monotonic()
            self._close_gap(session, now)
            self._persist_manifest(session)

    def end_session(self, session: dict[str, object], reason: str) -> None:
        with self.lock:
            if session.get("endedAt") is not None:
                return
            now = utc_now()
            self._close_gap(session, now)
            session["endedAt"] = now
            session["state"] = "ended"
            session["endReason"] = reason[:200]
            session["unflushed"] = False
            self._persist_manifest(session)

    def interrupt_session(self, session: dict[str, object], reason: str) -> None:
        with self.lock:
            if session.get("endedAt") is not None:
                return
            now = utc_now()
            chunks = session["chunks"]
            assert isinstance(chunks, list)
            last_committed_at = chunks[-1]["receivedAt"] if chunks else session["startedAt"]
            gap = {
                "startedAt": last_committed_at,
                "endedAt": now,
                "reason": "final MediaRecorder data was not confirmed persisted",
            }
            gaps = session["gaps"]
            assert isinstance(gaps, list)
            active_gap = session.get("active_gap")
            if isinstance(active_gap, dict):
                active_gap["endedAt"] = now
            gaps.append(gap)
            session["active_gap"] = None
            session["endedAt"] = now
            session["state"] = "interrupted"
            session["endReason"] = reason[:200]
            session["unflushed"] = True
            session["unflushedAt"] = now
            self._persist_manifest(session)

    def mark_stale_sessions(self) -> None:
        with self.lock:
            now_mono = time.monotonic()
            for session in self.sessions.values():
                if session["state"] != "recording" or session["active_gap"] is not None:
                    continue
                last_seen = float(session["last_seen_monotonic"])
                if now_mono - last_seen >= GAP_AFTER_SECONDS:
                    gap = {"startedAt": session["lastSeenAt"], "endedAt": None, "reason": "browser heartbeat lost"}
                    gaps = session["gaps"]
                    assert isinstance(gaps, list)
                    gaps.append(gap)
                    session["active_gap"] = gap
                    session["state"] = "gap"
                    self._persist_manifest(session)

    def _close_gap(self, session: dict[str, object], now: str) -> None:
        gap = session.get("active_gap")
        if isinstance(gap, dict):
            gap["endedAt"] = now
            session["active_gap"] = None
        if session.get("endedAt") is None:
            session["state"] = "recording"

    def _persist_manifest(self, session: dict[str, object]) -> None:
        manifest_path = session["manifest_path"]
        assert isinstance(manifest_path, Path)
        public = {key: value for key, value in session.items() if key not in {"secret", "manifest_path", "last_seen_monotonic", "active_gap"}}
        public["recordingPath"] = str((self.recordings_root / str(session["filename"])).resolve())
        public["manifestVersion"] = 2
        write_json(manifest_path, public)


class ShowcaseServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address: tuple[str, int], state: ShowcaseState) -> None:
        super().__init__(address, ShowcaseHandler)
        self.state = state


class ShowcaseHandler(BaseHTTPRequestHandler):
    server_version = "MeowWatchShowcase/1.0"

    @property
    def state(self) -> ShowcaseState:
        return self.server.state  # type: ignore[attr-defined]

    def log_message(self, format_string: str, *args: object) -> None:
        print(f"{utc_now()} {self.address_string()} {format_string % args}", flush=True)

    def _host_valid(self) -> bool:
        return self.headers.get("Host", "") in {f"127.0.0.1:{self.server.server_port}", f"localhost:{self.server.server_port}"}

    def _token_valid(self, query: dict[str, list[str]]) -> bool:
        supplied = query.get("token", [""])[0]
        return bool(supplied) and secrets.compare_digest(supplied, self.state.token)

    def _mutation_valid(self, query: dict[str, list[str]]) -> bool:
        if not self._host_valid():
            return False
        origin = self.headers.get("Origin", "")
        expected = {f"http://127.0.0.1:{self.server.server_port}", f"http://localhost:{self.server.server_port}"}
        if origin not in expected:
            return False
        return self._token_valid(query) and secrets.compare_digest(
            self.headers.get("X-Showcase-Token", ""), self.state.token
        )

    def _send_json(self, status: int, value: object) -> None:
        payload = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'")
        self.end_headers()
        self.wfile.write(payload)

    def _send_file(self, path: Path, content_type: str) -> None:
        try:
            payload = path.read_bytes()
        except FileNotFoundError:
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; img-src 'self' blob:; media-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'",
        )
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self) -> None:
        parsed = urllib.parse.urlsplit(self.path)
        query = urllib.parse.parse_qs(parsed.query)
        if not self._host_valid():
            self.send_error(HTTPStatus.FORBIDDEN)
            return
        if parsed.path == "/app.js":
            self._send_file(self.state.web_root / "app.js", "text/javascript; charset=utf-8")
            return
        if parsed.path == "/styles.css":
            self._send_file(self.state.web_root / "styles.css", "text/css; charset=utf-8")
            return
        if not self._token_valid(query):
            self.send_error(HTTPStatus.FORBIDDEN)
            return
        if parsed.path == "/":
            self._send_file(self.state.web_root / "index.html", "text/html; charset=utf-8")
            return
        if parsed.path == "/api/status":
            try:
                status = json.loads(self.state.status_path.read_text(encoding="utf-8"))
            except (FileNotFoundError, json.JSONDecodeError) as error:
                status = {"headline": "Status unavailable", "events": [], "error": str(error)}
            self._send_json(HTTPStatus.OK, {"serverTime": utc_now(), "status": status})
            return
        if parsed.path == "/api/frame":
            serial = query.get("serial", [None])[0]
            payload, source = self.state.capture_frame(serial)
            if payload is None:
                self._send_json(HTTPStatus.SERVICE_UNAVAILABLE, {"state": "waiting", "message": source, "capturedAt": utc_now()})
                return
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Frame-Source", source)
            self.end_headers()
            self.wfile.write(payload)
            return
        if parsed.path == "/api/devices":
            devices, error = self.state.list_devices()
            self._send_json(
                HTTPStatus.OK,
                {"items": devices, "message": error or ("Connected Android sources" if devices else "Waiting for Android device")},
            )
            return
        if parsed.path == "/api/evidence":
            self._send_json(HTTPStatus.OK, {"items": self.state.list_evidence()})
            return
        if parsed.path == "/api/previews":
            self._send_json(
                HTTPStatus.OK,
                {
                    "source": "Flutter UI preview · test renderer",
                    "runtimeEvidence": False,
                    "states": self.state.list_previews(),
                },
            )
            return
        if parsed.path.startswith("/preview/"):
            name = urllib.parse.unquote(parsed.path[len("/preview/") :])
            preview = self.state.resolve_preview(name)
            if preview is None:
                self.send_error(HTTPStatus.NOT_FOUND)
                return
            self._send_file(preview, "image/png")
            return
        if parsed.path.startswith("/evidence/"):
            relative = urllib.parse.unquote(parsed.path[len("/evidence/") :])
            candidate = (self.state.evidence_root / relative).resolve()
            if self.state.evidence_root not in candidate.parents or not candidate.is_file():
                self.send_error(HTTPStatus.NOT_FOUND)
                return
            content_type = mimetypes.guess_type(candidate.name)[0] or "application/octet-stream"
            if not (content_type.startswith("image/") or content_type.startswith("video/")):
                self.send_error(HTTPStatus.UNSUPPORTED_MEDIA_TYPE)
                return
            self._send_file(candidate, content_type)
            return
        self.send_error(HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:
        parsed = urllib.parse.urlsplit(self.path)
        query = urllib.parse.parse_qs(parsed.query)
        if not self._mutation_valid(query):
            self.send_error(HTTPStatus.FORBIDDEN)
            return
        try:
            length = validated_content_length(self.headers.get("Content-Length"))
        except OverflowError:
            self.send_error(HTTPStatus.REQUEST_ENTITY_TOO_LARGE)
            return
        except ValueError:
            self.send_error(HTTPStatus.BAD_REQUEST)
            return
        if parsed.path == "/api/recordings/start":
            try:
                payload = json.loads(self.rfile.read(length) or b"{}")
            except json.JSONDecodeError:
                self.send_error(HTTPStatus.BAD_REQUEST)
                return
            if not isinstance(payload, dict):
                self.send_error(HTTPStatus.BAD_REQUEST)
                return
            result = self.state.start_session(payload, self.headers.get("User-Agent", "unknown")[:300])
            self._send_json(HTTPStatus.CREATED, result)
            return
        parts = parsed.path.strip("/").split("/")
        if len(parts) != 4 or parts[:2] != ["api", "recordings"]:
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        session = self.state.authenticate_session(parts[2], self.headers.get("Authorization"))
        if session is None:
            self.send_error(HTTPStatus.UNAUTHORIZED)
            return
        action = parts[3]
        if action == "chunk":
            try:
                sequence = int(self.headers.get("X-Chunk-Sequence", "-1"))
                content = self.rfile.read(length)
                if len(content) != length:
                    self.send_error(HTTPStatus.BAD_REQUEST)
                    return
                replayed = self.state.append_chunk(session, sequence, content)
            except ValueError as error:
                self._send_json(HTTPStatus.CONFLICT, {"error": str(error)})
                return
            self._send_json(HTTPStatus.OK, {"accepted": sequence, "bytes": length, "replayed": replayed})
            return
        if action == "heartbeat":
            self.rfile.read(length)
            self.state.heartbeat(session)
            self._send_json(HTTPStatus.OK, {"serverTime": utc_now()})
            return
        if action == "end":
            try:
                payload = json.loads(self.rfile.read(length) or b"{}")
            except json.JSONDecodeError:
                payload = {}
            reason = str(payload.get("reason") or "browser ended") if isinstance(payload, dict) else "browser ended"
            self.state.end_session(session, reason)
            self._send_json(HTTPStatus.OK, {"ended": True})
            return
        if action == "interrupt":
            try:
                payload = json.loads(self.rfile.read(length) or b"{}")
            except json.JSONDecodeError:
                payload = {}
            reason = str(payload.get("reason") or "browser interrupted") if isinstance(payload, dict) else "browser interrupted"
            self.state.interrupt_session(session, reason)
            self._send_json(HTTPStatus.OK, {"interrupted": True, "unflushed": True})
            return
        self.send_error(HTTPStatus.NOT_FOUND)


def seed_status(path: Path) -> None:
    if path.exists():
        return
    write_json(
        path,
        {
            "headline": "Waiting for verified development status",
            "updatedAt": utc_now(),
            "events": [
                {
                    "state": "pending",
                    "label": "No build, test, device, or purchase evidence has been supplied yet",
                }
            ],
        },
    )


def gap_monitor(state: ShowcaseState, stop: threading.Event) -> None:
    while not stop.wait(2):
        state.mark_stale_sessions()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1", choices=["127.0.0.1"], help="fixed loopback bind")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--adb", type=Path, help="explicit adb executable; otherwise discover the Android SDK or PATH")
    parser.add_argument("--evidence-only", action="store_true", help="disable all live ADB polling to reduce local load")
    parser.add_argument("--token", default=secrets.token_urlsafe(32))
    args = parser.parse_args()

    state = ShowcaseState(args.root, args.adb or discover_adb(), args.token,
                          device_polling=not args.evidence_only)
    seed_status(state.status_path)
    server = ShowcaseServer((args.host, args.port), state)
    actual_port = server.server_address[1]
    state.origin = f"http://127.0.0.1:{actual_port}"
    runtime_path = state.local_root / "runtime.json"
    write_json(
        runtime_path,
        {
            "pid": os.getpid(),
            "owner": "tools/showcase/server.py",
            "startedAt": utc_now(),
            "bind": f"127.0.0.1:{actual_port}",
            "url": f"{state.origin}/?token={urllib.parse.quote(args.token)}",
            "adbPath": str(state.adb),
            "devicePolling": state.device_polling,
            "recordingsPath": str(state.recordings_root),
        },
    )
    stop = threading.Event()
    monitor = threading.Thread(target=gap_monitor, args=(state, stop), daemon=True)
    monitor.start()
    print(f"SHOWCASE_URL={state.origin}/?token={urllib.parse.quote(args.token)}", flush=True)
    print(f"SHOWCASE_PID={os.getpid()}", flush=True)
    try:
        server.serve_forever(poll_interval=0.25)
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        server.server_close()
        try:
            runtime = json.loads(runtime_path.read_text(encoding="utf-8"))
            runtime["stoppedAt"] = utc_now()
            write_json(runtime_path, runtime)
        except (OSError, json.JSONDecodeError):
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
