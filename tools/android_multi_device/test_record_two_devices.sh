#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/device"

cat > "$test_root/bin/adb" <<'ADB'
#!/usr/bin/env bash
set -euo pipefail

serial=''
if [[ "${1:-}" == -s ]]; then
  serial="$2"
  shift 2
fi
printf '%s\t%s\n' "$serial" "$*" >> "$FAKE_ADB_LOG"
serial_root="$FAKE_ANDROID_STORAGE/$serial"
pid_file="$FAKE_ANDROID_STORAGE/$serial.screenrecord.pid"
device_path() {
  printf '%s%s\n' "$serial_root" "$1"
}

if [[ "${1:-}" == shell ]]; then
  shift
  if [[ "$#" -eq 1 && "$1" == kill\ -* ]]; then
    # Background Bash ignores SIGINT. TERM exercises the same owned-recorder
    # shutdown path without changing the production signal sent to Android.
    kill -TERM "${1##* }"
    exit 0
  fi
  case "${1:-}" in
    mkdir)
      remote="${*: -1}"
      mkdir -p "$(device_path "$remote")"
      ;;
    pidof)
      if [[ -s "$pid_file" ]]; then
        pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
          printf '%s\n' "$pid"
        fi
      fi
      ;;
    screenrecord)
      remote="${*: -1}"
      if [[ ! "$remote" =~ ^/sdcard/meowwatch-evidence-[0-9TZ]+-[0-9]+-(phone|tablet)/(phone|tablet)-[0-9]+\.mp4$ ]]; then
        echo "Unable to open '$remote': Operation not permitted" >&2
        exit 1
      fi
      local_file=$(device_path "$remote")
      echo "fake screenrecord diagnostic for $serial" >&2
      printf '%s' "$$" > "$pid_file"
      finish_recording() {
        mkdir -p "$(dirname "$local_file")"
        if [[ "${FAKE_SCENARIO:-}" == missing-phone-clip && \
              "$serial" == emulator-5554 ]]; then
          : > "$local_file"
        else
          head -c 8192 /dev/zero > "$local_file"
        fi
        rm -f "$pid_file"
        exit 0
      }
      trap finish_recording INT TERM
      while :; do sleep 0.1; done
      ;;
    rm)
      remote="${*: -1}"
      if [[ "${FAKE_SCENARIO:-}" == cleanup-warning && \
            "$serial" == emulator-5554 && "$remote" == *.mp4 ]]; then
        echo 'remote cleanup unavailable' >&2
        exit 1
      fi
      rm -f "$(device_path "$remote")"
      ;;
    rmdir)
      rmdir "$(device_path "${*: -1}")"
      ;;
    getprop)
      printf '[ro.build.version.sdk]: [35]\n'
      ;;
    wm)
      printf 'Physical size: 1080x1920\n'
      ;;
    dumpsys)
      printf 'fake diagnostic\n'
      ;;
    *) ;;
  esac
  exit 0
fi

case "${1:-}" in
  get-state)
    count_file="$FAKE_ANDROID_STORAGE/$serial.get-state.count"
    count=0
    [[ -f "$count_file" ]] && count=$(cat "$count_file")
    count=$((count + 1))
    printf '%s' "$count" > "$count_file"
    if [[ "${FAKE_SCENARIO:-}" == transient && \
          "$serial" == emulator-5556 && "$count" -eq 2 ]]; then
      printf 'offline\n'
    else
      printf 'device\n'
    fi
    ;;
  pull)
    if [[ "${FAKE_SCENARIO:-}" == persistent-tablet-pull && \
          "$serial" == emulator-5556 ]]; then
      echo 'adb: error: failed to get feature set: device offline' >&2
      exit 1
    fi
    cp "$(device_path "$2")" "$3"
    ;;
  exec-out)
    printf 'fake-png'
    ;;
  logcat)
    if [[ "${2:-}" == -d ]]; then
      printf 'fake logcat diagnostic\n'
    fi
    ;;
  *) ;;
esac
ADB

cat > "$test_root/bin/ffmpeg" <<'FFMPEG'
#!/usr/bin/env bash
set -euo pipefail
head -c 8192 /dev/zero > "${*: -1}"
FFMPEG
cat > "$test_root/bin/ffprobe" <<'FFPROBE'
#!/usr/bin/env bash
set -euo pipefail
printf '{"streams":[{"codec_name":"h264","width":1080,"height":1920}]}\n'
FFPROBE
chmod +x "$test_root/bin/adb" "$test_root/bin/ffmpeg" "$test_root/bin/ffprobe"

cat > "$test_root/session.env" <<EOF
ADB=$test_root/bin/adb
PHONE_SERIAL=emulator-5554
TABLET_SERIAL=emulator-5556
SESSION_DIR=$test_root/session
EOF

# Production UI uses a 600-second outer recording window around its bounded
# 540-second drive. Validate that contract without waiting for a recording by
# continuing as far as the deliberately invalid bit-rate argument.
set +e
production_window_error="$(
  bash "$repo_root/tools/android_multi_device/record_two_devices.sh" \
    --session "$test_root/session.env" \
    --seconds 600 \
    --bit-rate 0 \
    2>&1
)"
production_window_status=$?
set -e
test "$production_window_status" -eq 2
grep -Fq -- '--bit-rate must be an integer of at least 1000000.' \
  <<< "$production_window_error"
