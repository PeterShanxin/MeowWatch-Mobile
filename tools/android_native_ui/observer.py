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
SHORT_COMPONENT = f"{OBSERVER_PACKAGE}/.SnapshotInstrumentation"
DEFAULT_APK = Path("build/android-native-ui/native-ui-observer.apk")
MAX_XML_BYTES = 262144
MAX_OUTPUT_BYTES = 360000
MAX_NODES = 2048
MAX_DEPTH = 48
MAX_ATTRIBUTE = 4096
MAX_CAPTURE_ATTEMPTS = 4
RETRYABLE_CAPTURE_ERRORS = frozenset({
    "root_missing", "root_refresh_failed", "root_invisible", "child_missing", "capture_deadline",
    "flutter_semantics_unavailable",
})
CAPTURE_ERRORS = RETRYABLE_CAPTURE_ERRORS | {
    "node_limit", "depth_limit", "attribute_limit", "byte_limit", "child_count_limit",
    "native_security_exception", "native_state_exception",
    "native_argument_exception", "serialization_io_exception", "native_exception",
}


class ObserverIntegrityFailure(RuntimeFailure):
    """An invalid capture or a changed production process cannot be retried away."""


class ObserverCaptureFailure(RuntimeFailure):
    """A validated native failure with bounded, content-free structural evidence."""

    def __init__(self, reason: str, uptime_ms: int, attempts: tuple[dict[str, object], ...]) -> None:
        super().__init__("native observer could not capture a complete active-window hierarchy "
                         f"({reason})")
        self.reason, self.uptime_ms, self.attempts = reason, uptime_ms, attempts


class ObserverNativeFailure(ObserverCaptureFailure, ObserverIntegrityFailure):
    """A native exception or exceeded structural limit must fail the gate immediately."""


@dataclass(frozen=True)
class Snapshot:
    xml: str
    uptime_ms: int
    node_count: int
    attempts: tuple[dict[str, object], ...]


