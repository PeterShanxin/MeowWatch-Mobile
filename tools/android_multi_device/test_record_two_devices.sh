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
    touch)
      remote="${*: -1}"
      count_file="$FAKE_ANDROID_STORAGE/$serial.touch.count"
      count=0
      [[ -f "$count_file" ]] && count=$(cat "$count_file")
      printf '%s' "$((count + 1))" > "$count_file"
      if [[ "$serial" == emulator-5554 ]] && \
         { [[ "${FAKE_SCENARIO:-}" == storage-never ]] || \
           [[ "${FAKE_SCENARIO:-}" == storage-late && "$count" -lt 2 ]]; }; then
        echo 'touch: Operation not permitted; external_primary not attached' >&2
        exit 1
      fi
      touch "$(device_path "$remote")"
      ;;
    test)
      test "$2" "$(device_path "$3")"
      ;;
    pidof)
      if [[ -s "$pid_file" ]]; then
        pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
          printf '%s\n' "$pid"
          if [[ "${FAKE_SCENARIO:-}" == recorder-open-denied && \
                "$serial" == emulator-5554 ]]; then
            kill -TERM "$pid"
            sleep 0.1
          fi
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
      if [[ "${FAKE_SCENARIO:-}" == recorder-open-denied && \
            "$serial" == emulator-5554 ]]; then
        echo "Unable to open '$remote': Operation not permitted" >&2
        trap 'rm -f "$pid_file"; exit 1' TERM
        while :; do sleep 0.1; done
      fi
      mkdir -p "$(dirname "$local_file")"
      if [[ "${FAKE_SCENARIO:-}" != recorder-no-file || \
            "$serial" != emulator-5554 ]]; then
        head -c 8192 /dev/zero > "$local_file"
      fi
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
      while :; do
        if [[ "${FAKE_SCENARIO:-}" == recorder-dies-later && \
              "$serial" == emulator-5554 && -e "$FAKE_COMMAND_MARKER" ]]; then
          echo 'encoder failed after startup' >&2
          rm -f "$pid_file"
          exit 1
        fi
        sleep 0.1
      done
      ;;
    rm)
      remote="${*: -1}"
      if [[ "${FAKE_SCENARIO:-}" == cleanup-warning && \
            "$serial" == emulator-5554 && "$remote" == */phone-*.mp4 ]]; then
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
      if [[ "${2:-} ${3:-}" == 'window displays' ]]; then
        size=1080x2400
        if [[ "$serial" == emulator-5556 ]]; then
          size=1600x2560
          [[ "${FAKE_SCENARIO:-}" == landscape ]] && size=2560x1600
        fi
        count_file="$FAKE_ANDROID_STORAGE/$serial.display.count"
        count=0
        [[ -f "$count_file" ]] && count=$(cat "$count_file")
        printf '%s' "$((count + 1))" > "$count_file"
        # Initial evidence is deliberately stale: segment startup must refresh.
        [[ "$count" -eq 0 ]] && size=800x600
        printf '  Display: mDisplayId=0 (organized)\n    init=2560x1600 cur=%s app=%s\n' "$size" "$size"
        if [[ "${FAKE_SCENARIO:-}" == ambiguous ]]; then
          printf '    cur=100x200 app=100x200\n'
        fi
      else
        printf 'fake diagnostic\n'
      fi
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
  shift 3
  local case_root="$test_root/$name"
  mkdir -p "$case_root/device"
  set +e
  PATH="$test_root/bin:$PATH" \
    FAKE_ADB_LOG="$case_root/adb.log" \
    FAKE_ANDROID_STORAGE="$case_root/device" \
    FAKE_SCENARIO="$scenario" \
    FAKE_COMMAND_MARKER="$case_root/command-started" \
    bash "$repo_root/tools/android_multi_device/record_two_devices.sh" \
      --session "$test_root/session.env" \
      --output "$case_root/evidence" \
      --seconds 5 \
      "$@" \
      -- sh -c ': > "$2"; if [ "$3" = recorder-dies-later ]; then sleep 20; : > "$2.completed"; fi; exit "$1"' \
        recorder-contract "$command_exit" "$case_root/command-started" "$scenario" \
        > "$case_root/run.log" 2>&1
  case_status=$?
  set -e
  cat "$case_root/run.log"
}

run_case startup_denied recorder-open-denied 0
test "$case_status" -ne 0
test ! -e "$test_root/startup_denied/command-started"
test ! -e "$test_root/startup_denied/evidence/recorder-control/phone.ready"
test -e "$test_root/startup_denied/evidence/recorder-control/phone.failed"
grep -Fq 'Operation not permitted' \
  "$test_root/startup_denied/evidence/phone-emulator-5554/segments/phone-000.mp4.screenrecord.log"
test "$(grep -Ec $'^emulator-5554\tshell screenrecord ' \
  "$test_root/startup_denied/adb.log")" -eq 1

