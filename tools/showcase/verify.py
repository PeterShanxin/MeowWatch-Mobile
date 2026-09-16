#!/usr/bin/env python3
"""HTTP-level verification for a running local showcase server."""

from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
RUNTIME_PATH = ROOT / ".local" / "showcase" / "runtime.json"


def request(
    url: str,
    *,
    method: str = "GET",
    headers: dict[str, str] | None = None,
    body: bytes | None = None,
) -> tuple[int, bytes, dict[str, str]]:
    req = urllib.request.Request(url, method=method, headers=headers or {}, data=body)
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            return response.status, response.read(), dict(response.headers)
    except urllib.error.HTTPError as error:
        return error.code, error.read(), dict(error.headers)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)
    print(f"PASS {message}")


def main() -> int:
    runtime = json.loads(RUNTIME_PATH.read_text(encoding="utf-8"))
    page_url = runtime["url"]
    parsed = urllib.parse.urlsplit(page_url)
    origin = f"{parsed.scheme}://{parsed.netloc}"
    token = urllib.parse.parse_qs(parsed.query)["token"][0]
    query = urllib.parse.urlencode({"token": token})

    status, body, _ = request(page_url)
    require(status == 200 and b"Live development showcase" in body, "tokenized page is served")
    status, _, _ = request(f"{origin}/styles.css")
    require(status == 200, "static asset is served to the local page")
    status, _, _ = request(f"{origin}/api/status")
    require(status == 403, "API rejects a missing launch token")
    status, _, _ = request(
        f"{origin}/api/status?{query}",
        headers={"Host": "attacker.invalid"},
    )
    require(status == 403, "API rejects an unexpected Host header")

    status, body, headers = request(f"{origin}/api/frame?{query}")
    require(status in {200, 503}, "frame endpoint reports a real frame or explicit waiting state")
    if status == 200:
        require(body.startswith(b"\x89PNG\r\n\x1a\n"), "live frame is a PNG")
    else:
        waiting = json.loads(body)
        require(waiting.get("state") == "waiting", "no-device response is truthful and machine-readable")
    status, body, _ = request(f"{origin}/api/devices?{query}")
    device_index = json.loads(body)
    require(status == 200 and isinstance(device_index.get("items"), list), "multi-device source index is available")

    common_headers = {
        "Origin": origin,
        "X-Showcase-Token": token,
        "Content-Type": "application/json",
    }
    status, _, _ = request(
        f"{origin}/api/recordings/start?{query}",
        method="POST",
        headers={**common_headers, "Origin": "http://attacker.invalid"},
        body=b"{}",
    )
    require(status == 403, "recording mutation rejects a foreign Origin")

    status, body, _ = request(
        f"{origin}/api/recordings/start?{query}",
        method="POST",
        headers=common_headers,
        body=json.dumps({"mimeType": "video/webm", "canvasFps": 2, "requestedBitsPerSecond": 900000}).encode(),
    )
    require(status == 201, "recording session starts with local CSRF guard")
    session = json.loads(body)
    session_id = session["sessionId"]
    bearer = {**common_headers, "Authorization": f"Bearer {session['sessionSecret']}"}
    recording_path = Path(runtime["recordingsPath"]) / session["filename"]
    manifest_path = recording_path.with_name(recording_path.name + ".manifest.json")
    probe = b"showcase-http-persistence-probe"
    try:
        status, _, _ = request(
            f"{origin}/api/recordings/{session_id}/chunk?{query}",
            method="POST",
            headers={**bearer, "Content-Type": "video/webm", "X-Chunk-Sequence": "0"},
            body=probe,
        )
        require(status == 200, "first recording chunk is accepted")
        require(recording_path.read_bytes() == probe, "recording bytes are durably persisted")
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        require(manifest["bytes"] == len(probe) and len(manifest["chunks"]) == 1, "manifest tracks persisted chunk")

        status, body, _ = request(
            f"{origin}/api/recordings/{session_id}/chunk?{query}",
            method="POST",
            headers={**bearer, "Content-Type": "video/webm", "X-Chunk-Sequence": "0"},
            body=probe,
        )
        replay = json.loads(body)
        require(status == 200 and replay.get("replayed") is True, "identical chunk replay is idempotently accepted")
        require(recording_path.read_bytes() == probe, "idempotent replay does not duplicate recording bytes")

        status, _, _ = request(
            f"{origin}/api/recordings/{session_id}/chunk?{query}",
            method="POST",
            headers={**bearer, "Content-Type": "video/webm", "X-Chunk-Sequence": "0"},
            body=b"changed replay",
        )
        require(status == 409, "changed chunk replay is rejected")
        status, _, _ = request(
            f"{origin}/api/recordings/{session_id}/heartbeat?{query}",
            method="POST",
            headers={**common_headers, "Authorization": "Bearer wrong-secret"},
            body=b"",
        )
        require(status == 401, "per-session recording secret is enforced")

        print("WAIT verifying browser-disconnect gap marker (about 18 seconds)")
        time.sleep(18)
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        require(manifest["state"] == "gap" and manifest["gaps"][-1]["endedAt"] is None, "lost heartbeat opens a manifest gap")
        status, _, _ = request(
            f"{origin}/api/recordings/{session_id}/heartbeat?{query}",
            method="POST",
            headers=bearer,
            body=b"",
        )
        require(status == 200, "valid heartbeat reconnects the session")
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        require(manifest["state"] == "recording" and manifest["gaps"][-1]["endedAt"], "reconnect closes the recorded gap")
        status, _, _ = request(
            f"{origin}/api/recordings/{session_id}/end?{query}",
            method="POST",
            headers=bearer,
            body=b'{"reason":"verification complete"}',
        )
        require(status == 200, "recording session ends explicitly")
    finally:
        request(
            f"{origin}/api/recordings/{session_id}/end?{query}",
            method="POST",
            headers=bearer,
            body=b'{"reason":"verification cleanup"}',
        )
        time.sleep(0.1)
        recording_path.unlink(missing_ok=True)
        manifest_path.unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"FAIL {error}", file=sys.stderr)
        raise