def parse_attempts(value: str) -> tuple[dict[str, object], ...]:
    """Only fixed reason codes and bounded integers may reach evidence or logs."""
    entries = value.split(";")
    if not 1 <= len(entries) <= MAX_CAPTURE_ATTEMPTS:
        raise ObserverIntegrityFailure("native observer attempt count is invalid")
    attempts = []
    for entry in entries:
        match = re.fullmatch(r"([a-z_]+):([0-9]{1,4}):(-?[0-9]{1,2}):(-?[0-9]{1,4}):(-?[0-9]{1,4})", entry)
        if match is None or match[1] not in CAPTURE_ERRORS | {"ok"}:
            raise ObserverIntegrityFailure("native observer attempt diagnostics are invalid")
        nodes, depth, index, children = map(int, match.groups()[1:])
        if (not 0 <= nodes <= MAX_NODES + 1 or not -1 <= depth <= MAX_DEPTH + 1
                or not -1 <= index <= MAX_NODES or not -1 <= children <= MAX_NODES + 1):
            raise ObserverIntegrityFailure("native observer attempt diagnostics exceed their bounds")
        attempts.append({"reason": match[1], "visitedNodes": nodes, "depth": depth,
                         "childIndex": index, "childCount": children})
    if any(attempt["reason"] not in RETRYABLE_CAPTURE_ERRORS - {"capture_deadline"}
           for attempt in attempts[:-1]):
        raise ObserverIntegrityFailure("native observer retried a terminal capture failure")
    return tuple(attempts)


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
    common = {"observer_protocol", "observer_nonce", "observer_uptime_ms", "observer_attempts"}
    expected = common | ({"observer_nodes", "observer_xml"} if code == "-1" else {"observer_error"})
    if code not in {"0", "-1"} or set(fields) != expected or fields["observer_protocol"] != "2":
        raise ObserverIntegrityFailure("native observer response protocol is invalid")
    if (re.fullmatch(r"[a-f0-9]{32}", fields["observer_nonce"]) is None
            or not secrets.compare_digest(fields["observer_nonce"], nonce)):
        raise ObserverIntegrityFailure("native observer response is not from this capture request")
    if re.fullmatch(r"[0-9]{1,16}", fields["observer_uptime_ms"]) is None:
        raise ObserverIntegrityFailure("native observer snapshot metadata is invalid")
    uptime = int(fields["observer_uptime_ms"])
    if uptime <= previous_uptime_ms:
        raise ObserverIntegrityFailure("native observer snapshot is stale or exceeds the node limit")
    attempts = parse_attempts(fields["observer_attempts"])
    if code == "0":
        reason = fields["observer_error"]
        if reason not in CAPTURE_ERRORS or attempts[-1]["reason"] != reason:
            raise ObserverIntegrityFailure("native observer failure diagnostics do not match")
        failure_type = ObserverCaptureFailure if reason in RETRYABLE_CAPTURE_ERRORS else ObserverNativeFailure
        raise failure_type(reason, uptime, attempts)
    if (re.fullmatch(r"[0-9]{1,4}", fields["observer_nodes"]) is None
            or attempts[-1]["reason"] != "ok"):
        raise ObserverIntegrityFailure("native observer snapshot metadata is invalid")
    node_count = int(fields["observer_nodes"])
    if not 1 <= node_count <= MAX_NODES or attempts[-1]["visitedNodes"] != node_count:
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
    if all(node.get("package") == PACKAGE and node.get("class") == "android.widget.FrameLayout"
           and not any(node.get(name, "") for name in ("text", "content-desc", "resource-id"))
           and all(node.get(name, "false") == "false"
                   for name in ("clickable", "long-clickable", "scrollable", "checkable"))
           for node in root.iter("node")):
        # The helper must retry this known Android-container-only response while
        # its accessibility connection is alive, never label it a complete tree.
        raise ObserverIntegrityFailure("native observer returned an incomplete Flutter accessibility shell")
    return Snapshot(xml, uptime, count, attempts)


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
        # PackageManagerShellCommand uses ComponentName.flattenToShortString().
        # Keep the exact self-target check while matching Android's wire output.
        expected = f"instrumentation:{SHORT_COMPONENT} (target={OBSERVER_PACKAGE})"
        self.installation["instrumentationCheck"] = {
            "matchesExactSelfTarget": instrumentation.strip() == expected,
            "stdoutBytes": len(instrumentation.encode("utf-8")),
            "stdoutSha256": hashlib.sha256(instrumentation.encode("utf-8")).hexdigest(),
        }
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
        evidence: dict[str, object] = {"status": "failure", "requestNonce": nonce,
                                      "startedAtMonotonic": started}
        stage = "application_pid_before"
        try:
            before_pid = self.production_pid()
            evidence["applicationPid"] = int(before_pid)
            stage = "instrumentation"
            try:
                result = self.adb.run("shell", "am", "instrument", "-w", "-r", "-e", "nonce", nonce,
                                      "-e", "expectedPackage", PACKAGE,
                                      COMPONENT, timeout=10)
            except subprocess.TimeoutExpired:
                # Stop only our independently installed helper, never the app.
                self.adb.run("shell", "am", "force-stop", OBSERVER_PACKAGE, timeout=10)
                if self.production_pid() != before_pid:
                    raise ObserverIntegrityFailure("application process changed during timed-out native UI capture")
                raise
            evidence["stdoutBytes"] = len(result.stdout)
            evidence["stdoutSha256"] = hashlib.sha256(result.stdout).hexdigest()
            stage = "window"
            window = self.adb.run("shell", "dumpsys", "window", "displays", timeout=10).stdout.decode(
                "utf-8", errors="replace")
            focuses = re.findall(r"mCurrentFocus=([^\r\n]+)", window)
            evidence["window"] = {
                "bytes": len(window.encode("utf-8")), "sha256": hashlib.sha256(window.encode()).hexdigest(),
                "focusedWindowCount": len(focuses),
                "applicationFocused": len(focuses) == 1 and re.search(
                    rf"\b{re.escape(PACKAGE)}/[^\s}}]+", focuses[0]) is not None,
            }
            stage = "application_pid_after"
            after_pid = self.production_pid()
            evidence["applicationPidAfter"] = int(after_pid)
            if after_pid != before_pid:
                raise ObserverIntegrityFailure("application process changed during native UI capture")
            stage = "response"
            snapshot = parse_snapshot(result.stdout, nonce, previous_uptime_ms=self.previous_uptime_ms)
            self.previous_uptime_ms = snapshot.uptime_ms
            evidence.update({"status": "success", "capturedAtUptimeMs": snapshot.uptime_ms,
                             "nodeCount": snapshot.node_count, "attempts": list(snapshot.attempts),
                             "xmlSha256": hashlib.sha256(snapshot.xml.encode()).hexdigest()})
            return snapshot.xml, window
        except ObserverCaptureFailure as error:
            self.previous_uptime_ms = error.uptime_ms
            evidence.update({"failure": error.reason, "capturedAtUptimeMs": error.uptime_ms,
                             "attempts": list(error.attempts),
                             "integrityFailure": isinstance(error, ObserverIntegrityFailure)})
            raise
        except subprocess.TimeoutExpired:
            evidence["failure"] = stage + "_timeout"
            raise
        except RuntimeFailure as error:
            evidence.update({"failure": stage + "_failed",
                             "integrityFailure": isinstance(error, ObserverIntegrityFailure)})
            raise
        finally:
            evidence["completedAtMonotonic"] = time.monotonic()
            self.observations.append(evidence)

    def cleanup(self) -> None:
        if self.owns_package:
            result = self.adb.run("uninstall", OBSERVER_PACKAGE, timeout=60, check=False)
            if result.returncode or result.stdout.strip() != b"Success":
                # A failed installation may have left no package to uninstall.
                if self.adb.run("shell", "pm", "path", OBSERVER_PACKAGE, check=False).stdout.strip():
                    raise RuntimeFailure("could not remove the task-owned native UI observer")
            self.owns_package = self.installed = False
