#!/usr/bin/env bash
set -euo pipefail

fixture='build/android-lifecycle-fixture/sync-fixture.mp4'
server_state='build/android-lifecycle-server'
cleanup() {
  if [[ -f "$server_state/server.env" ]]; then
    bash tools/android_multi_device/stop_fixture_server.sh "$server_state/server.env"
  fi
}
trap cleanup EXIT
bash tools/android_multi_device/start_fixture_server.sh \
  --fixture "$fixture" --state "$server_state" --port 18765
timeout --signal=TERM --kill-after=15s 480s \
  python3 -m tools.android_lifecycle_runtime.run \
    --serial emulator-5554 \
    --apk build/app/outputs/flutter-apk/app-release.apk \
    --fixture "$fixture"
