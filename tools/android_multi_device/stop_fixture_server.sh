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
: "${FIXTURE_FILE:?server state is missing FIXTURE_FILE}"
if [[ ! "$SERVER_PID" =~ ^[0-9]+$ ]]; then
  echo 'Fixture server PID is invalid.' >&2
  exit 3
fi
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
  echo 'Task-owned fixture server is already stopped.'
  exit 0
fi

cmdline="$(tr '\0' ' ' < "/proc/$SERVER_PID/cmdline" 2>/dev/null || true)"
if [[ "$cmdline" != *'python3 -m http.server '* || \
      "$cmdline" != *" $SERVER_PORT "* || \
      "$cmdline" != *"--directory $(dirname "$FIXTURE_FILE")"* ]]; then
  echo "PID $SERVER_PID no longer matches the task-owned fixture server." >&2
  exit 3
fi

kill -INT "$SERVER_PID"
for _ in $(seq 1 40); do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo 'Task-owned fixture server stopped.'
    exit 0
  fi
  sleep 0.25
done
if kill -0 "$SERVER_PID" 2>/dev/null; then
  kill -TERM "$SERVER_PID"
fi
echo 'Task-owned fixture server stopped after TERM fallback.'
