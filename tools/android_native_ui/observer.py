"""Fresh native accessibility snapshots without waiting for UI idleness."""

from __future__ import annotations

import base64
import binascii
from dataclasses import dataclass
import hashlib
from pathlib import Path
import queue
import re
import secrets
import subprocess
import threading
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
MAX_STAGE_EVENTS = 40
STARTUP_TIMEOUT_SECONDS = 20
CAPTURE_TIMEOUT_SECONDS = 4
RESULT_TIMEOUT_SECONDS = 2
TOTAL_TIMEOUT_SECONDS = 26
STAGES = frozenset({
    "on_create", "on_start", "automation_start", "automation_ready", "service_ready",
    "root_start", "root_ready", "refresh_start", "refresh_ready", "traverse_start",
    "traverse_ready", "attempt_failed", "finish",
})
STAGE_PREFIX = "INSTRUMENTATION_STATUS: observer_stage="
STAGE_CODE = "INSTRUMENTATION_STATUS_CODE: 2"
RETRYABLE_CAPTURE_ERRORS = frozenset({
    "root_missing", "root_refresh_failed", "root_invisible", "child_missing",
    "flutter_semantics_unavailable",
})
CAPTURE_ERRORS = RETRYABLE_CAPTURE_ERRORS | {
    "capture_deadline",
    "node_limit", "depth_limit", "attribute_limit", "byte_limit", "child_count_limit",
    "native_security_exception", "native_state_exception",
    "native_argument_exception", "serialization_io_exception", "native_exception",
}


class ObserverIntegrityFailure(RuntimeFailure):
    """An invalid capture or a changed production process cannot be retried away."""


class ObserverTimeout(subprocess.TimeoutExpired, ObserverIntegrityFailure):
    """An expired owned capture must not buy a fresh cold-start budget."""

    def __init__(self, command, timeout, *, phase, output=b"", stderr=b""):
        subprocess.TimeoutExpired.__init__(self, command, timeout, output=output, stderr=stderr)
        self.phase = phase


def remaining_timeout(deadline: float | None, cap: float = 10) -> float:
    remaining = cap if deadline is None else min(cap, deadline - time.monotonic())
    if remaining <= 0:
        raise ObserverTimeout("native accessibility snapshot", 0, phase="caller_deadline")
    return remaining


class InstrumentationBudget:
    """One cold start and one capture; progress can never refresh a budget."""

    def __init__(self, nonce: str, started: float, deadline: float):
        self.nonce = nonce
        self.total_deadline = min(deadline, started + TOTAL_TIMEOUT_SECONDS)
        self.deadline = min(self.total_deadline, started + STARTUP_TIMEOUT_SECONDS)
        self.phase = "startup"
        self.events: list[dict[str, object]] = []
        self.ready = False
        self.finished = False
        self.capture_uptime: int | None = None
        self.traversed = False

    def progress(self, output: bytes, now: float) -> None:
        if now >= self.deadline:
            raise ObserverTimeout("native accessibility snapshot", 0, phase=self.phase, output=output)
        # A read can split UTF-8 or an instrumentation line. Only parse complete
        # lines, and never treat a lone status line as permission to extend time.
        complete = output[:output.rfind(b"\n") + 1]
        _, events, status = _stage_output(complete, self.nonce, partial=True)
        if status not in {"valid", "incomplete_status"}:
            raise ObserverIntegrityFailure("native observer progress is invalid")
        if events[:len(self.events)] != self.events:
            raise ObserverIntegrityFailure("native observer progress changed")
        startup = ("on_create", "on_start", "automation_start", "automation_ready", "service_ready")
        for event in events[len(self.events):]:
            name = event["stage"]
            if self.finished:
                raise ObserverIntegrityFailure("native observer emitted progress after finish")
            if not self.ready:
                if name == "finish":
                    # A native startup exception may return a failed protocol
                    # result; it still has no hierarchy or acceptance credit.
                    self.finished = True
                    self.phase = "result"
                    self.deadline = min(self.deadline, now + RESULT_TIMEOUT_SECONDS)
                elif (len(self.events) >= len(startup) or name != startup[len(self.events)]
                      or event["attempt"] != 0 or event["visitedNodes"] != 0):
                    raise ObserverIntegrityFailure("native observer startup sequence is invalid")
                elif name == "service_ready":
                    self.ready = True
                    self.capture_uptime = event["uptimeMs"]
                    self.phase = "capture"
                    # Native code enforces four seconds of hierarchy work. Two
                    # further seconds bound delivery of its final result.
                    self.deadline = min(self.total_deadline,
                                        now + CAPTURE_TIMEOUT_SECONDS + RESULT_TIMEOUT_SECONDS)
            elif name in startup:
                raise ObserverIntegrityFailure("native observer repeated startup readiness")
            elif name == "traverse_ready":
                if event["uptimeMs"] - self.capture_uptime >= CAPTURE_TIMEOUT_SECONDS * 1000:
                    raise ObserverIntegrityFailure("native hierarchy exceeded its four-second capture budget")
                self.traversed = True
            elif name == "finish":
                self.finished = True
                self.phase = "result"
                self.deadline = min(self.deadline, now + RESULT_TIMEOUT_SECONDS)
            self.events.append(event)


