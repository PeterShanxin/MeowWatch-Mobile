#!/usr/bin/env bash
set -euo pipefail

state='build/production-purchase-fixture-server'
started=0
cleanup() {
  status=$?
  trap - EXIT INT TERM
  if [[ "$started" -eq 1 ]]; then
    bash tools/android_multi_device/stop_fixture_server.sh "$state/server.env" || status=1
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
bash tools/android_multi_device/start_fixture_server.sh --state "$state"
started=1
python3 tools/production_purchase_runtime/run.py \
  --serial emulator-5554 \
  --apk build/app/outputs/flutter-apk/app-debug.apk
