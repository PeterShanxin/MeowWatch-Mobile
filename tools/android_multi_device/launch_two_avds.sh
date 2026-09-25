#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: launch_two_avds.sh [output-directory]

Creates and launches a clean Pixel 6 phone AVD on emulator-5554 and a clean
Pixel Tablet AVD on emulator-5556 using fixed, resource-limited dual-player CI
displays: 720x1600@280 and 1280x800@160. The output directory receives emulator
logs, measured cold-boot readiness and session.env for recording and cleanup.
MEOWWATCH_CI_DISPLAY_PROFILE=recording uses 432x960@168 and 960x600@120 with
identical logical layout sizes. The default standard profile stays unchanged.
Required API 35 packages must already be prepared; this launcher only validates
them. MEOWWATCH_ANDROID_SDK_PREPARATION optionally binds a preparation receipt.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

display_profile="${MEOWWATCH_CI_DISPLAY_PROFILE:-standard}"
case "$display_profile" in standard|recording) ;; *) echo 'Unsupported CI display profile' >&2; exit 2 ;; esac
export MEOWWATCH_CI_DISPLAY_PROFILE="$display_profile"

output_root="${1:-build/android-multi-device}"
session_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$output_root"
output_root="$(cd "$output_root" && pwd -P)"
session_dir="$output_root/$session_id"
mkdir -p "$session_dir"
avd_home="$session_dir/avd"
mkdir -p "$avd_home"

sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [[ -z "$sdk_root" ]]; then
  echo 'ANDROID_SDK_ROOT or ANDROID_HOME must identify the Android SDK.' >&2
  exit 2
fi

resolve_tool() {
  local preferred="$1"
  if [[ -x "$preferred" ]]; then
    printf '%s\n' "$preferred"
  else
    echo "Required executable not found in the selected Android SDK: $preferred" >&2
    exit 2
  fi
}

avdmanager="$(resolve_tool "$sdk_root/cmdline-tools/latest/bin/avdmanager")"
emulator="$(resolve_tool "$sdk_root/emulator/emulator")"
adb="$(resolve_tool "$sdk_root/platform-tools/adb")"

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
  echo 'This launcher is intentionally limited to Linux x86_64 hosted runners.' >&2
  exit 2
fi
if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
  echo '/dev/kvm is not readable and writable; enable KVM before launching.' >&2
  exit 2
fi

system_image='system-images;android-35;google_apis;x86_64'
sdk_verification=(--sdk-root "$sdk_root")
if [[ -n "${MEOWWATCH_ANDROID_SDK_PREPARATION:-}" ]]; then
  sdk_verification+=(--preparation-report "$MEOWWATCH_ANDROID_SDK_PREPARATION")
fi
python3 -m tools.android_multi_device.prepare_sdk_packages verify "${sdk_verification[@]}" \
  > "$session_dir/sdk-validation.json"

"$emulator" -accel-check | tee "$session_dir/acceleration.txt"

device_list="$session_dir/avdmanager-devices.txt"
"$avdmanager" list device > "$device_list"
for profile in pixel_6 pixel_tablet; do
  if ! grep -Fq "\"$profile\"" "$device_list"; then
    echo "Required AVD hardware profile is unavailable: $profile" >&2
    exit 3
  fi
done

phone_avd="meowwatch_phone_${session_id//[^[:alnum:]]/_}"
tablet_avd="meowwatch_tablet_${session_id//[^[:alnum:]]/_}"

printf 'no\n' | ANDROID_AVD_HOME="$avd_home" "$avdmanager" create avd \
  --force \
  --name "$phone_avd" \
  --package "$system_image" \
  --device pixel_6
printf 'no\n' | ANDROID_AVD_HOME="$avd_home" "$avdmanager" create avd \
  --force \
  --name "$tablet_avd" \
  --package "$system_image" \
  --device pixel_tablet

