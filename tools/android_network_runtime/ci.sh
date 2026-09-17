#!/usr/bin/env bash
set -euo pipefail

: "${NETWORK_RUN_ID:?Provide the same run ID used to compile the APK}"
: "${NETWORK_AVD_NAME:?Provide the dedicated network AVD name}"
state='build/android-network-fixture-server'
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
bash tools/android_multi_device/start_fixture_server.sh \
  --fixture build/android-network-fixture/sync-fixture.mp4 --state "$state"
started=1
python3 -m tools.android_network_runtime.run \
  --serial emulator-5554 --avd-name "$NETWORK_AVD_NAME" --run-id "$NETWORK_RUN_ID" \
  --apk build/app/outputs/flutter-apk/app-debug.apk
