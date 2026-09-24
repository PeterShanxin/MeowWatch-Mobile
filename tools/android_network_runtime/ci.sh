#!/usr/bin/env bash
set -euo pipefail

: "${NETWORK_RUN_ID:?Provide the same run ID used to compile the APK}"
: "${NETWORK_AVD_NAME:?Provide the dedicated network AVD name}"
build_mode="${NETWORK_BUILD_MODE:-debug}"
case "$build_mode" in debug|profile) ;; *) echo 'Unsupported network build mode' >&2; exit 2 ;; esac
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
mkdir -p build/android-network-artifacts
export NETWORK_SDK_SETUP_REPORT=build/android-network-artifacts/sdk-setup-preparation/result.json
python3 - "$NETWORK_AVD_NAME" <<'PY'
from pathlib import Path
import sys

from tools.android_multi_device.prepare_sdk_setup import prepare

report = prepare("adb", {"emulator-5554": sys.argv[1]},
                 Path("build/android-network-artifacts/sdk-setup-preparation"))
print(f"SDK_SETUP_PREPARATION_{report['status'].upper()}: "
      f"{report.get('reason', 'exact task AVD checked')}", flush=True)
if report["status"] != "prepared":
    raise SystemExit(1)
PY
bash tools/android_multi_device/start_fixture_server.sh \
  --fixture build/android-network-fixture/sync-fixture.mp4 --state "$state"
started=1
python3 -m tools.android_network_runtime.run \
  --serial emulator-5554 --avd-name "$NETWORK_AVD_NAME" --run-id "$NETWORK_RUN_ID" \
  --build-mode "$build_mode" --apk "build/app/outputs/flutter-apk/app-${build_mode}.apk"