# Preserve the profiles' dp geometry while reducing physical pixels for two
# software-rendered players on one CI host. Full-resolution layout acceptance
# runs separately. Resource improvements must be established by measurements.
python3 - "$avd_home/$phone_avd.avd/config.ini" "$avd_home/$tablet_avd.avd/config.ini" <<'PY'
from pathlib import Path
import os
import sys
from tools.android_multi_device.device_readiness import DISPLAY_PROFILES

geometry = DISPLAY_PROFILES[os.environ.get("MEOWWATCH_CI_DISPLAY_PROFILE", "standard")]
for name, role in zip(sys.argv[1:], ("phone", "tablet"), strict=True):
    width, height, density = geometry[role]
    path = Path(name)
    # The emulator resolves skin.path before skin.name or the LCD-size fallback.
    # Keep both explicit magic-size skins aligned with the physical framebuffer.
    values = {"hw.lcd.width": width, "hw.lcd.height": height, "hw.lcd.density": density,
              "skin.name": f"{width}x{height}", "skin.path": f"{width}x{height}"}
    lines = [line for line in path.read_text().splitlines() if line.partition("=")[0].strip() not in values]
    lines.extend(f"{key}={value}" for key, value in values.items())
    path.write_text("\n".join(lines) + "\n")
PY
cp "$avd_home/$phone_avd.avd/config.ini" "$session_dir/phone-avd-config.ini"
cp "$avd_home/$tablet_avd.avd/config.ini" "$session_dir/tablet-avd-config.ini"

ANDROID_AVD_HOME="$avd_home" "$emulator" -list-avds \
  > "$session_dir/created-avds.txt"
for created_avd in "$phone_avd" "$tablet_avd"; do
  if ! grep -Fxq "$created_avd" "$session_dir/created-avds.txt"; then
    echo "Created AVD is not visible to the emulator: $created_avd" >&2
    exit 3
  fi
done

"$adb" start-server >/dev/null
for serial in emulator-5554 emulator-5556; do
  if "$adb" devices | awk 'NR > 1 { print $1 }' | grep -Fxq "$serial"; then
    echo "Refusing to reuse an existing Android emulator serial: $serial" >&2
    exit 3
  fi
done

ANDROID_AVD_HOME="$avd_home" "$emulator" -avd "$phone_avd" \
  -port 5554 \
  -accel on \
  -gpu swiftshader \
  -cores 2 \
  -memory 3072 \
  -no-window \
  -no-snapshot \
  -noaudio \
  -no-boot-anim \
  -camera-back none \
  -camera-front none \
  > "$session_dir/phone-emulator.log" 2>&1 &
phone_emulator_pid=$!

ANDROID_AVD_HOME="$avd_home" "$emulator" -avd "$tablet_avd" \
  -port 5556 \
  -accel on \
  -gpu swiftshader \
  -cores 2 \
  -memory 3072 \
  -no-window \
  -no-snapshot \
  -noaudio \
  -no-boot-anim \
  -camera-back none \
  -camera-front none \
  > "$session_dir/tablet-emulator.log" 2>&1 &
tablet_emulator_pid=$!

phone_serial='emulator-5554'
tablet_serial='emulator-5556'

write_session() {
  {
    printf 'SESSION_ID=%q\n' "$session_id"
    printf 'SESSION_DIR=%q\n' "$session_dir"
    printf 'CI_DISPLAY_PROFILE=%q\n' "$display_profile"
    printf 'SDK_ROOT=%q\n' "$sdk_root"
    printf 'AVD_HOME=%q\n' "$avd_home"
    printf 'ADB=%q\n' "$adb"
    printf 'AVDMANAGER=%q\n' "$avdmanager"
    printf 'PHONE_AVD=%q\n' "$phone_avd"
    printf 'TABLET_AVD=%q\n' "$tablet_avd"
    printf 'PHONE_SERIAL=%q\n' "$phone_serial"
    printf 'TABLET_SERIAL=%q\n' "$tablet_serial"
    printf 'PHONE_EMULATOR_PID=%q\n' "$phone_emulator_pid"
    printf 'TABLET_EMULATOR_PID=%q\n' "$tablet_emulator_pid"
  } > "$session_dir/session.env"
}
write_session

