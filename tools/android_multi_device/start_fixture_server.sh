#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: start_fixture_server.sh [--fixture <mp4>] [--state <directory>] [--port <port>]
       [--max-body-offset <bytes> --body-bytes-per-second <bytes>]

Starts a task-owned range-capable MP4 server on host loopback. Android emulators reach
the default service as http://10.0.2.2:18765/sync-fixture.mp4.
EOF
}

fixture='build/android-multi-device/fixture/sync-fixture.mp4'
state_dir='build/android-multi-device/fixture-server'
port=18765
max_body_offset=0
body_bytes_per_second=0
while (( $# > 0 )); do
  case "$1" in
    --fixture) fixture="${2:-}"; shift 2 ;;
    --state) state_dir="${2:-}"; shift 2 ;;
    --port) port="${2:-}"; shift 2 ;;
    --max-body-offset) max_body_offset="${2:-}"; shift 2 ;;
    --body-bytes-per-second) body_bytes_per_second="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! -s "$fixture" || "$(basename "$fixture")" != 'sync-fixture.mp4' ]]; then
  echo 'The prepared sync-fixture.mp4 is missing or empty.' >&2
  exit 2
fi
if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1024 || port > 65535 )); then
  echo '--port must be an integer from 1024 through 65535.' >&2
  exit 2
fi
if [[ ! "$max_body_offset" =~ ^[0-9]+$ || ! "$body_bytes_per_second" =~ ^[0-9]+$ ]] || \
    { (( max_body_offset == 0 )) && (( body_bytes_per_second != 0 )); } || \
    { (( max_body_offset != 0 )) && (( body_bytes_per_second == 0 )); }; then
  echo 'Byte cap and pacing must be nonnegative and enabled together.' >&2
  exit 2
fi
if (( max_body_offset > 0 )) && (( max_body_offset >= $(stat -c %s "$fixture") )); then
  echo 'Byte cap must be below the fixture size.' >&2
  exit 2
fi
for tool in python3 curl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required server tool is unavailable: $tool" >&2
    exit 2
  fi
done

mkdir -p "$state_dir"
if find "$state_dir" -mindepth 1 -print -quit | grep -q .; then
  echo "Fixture server state must be empty: $state_dir" >&2
  exit 3
fi
state_dir="$(cd "$state_dir" && pwd -P)"
fixture="$(cd "$(dirname "$fixture")" && pwd -P)/$(basename "$fixture")"
fixture_dir="$(dirname "$fixture")"
server_log="$state_dir/http-server.log"
server_env="$state_dir/server.env"
server_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/fixture_server.py"

NETWORK_FIXTURE_MAX_BODY_OFFSET="$max_body_offset" \
NETWORK_FIXTURE_BODY_BYTES_PER_SECOND="$body_bytes_per_second" \
python3 "$server_script" --directory "$fixture_dir" --port "$port" \
  > "$server_log" 2>&1 &
server_pid=$!
server_start_ticks=''

matches_server() {
  # Never authorize cleanup from argv alone, even before readiness.
  [[ "$server_start_ticks" =~ ^[0-9]+$ ]] || return 1
  python3 "$server_script" --directory "$fixture_dir" --port "$port" \
    --owner-pid "$server_pid" --parent-pid "$$" \
    --start-ticks "$server_start_ticks" >/dev/null 2>&1
}

startup_ok=0
cleanup_failed_startup() {
  if [[ "$startup_ok" -eq 0 ]] && matches_server; then
    kill -INT "$server_pid" 2>/dev/null || true
    for _ in $(seq 1 20); do
      if ! matches_server; then break; fi
      sleep 0.1
    done
    if matches_server; then kill -TERM "$server_pid" 2>/dev/null || true; fi
  fi
}
trap cleanup_failed_startup EXIT

# Capture the birth token before waiting for HTTP. The parent check proves this
# is still our launched child; retries allow its initial exec to finish. If no
# identity can be retained, the failure trap must leave it unsignalled.
for _ in $(seq 1 40); do
  if server_start_ticks="$(python3 "$server_script" --directory "$fixture_dir" \
      --port "$port" --owner-pid "$server_pid" --parent-pid "$$")" && \
      [[ "$server_start_ticks" =~ ^[0-9]+$ ]]; then
    break
  fi
  server_start_ticks=''
  if ! kill -0 "$server_pid" 2>/dev/null; then break; fi
  sleep 0.025
done
if [[ ! "$server_start_ticks" =~ ^[0-9]+$ ]]; then
  echo 'Fixture server child identity could not be retained; no cleanup signal sent.' >&2
  exit 4
fi

host_url="http://127.0.0.1:$port/sync-fixture.mp4"
ready=0
for _ in $(seq 1 40); do
  if ! matches_server; then
    echo 'Fixture HTTP server exited or changed identity during startup.' >&2
    cat "$server_log" >&2
    exit 4
  fi
  if grep -q '"event":"ready"' "$server_log" && \
      curl --fail --silent --show-error --connect-timeout 1 --max-time 2 --head "$host_url" \
      > "$state_dir/response-headers.txt" 2>/dev/null && \
      grep -qi '^Accept-Ranges: bytes' "$state_dir/response-headers.txt"; then
    ready=1
    break
  fi
  sleep 0.25
done
if [[ "$ready" -ne 1 ]]; then
  echo 'Fixture HTTP server did not become ready.' >&2
  exit 4
fi
if ! matches_server; then
  echo 'Fixture server identity changed before its receipt was written.' >&2
  exit 4
fi

{
  printf 'SERVER_PID=%q\n' "$server_pid"
  printf 'SERVER_PORT=%q\n' "$port"
  printf 'SERVER_START_TICKS=%q\n' "$server_start_ticks"
  printf 'SERVER_STATE_DIR=%q\n' "$state_dir"
  printf 'SERVER_LOG=%q\n' "$server_log"
  printf 'FIXTURE_FILE=%q\n' "$fixture"
  printf 'HOST_FIXTURE_URL=%q\n' "$host_url"
  printf 'EMULATOR_FIXTURE_URL=%q\n' "http://10.0.2.2:$port/sync-fixture.mp4"
  printf 'MAX_BODY_OFFSET=%q\n' "$max_body_offset"
  printf 'BODY_BYTES_PER_SECOND=%q\n' "$body_bytes_per_second"
} > "$server_env"

startup_ok=1
trap - EXIT
printf 'Fixture server is ready. State: %s\n' "$server_env"
