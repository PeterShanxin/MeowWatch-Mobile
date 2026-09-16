#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: start_fixture_server.sh [--fixture <mp4>] [--state <directory>] [--port <port>]

Starts a task-owned Python HTTP server on host loopback. Android emulators reach
the default service as http://10.0.2.2:18765/sync-fixture.mp4.
EOF
}

fixture='build/android-multi-device/fixture/sync-fixture.mp4'
state_dir='build/android-multi-device/fixture-server'
port=18765
while (( $# > 0 )); do
  case "$1" in
    --fixture) fixture="${2:-}"; shift 2 ;;
    --state) state_dir="${2:-}"; shift 2 ;;
    --port) port="${2:-}"; shift 2 ;;
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

python3 -m http.server "$port" \
  --bind 127.0.0.1 \
  --directory "$fixture_dir" \
  > "$server_log" 2>&1 &
server_pid=$!

startup_ok=0
cleanup_failed_startup() {
  if [[ "$startup_ok" -eq 0 ]] && kill -0 "$server_pid" 2>/dev/null; then
    kill -INT "$server_pid" 2>/dev/null || true
  fi
}
trap cleanup_failed_startup EXIT

host_url="http://127.0.0.1:$port/sync-fixture.mp4"
for _ in $(seq 1 40); do
  if ! kill -0 "$server_pid" 2>/dev/null; then
    echo 'Fixture HTTP server exited during startup.' >&2
    cat "$server_log" >&2
    exit 4
  fi
  if curl --fail --silent --show-error --head "$host_url" \
      > "$state_dir/response-headers.txt" 2>/dev/null; then
    break
  fi
  sleep 0.25
done
if [[ ! -s "$state_dir/response-headers.txt" ]]; then
  echo 'Fixture HTTP server did not become ready.' >&2
  exit 4
fi

{
  printf 'SERVER_PID=%q\n' "$server_pid"
  printf 'SERVER_PORT=%q\n' "$port"
  printf 'SERVER_STATE_DIR=%q\n' "$state_dir"
  printf 'SERVER_LOG=%q\n' "$server_log"
  printf 'FIXTURE_FILE=%q\n' "$fixture"
  printf 'HOST_FIXTURE_URL=%q\n' "$host_url"
  printf 'EMULATOR_FIXTURE_URL=%q\n' "http://10.0.2.2:$port/sync-fixture.mp4"
} > "$server_env"

startup_ok=1
trap - EXIT
printf 'Fixture server is ready. State: %s\n' "$server_env"
