"""Real loopback HTTP and Linux process-ownership contracts; no Android tools."""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
import http.client
import io
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest

from tools.android_multi_device import fixture_server as fixture


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "tools/android_multi_device"
PAYLOAD = bytes(range(251)) * 4096


class FixtureHttpTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name).resolve()
        for name in fixture.ASSETS:
            (self.directory / name).write_bytes(PAYLOAD)
        (self.directory / "private.txt").write_text("never serve this file")
        self.log = io.StringIO()
        self.server = fixture.FixtureServer(self.directory, 0, log=self.log)
        self.worker = threading.Thread(target=self.server.serve_forever,
                                       kwargs={"poll_interval": 0.01}, daemon=True)
        self.worker.start()
        self.addCleanup(self.stop_server)
        self.port = self.server.server_port

    def stop_server(self):
        self.server.shutdown()
        self.server.server_close()
        self.worker.join(timeout=2)
        self.assertFalse(self.worker.is_alive())

    def request(self, path="/Bee.mp4", *, method="GET", headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=3)
        try:
            connection.request(method, path, headers=headers or {})
            response = connection.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            connection.close()

    def rows(self, count):
        until = time.monotonic() + 2
        while time.monotonic() < until:
            rows = [json.loads(line) for line in self.log.getvalue().splitlines()]
            if len(rows) >= count:
                return rows
            time.sleep(0.005)
        self.fail(f"request diagnostics missing: expected {count}")

    def test_full_get_and_head_for_both_fixed_names(self):
        self.assertEqual(self.server.server_address[0], "127.0.0.1")
        for name in fixture.ASSETS:
            for method in ("GET", "HEAD"):
                with self.subTest(name=name, method=method):
                    status, headers, body = self.request(f"/{name}", method=method)
                    self.assertEqual(status, 200)
                    self.assertEqual(headers["Accept-Ranges"], "bytes")
                    self.assertEqual(headers["Content-Type"], "video/mp4")
                    self.assertEqual(int(headers["Content-Length"]), len(PAYLOAD))
                    self.assertNotIn("Content-Range", headers)
                    self.assertEqual(body, PAYLOAD if method == "GET" else b"")

    def test_real_seek_ranges_return_only_requested_bytes(self):
        cases = (
            ("bytes=500001-530004", 500001, 530004),
            ("bytes=1000000-", 1000000, len(PAYLOAD) - 1),
            ("bytes=-789", len(PAYLOAD) - 789, len(PAYLOAD) - 1),
            ("bytes=0-0", 0, 0),
            ("bytes=1000000-999999999", 1000000, len(PAYLOAD) - 1),
            ("bytes=-999999999", 0, len(PAYLOAD) - 1),
        )
        for header, first, last in cases:
            with self.subTest(header=header):
                status, headers, body = self.request(headers={"Range": header})
                self.assertEqual(status, 206)
                self.assertEqual(headers["Content-Range"], f"bytes {first}-{last}/{len(PAYLOAD)}")
                self.assertEqual(int(headers["Content-Length"]), last - first + 1)
                self.assertEqual(body, PAYLOAD[first:last + 1])

    def test_head_ignores_range_and_returns_full_metadata_without_body(self):
        status, headers, body = self.request(method="HEAD", headers={"Range": "bytes=99-101"})
        self.assertEqual(status, 200)
        self.assertEqual(int(headers["Content-Length"]), len(PAYLOAD))
        self.assertNotIn("Content-Range", headers)
        self.assertEqual(body, b"")

    def test_unsatisfied_malformed_and_multiple_ranges_return_416(self):
        for value in (f"bytes={len(PAYLOAD)}-", "bytes=9-2", "bytes=-0", "bytes=-",
                      "bytes=0-3,8-10", "bytes=" + "9" * 81,
                      "private-value", "bytes=abc-def"):
            with self.subTest(value=value):
                status, headers, body = self.request(headers={"Range": value})
                self.assertEqual(status, 416)
                self.assertEqual(headers["Content-Range"], f"bytes */{len(PAYLOAD)}")
                self.assertEqual(headers["Content-Length"], "0")
                self.assertEqual(body, b"")
        self.assertNotIn("private-value", self.log.getvalue())

    def test_unknown_units_and_stale_if_range_return_the_full_object(self):
        for headers in ({"Range": "items=1-2"},
                        {"Range": "bytes=10-20", "If-Range": '"unknown-etag"'}):
            status, response_headers, body = self.request(headers=headers)
            self.assertEqual((status, body), (200, PAYLOAD))
            self.assertNotIn("Content-Range", response_headers)
        old = time.time() - 120
        os.utime(self.directory / "Bee.mp4", (old, old))
        _, headers, _ = self.request(method="HEAD")
        status, _, body = self.request(headers={"Range": "bytes=10-20",
                                               "If-Range": headers["Last-Modified"]})
        self.assertEqual((status, body), (206, PAYLOAD[10:21]))

    def test_duplicate_range_headers_do_not_select_an_ambiguous_range(self):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=3)
        try:
            connection.putrequest("GET", "/Bee.mp4")
            connection.putheader("Range", "bytes=0-3")
            connection.putheader("Range", "bytes=20-30")
            connection.endheaders()
            response = connection.getresponse()
            self.assertEqual(response.status, 416)
            self.assertEqual(response.read(), b"")
        finally:
            connection.close()

    def test_query_alias_works_but_query_and_unknown_path_never_leak(self):
        status, _, body = self.request("/Bee.mp4?shared=private-value",
                                       headers={"Range": "bytes=10-20"})
        self.assertEqual((status, body), (206, PAYLOAD[10:21]))
        status, _, body = self.request("/missing-private-value.mp4?secret=private-value")
        self.assertEqual((status, body), (404, b""))
        rows = self.rows(2)
        self.assertEqual(rows[0]["asset"], "Bee.mp4")
        self.assertEqual(rows[0]["bytes"], 11)
        self.assertGreaterEqual(rows[0]["elapsed_ms"], 0)
        self.assertEqual(rows[1]["asset"], "unmatched")
        self.assertNotIn("private-value", self.log.getvalue())

    def test_no_directory_listing_traversal_other_files_or_absolute_targets(self):
        for path in ("/", "/private.txt", "/../private.txt", "/%2e%2e/private.txt",
                     "/folder/../Bee.mp4", "/%42ee.mp4", "/Bee.mp4/extra",
                     "http://example.test/Bee.mp4"):
            with self.subTest(path=path):
                self.assertEqual(self.request(path)[::2], (404, b""))

    def test_missing_alias_remains_404_while_canonical_works(self):
        (self.directory / "Bee.mp4").unlink()
        self.assertEqual(self.request()[0], 404)
        self.assertEqual(self.request("/sync-fixture.mp4", method="HEAD")[0], 200)

    def test_symlink_alias_cannot_expose_even_an_in_directory_file(self):
        alias = self.directory / "Bee.mp4"
        alias.unlink()
        try:
            alias.symlink_to(self.directory / "private.txt")
        except OSError as error:
            self.skipTest(f"symlinks unavailable: {type(error).__name__}")
        self.assertEqual(self.request()[0], 404)
        with self.assertRaises(ValueError):
            fixture.FixtureServer(self.directory, 0, log=self.log)

    def test_simultaneous_nonzero_ranges_have_independent_file_positions(self):
        def fetch(start):
            status, headers, body = self.request(headers={"Range": f"bytes={start}-{start + 90000}"})
            self.assertEqual(status, 206)
            self.assertEqual(len(body), int(headers["Content-Length"]))
            self.assertEqual(body, PAYLOAD[start:start + 90001])

        with ThreadPoolExecutor(max_workers=6) as executor:
            list(executor.map(fetch, (17, 777, 89000, 256789, 450003, 789111)))

    def test_aborted_large_download_does_not_block_another_client(self):
        with (self.directory / "Bee.mp4").open("ab") as media:
            media.truncate(32 * 1024 * 1024)
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=3)
        connection.request("GET", "/Bee.mp4")
        response = connection.getresponse()
        self.assertEqual(response.status, 200)
        self.assertEqual(response.read(1024), PAYLOAD[:1024])
        # A second native player must not wait behind a stalled first reader.
        status, _, body = self.request("/sync-fixture.mp4", headers={"Range": "bytes=300000-300999"})
        self.assertEqual((status, body), (206, PAYLOAD[300000:301000]))
        response.close()
        connection.close()
        rows = self.rows(2)
        cancelled = [row for row in rows if row["asset"] == "Bee.mp4"]
        self.assertEqual(len(cancelled), 1)
        self.assertEqual(cancelled[0]["outcome"], "cancelled")
        self.assertLess(cancelled[0]["bytes"], 32 * 1024 * 1024)
        self.assertEqual(self.request(method="HEAD")[0], 200)

    def test_real_socket_write_timeout_is_not_reported_as_peer_cancellation(self):
        self.assertIsNone(fixture.FixtureHandler.timeout)

        class TestTimeoutHandler(fixture.FixtureHandler):
            def setup(self):
                super().setup()
                # Only this test imposes a short timeout to exercise the OS error.
                self.connection.settimeout(0.05)
                self.connection.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 4096)

        self.server.RequestHandlerClass = TestTimeoutHandler
        with (self.directory / "Bee.mp4").open("ab") as media:
            media.truncate(32 * 1024 * 1024)
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=3)
        response = None
        try:
            connection.request("GET", "/Bee.mp4")
            response = connection.getresponse()
            self.assertEqual(response.read(1024), PAYLOAD[:1024])
            row = self.rows(1)[0]  # Keep the peer open, but stop consuming its body.
            self.assertEqual(row["outcome"], "timeout")
            self.assertEqual(row["status"], 200)
            self.assertLess(row["bytes"], 32 * 1024 * 1024)
        finally:
            if response is not None:
                response.close()
            connection.close()

    def test_real_header_timeout_retains_a_distinct_pre_response_record(self):
        class TestTimeoutHandler(fixture.FixtureHandler):
            def setup(self):
                super().setup()
                self.connection.settimeout(0.05)

        self.server.RequestHandlerClass = TestTimeoutHandler
        with socket.create_connection(("127.0.0.1", self.port), timeout=3) as client:
            # Incomplete headers make BaseHTTPRequestHandler itself catch the
            # actual socket timeout, before any response status has been sent.
            client.sendall(b"GET /Bee.mp4?private-value HTTP/1.1\r\nHost: localhost\r\n")
            row = self.rows(1)[0]
            self.assertEqual(row["outcome"], "timeout")
            self.assertEqual(row["status"], 0)
            self.assertEqual(row["bytes"], 0)
        self.assertNotIn("private-value", self.log.getvalue())

    def test_diagnostic_volume_is_bounded_with_an_explicit_limit_record(self):
        self.server.max_log_records = 2
        for _ in range(6):
            self.assertEqual(self.request(method="HEAD")[0], 200)
        rows = self.rows(3)
        self.assertEqual(len(rows), 3)
        self.assertEqual(rows[-1], {"event": "request_log_limit", "limit": 2})


