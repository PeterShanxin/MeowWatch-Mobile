#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: run.sh --serial <emulator-serial> --apk <prebuilt-apk> [options]

Options:
  --driver <dart-file>   Default: test_driver/app_journey_driver.dart
  --target <dart-file>   Default: integration_test/app_journey_test.dart
  --timeout <duration>   Per-profile GNU timeout (default: 750s)

Runs one clean, recorded production-app journey for each viewport profile on
the explicitly selected Android emulator. Profiles are wm size/density
overrides on the same AVD; they are not different hardware devices.
EOF
}

serial=''
apk=''
driver='test_driver/app_journey_driver.dart'
target='integration_test/app_journey_test.dart'
profile_timeout='750s'
package_name='com.meowwatch.meowwatch_mobile'

while (( $# > 0 )); do
  case "$1" in
    --serial) serial="${2:-}"; shift 2 ;;
    --apk) apk="${2:-}"; shift 2 ;;
    --driver) driver="${2:-}"; shift 2 ;;
    --target) target="${2:-}"; shift 2 ;;
    --timeout) profile_timeout="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! "$serial" =~ ^emulator-[0-9]+$ ]]; then
  echo '--serial must explicitly name an Android emulator, for example emulator-5554.' >&2
  exit 2
fi
for required in "$apk" "$driver" "$target"; do
  if [[ ! -f "$required" ]]; then
    echo "Required file does not exist: $required" >&2
    exit 2
  fi
done
if [[ ! "$profile_timeout" =~ ^[1-9][0-9]*[smh]?$ ]]; then
  echo '--timeout must be a positive GNU timeout duration such as 750s.' >&2
  exit 2
fi
for tool in adb flutter timeout sha256sum; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required journey tool is unavailable: $tool" >&2
    exit 2
  fi
done
if [[ "$(adb -s "$serial" get-state 2>/dev/null || true)" != 'device' ]]; then
  echo "Selected Android emulator is unavailable: $serial" >&2
  exit 3
fi
if [[ "$(adb -s "$serial" shell getprop ro.kernel.qemu 2>/dev/null | tr -d '\r\n')" != '1' ]]; then
  echo "Selected serial is not an Android emulator: $serial" >&2
  exit 3
fi

artifact_root='build/app-journey-artifacts'
runner_root='build/app-journey-runner'
mkdir -p "$artifact_root" "$runner_root"
for fresh_root in "$artifact_root" "$runner_root"; do
  if find "$fresh_root" -mindepth 1 -print -quit | grep -q .; then
    echo "Journey output must be empty before a fresh run: $fresh_root" >&2
    exit 3
  fi
done

original_size_output="$(adb -s "$serial" shell wm size | tr -d '\r')"
original_density_output="$(adb -s "$serial" shell wm density | tr -d '\r')"
original_size_override="$(awk -F ': ' '/Override size:/ { print $2; exit }' <<< "$original_size_output")"
original_density_override="$(awk -F ': ' '/Override density:/ { print $2; exit }' <<< "$original_density_output")"
original_accelerometer_rotation="$(adb -s "$serial" shell settings get system accelerometer_rotation | tr -d '\r\n')"
original_user_rotation="$(adb -s "$serial" shell settings get system user_rotation | tr -d '\r\n')"
printf '%s\n' "$original_size_output" > "$artifact_root/original-wm-size.txt"
printf '%s\n' "$original_density_output" > "$artifact_root/original-wm-density.txt"

current_recorder_loop_pid=''
current_recorder_serial=''
current_recorder_pid_file=''
current_recorder_stop_file=''
restore_status=0

