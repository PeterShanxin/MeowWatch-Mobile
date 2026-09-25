#!/usr/bin/env bash
set -euo pipefail

: "${TOGETHER_FOCUS_AVD_NAME:?Provide the unique Together focus AVD name}"
fixture='build/android-together-focus-fixture/sync-fixture.mp4'
server_state='build/android-together-focus-server'
started=0
cleanup() {
  status=$?
  trap - EXIT INT TERM
  if [[ "$started" -eq 1 ]]; then
    bash tools/android_multi_device/stop_fixture_server.sh "$server_state/server.env" || status=1
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

bash tools/android_multi_device/start_fixture_server.sh \
  --fixture "$fixture" --state "$server_state" --port 18765
started=1
timeout --signal=TERM --kill-after=15s 650s \
  python3 -m tools.android_together_focus_runtime.run \
    --serial emulator-5554 \
    --avd-name "$TOGETHER_FOCUS_AVD_NAME" \
    --apk build/app/outputs/flutter-apk/app-debug.apk
