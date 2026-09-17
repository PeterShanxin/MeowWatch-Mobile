#!/usr/bin/env bash
set -euo pipefail

: "${INTERRUPTION_AVD_NAME:?Provide the unique interruption task AVD name}"
fixture='build/android-interruption-fixture/sync-fixture.mp4'
server_state='build/android-interruption-server'
server_started=0
cleanup() {
  status=$?
  trap - EXIT INT TERM
  if [[ "$server_started" -eq 1 ]]; then
    bash tools/android_multi_device/stop_fixture_server.sh "$server_state/server.env" || status=1
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
bash tools/android_multi_device/start_fixture_server.sh \
  --fixture "$fixture" --state "$server_state" --port 18765
server_started=1
timeout --signal=TERM --kill-after=15s 480s \
  python3 -m tools.android_interruption_runtime.run \
    --serial emulator-5554 \
    --avd-name "$INTERRUPTION_AVD_NAME" \
    --apk build/app/outputs/flutter-apk/app-release.apk \
    --fixture "$fixture"
