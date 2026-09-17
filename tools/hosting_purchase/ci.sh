#!/usr/bin/env bash
set -euo pipefail

serial='emulator-5554'
apk='build/app/outputs/flutter-apk/app-debug.apk'
fixture='build/hosting-purchase-fixture/sync-fixture.mp4'
server_state='build/hosting-purchase-fixture-server'

usage() {
  cat <<'EOF'
Usage: ci.sh [--serial <adb-serial>] [--apk <integration-apk>]

Runs the hosted-session quota and real RevenueCat Test Store funnel on one
explicit Android emulator. The guest is a second TLS client and native decoder
inside the same application process; this is not two-device evidence.
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --serial) serial="${2:-}"; shift 2 ;;
    --apk) apk="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! "$serial" =~ ^[A-Za-z0-9_.:-]+$ ]]; then
  echo 'A valid explicit adb serial is required.' >&2
  exit 2
fi
if [[ ! -f "$apk" || "$apk" != *.apk ]]; then
  echo 'The prebuilt hosting purchase APK is missing.' >&2
  exit 2
fi
if [[ ! -s "$fixture" ]]; then
  echo 'The prepared 90-second fixture is missing.' >&2
  exit 2
fi

server_env="$server_state/server.env"
server_started=0
final_status=0
cleanup() {
  incoming_status=$?
  trap - EXIT INT TERM
  if [[ "$final_status" -eq 0 && "$incoming_status" -ne 0 ]]; then
    final_status="$incoming_status"
  fi
  if [[ "$server_started" -eq 1 ]]; then
    set +e
    bash tools/android_multi_device/stop_fixture_server.sh "$server_env"
    cleanup_status=$?
    set -e
    if [[ "$final_status" -eq 0 && "$cleanup_status" -ne 0 ]]; then
      final_status="$cleanup_status"
    fi
  fi
  exit "$final_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

bash tools/android_multi_device/start_fixture_server.sh \
  --fixture "$fixture" \
  --state "$server_state"
server_started=1

set +e
python3 tools/hosting_purchase/run_hosting_purchase.py \
  --serial "$serial" \
  --apk "$apk"
final_status=$?
set -e

exit "$final_status"
