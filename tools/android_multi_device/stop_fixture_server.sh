#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == '-h' || "${1:-}" == '--help' ]]; then
  echo 'Usage: stop_fixture_server.sh <server.env>'
  exit 0
fi
if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo 'Usage: stop_fixture_server.sh <server.env>' >&2
  exit 2
fi

# server.env is emitted by start_fixture_server.sh. Do not source an untrusted
# file here.
source "$1"
: "${SERVER_PID:?server state is missing SERVER_PID}"
: "${SERVER_PORT:?server state is missing SERVER_PORT}"
: "${SERVER_START_TICKS:?server state is missing SERVER_START_TICKS}"
: "${FIXTURE_FILE:?server state is missing FIXTURE_FILE}"
if [[ ! "$SERVER_PID" =~ ^[0-9]+$ || ! "$SERVER_START_TICKS" =~ ^[0-9]+$ ]]; then
  echo 'Fixture server PID/birth token is invalid.' >&2
  exit 3
fi
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
  echo 'Task-owned fixture server is already stopped.'
  exit 0
fi
server_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/fixture_server.py"
matches_server() {
  python3 "$server_script" --directory "$(dirname "$FIXTURE_FILE")" \
    --port "$SERVER_PORT" --owner-pid "$SERVER_PID" \
    --start-ticks "$SERVER_START_TICKS" >/dev/null 2>&1
}
is_stopped() {
  ! kill -0 "$SERVER_PID" 2>/dev/null || \
    [[ "$(awk '{print $3}' "/proc/$SERVER_PID/stat" 2>/dev/null || true)" == Z ]]
}

if is_stopped; then
  echo 'Task-owned fixture server is already stopped.'
  exit 0
fi
if ! matches_server; then
  echo "PID $SERVER_PID no longer matches the task-owned fixture server." >&2
  exit 3
fi

kill -INT "$SERVER_PID"
for _ in $(seq 1 40); do
  if is_stopped; then
    echo 'Task-owned fixture server stopped.'
    exit 0
  fi
  sleep 0.25
done
if matches_server; then
  kill -TERM "$SERVER_PID"
else
  echo 'Fixture server identity changed before TERM; refusing to signal.' >&2
  exit 3
fi
for _ in $(seq 1 20); do
  if is_stopped; then
    echo 'Task-owned fixture server stopped after TERM fallback.'
    exit 0
  fi
  sleep 0.25
done
echo 'Fixture server did not stop after TERM.' >&2
exit 4