if grep -Fq -- '--seconds must be an integer' <<< "$production_window_error"; then
  echo 'Production recording window was rejected before recorder startup.' >&2
  exit 1
fi

set +e
overlong_window_error="$(
  bash "$repo_root/tools/android_multi_device/record_two_devices.sh" \
    --session "$test_root/session.env" \
    --seconds 601 \
    2>&1
)"
overlong_window_status=$?
set -e
test "$overlong_window_status" -eq 2
grep -Fq -- '--seconds must be an integer from 1 through 600.' \
  <<< "$overlong_window_error"

run_case() {
  local name="$1"
  local scenario="$2"
  local command_exit="${3:-0}"
  local case_root="$test_root/$name"
  mkdir -p "$case_root/device"
  set +e
  PATH="$test_root/bin:$PATH" \
    FAKE_ADB_LOG="$case_root/adb.log" \
    FAKE_ANDROID_STORAGE="$case_root/device" \
    FAKE_SCENARIO="$scenario" \
    bash "$repo_root/tools/android_multi_device/record_two_devices.sh" \
      --session "$test_root/session.env" \
      --output "$case_root/evidence" \
      --seconds 5 \
      -- sh -c 'exit "$1"' recorder-contract "$command_exit"
  case_status=$?
  set -e
}

run_case transient transient
test "$case_status" -eq 0
evidence="$test_root/transient/evidence"

for role in phone tablet; do
  serial=emulator-5554
  [[ "$role" == tablet ]] && serial=emulator-5556
  segment="$evidence/$role-$serial/segments/$role-000.mp4"
  test -f "$segment"
  test "$(wc -c < "$segment")" -eq 8192
  segment_log="$evidence/$role-$serial/segments/$role-000.mp4.screenrecord.log"
  test -s "$segment_log"
  grep -Fq "fake screenrecord diagnostic for $serial" "$segment_log"
  test ! -e "$evidence/recorder-control/$role.failed"
  if find "$test_root/transient/device/$serial/sdcard" -maxdepth 1 \
      -type d -name "meowwatch-evidence-*-$role" -print -quit | grep -q .; then
    echo "Remote $role recording directory was not removed." >&2
    exit 1
  fi
  grep -Fq "$role"$'\tclean' "$evidence/recording-cleanup.tsv"
done

phone_ns=$(awk -F '\t' '$1 == "phone_first_segment_ns" {print $2}' \
  "$evidence/recording-session.tsv")
tablet_ns=$(awk -F '\t' '$1 == "tablet_first_segment_ns" {print $2}' \
  "$evidence/recording-session.tsv")
delta_ms=$(( (tablet_ns - phone_ns) / 1000000 ))
(( delta_ms >= -1000 && delta_ms <= 1000 ))
grep -Eq $'emulator-5554\tshell screenrecord .* /sdcard/meowwatch-evidence-.+-phone/phone-000.mp4$' \
  "$test_root/transient/adb.log"
grep -Eq $'emulator-5556\tshell screenrecord .* /sdcard/meowwatch-evidence-.+-tablet/tablet-000.mp4$' \
  "$test_root/transient/adb.log"

run_case cleanup cleanup-warning
test "$case_status" -eq 0
test -s "$test_root/cleanup/evidence/phone-emulator-5554/segments/phone-000.mp4"
test ! -e "$test_root/cleanup/evidence/recorder-control/phone.failed"
test -e "$test_root/cleanup/evidence/recorder-control/phone.cleanup-warning"
grep -Fq $'phone\twarning' \
  "$test_root/cleanup/evidence/recording-cleanup.tsv"
grep -Fq $'tablet\tclean' \
  "$test_root/cleanup/evidence/recording-cleanup.tsv"

run_case persistent persistent-tablet-pull 7
test "$case_status" -eq 7
test -e "$test_root/persistent/evidence/recorder-control/tablet.failed"
tablet_pull_attempts=$(grep -Ec $'^emulator-5556\tpull ' \
  "$test_root/persistent/adb.log")
test "$tablet_pull_attempts" -eq 3
test ! -e \
  "$test_root/persistent/evidence/tablet-emulator-5556/segments/tablet-000.mp4.partial"

run_case missing_phone missing-phone-clip 7
test "$case_status" -eq 7
missing_phone_evidence="$test_root/missing_phone/evidence"
test ! -s \
  "$missing_phone_evidence/phone-emulator-5554/native-segments.sha256"
test -s \
  "$missing_phone_evidence/tablet-emulator-5556/native-segments.sha256"
test -s "$missing_phone_evidence/tablet-emulator-5556/native.mp4"
test -s "$missing_phone_evidence/tablet-emulator-5556/after.png"
test -s "$missing_phone_evidence/tablet-emulator-5556/logcat.txt"
test -s "$missing_phone_evidence/tablet-emulator-5556/media-codec.txt"
test -s "$missing_phone_evidence/tablet-emulator-5556/display-after.txt"

echo 'two-device recording duration, path and alignment contract passed'
