#!/usr/bin/env bash
set -euo pipefail

: "${FULLSCREEN_AVD_NAME:?Provide the dedicated fullscreen AVD name}"
: "${FULLSCREEN_FORM_FACTOR:?Provide phone or tablet}"
fixture='build/android-fullscreen-fixture/sync-fixture.mp4'
state='build/android-fullscreen-server'
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
  --fixture "$fixture" --state "$state" --port 18765
started=1
timeout --signal=TERM --kill-after=30s 480s \
  python3 -m tools.android_fullscreen_runtime.run \
    --serial emulator-5554 --avd-name "$FULLSCREEN_AVD_NAME" \
    --form-factor "$FULLSCREEN_FORM_FACTOR" \
    --apk build/app/outputs/flutter-apk/app-release.apk --fixture "$fixture"