run_case no_file recorder-no-file 0
test "$case_status" -ne 0
test ! -e "$test_root/no_file/command-started"
test ! -e "$test_root/no_file/evidence/recorder-control/phone.ready"
test -e "$test_root/no_file/evidence/recorder-control/phone.failed"
test "$(grep -Ec $'^emulator-5554\tshell screenrecord ' \
  "$test_root/no_file/adb.log")" -eq 1

run_case storage_late storage-late 0
test "$case_status" -eq 0
test "$(cat "$test_root/storage_late/device/emulator-5554.touch.count")" -eq 3
test "$(grep -Fc 'external_primary not attached' \
  "$test_root/storage_late/evidence/phone-emulator-5554/storage-readiness.log")" -eq 2
test "$(grep -Ec $'^emulator-5554\tshell screenrecord ' \
  "$test_root/storage_late/adb.log")" -eq 1

run_case storage_never storage-never 0
test "$case_status" -ne 0
test ! -e "$test_root/storage_never/command-started"
test "$(grep -c 'shell screenrecord ' "$test_root/storage_never/adb.log" || true)" -eq 0
grep -Fq 'not writable within 20 seconds' \
  "$test_root/storage_never/evidence/phone-emulator-5554/storage-readiness.log"

run_case later_exit recorder-dies-later 0
test "$case_status" -ne 0
test -e "$test_root/later_exit/command-started"
test ! -e "$test_root/later_exit/command-started.completed"
test -e "$test_root/later_exit/evidence/recorder-control/phone.failed"
grep -Fq 'stopping the task-owned showcase command' "$test_root/later_exit/run.log"
test "$(grep -Ec $'^emulator-5554\tshell screenrecord ' \
  "$test_root/later_exit/adb.log")" -eq 1
test -s "$test_root/later_exit/evidence/phone-emulator-5554/segments/phone-000.mp4"
echo 'storage, stable native startup and active recorder failure contracts passed'

run_case transient transient 0
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

run_case cleanup cleanup-warning 0
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

for role in phone tablet; do
  for invalid in '' 0 1 3 4098 999999999999999999999 01600 720x1600 nope; do
    set +e
    error="$(bash "$repo_root/tools/android_multi_device/record_two_devices.sh" \
      --session "$test_root/session.env" "--$role-max-edge" "$invalid" 2>&1)"
    status=$?
    set -e
    test "$status" -eq 2
    grep -Fq -- "--$role-max-edge must be an even integer" <<< "$error"
  done
done

for orientation in portrait landscape; do
  run_case "$orientation" "$orientation" 0 \
    --phone-max-edge 1600 --tablet-max-edge 1280 --bit-rate 3000000
  test "$case_status" -eq 0
  evidence="$test_root/$orientation/evidence"
  tablet_source=1600x2560
  tablet_output=800x1280
  if [[ "$orientation" == landscape ]]; then
    tablet_source=2560x1600
    tablet_output=1280x800
  fi
  grep -Fq $'emulator-5554\tshell screenrecord --size 720x1600 --bit-rate 3000000' \
    "$test_root/$orientation/adb.log"
  grep -Fq "shell screenrecord --size $tablet_output --bit-rate 3000000" \
    "$test_root/$orientation/adb.log"
  grep -Fq $'0\tphone-000.mp4\t1080x2400\t720x1600' \
    "$evidence/phone-emulator-5554/recording-sizes.tsv"
  grep -Fq "0"$'\t'"tablet-000.mp4"$'\t'"$tablet_source"$'\t'"$tablet_output" \
    "$evidence/tablet-emulator-5556/recording-sizes.tsv"
  grep -Fq $'requested_bit_rate\t3000000' "$evidence/recording-session.tsv"
  if grep -Eq $'\tshell wm (size|density) [0-9]' "$test_root/$orientation/adb.log"; then
    echo 'Recorder changed Android display geometry.' >&2
    exit 1
  fi
done

run_case rounding portrait 0 --phone-max-edge 4096 --tablet-max-edge 1000
test "$case_status" -eq 0
grep -Fq 'shell screenrecord --size 1080x2400 --bit-rate 8000000' \
  "$test_root/rounding/adb.log"
grep -Fq 'shell screenrecord --size 624x1000 --bit-rate 8000000' \
  "$test_root/rounding/adb.log"

run_case ambiguous ambiguous 0 --phone-max-edge 1600 --tablet-max-edge 1280
test "$case_status" -ne 0
if grep -q 'shell screenrecord ' "$test_root/ambiguous/adb.log"; then
  echo 'Recorder accepted ambiguous source display dimensions.' >&2
  exit 1
fi
grep -Fq 'shell screenrecord --bit-rate 8000000' "$test_root/transient/adb.log"
echo 'per-device native recording size and bitrate contracts passed'