startup_failed=0
cleanup_failed_startup() {
  if [[ "$startup_failed" -eq 0 ]]; then
    return
  fi
  "$adb" -s "$phone_serial" emu kill >/dev/null 2>&1 || true
  "$adb" -s "$tablet_serial" emu kill >/dev/null 2>&1 || true
  sleep 2
  for emulator_pid in "$phone_emulator_pid" "$tablet_emulator_pid"; do
    if kill -0 "$emulator_pid" 2>/dev/null; then
      kill -TERM "$emulator_pid" 2>/dev/null || true
    fi
  done
}
trap cleanup_failed_startup EXIT
startup_failed=1

wait_for_boot() {
  local serial="$1"
  local label="$2"
  local pid_variable="${label}_emulator_pid"
  local emulator_pid="${!pid_variable}"
  local deadline=$((SECONDS + 600))
  while (( SECONDS < deadline )); do
    if ! kill -0 "$emulator_pid" 2>/dev/null; then
      echo "$label emulator process exited before Android booted." >&2
      return 1
    fi
    local state="$($adb -s "$serial" get-state 2>/dev/null || true)"
    local complete="$($adb -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
    if [[ "$state" == 'device' && "$complete" == '1' ]]; then
      "$adb" -s "$serial" shell input keyevent 82 >/dev/null 2>&1 || true
      return 0
    fi
    sleep 2
  done
  echo "$label failed to boot on $serial within 600 seconds." >&2
  return 1
}

wait_for_boot "$phone_serial" phone &
phone_wait_pid=$!
wait_for_boot "$tablet_serial" tablet &
tablet_wait_pid=$!
wait "$phone_wait_pid"
wait "$tablet_wait_pid"

for serial in "$phone_serial" "$tablet_serial"; do
  "$adb" -s "$serial" shell settings put global window_animation_scale 0
  "$adb" -s "$serial" shell settings put global transition_animation_scale 0
  "$adb" -s "$serial" shell settings put global animator_duration_scale 0
done

"$adb" -s "$phone_serial" shell settings put system accelerometer_rotation 0
"$adb" -s "$phone_serial" shell settings put system user_rotation 0
"$adb" -s "$tablet_serial" shell settings put system accelerometer_rotation 0
# This tablet's natural CI display is already landscape. Rotating it
# by 90 degrees produces a portrait app viewport and incorrect capture framing.
"$adb" -s "$tablet_serial" shell settings put system user_rotation 0

"$adb" devices -l > "$session_dir/adb-devices.txt"
write_session
python3 -m tools.android_multi_device.prepare_sdk_setup \
  --adb "$adb" --phone "$phone_serial" --tablet "$tablet_serial" \
  --phone-avd "$phone_avd" --tablet-avd "$tablet_avd" \
  --output "$session_dir/sdk-setup-preparation"
python3 -m tools.android_multi_device.device_readiness \
  --adb "$adb" --phone "$phone_serial" --tablet "$tablet_serial" \
  --phone-log "$session_dir/phone-emulator.log" \
  --tablet-log "$session_dir/tablet-emulator.log" \
  --display-profile "$display_profile" --requested-memory-mib 3072 --output "$session_dir/device-readiness"
startup_failed=0
trap - EXIT

printf 'Two AVDs are ready. Session: %s\n' "$session_dir/session.env"
printf 'Display profile: %s (physical geometry retained in phone/tablet-avd-config.ini)\n' "$display_profile"
printf 'Phone:  %s (%s, 2 cores, requested 3072 MiB)\n' "$phone_serial" "$phone_avd"
printf 'Tablet: %s (%s, 2 cores, requested 3072 MiB)\n' "$tablet_serial" "$tablet_avd"
printf 'Measured guest RAM, display and admission evidence: %s/device-readiness/result.json\n' "$session_dir"