class ProcessIdentityTests(unittest.TestCase):
    def test_exact_command_and_birth_token_reject_reused_or_other_processes(self):
        with tempfile.TemporaryDirectory() as directory:
            proc = Path(directory)
            entry = proc / "4242"
            entry.mkdir()
            args = ["/usr/bin/python3", str(Path(fixture.__file__).resolve()),
                    "--directory", str(proc.resolve()), "--port", "18765"]

            def write(arguments, state="S", ticks="912345"):
                (entry / "cmdline").write_bytes(b"\0".join(os.fsencode(a) for a in arguments) + b"\0")
                fields = [state] + ["0"] * 18 + [ticks]
                (entry / "stat").write_text("4242 (python worker) " + " ".join(fields))

            write(args)
            self.assertEqual(fixture.process_identity(4242, proc, 18765, proc=proc), "912345")
            self.assertEqual(fixture.process_identity(4242, proc, 18765, proc=proc,
                                                      parent_pid=0), "912345")
            self.assertIsNone(fixture.process_identity(4242, proc, 18765, proc=proc,
                                                       parent_pid=9999))
            self.assertIsNone(fixture.process_identity(4242, proc, 18766, proc=proc))
            self.assertIsNone(fixture.process_identity(4242, proc / "elsewhere", 18765, proc=proc))
            for wrong in (args + ["--extra"], ["/bin/echo"] + args[1:],
                          [args[0], "different.py"] + args[2:], args[:-1]):
                write(wrong)
                self.assertIsNone(fixture.process_identity(4242, proc, 18765, proc=proc))
            write(args, state="Z")
            self.assertIsNone(fixture.process_identity(4242, proc, 18765, proc=proc))
            write(args, ticks="new-bad-token")
            self.assertIsNone(fixture.process_identity(4242, proc, 18765, proc=proc))