def collect_instrumentation(command: list[str], nonce: str, *, deadline: float) -> subprocess.CompletedProcess:
    """Read bounded output from exactly the adb child launched by this call."""
    started = time.monotonic()
    remaining_timeout(deadline)
    budget = InstrumentationBudget(nonce, started, deadline)
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    chunks: queue.Queue = queue.Queue(maxsize=16)
    stopping = threading.Event()
    buffers = {"stdout": bytearray(), "stderr": bytearray()}

    def reader(name, stream):
        try:
            while not stopping.is_set():
                value = stream.read1(4096)
                while not stopping.is_set():
                    try:
                        chunks.put((name, value), timeout=0.05)
                        break
                    except queue.Full:
                        continue
                if not value:
                    return
        except (OSError, ValueError):
            while not stopping.is_set():
                try:
                    chunks.put((name, None), timeout=0.05)
                    return
                except queue.Full:
                    continue

    threads = [threading.Thread(target=reader, args=(name, getattr(process, name)), daemon=True)
               for name in buffers]
    for thread in threads:
        thread.start()
    try:
        closed = set()
        while len(closed) != 2 or process.poll() is None:
            now = time.monotonic()
            if now >= budget.deadline:
                raise ObserverTimeout(command, budget.deadline - started, phase=budget.phase,
                                      output=bytes(buffers["stdout"]), stderr=bytes(buffers["stderr"]))
            try:
                name, value = chunks.get(timeout=min(0.05, budget.deadline - now))
            except queue.Empty:
                continue
            if value is None:
                raise ObserverIntegrityFailure("native observer output pipe failed")
            if not value:
                closed.add(name)
                continue
            if sum(map(len, buffers.values())) + len(value) > MAX_OUTPUT_BYTES:
                raise ObserverIntegrityFailure("native observer output exceeds its byte limit")
            buffers[name].extend(value)
            if name == "stdout":
                budget.progress(bytes(buffers[name]), time.monotonic())
        budget.progress(bytes(buffers["stdout"]), time.monotonic())
        if not budget.finished:
            raise ObserverIntegrityFailure("native observer exited without completed progress")
        if b"INSTRUMENTATION_CODE: -1" in buffers["stdout"] and not (budget.ready and budget.traversed):
            raise ObserverIntegrityFailure("native observer returned a hierarchy without a completed capture")
        if process.returncode:
            raise ObserverIntegrityFailure("native observer instrumentation exited unsuccessfully")
        return subprocess.CompletedProcess(command, process.returncode,
                                           bytes(buffers["stdout"]), bytes(buffers["stderr"]))
    except ObserverIntegrityFailure as error:
        error.output, error.stderr = bytes(buffers["stdout"]), bytes(buffers["stderr"])
        raise
    finally:
        # No process-name selection or process-group signals. This Popen handle
        # is our adb client only; Android helper cleanup stays package-scoped.
        stopping.set()
        if process.poll() is None:
            process.kill()
        process.wait(timeout=2)
        for thread in threads:
            thread.join(timeout=1)
        for name in buffers:
            getattr(process, name).close()


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


