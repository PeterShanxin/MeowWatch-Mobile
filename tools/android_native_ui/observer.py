"""Fresh native accessibility snapshots without waiting for UI idleness."""

from __future__ import annotations

import base64
import binascii
from dataclasses import dataclass
import hashlib
from pathlib import Path
import re
import secrets
import subprocess
import time
import xml.etree.ElementTree as ET

from tools.android_install.runner import Adb, PACKAGE, RuntimeFailure, install_output_succeeded


OBSERVER_PACKAGE = "com.meowwatch.native_ui_observer"
COMPONENT = f"{OBSERVER_PACKAGE}/{OBSERVER_PACKAGE}.SnapshotInstrumentation"
DEFAULT_APK = Path("build/android-native-ui/native-ui-observer.apk")
MAX_XML_BYTES = 262144
MAX_OUTPUT_BYTES = 360000
MAX_NODES = 2048
MAX_DEPTH = 48
MAX_ATTRIBUTE = 4096


class ObserverIntegrityFailure(RuntimeFailure):
    """An invalid capture or a changed production process cannot be retried away."""


@dataclass(frozen=True)
class Snapshot:
    xml: str
    uptime_ms: int
    node_count: int


def installation_diagnostics(result: subprocess.CompletedProcess[bytes]) -> dict[str, object]:
    """Retain recognized installer state without paths or arbitrary raw payloads."""
    stdout, stderr = result.stdout or b"", result.stderr or b""
    lines = [line.strip() for line in stdout.decode("utf-8", errors="replace").splitlines() if line.strip()]
    known_modes = {"Performing Streamed Install": "streamed", "Performing Push Install": "push",
                   "Performing Incremental Install": "incremental"}
    modes = [known_modes[line] for line in lines if line in known_modes]
    error_codes = sorted(set(re.findall(rb"\bINSTALL_(?:FAILED|PARSE_FAILED)_[A-Z0-9_]+\b", stdout + stderr)))
    return {"requestedMode": "non-incremental", "exitCode": result.returncode,
            "observedModes": modes, "successLinePresent": "Success" in lines,
            "terminalSuccess": bool(lines) and lines[-1] == "Success",
            "incrementalCompletionPresent": any(re.fullmatch(r"Install command complete in \d+ ms", line)
                                                 for line in lines),
            "errorCodes": [value.decode("ascii") for value in error_codes],
            "stdoutBytes": len(stdout), "stderrBytes": len(stderr),
            "stdoutSha256": hashlib.sha256(stdout).hexdigest(),
            "stderrSha256": hashlib.sha256(stderr).hexdigest()}


def parse_snapshot(output: bytes, nonce: str, *, previous_uptime_ms: int = -1) -> Snapshot:
    """Reject malformed/stale/oversized output without echoing its UI contents."""
    if len(output) > MAX_OUTPUT_BYTES or re.fullmatch(r"[a-f0-9]{32}", nonce) is None:
        raise ObserverIntegrityFailure("native observer output or request is invalid")
    try:
        decoded = output.decode("utf-8", errors="strict")
    except UnicodeError:
        raise ObserverIntegrityFailure("native observer output encoding is invalid") from None
    fields: dict[str, str] = {}
    code = None
    for line in decoded.splitlines():
        if not line.strip():
            continue
        match = re.fullmatch(r"INSTRUMENTATION_RESULT: (observer_[a-z_]+)=(.*)", line)
        if match and match[1] not in fields:
            fields[match[1]] = match[2]
        elif line.startswith("INSTRUMENTATION_CODE: ") and code is None:
            code = line.removeprefix("INSTRUMENTATION_CODE: ")
        else:
            raise ObserverIntegrityFailure("native observer returned an unexpected response")
    if code == "0" and set(fields) == {"observer_error"} and fields["observer_error"] in {
        "root_unavailable", "snapshot_failed",
    }:
        raise RuntimeFailure("native observer could not capture a complete active-window hierarchy")
    expected = {"observer_protocol", "observer_nonce", "observer_uptime_ms", "observer_nodes", "observer_xml"}
    if code != "-1" or set(fields) != expected or fields["observer_protocol"] != "1":
        raise ObserverIntegrityFailure("native observer did not return a successful snapshot")
    if (re.fullmatch(r"[a-f0-9]{32}", fields["observer_nonce"]) is None
            or not secrets.compare_digest(fields["observer_nonce"], nonce)):
        raise ObserverIntegrityFailure("native observer response is not from this capture request")
    if (re.fullmatch(r"[0-9]{1,16}", fields["observer_uptime_ms"]) is None
            or re.fullmatch(r"[0-9]{1,4}", fields["observer_nodes"]) is None):
        raise ObserverIntegrityFailure("native observer snapshot metadata is invalid")
    uptime, node_count = int(fields["observer_uptime_ms"]), int(fields["observer_nodes"])
    if uptime <= previous_uptime_ms or not 1 <= node_count <= MAX_NODES:
        raise ObserverIntegrityFailure("native observer snapshot is stale or exceeds the node limit")
    try:
        xml_bytes = base64.b64decode(fields["observer_xml"], validate=True)
        if len(xml_bytes) > MAX_XML_BYTES or b"<!" in xml_bytes:
            raise ValueError()
        xml = xml_bytes.decode("utf-8", errors="strict")
        root = ET.fromstring(xml)
    except (binascii.Error, ValueError, UnicodeError, ET.ParseError):
        raise ObserverIntegrityFailure("native observer hierarchy encoding is invalid") from None
    if root.tag != "hierarchy" or len(root) != 1:
        raise ObserverIntegrityFailure("native observer hierarchy has no unique active root")
    stack = [(root[0], 0)]
    count = 0
    while stack:
        node, depth = stack.pop()
        count += 1
        if (node.tag != "node" or depth > MAX_DEPTH or count > MAX_NODES
                or any(len(value) > MAX_ATTRIBUTE for value in node.attrib.values())):
            raise ObserverIntegrityFailure("native observer hierarchy exceeds its structural bounds")
        if (not {"text", "content-desc", "resource-id", "class", "package", "bounds",
                 "enabled", "visible-to-user", "clickable", "scrollable"}.issubset(node.attrib)
                or re.fullmatch(r"\[-?\d+,-?\d+\]\[-?\d+,-?\d+\]", node.get("bounds", "")) is None
                or any(node.get(name) not in {"true", "false"}
                       for name in ("enabled", "visible-to-user", "clickable", "scrollable"))
                or node.get("visible-to-user") != "true"):
            raise ObserverIntegrityFailure("native observer hierarchy attributes are invalid")
        stack.extend((child, depth + 1) for child in node)
    if count != node_count:
        raise ObserverIntegrityFailure("native observer hierarchy node count does not match")
    return Snapshot(xml, uptime, count)