stop_current_recorder() {
  if [[ -z "$current_recorder_loop_pid" ]]; then
    return 0
  fi
  touch "$current_recorder_stop_file"
  for _ in $(seq 1 80); do
    if ! kill -0 "$current_recorder_loop_pid" 2>/dev/null; then
      break
    fi
    owned_pid=''
    if [[ -s "$current_recorder_pid_file" ]]; then
      owned_pid="$(tr -d '\r\n' < "$current_recorder_pid_file")"
    fi
    active_pid="$(adb -s "$current_recorder_serial" shell pidof screenrecord 2>/dev/null | tr -d '\r\n')"
    if [[ "$owned_pid" =~ ^[0-9]+$ && "$active_pid" == "$owned_pid" ]]; then
      adb -s "$current_recorder_serial" shell "kill -2 $owned_pid" >/dev/null 2>&1 || true
    fi
    sleep 0.25
  done
  if kill -0 "$current_recorder_loop_pid" 2>/dev/null; then
    owned_pid=''
    if [[ -s "$current_recorder_pid_file" ]]; then
      owned_pid="$(tr -d '\r\n' < "$current_recorder_pid_file")"
    fi
    active_pid="$(adb -s "$current_recorder_serial" shell pidof screenrecord 2>/dev/null | tr -d '\r\n')"
    if [[ "$owned_pid" =~ ^[0-9]+$ && "$active_pid" == "$owned_pid" ]]; then
      adb -s "$current_recorder_serial" shell "kill -15 $owned_pid" >/dev/null 2>&1 || true
    fi
  fi
  for _ in $(seq 1 40); do
    if ! kill -0 "$current_recorder_loop_pid" 2>/dev/null; then
      break
    fi
    sleep 0.25
  done
  if kill -0 "$current_recorder_loop_pid" 2>/dev/null; then
    owned_pid=''
    if [[ -s "$current_recorder_pid_file" ]]; then
      owned_pid="$(tr -d '\r\n' < "$current_recorder_pid_file")"
    fi
    active_pid="$(adb -s "$current_recorder_serial" shell pidof screenrecord 2>/dev/null | tr -d '\r\n')"
    if [[ "$owned_pid" =~ ^[0-9]+$ && "$active_pid" == "$owned_pid" ]]; then
      adb -s "$current_recorder_serial" shell "kill -9 $owned_pid" >/dev/null 2>&1 || true
    fi
    kill -TERM "$current_recorder_loop_pid" 2>/dev/null || true
    touch "$(dirname "$current_recorder_pid_file")/recorder.failed"
  fi
  wait "$current_recorder_loop_pid" 2>/dev/null || true
  current_recorder_loop_pid=''
  current_recorder_serial=''
  current_recorder_pid_file=''
  current_recorder_stop_file=''
}

restore_setting() {
  local namespace="$1"
  local key="$2"
  local value="$3"
  if [[ -z "$value" || "$value" == 'null' ]]; then
    adb -s "$serial" shell settings delete "$namespace" "$key" >/dev/null
  else
    adb -s "$serial" shell settings put "$namespace" "$key" "$value"
  fi
}