def _stage_output(
    output: bytes, nonce: str, *, partial: bool = False,
) -> tuple[bytes, list[dict[str, object]], str]:
    """Separate validated progress from the unchanged final snapshot protocol."""
    events: list[dict[str, object]] = []

    def invalid(reason: str) -> tuple[bytes, list[dict[str, object]], str]:
        if not partial:
            raise ObserverIntegrityFailure("native observer stage diagnostics are invalid")
        return b"", events, reason

    if re.fullmatch(r"[a-f0-9]{32}", nonce) is None:
        return invalid("invalid_nonce")
    oversized = len(output) > MAX_OUTPUT_BYTES
    if oversized and not partial:
        return invalid("output_limit")
    lines = output[:MAX_OUTPUT_BYTES].splitlines()
    payload: list[str] = []
    index = 0
    while index < len(lines):
        try:
            line = lines[index].decode("utf-8", errors="strict")
        except UnicodeError:
            return invalid("invalid_encoding")
        if not line.startswith(STAGE_PREFIX):
            if line.startswith("INSTRUMENTATION_STATUS"):
                return invalid("invalid_status")
            payload.append(line)
            index += 1
            continue
        if index + 1 == len(lines):
            return invalid("incomplete_status")
        if lines[index + 1] != STAGE_CODE.encode("ascii"):
            return invalid("invalid_status")
        match = re.fullmatch(
            r"([a-f0-9]{32}):([0-9]{1,10}):([0-9]{1,2}):([a-z_]+):"
            r"([0-9]{1,16}):([0-9]):([0-9]{1,4})", line[len(STAGE_PREFIX):])
        if match is None or not secrets.compare_digest(match[1], nonce) or match[4] not in STAGES:
            return invalid("invalid_stage")
        helper_pid, sequence, uptime, attempt, nodes = map(int, (match[2], match[3], match[5], match[6], match[7]))
        if (helper_pid <= 0 or sequence != len(events) + 1 or sequence > MAX_STAGE_EVENTS
                or not 0 <= attempt <= MAX_CAPTURE_ATTEMPTS or not 0 <= nodes <= MAX_NODES + 1
                or (events and (helper_pid != events[-1]["helperPid"] or uptime < events[-1]["uptimeMs"]))):
            return invalid("invalid_sequence")
        events.append({"nonce": nonce, "helperPid": helper_pid, "sequence": sequence,
                       "stage": match[4], "uptimeMs": uptime, "attempt": attempt, "visitedNodes": nodes})
        index += 2
    return "\n".join(payload).encode("utf-8"), events, "output_limit" if oversized else "valid"


def stage_diagnostics(output: bytes | str | None, nonce: str) -> dict[str, object]:
    """Keep only a bounded validated prefix; never retain arbitrary partial XML."""
    data = output.encode("utf-8", errors="replace") if isinstance(output, str) else output or b""
    _, events, status = _stage_output(data, nonce, partial=True)
    return {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
            "stageStreamStatus": status, "stages": events}


