#!/usr/bin/env bash
set -euo pipefail

sdk_root="${ANDROID_SDK_ROOT:-$ANDROID_HOME}"
export PATH="$sdk_root/platform-tools:$PATH"
command -v adb >/dev/null

root='build/normal-apk-rehearsal'
fixture='build/android-multi-device/fixture/sync-fixture.mp4'
apk='build/app/outputs/flutter-apk/app-debug.apk'
observer='build/android-native-ui/native-ui-observer.apk'
server_env="$root/server/server.env"
session_file=''

for required in "$fixture" "$apk" "$observer"; do
  if [[ ! -s "$required" ]]; then
    echo "Missing rehearsal input: $required" >&2
    exit 2
  fi
done
if [[ -e "$root" ]]; then
  echo "Rehearsal output must start absent: $root" >&2
  exit 2
fi
mkdir -p "$root"

cleanup() {
  local status=$?
  trap - EXIT
  set +e
  if [[ -n "$session_file" && -f "$session_file" ]]; then
    bash tools/android_multi_device/stop_two_avds.sh "$session_file" --delete-avds
  fi
  if [[ -f "$server_env" ]]; then
    bash tools/android_multi_device/stop_fixture_server.sh "$server_env"
  fi
  exit "$status"
}
trap cleanup EXIT

sha256sum "$apk" > "$root/application.apk.sha256"
bash tools/android_multi_device/start_fixture_server.sh \
  --fixture "$fixture" --state "$root/server"
bash tools/android_multi_device/launch_two_avds.sh "$root/sessions"
mapfile -t sessions < <(find "$root/sessions" -mindepth 2 -maxdepth 2 -name session.env -print)
if [[ ${#sessions[@]} -ne 1 ]]; then
  echo 'Expected one newly created phone/tablet AVD session.' >&2
  exit 3
fi
session_file="${sessions[0]}"
# This file was written by this run's AVD launcher, with shell-quoted values.
source "$session_file"
python3 -m tools.normal_apk_rehearsal.run \
  --phone "$PHONE_SERIAL" --tablet "$TABLET_SERIAL" \
  --apk "$apk" --observer-apk "$observer" --fixture "$fixture" \
  --output "$root/evidence"