restore_device() {
  set +e
  stop_current_recorder
  if [[ -n "$original_size_override" ]]; then
    adb -s "$serial" shell wm size "$original_size_override"
  else
    adb -s "$serial" shell wm size reset
  fi
  size_restore_status=$?
  if [[ -n "$original_density_override" ]]; then
    adb -s "$serial" shell wm density "$original_density_override"
  else
    adb -s "$serial" shell wm density reset
  fi
  density_restore_status=$?
  restore_setting system accelerometer_rotation "$original_accelerometer_rotation"
  accelerometer_restore_status=$?
  restore_setting system user_rotation "$original_user_rotation"
  rotation_restore_status=$?
  restored_size_output="$(adb -s "$serial" shell wm size 2>/dev/null | tr -d '\r')"
  size_verify_status=$?
  restored_density_output="$(adb -s "$serial" shell wm density 2>/dev/null | tr -d '\r')"
  density_verify_status=$?
  restored_accelerometer_rotation="$(adb -s "$serial" shell settings get system accelerometer_rotation 2>/dev/null | tr -d '\r\n')"
  accelerometer_verify_status=$?
  restored_user_rotation="$(adb -s "$serial" shell settings get system user_rotation 2>/dev/null | tr -d '\r\n')"
  rotation_verify_status=$?
  restore_status=0
  for status in "$size_restore_status" "$density_restore_status" \
    "$accelerometer_restore_status" "$rotation_restore_status" \
    "$size_verify_status" "$density_verify_status" \
    "$accelerometer_verify_status" "$rotation_verify_status"; do
    if [[ "$status" -ne 0 ]]; then restore_status=1; fi
  done
  if [[ "$restored_size_output" != "$original_size_output" || \
        "$restored_density_output" != "$original_density_output" || \
        "$restored_accelerometer_rotation" != "$original_accelerometer_rotation" || \
        "$restored_user_rotation" != "$original_user_rotation" ]]; then
    restore_status=1
  fi
  printf '%s\n' "$restored_size_output" > "$artifact_root/restored-wm-size.txt" || restore_status=1
  printf '%s\n' "$restored_density_output" > "$artifact_root/restored-wm-density.txt" || restore_status=1
  {
    printf 'size_restore_exit\t%s\n' "$size_restore_status"
    printf 'density_restore_exit\t%s\n' "$density_restore_status"
    printf 'accelerometer_restore_exit\t%s\n' "$accelerometer_restore_status"
    printf 'rotation_restore_exit\t%s\n' "$rotation_restore_status"
    printf 'verified_equal_to_original\t%s\n' "$([[ "$restore_status" -eq 0 ]] && echo true || echo false)"
    printf 'restored_utc\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$artifact_root/device-restore.tsv" || restore_status=1
  set -e
}

final_status=0
on_exit() {
  incoming_status=$?
  trap - EXIT INT TERM
  if [[ "$final_status" -eq 0 && "$incoming_status" -ne 0 ]]; then
    final_status="$incoming_status"
  fi
  restore_device
  if [[ "$final_status" -eq 0 && "$restore_status" -ne 0 ]]; then
    final_status="$restore_status"
  fi
  exit "$final_status"
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

install_log="$artifact_root/apk-install.log"
set +e
adb -s "$serial" install -r -t "$apk" > "$install_log" 2>&1
install_status=$?
set -e
if [[ "$install_status" -ne 0 ]]; then
  cat "$install_log" >&2
  exit "$install_status"
fi
sha256sum "$apk" > "$artifact_root/application.apk.sha256"

declare -a profiles=(phone small tablet landscape)
declare -A profile_size=(
  [phone]='1080x2400'
  [small]='720x1280'
  [tablet]='1600x2560'
  [landscape]='720x1600'
)
declare -A profile_density=(
  [phone]='420'
  [small]='320'
  [tablet]='320'
  [landscape]='320'
)
declare -A profile_rotation=(
  [phone]='0'
  [small]='0'
  [tablet]='1'
  [landscape]='1'
)
declare -A profile_vm_port=(
  [phone]='39301'
  [small]='39302'
  [tablet]='39303'
  [landscape]='39304'
)

record_segments() {
  local profile="$1"
  local remote_dir="$2"
  local profile_runner="$3"
  local stop_file="$profile_runner/recorder.stop"
  local pid_file="$profile_runner/recorder.pid"
  local timing_file="$profile_runner/screenrecord-segments.tsv"
  local segment=0
  while [[ ! -e "$stop_file" ]]; do
    local name
    name="$(printf '%s-%03d.mp4' "$profile" "$segment")"
    local command_ns
    command_ns="$(date +%s%N)"
    adb -s "$serial" shell screenrecord \
      --bit-rate 6000000 \
      --time-limit 170 \
      "$remote_dir/$name" \
      >> "$profile_runner/screenrecord.log" 2>&1 &
    local adb_pid=$!
    local remote_pid=''
    local deadline=$((SECONDS + 10))
    while (( SECONDS < deadline )); do
      remote_pid="$(adb -s "$serial" shell pidof screenrecord 2>/dev/null | tr -d '\r\n')"
      if [[ "$remote_pid" =~ ^[0-9]+$ ]]; then break; fi
      sleep 0.25
    done
    if [[ ! "$remote_pid" =~ ^[0-9]+$ ]]; then
      echo 'Could not identify the task-owned screenrecord PID.' >> "$profile_runner/screenrecord.log"
      touch "$profile_runner/recorder.failed"
      wait "$adb_pid" 2>/dev/null || true
      return 1
    fi
    printf '%s\n' "$remote_pid" > "$pid_file"
    printf '%s\t%s\t%s\n' "$segment" "$command_ns" "$name" >> "$timing_file"
    if [[ "$segment" -eq 0 ]]; then printf '%s\n' "$command_ns" > "$profile_runner/recorder.ready"; fi
    wait "$adb_pid" 2>/dev/null || true
    rm -f "$pid_file"
    segment=$((segment + 1))
  done
}

run_profile() {
  local profile="$1"
  local size="${profile_size[$profile]}"
  local density="${profile_density[$profile]}"
  local rotation="${profile_rotation[$profile]}"
  local vmservice_port="${profile_vm_port[$profile]}"
  local profile_runner="$runner_root/$profile"
  local profile_artifact="$artifact_root/$profile"
  local remote_dir="/sdcard/meowwatch-app-journey-${profile}-$$"
  local existing_recorder=''
  mkdir -p "$profile_runner/segments" || return 9
  {
    printf 'profile\t%s\n' "$profile"
    printf 'runtime\tAndroid Emulator wm override on one explicitly selected AVD\n'
    printf 'serial\t%s\n' "$serial"
    printf 'requested_size\t%s\n' "$size"
    printf 'requested_density\t%s\n' "$density"
    printf 'requested_rotation\t%s\n' "$rotation"
    printf 'vmservice_port\t%s\n' "$vmservice_port"
    printf 'outer_timeout\t%s\n' "$profile_timeout"
    printf 'package\t%s\n' "$package_name"
    printf 'started_utc\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$profile_runner/profile.tsv"

  adb -s "$serial" shell wm size "$size" || return 9
  adb -s "$serial" shell wm density "$density" || return 9
  adb -s "$serial" shell settings put system accelerometer_rotation 0 || return 9
  adb -s "$serial" shell settings put system user_rotation "$rotation" || return 9
  sleep 2

  clear_result="$(adb -s "$serial" shell pm clear "$package_name" | tr -d '\r\n')"
  printf 'pm_clear\t%s\n' "$clear_result" >> "$profile_runner/profile.tsv"
  if [[ "$clear_result" != 'Success' ]]; then
    echo "$profile: pm clear failed: $clear_result" >&2
    return 4
  fi

  adb -s "$serial" logcat -c || return 9
  adb -s "$serial" shell mkdir -p "$remote_dir" || return 9
  adb -s "$serial" shell wm size > "$profile_runner/wm-size.txt" || return 9
  adb -s "$serial" shell wm density > "$profile_runner/wm-density.txt" || return 9
  adb -s "$serial" shell dumpsys display > "$profile_runner/display-before.txt" || return 9
  adb -s "$serial" shell dumpsys window displays > "$profile_runner/window-before.txt" || return 9
  adb -s "$serial" shell getprop > "$profile_runner/device-properties.txt" || return 9
  adb -s "$serial" exec-out screencap -p > "$profile_runner/before.png" || return 9
  existing_recorder="$(adb -s "$serial" shell pidof screenrecord 2>/dev/null | tr -d '\r\n')"
  if [[ -n "$existing_recorder" ]]; then
    echo "$profile: refusing to interfere with existing screenrecord PID(s): $existing_recorder" >&2
    return 5
  fi
  record_segments "$profile" "$remote_dir" "$profile_runner" &
  current_recorder_loop_pid=$!
  current_recorder_serial="$serial"
  current_recorder_pid_file="$profile_runner/recorder.pid"
  current_recorder_stop_file="$profile_runner/recorder.stop"
  ready_deadline=$((SECONDS + 15))
  while [[ ! -s "$profile_runner/recorder.ready" ]]; do
    if (( SECONDS >= ready_deadline )) || ! kill -0 "$current_recorder_loop_pid" 2>/dev/null; then
      echo "$profile: native recorder did not become ready." >&2
      stop_current_recorder
      return 5
    fi
    sleep 0.25
  done

  set +e
  UI_PROFILE="$profile" timeout --signal=INT --kill-after=30s "$profile_timeout" \
    flutter drive \
      --no-pub \
      --driver="$driver" \
      --target="$target" \
      --use-application-binary="$apk" \
      --host-vmservice-port="$vmservice_port" \
      -d "$serial" \
      2>&1 | tee "$profile_runner/flutter-drive.log"
  drive_pipeline_status=("${PIPESTATUS[@]}")
  drive_status="${drive_pipeline_status[0]}"
  tee_status="${drive_pipeline_status[1]}"

  stop_current_recorder
  set +e
  adb -s "$serial" pull "$remote_dir/." "$profile_runner/segments/" \
    >> "$profile_runner/screenrecord.log" 2>&1
  pull_status=$?
  capture_status=0
  adb -s "$serial" exec-out screencap -p > "$profile_runner/after.png" || capture_status=1
  adb -s "$serial" logcat -d -v threadtime > "$profile_runner/logcat.txt" || capture_status=1
  adb -s "$serial" shell dumpsys display > "$profile_runner/display-after.txt" || capture_status=1
  adb -s "$serial" shell dumpsys window displays > "$profile_runner/window-after.txt" || capture_status=1
  adb -s "$serial" shell dumpsys media.codec > "$profile_runner/media-codec.txt" || capture_status=1
  adb -s "$serial" shell dumpsys SurfaceFlinger --list > "$profile_runner/surfaceflinger-layers.txt" || capture_status=1

  find "$profile_runner/segments" -type f -name '*.mp4' -size +4096c \
    -print0 | sort -z | xargs -0 -r sha256sum > "$profile_runner/native-segments.sha256"
  hash_status=$?
  evidence_status=0
  if [[ "$tee_status" -ne 0 || "$pull_status" -ne 0 || \
        "$capture_status" -ne 0 || \
        "$hash_status" -ne 0 || \
        ! -s "$profile_runner/native-segments.sha256" || \
        ! -s "$profile_runner/flutter-drive.log" || \
        ! -s "$profile_runner/before.png" || \
        ! -s "$profile_runner/after.png" || \
        ! -s "$profile_runner/logcat.txt" || \
        -e "$profile_runner/recorder.failed" ]]; then
    evidence_status=1
  fi
  {
    printf 'flutter_drive_exit\t%s\n' "$drive_status"
    printf 'flutter_log_tee_exit\t%s\n' "$tee_status"
    printf 'recording_pull_exit\t%s\n' "$pull_status"
    printf 'native_capture_exit\t%s\n' "$capture_status"
    printf 'recording_hash_exit\t%s\n' "$hash_status"
    printf 'recording_evidence_exit\t%s\n' "$evidence_status"
    printf 'finished_utc\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >> "$profile_runner/profile.tsv"

  mkdir -p "$profile_artifact" || return 6
  if [[ -e "$profile_artifact/native" ]]; then
    echo "$profile: native artifact destination already exists." >&2
    return 6
  fi
  mv "$profile_runner" "$profile_artifact/native" || return 6

  if [[ "$drive_status" -ne 0 ]]; then return "$drive_status"; fi
  if [[ "$evidence_status" -ne 0 ]]; then return 1; fi
  if [[ ! -s "$profile_artifact/result.json" ]]; then
    echo "$profile: integration driver result.json is missing." >&2
    return 7
  fi
  return 0
}

{
  printf 'serial\t%s\n' "$serial"
  printf 'apk\t%s\n' "$apk"
  printf 'driver\t%s\n' "$driver"
  printf 'target\t%s\n' "$target"
  printf 'profile_timeout\t%s\n' "$profile_timeout"
  printf 'runtime_boundary\tall profiles are wm overrides on the same AVD\n'
} > "$artifact_root/run-environment.tsv"

for profile in "${profiles[@]}"; do
  set +e
  run_profile "$profile"
  profile_status=$?
  set -e
  if [[ -d "$runner_root/$profile" ]]; then
    mkdir -p "$artifact_root/$profile"
    if [[ ! -e "$artifact_root/$profile/native" ]]; then
      mv "$runner_root/$profile" "$artifact_root/$profile/native"
    fi
  fi
  printf '%s\t%s\n' "$profile" "$profile_status" >> "$artifact_root/profile-exits.tsv"
  if [[ "$final_status" -eq 0 && "$profile_status" -ne 0 ]]; then
    final_status="$profile_status"
  fi
  if [[ "$(adb -s "$serial" get-state 2>/dev/null || true)" != 'device' ]]; then
    echo 'Selected emulator became unavailable; remaining profiles cannot run.' >&2
    if [[ "$final_status" -eq 0 ]]; then final_status=8; fi
    break
  fi
done

exit "$final_status"