@unittest.skipUnless(sys.platform == "linux", "actual scripts use Linux /proc ownership")
class LinuxLifecycleTests(unittest.TestCase):
    def test_startup_failure_cleanup_never_signals_without_the_original_birth(self):
        # Execute the actual start script. Substitute only its process/HTTP
        # boundary observations and signals so PID reuse is deterministic and
        # this regression can never signal a real unrelated process.
        environment_script = r'''python3() {
  local owner='' token='' parent=''
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --owner-pid) owner="$2"; shift ;;
      --start-ticks) token="$2"; shift ;;
      --parent-pid) parent="$2"; shift ;;
    esac
    shift
  done
  if [[ -z "$owner" ]]; then printf '{"event":"ready"}\n'; return 0; fi
  if [[ -z "$parent" ]]; then return 3; fi
  if [[ -z "$token" ]]; then
    printf 'capture\n' >> "$TASK_TRACE"
    [[ "$TASK_CASE" != missing ]] || return 3
    printf '111\n'
  else
    local actual
    actual="$(cat "$TASK_BIRTH")"
    printf 'check:%s:%s\n' "$token" "$actual" >> "$TASK_TRACE"
    [[ "$token" == "$actual" ]]
  fi
}
curl() {
  local count
  count="$(cat "$TASK_CURL_COUNT")"
  count=$((count + 1))
  printf '%s\n' "$count" > "$TASK_CURL_COUNT"
  printf 'curl\n' >> "$TASK_TRACE"
  if [[ "$TASK_CASE" == startup_failure ||
        ( "$TASK_CASE" == timeout && "$count" -eq 40 ) ]]; then
    printf '222\n' > "$TASK_BIRTH"
  fi
  return 22
}
kill() {
  if [[ "$1" == -0 ]]; then return 0; fi
  printf 'signal:%s\n' "$1" >> "$TASK_TRACE"
  printf 'stopped\n' > "$TASK_BIRTH"
}
sleep() { return 0; }
grep() {
  if [[ "$*" == *'"event":"ready"'* ]]; then return 0; fi
  command grep "$@"
}
'''
        for cause in ("missing", "startup_failure", "timeout", "unchanged"):
            with self.subTest(cause=cause), tempfile.TemporaryDirectory() as temporary:
                directory = Path(temporary)
                canonical = directory / "sync-fixture.mp4"
                canonical.write_bytes(PAYLOAD)
                shell_environment = directory / "boundary.sh"
                shell_environment.write_text(environment_script)
                trace = directory / "trace.txt"
                trace.touch()
                birth = directory / "birth.txt"
                birth.write_text("111\n")
                count = directory / "curl-count.txt"
                count.write_text("0\n")
                environment = dict(os.environ, BASH_ENV=str(shell_environment),
                                   TASK_CASE=cause, TASK_TRACE=str(trace), TASK_BIRTH=str(birth),
                                   TASK_CURL_COUNT=str(count))
                result = subprocess.run([
                    "bash", str(SCRIPTS / "start_fixture_server.sh"),
                    "--fixture", str(canonical), "--state", str(directory / "state")],
                    env=environment, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 4, result.stderr)
                self.assertFalse((directory / "state" / "server.env").exists())
                events = trace.read_text().splitlines()
                signals = [row for row in events if row.startswith("signal:")]
                self.assertEqual(signals, ["signal:-INT"] if cause == "unchanged" else [])
                self.assertEqual(events[0], "capture")
                if cause == "missing":
                    self.assertNotIn("curl", events)
                    self.assertFalse(any(row.startswith("check:") for row in events))
                else:
                    self.assertEqual(events.count("capture"), 1)
                    self.assertTrue(all(row.startswith("check:111:") for row in events
                                        if row.startswith("check:")))
                    self.assertEqual(events.count("curl"), 1 if cause == "startup_failure" else 40)

    def test_real_start_stop_refuses_other_pid_or_changed_birth_token(self):
        with tempfile.TemporaryDirectory(prefix="fixture server ") as temporary:
            directory = Path(temporary)
            media = directory / "media"
            media.mkdir()
            (media / "sync-fixture.mp4").write_bytes(PAYLOAD)
            state = directory / "state"
            with socket.socket() as reserve:
                reserve.bind(("127.0.0.1", 0))
                port = reserve.getsockname()[1]
            start = subprocess.run(["bash", str(SCRIPTS / "start_fixture_server.sh"),
                                    "--fixture", str(media / "sync-fixture.mp4"),
                                    "--state", str(state), "--port", str(port)],
                                   capture_output=True, text=True, timeout=15)
            self.assertEqual(start.returncode, 0, start.stderr)
            receipt = state / "server.env"
            original = receipt.read_text()
            owned_pid = int(re.search(r"^SERVER_PID=(\d+)$", original, re.M)[1])
            birth = re.search(r"^SERVER_START_TICKS=(\d+)$", original, re.M)[1]
            unrelated = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"])

            def stop(path):
                return subprocess.run(["bash", str(SCRIPTS / "stop_fixture_server.sh"), str(path)],
                                      capture_output=True, text=True, timeout=20)

            def assert_live():
                connection = http.client.HTTPConnection("127.0.0.1", port, timeout=2)
                try:
                    connection.request("GET", "/sync-fixture.mp4", headers={"Range": "bytes=1200-1400"})
                    response = connection.getresponse()
                    self.assertEqual(response.status, 206)
                    self.assertEqual(response.read(), PAYLOAD[1200:1401])
                finally:
                    connection.close()

            try:
                assert_live()
                self.assertEqual(fixture.process_identity(owned_pid, media, port), birth)
                conflict = subprocess.run([
                    "bash", str(SCRIPTS / "start_fixture_server.sh"),
                    "--fixture", str(media / "sync-fixture.mp4"), "--port", str(port),
                    "--state", str(directory / "conflict-state")],
                    capture_output=True, text=True, timeout=15)
                self.assertEqual(conflict.returncode, 4, conflict.stderr)
                self.assertFalse((directory / "conflict-state" / "server.env").exists())
                assert_live()
                altered = state / "altered.env"
                altered.write_text(original.replace(f"SERVER_PID={owned_pid}\n",
                                                     f"SERVER_PID={unrelated.pid}\n"))
                self.assertEqual(stop(altered).returncode, 3)
                self.assertIsNone(unrelated.poll())
                assert_live()
                altered.write_text(original.replace(f"SERVER_START_TICKS={birth}\n",
                                                     f"SERVER_START_TICKS={int(birth) + 1}\n"))
                self.assertEqual(stop(altered).returncode, 3)
                assert_live()
                stopped = stop(receipt)
                self.assertEqual(stopped.returncode, 0, stopped.stderr)
                self.assertIsNone(fixture.process_identity(owned_pid, media, port))
                self.assertEqual(stop(receipt).returncode, 0)
            finally:
                stop(receipt)
                unrelated.terminate()
                unrelated.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()
