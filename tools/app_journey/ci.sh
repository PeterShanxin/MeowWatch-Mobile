#!/usr/bin/env bash
set -euo pipefail

state='build/app-journey-fixture-server'
cleanup() {
  local result=$?
  trap - EXIT
  if [[ -f "$state/server.env" ]]; then
    bash tools/android_multi_device/stop_fixture_server.sh "$state/server.env" || {
      if [[ "$result" -eq 0 ]]; then result=1; fi
    }
  fi
  exit "$result"
}
trap cleanup EXIT
bash tools/android_multi_device/start_fixture_server.sh --state "$state"
bash tools/app_journey/run.sh \
  --serial emulator-5554 \
  --apk build/app/outputs/flutter-apk/app-debug.apk