def parse_snapshot(output: bytes, nonce: str, *, previous_uptime_ms: int = -1) -> Snapshot:
    """Reject malformed/stale/oversized output without echoing its UI contents."""
    if len(output) > MAX_OUTPUT_BYTES or re.fullmatch(r"[a-f0-9]{32}", nonce) is None:
        raise ObserverIntegrityFailure("native observer output or request is invalid")
    output, _, _ = _stage_output(output, nonce)
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

    def production_pid(self, *, deadline: float | None = None) -> str:
        pid = self.adb.run("shell", "pidof", PACKAGE, check=False,
                           timeout=remaining_timeout(deadline)).stdout.decode(
            "ascii", errors="replace").strip()
        remaining_timeout(deadline)
        if re.fullmatch(r"[0-9]+", pid) is None:
            raise ObserverIntegrityFailure("native UI capture requires exactly one live application process")
        return pid

    def _instrument(self, nonce: str, *, deadline: float) -> subprocess.CompletedProcess:
        return collect_instrumentation(self.adb.prefix + [
            "shell", "am", "instrument", "-w", "-r", "-e", "nonce", nonce,
            "-e", "expectedPackage", PACKAGE, COMPONENT], nonce, deadline=deadline)

    def observe(self, *, deadline: float | None = None) -> tuple[str, str]:
        if not self.installed:
            raise ObserverIntegrityFailure("native UI observer has not been installed and verified")
        nonce = secrets.token_hex(16)
        started = time.monotonic()
        deadline = min(started + TOTAL_TIMEOUT_SECONDS,
                       deadline if deadline is not None else float("inf"))
        evidence: dict[str, object] = {"status": "failure", "requestNonce": nonce,
                                      "startedAtMonotonic": started, "deadlineAtMonotonic": deadline,
                                      "startupTimeoutSeconds": STARTUP_TIMEOUT_SECONDS,
                                      "captureTimeoutSeconds": CAPTURE_TIMEOUT_SECONDS,
                                      "resultTimeoutSeconds": RESULT_TIMEOUT_SECONDS}
        stage = "application_pid_before"
        try:
            before_pid = self.production_pid(deadline=deadline)
            evidence["applicationPid"] = int(before_pid)
            stage = "instrumentation"
            try:
                result = self._instrument(nonce, deadline=deadline)
            except (subprocess.TimeoutExpired, ObserverIntegrityFailure) as error:
                evidence["instrumentationProgress"] = stage_diagnostics(getattr(error, "output", None), nonce)
                evidence["instrumentationStderr"] = stage_diagnostics(getattr(error, "stderr", None), nonce)
                if isinstance(error, subprocess.TimeoutExpired):
                    evidence["timeoutPhase"] = getattr(error, "phase", "instrumentation")
                # Stop only our independently installed helper, never the app.
                self.adb.run("shell", "am", "force-stop", OBSERVER_PACKAGE, timeout=10)
                if self.production_pid() != before_pid:
                    raise ObserverIntegrityFailure("application process changed during timed-out native UI capture")
                raise
            evidence["stdoutBytes"] = len(result.stdout)
            evidence["stdoutSha256"] = hashlib.sha256(result.stdout).hexdigest()
            evidence["instrumentationProgress"] = stage_diagnostics(result.stdout, nonce)
            stage = "window"
            window = self.adb.run("shell", "dumpsys", "window", "displays",
                                  timeout=remaining_timeout(deadline)).stdout.decode(
                "utf-8", errors="replace")
            remaining_timeout(deadline)
            focuses = re.findall(r"mCurrentFocus=([^\r\n]+)", window)
            evidence["window"] = {
                "bytes": len(window.encode("utf-8")), "sha256": hashlib.sha256(window.encode()).hexdigest(),
                "focusedWindowCount": len(focuses),
                "applicationFocused": len(focuses) == 1 and re.search(
                    rf"\b{re.escape(PACKAGE)}/[^\s}}]+", focuses[0]) is not None,
            }
            stage = "application_pid_after"
            after_pid = self.production_pid(deadline=deadline)
            evidence["applicationPidAfter"] = int(after_pid)
            if after_pid != before_pid:
                raise ObserverIntegrityFailure("application process changed during native UI capture")
            stage = "response"
            snapshot = parse_snapshot(result.stdout, nonce, previous_uptime_ms=self.previous_uptime_ms)
            remaining_timeout(deadline)
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
