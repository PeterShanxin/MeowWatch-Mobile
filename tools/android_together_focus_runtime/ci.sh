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

python3 - "$TOGETHER_FOCUS_AVD_NAME" <<'PY'
from pathlib import Path
import json
import re
import sys
import time

from tools.android_multi_device.prepare_sdk_setup import Preparation, prepare
from tools.android_together_focus_runtime.run import require_prelaunch_home

avd = sys.argv[1]
if re.fullmatch(r"meowwatch_interruption_[0-9]+_[0-9]+", avd) is None:
    raise SystemExit("Together focus requires its exact task AVD name")
serial = "emulator-5554"
output = Path("build/android-together-focus-sdk-preparation")
report = prepare("adb", {serial: avd}, output)
if report["status"] != "prepared":
    raise SystemExit(f"SDK preparation failed: {report.get('reason')}")
# A fresh Home sample after a bounded quiet interval must retain the same ANR
# history. A later Launcher ANR during the app journey remains a test failure.
time.sleep(5)
runner = Preparation("adb", output, time.monotonic() + 20)
fresh = runner.snapshot(serial, avd, "admission-after-5s")
receipt = require_prelaunch_home(report, fresh, serial, avd)
(output / "admission.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
print("TOGETHER_FOCUS_SDK_PREPARATION_PASS", flush=True)
PY

bash tools/android_multi_device/start_fixture_server.sh \
  --fixture "$fixture" --state "$server_state" --port 18765
started=1
timeout --signal=TERM --kill-after=15s 650s \
  python3 -m tools.android_together_focus_runtime.run \
    --serial emulator-5554 \
    --avd-name "$TOGETHER_FOCUS_AVD_NAME" \
    --apk build/app/outputs/flutter-apk/app-debug.apk