class NativeUiObserver:
    def __init__(self, adb: Adb, apk: Path = DEFAULT_APK) -> None:
        self.adb, self.apk = adb, apk
        self.owns_package = False
        self.installed = False
        self.previous_uptime_ms = -1
        self.observations: list[dict[str, object]] = []
        self.installation: dict[str, object] | None = None

    def install(self) -> dict[str, object]:
        if not self.apk.is_file():
            raise RuntimeFailure("build the standalone native UI observer APK before this gate")
        if (re.fullmatch(r"emulator-[0-9]+", self.adb.serial) is None
                or self.adb.run("shell", "getprop", "ro.kernel.qemu").stdout.strip() != b"1"):
            raise ObserverIntegrityFailure("native UI observer requires a verified explicit emulator")
        if self.adb.run("shell", "pm", "path", OBSERVER_PACKAGE, check=False).stdout.strip():
            raise ObserverIntegrityFailure("refusing to replace a pre-existing native UI observer")
        self.owns_package = True
        # apksigner emits a .idsig sidecar. Without an explicit mode, ADB can
        # choose incremental delivery and append timing output after Success.
        # This tiny helper needs a completed ordinary install before inspection.
        result = self.adb.run("install", "--no-incremental", "-t", str(self.apk), timeout=60, check=False)
        self.installation = installation_diagnostics(result)
        installed = result.stdout.decode("utf-8", errors="replace")
        if result.returncode or not install_output_succeeded(installed):
            raise RuntimeFailure("standalone native UI observer installation failed")
        instrumentation = self.adb.run("shell", "pm", "list", "instrumentation", OBSERVER_PACKAGE).stdout.decode(
            "utf-8", errors="replace")
        expected = f"instrumentation:{COMPONENT} (target={OBSERVER_PACKAGE})"
        if instrumentation.strip() != expected:
            raise ObserverIntegrityFailure("native UI instrumentation does not target only its own package")
        self.installed = True
        return {"package": OBSERVER_PACKAGE, "targetPackage": OBSERVER_PACKAGE,
                "apkSha256": hashlib.sha256(self.apk.read_bytes()).hexdigest(),
                "method": "UiAutomation.getRootInActiveWindow", "waitForIdle": False,
                "installation": self.installation}

    def production_pid(self) -> str:
        pid = self.adb.run("shell", "pidof", PACKAGE, check=False, timeout=10).stdout.decode(
            "ascii", errors="replace").strip()
        if re.fullmatch(r"[0-9]+", pid) is None:
            raise ObserverIntegrityFailure("native UI capture requires exactly one live application process")
        return pid

    def observe(self) -> tuple[str, str]:
        if not self.installed:
            raise ObserverIntegrityFailure("native UI observer has not been installed and verified")
        nonce = secrets.token_hex(16)
        started = time.monotonic()
        before_pid = self.production_pid()
        try:
            result = self.adb.run("shell", "am", "instrument", "-w", "-r", "-e", "nonce", nonce,
                                  COMPONENT, timeout=10)
        except subprocess.TimeoutExpired:
            # A timed-out host command may leave our helper running on Android.
            # Stop only the independently installed package, never the app.
            self.adb.run("shell", "am", "force-stop", OBSERVER_PACKAGE, timeout=10)
            if self.production_pid() != before_pid:
                raise ObserverIntegrityFailure("application process changed during timed-out native UI capture")
            raise
        window = self.adb.run("shell", "dumpsys", "window", "displays", timeout=10).stdout.decode(
            "utf-8", errors="replace")
        if self.production_pid() != before_pid:
            raise ObserverIntegrityFailure("application process changed during native UI capture")
        snapshot = parse_snapshot(result.stdout, nonce, previous_uptime_ms=self.previous_uptime_ms)
        self.previous_uptime_ms = snapshot.uptime_ms
        self.observations.append({
            "requestNonce": nonce, "capturedAtUptimeMs": snapshot.uptime_ms,
            "startedAtMonotonic": started, "completedAtMonotonic": time.monotonic(),
            "applicationPid": int(before_pid), "nodeCount": snapshot.node_count,
            "xmlSha256": hashlib.sha256(snapshot.xml.encode()).hexdigest(),
        })
        return snapshot.xml, window

    def cleanup(self) -> None:
        if self.owns_package:
            result = self.adb.run("uninstall", OBSERVER_PACKAGE, timeout=60, check=False)
            if result.returncode or result.stdout.strip() != b"Success":
                # A failed installation may have left no package to uninstall.
                if self.adb.run("shell", "pm", "path", OBSERVER_PACKAGE, check=False).stdout.strip():
                    raise RuntimeFailure("could not remove the task-owned native UI observer")
            self.owns_package = self.installed = False
