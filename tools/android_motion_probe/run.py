#!/usr/bin/env python3
"""Compare native screen capture with two active AVDs and one active tablet."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import select
import subprocess
import threading
import time

from tools.android_install.runner import RuntimeFailure
from tools.android_lifecycle_runtime.run import Runner, button, playback
from tools.incoming_media_runtime.run import nodes


BIT_RATE = 3_000_000
TABLET_SIZE = (960, 600)
PHONE_SIZE = (432, 960)
SEEK_SECOND = 10
MAX_SECONDS = 40


def command(arguments: list[str], *, timeout: float = 30) -> subprocess.CompletedProcess[str]:
    return subprocess.run(arguments, text=True, capture_output=True, timeout=timeout, check=True)


def device_elapsed(adb) -> float:
    value = adb.run("exec-out", "cat", "/proc/uptime", timeout=5).stdout.decode("ascii")
    return float(value.split()[0])


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def frame_times(path: Path) -> list[float]:
    result = command(["ffprobe", "-v", "error", "-select_streams", "v:0",
                      "-show_entries", "frame=best_effort_timestamp_time",
                      "-of", "csv=p=0", str(path)], timeout=45)
    values = [float(line.strip()) for line in result.stdout.splitlines() if line.strip()]
    if (len(values) < 2 or any(not math.isfinite(value) for value in values)
            or any(right <= left for left, right in zip(values, values[1:]))):
        raise RuntimeFailure("original recording has fewer than two strictly ordered video frames")
    return values


def file_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="ascii", errors="replace").strip()
    except OSError:
        return None


def proc_snapshot(pid: int) -> dict[str, object]:
    stat = file_text(Path(f"/proc/{pid}/stat"))
    status = file_text(Path(f"/proc/{pid}/status"))
    if stat is None:
        return {"pid": pid, "alive": False}
    tail = stat.rsplit(") ", 1)[-1].split()
    rss = next((line.split(":", 1)[1].strip() for line in (status or "").splitlines()
                if line.startswith("VmRSS:")), None)
    return {"pid": pid, "alive": True, "utimeTicks": int(tail[11]),
            "stimeTicks": int(tail[12]), "rss": rss}


class HostSampler:
    def __init__(self, output: Path, pids: dict[str, int]):
        self.output, self.pids = output, pids
        self.stop_event = threading.Event()
        self.ready_event = threading.Event()
        self.error: Exception | None = None
        self.thread: threading.Thread | None = None

    def start(self) -> None:
        self.output.parent.mkdir(parents=True, exist_ok=True)
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()
        if not self.ready_event.wait(3) or self.error is not None:
            raise RuntimeFailure("host resource sampler failed before its first sample")

    def _run(self) -> None:
        try:
            with self.output.open("w", encoding="utf-8") as stream:
                while not self.stop_event.is_set():
                    stat = file_text(Path("/proc/stat"))
                    row = {"monotonic": time.monotonic(), "utcNs": time.time_ns(),
                           "hostCpu": stat.splitlines()[0] if stat else None,
                           "pressure": {name: file_text(Path(f"/proc/pressure/{name}"))
                                        for name in ("cpu", "memory", "io")},
                           "cgroup": {name: file_text(Path(f"/sys/fs/cgroup/{name}"))
                                      for name in ("cpu.max", "cpu.stat", "memory.current", "memory.max")},
                           "processes": {name: proc_snapshot(pid) for name, pid in self.pids.items()}}
                    stream.write(json.dumps(row, separators=(",", ":")) + "\n")
                    stream.flush()
                    self.ready_event.set()
                    self.stop_event.wait(1)
        except Exception as error:
            self.error = error
            self.ready_event.set()

    def stop(self) -> None:
        self.stop_event.set()
        if self.thread is not None:
            self.thread.join(timeout=3)
            if self.thread.is_alive():
                raise RuntimeFailure("host resource sampler did not stop")
        if self.error is not None:
            raise RuntimeFailure("host resource sampler failed") from self.error


class Recording:
    def __init__(self, runner: Runner, output: Path, size: tuple[int, int]):
        self.runner, self.output, self.size = runner, output, size
        self.remote = runner.adb.remote_prefix + output.name
        self.process: subprocess.Popen[str] | None = None
        self.pid: str | None = None
        self.receipt: dict[str, object] = {"file": output.name, "size": list(size),
                                          "bitRate": BIT_RATE, "status": "not-started"}

    def start(self) -> None:
        adb = self.runner.adb
        if not re.fullmatch(r"emulator-\d+", adb.serial):
            raise RuntimeFailure("native recording needs an explicit emulator serial")
        if adb.run("shell", "getprop", "ro.kernel.qemu").stdout.strip() != b"1":
            raise RuntimeFailure("native recording needs an emulator")
        if adb.run("shell", "pidof", "screenrecord", check=False).stdout.strip():
            raise RuntimeFailure("refusing to replace a pre-existing native recorder")
        if not self.remote.startswith(adb.remote_prefix) or not re.fullmatch(r"[A-Za-z0-9-]+\.mp4", self.output.name):
            raise RuntimeFailure("recording path is not task-owned")
        self.output.parent.mkdir(parents=True, exist_ok=True)
        adb.remote_files.append(self.remote)
        width, height = self.size
        script = (f"screenrecord --size {width}x{height} --bit-rate {BIT_RATE} --time-limit 120 {self.remote} & "
                  "record_pid=$!; echo MOTION_RECORDER_PID=$record_pid; wait $record_pid")
        self.receipt["startedAtDeviceElapsed"] = device_elapsed(adb)
        self.receipt["startedAtMonotonic"] = time.monotonic()
        self.process = subprocess.Popen(adb.prefix + ["shell", script], stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT, text=True, bufsize=1)
        assert self.process.stdout is not None
        ready, _, _ = select.select([self.process.stdout], [], [], 12)
        if not ready:
            raise RuntimeFailure("native recorder did not report its owned PID")
        match = re.fullmatch(r"MOTION_RECORDER_PID=(\d+)", self.process.stdout.readline().strip())
        if match is None:
            raise RuntimeFailure("native recorder PID receipt is invalid")
        self.pid = match[1]
        deadline = time.monotonic() + 12
        while time.monotonic() < deadline:
            actual = adb.run("shell", "pidof", "screenrecord", check=False, timeout=3).stdout.decode().strip()
            if actual == self.pid:
                self.receipt.update({"pid": int(self.pid), "status": "recording"})
                return
            if actual and actual != self.pid:
                raise RuntimeFailure("an unowned native recorder appeared")
            time.sleep(0.2)
        raise RuntimeFailure("native recorder ownership did not become stable")

    def request_stop(self) -> None:
        if self.process is None or self.pid is None:
            raise RuntimeFailure("recording never started")
        adb = self.runner.adb
        self.receipt["stopRequestedAtDeviceElapsed"] = device_elapsed(adb)
        self.receipt["stopRequestedAtMonotonic"] = time.monotonic()
        actual = adb.run("shell", "pidof", "screenrecord", check=False, timeout=5).stdout.decode().strip()
        if actual != self.pid:
            raise RuntimeFailure("owned recorder exited or changed before stop")
        cmdline = adb.run("exec-out", "cat", f"/proc/{self.pid}/cmdline", timeout=5).stdout.decode(
            "utf-8", errors="replace").split("\0")
        if cmdline[0].rsplit("/", 1)[-1] != "screenrecord" or self.remote not in cmdline:
            raise RuntimeFailure("native recorder command no longer owns the exact output path")
        adb.run("shell", f"kill -2 {self.pid}", timeout=5)

    def wait_stopped(self) -> None:
        if self.process is None or self.pid is None:
            raise RuntimeFailure("recording never started")
        try:
            stdout, _ = self.process.communicate(timeout=15)
        except subprocess.TimeoutExpired as error:
            raise RuntimeFailure("native recorder failed to finalize") from error
        self.receipt.update({"wrapperExit": self.process.returncode, "wrapperOutput": stdout[:2048]})
        if self.process.returncode != 0:
            raise RuntimeFailure("native recorder exited unsuccessfully")

    def analyze(self) -> dict[str, object]:
        if self.process is None or self.process.poll() != 0:
            raise RuntimeFailure("native recorder was not finalized successfully")
        adb = self.runner.adb
        remote_size = adb.run("exec-out", "stat", "-c", "%s", self.remote, timeout=5).stdout.decode().strip()
        hash_output = adb.run("exec-out", "sha256sum", self.remote, timeout=5).stdout.decode().strip()
        match = re.fullmatch(rf"([0-9a-f]{{64}})  {re.escape(self.remote)}", hash_output)
        if not remote_size.isdecimal() or not 0 < int(remote_size) <= 64 * 1024 * 1024 or match is None:
            raise RuntimeFailure("native recording receipt is invalid")
        remote_hash = match[1]
        adb.run("pull", self.remote, str(self.output), timeout=45)
        if self.output.stat().st_size != int(remote_size) or sha256(self.output) != remote_hash:
            raise RuntimeFailure("pulled recording differs from the device original")
        decode = subprocess.run(["ffmpeg", "-v", "error", "-xerror", "-i", str(self.output),
                                 "-f", "null", "-"], text=True, capture_output=True, timeout=90)
        self.output.with_suffix(".decode.log").write_text(decode.stderr[:8192], encoding="utf-8")
        if decode.returncode != 0:
            raise RuntimeFailure("original recording failed a full decode")
        stream_probe = command(["ffprobe", "-v", "error", "-select_streams", "v:0",
                                "-show_entries", "stream=codec_name,width,height:format=duration",
                                "-of", "json", str(self.output)], timeout=15)
        details = json.loads(stream_probe.stdout)
        streams = details.get("streams", [])
        if (len(streams) != 1 or streams[0].get("codec_name") != "h264"
                or (streams[0].get("width"), streams[0].get("height")) != self.size):
            raise RuntimeFailure("original recording codec or dimensions differ from the fixed capture")
        times = frame_times(self.output)
        self.receipt.update({"status": "verified", "bytes": int(remote_size), "sha256": remote_hash,
                             "fullDecodeExitCode": 0,
                             "frameCount": len(times), "firstPts": times[0], "lastPts": times[-1],
                             "pictureSpanSeconds": times[-1] - times[0],
                             "durationSeconds": float(details["format"]["duration"]),
                             "maxFrameGapSeconds": max(right - left for left, right in zip(times, times[1:])),
                             "framePtsFile": self.output.with_suffix(".pts.json").name})
        self.output.with_suffix(".pts.json").write_text(json.dumps(times), encoding="utf-8")
        return self.receipt

    def retain_partial(self) -> None:
        """Keep the exact task-owned device file when strict verification fails."""
        if self.output.exists() or not self.remote.startswith(self.runner.adb.remote_prefix):
            return
        partial = self.output.with_suffix(".partial.mp4")
        try:
            result = self.runner.adb.run("pull", self.remote, str(partial), timeout=15, check=False)
            if result.returncode == 0 and partial.is_file():
                self.receipt["partial"] = {"file": partial.name, "bytes": partial.stat().st_size,
                                           "sha256": sha256(partial), "accepted": False}
        except (OSError, subprocess.TimeoutExpired, RuntimeFailure):
            self.receipt["partial"] = {"status": "unavailable"}


def seek_to_start(runner: Runner, phase: str) -> tuple[dict[str, object], str]:
    xml, state = runner.wait(phase + "-player", playback)
    if state.playing:
        runner.tap(button(xml, "Pause", "Pause together"))
        xml, _ = runner.sample(phase + "-paused", playing=False)
    bars = [node for node in nodes(xml) if node.get("class", "").endswith("SeekBar")]
    if len(bars) != 1:
        raise RuntimeFailure("expected one native player seek bar")
    match = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bars[0].get("bounds", ""))
    if match is None:
        raise RuntimeFailure("native seek bar has no bounds")
    left, top, right, bottom = map(int, match.groups())
    x = left + round((right - left) * SEEK_SECOND / 90)
    runner.adb.run("shell", "input", "tap", str(x), str((top + bottom) // 2))
    xml, state = runner.wait(phase + "-seeked", lambda value: checked_seek(value))
    return {"seekedPosition": state.position_seconds, "appPid": runner.pid()}, xml


def checked_seek(xml: str):
    state = playback(xml)
    if state.playing or not 7 <= state.position_seconds <= 13:
        raise RuntimeFailure("native seek did not return to the same Bee interval")
    return state


def verify_owned_avd(adb, avd_name: str, host_pid: int, role: str) -> None:
    if role not in {"phone", "tablet"} or not re.fullmatch(rf"meowwatch_{role}_[A-Za-z0-9_]+", avd_name):
        raise RuntimeFailure("AVD name is not task-owned")
    observed = [line.strip() for line in adb.run("emu", "avd", "name").stdout.decode().splitlines()
                if line.strip() and line.strip() != "OK"]
    if (observed != [avd_name] or adb.run("shell", "getprop", "ro.kernel.qemu").stdout.strip() != b"1"
            or adb.run("shell", "getprop", "ro.build.version.sdk").stdout.strip() != b"35"):
        raise RuntimeFailure("AVD identity or API changed")
    cmdline = Path(f"/proc/{host_pid}/cmdline").read_bytes().split(b"\0")
    if b"-avd" not in cmdline or cmdline[cmdline.index(b"-avd") + 1] != avd_name.encode():
        raise RuntimeFailure("emulator process PID is not the owned AVD")


def phase(name: str, runners: dict[str, Runner], output: Path, seconds: int,
          host_pids: dict[str, int]) -> dict[str, object]:
    (output / name).mkdir(parents=True, exist_ok=True)
    active = {key: runner for key, runner in runners.items() if key in ({"phone", "tablet"} if name == "A" else {"tablet"})}
    seeked = {key: seek_to_start(runner, f"{name}-{key}") for key, runner in active.items()}
    preparations = {key: receipt for key, (receipt, _) in seeked.items()}
    for key, runner in active.items():
        preparations[key]["playTapBeforeDeviceElapsed"] = device_elapsed(runner.adb)
        preparations[key]["playTapBeforeMonotonic"] = time.monotonic()
        runner.tap(button(seeked[key][1], "Play", "Play together"))
        preparations[key]["playTapAfterDeviceElapsed"] = device_elapsed(runner.adb)
        preparations[key]["playTapAfterMonotonic"] = time.monotonic()
    for key, runner in active.items():
        preparations[key]["playingObservationBeforeDeviceElapsed"] = device_elapsed(runner.adb)
        _, state = runner.sample(f"{name}-{key}-playing", playing=True, screenshot=False)
        preparations[key]["playingObservedAtDeviceElapsed"] = device_elapsed(runner.adb)
        preparations[key]["playingObservedAtMonotonic"] = time.monotonic()
        preparations[key]["playingPosition"] = state.position_seconds
    recordings = {key: Recording(runner, output / name / f"{key}.mp4",
                                 PHONE_SIZE if key == "phone" else TABLET_SIZE)
                  for key, runner in active.items()}
    sampler = HostSampler(output / name / "host-1hz.jsonl", host_pids)
    receipts: dict[str, object] = {"name": name, "preparations": preparations, "recordings": {}}
    stop_errors: dict[str, str] = {}
    try:
        for key, runner in active.items():
            runner.output.joinpath(f"{name}-before.png").write_bytes(runner.adb.screenshot())
        sampler.start()
        for recording in recordings.values():
            recording.start()
        receipts["measurementStartMonotonic"] = time.monotonic()
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if any(rec.process is None or rec.process.poll() is not None for rec in recordings.values()):
                raise RuntimeFailure("native recorder exited during bounded playback window")
            time.sleep(max(0, min(0.5, deadline - time.monotonic())))
        receipts["measurementEndMonotonic"] = time.monotonic()
    finally:
        # End both device loads before waiting on either recorder or doing any
        # offline transfer/decoding. A second recorder must not keep running
        # while the first device's artifact is being inspected.
        for key, recording in recordings.items():
            try:
                recording.request_stop()
            except Exception as error:
                stop_errors[key] = type(error).__name__ + ": " + str(error)
        try:
            sampler.stop()
            with sampler.output.open(encoding="utf-8") as samples:
                receipts["hostSamples"] = sum(1 for _ in samples)
            if receipts["hostSamples"] < seconds // 2:
                raise RuntimeFailure("host resource sampling did not cover the playback window")
        except Exception as error:
            receipts["hostSamplerError"] = type(error).__name__ + ": " + str(error)
        for key, runner in active.items():
            try:
                observation_before = device_elapsed(runner.adb)
                # One bounded native observation records the state at the
                # capture boundary. Polling for a later Playing state could
                # turn an EOF or pause into an apparently successful sample.
                xml = runner.observe(deadline=time.monotonic() + 10)
                state = playback(xml)
                runner.output.joinpath(f"{name}-{key}-after.xml").write_text(xml, encoding="utf-8")
                receipts.setdefault("after", {})[key] = {
                    "observationBeforeDeviceElapsed": observation_before,
                    "observedAtDeviceElapsed": device_elapsed(runner.adb),
                    "observedAtMonotonic": time.monotonic(),
                    "playing": state.playing,
                    "positionSeconds": state.position_seconds,
                    "appPid": runner.pid(),
                }
            except Exception as error:
                receipts.setdefault("afterErrors", {})[key] = type(error).__name__ + ": " + str(error)
        for key, runner in active.items():
            try:
                runner.output.joinpath(f"{name}-after.png").write_bytes(runner.adb.screenshot())
            except Exception as error:
                receipts.setdefault("afterScreenshotErrors", {})[key] = type(error).__name__ + ": " + str(error)
        for key, recording in recordings.items():
            if key in stop_errors:
                continue
            try:
                recording.wait_stopped()
            except Exception as error:
                stop_errors[key] = type(error).__name__ + ": " + str(error)
        for key, recording in recordings.items():
            if key in stop_errors:
                recording.retain_partial()
                receipts["recordings"][key] = {**recording.receipt, "error": stop_errors[key]}
                continue
            try:
                receipts["recordings"][key] = recording.analyze()
            except Exception as error:
                recording.retain_partial()
                receipts["recordings"][key] = {**recording.receipt, "error": type(error).__name__ + ": " + str(error)}
        (output / name / "result.json").write_text(json.dumps(receipts, indent=2), encoding="utf-8")
    if any(row.get("status") != "verified" for row in receipts["recordings"].values()):
        raise RuntimeFailure(f"phase {name} native recording was not verified")
    if any(row["pictureSpanSeconds"] < seconds - 3 for row in receipts["recordings"].values()):
        raise RuntimeFailure(f"phase {name} original frames do not cover the bounded playback window")
    if "hostSamplerError" in receipts:
        raise RuntimeFailure(f"phase {name} host resource sampler failed")
    if "afterErrors" in receipts:
        raise RuntimeFailure(f"phase {name} native playback state was not verified at the window end")
    if "afterScreenshotErrors" in receipts:
        raise RuntimeFailure(f"phase {name} original end screenshots were not retained")
    for key in active:
        if not receipts["after"][key]["playing"]:
            raise RuntimeFailure(f"phase {name} {key} was not playing at the capture boundary")
        if receipts["after"][key]["positionSeconds"] < int(preparations[key]["playingPosition"]) + seconds // 2:
            raise RuntimeFailure(f"phase {name} {key} native playback did not advance")
    (output / name / "result.json").write_text(json.dumps(receipts, indent=2), encoding="utf-8")
    return receipts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--phone-serial", required=True)
    parser.add_argument("--tablet-serial", required=True)
    parser.add_argument("--phone-avd", required=True)
    parser.add_argument("--tablet-avd", required=True)
    parser.add_argument("--phone-emulator-pid", type=int, required=True)
    parser.add_argument("--tablet-emulator-pid", type=int, required=True)
    parser.add_argument("--seconds", type=int, default=30)
    args = parser.parse_args()
    if not 20 <= args.seconds <= MAX_SECONDS or args.output.exists() and any(args.output.iterdir()):
        parser.error("duration must be 20–40 seconds and output must start empty")
    args.output.mkdir(parents=True, exist_ok=True)
    report: dict[str, object] = {"completed": False, "diagnosticOnly": True,
                                 "boundary": "Local-player native motion probe; not Together Session acceptance",
                                 "comparisonBoundary": (
                                     "Both phases target the 10-second Bee interval, but the two Play taps, "
                                     "native observations, screenshots and recorder starts are sequential. "
                                     "Device uptime bounds each capture and original frame PTS gives "
                                     "within-recording spacing; these do not establish exact cross-device "
                                     "source-frame alignment."),
                                 "apkSha256": sha256(args.apk), "fixtureSha256": sha256(args.fixture),
                                 "host": {"cpuCount": os.cpu_count(),
                                          "affinityCount": len(os.sched_getaffinity(0)),
                                          "cpuMax": file_text(Path("/sys/fs/cgroup/cpu.max")),
                                          "memoryMax": file_text(Path("/sys/fs/cgroup/memory.max"))},
                                 "phases": {}}
    runners = {"phone": Runner(args.phone_serial, args.apk, args.fixture, args.output / "phone-ui"),
               "tablet": Runner(args.tablet_serial, args.apk, args.fixture, args.output / "tablet-ui")}
    phone_closed = False
    try:
        verify_owned_avd(runners["phone"].adb, args.phone_avd, args.phone_emulator_pid, "phone")
        verify_owned_avd(runners["tablet"].adb, args.tablet_avd, args.tablet_emulator_pid, "tablet")
        for key, runner in runners.items():
            report.setdefault("devices", {})[key] = runner.prepare()
            report["devices"][key]["wmSize"] = runner.adb.run("shell", "wm", "size").stdout.decode().strip()
            report["devices"][key]["wmDensity"] = runner.adb.run("shell", "wm", "density").stdout.decode().strip()
            runner.load_fixture()
            runner.sample(f"{key}-loaded", playing=False)
        host_pids = {"phoneEmulator": args.phone_emulator_pid,
                     "tabletEmulator": args.tablet_emulator_pid}
        report["phases"]["A"] = phase("A", runners, args.output, args.seconds, host_pids)
        runners["phone"].cleanup()
        verify_owned_avd(runners["phone"].adb, args.phone_avd, args.phone_emulator_pid, "phone")
        runners["phone"].adb.run("emu", "kill", timeout=10)
        phone_closed = True
        deadline = time.monotonic() + 15
        while Path(f"/proc/{args.phone_emulator_pid}").exists() and time.monotonic() < deadline:
            time.sleep(0.2)
        if Path(f"/proc/{args.phone_emulator_pid}").exists():
            raise RuntimeFailure("owned phone AVD did not stop before isolated tablet phase")
        verify_owned_avd(runners["tablet"].adb, args.tablet_avd, args.tablet_emulator_pid, "tablet")
        if runners["tablet"].pid() != report["phases"]["A"]["after"]["tablet"]["appPid"]:
            raise RuntimeFailure("tablet app process changed before the isolated phase")
        time.sleep(3)
        report["phases"]["B"] = phase("B", runners, args.output, args.seconds, host_pids)
        if (report["phases"]["B"]["after"]["tablet"]["appPid"]
                != report["phases"]["A"]["after"]["tablet"]["appPid"]):
            raise RuntimeFailure("tablet app process changed between comparison phases")
        report["completed"] = True
    except Exception as error:
        report["error"] = type(error).__name__ + ": " + str(error)
        raise
    finally:
        args.output.joinpath("result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        for key, runner in runners.items():
            if key == "phone" and phone_closed:
                continue
            try:
                runner.cleanup()
            except Exception as error:
                args.output.joinpath(f"{key}-cleanup-error.txt").write_text(str(error), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
