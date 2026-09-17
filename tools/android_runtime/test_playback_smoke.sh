#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/device"

cat > "$test_root/bin/adb" <<'ADB'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$FAKE_ADB_LOG"
device_path() {
  printf '%s%s\n' "$FAKE_ANDROID_STORAGE" "$1"
}

if [[ "${1:-}" == shell ]]; then
  shift
  if [[ "$#" -eq 1 && "$1" == kill\ -* ]]; then
    # A background Bash process inherits SIGINT ignored; TERM exercises the
    # same owned-recorder shutdown path without pretending to be screenrecord.
    kill -TERM "${1##* }"
    exit 0
  fi
  case "${1:-}" in
    mkdir)
      remote="${*: -1}"
      attempts=0
      if [[ -f "$FAKE_ANDROID_STORAGE/mkdir-attempts" ]]; then
        attempts=$(cat "$FAKE_ANDROID_STORAGE/mkdir-attempts")
      fi
      attempts=$((attempts + 1))
      printf '%s' "$attempts" > "$FAKE_ANDROID_STORAGE/mkdir-attempts"
      if (( attempts < 3 )); then
        echo "mkdir: '$remote': No such file or directory" >&2
        exit 1
      fi
      mkdir -p "$(device_path "$remote")"
      ;;
    pidof)
      if [[ -s "$FAKE_SCREENRECORD_PID" ]]; then
        pid=$(cat "$FAKE_SCREENRECORD_PID")
        if kill -0 "$pid" 2>/dev/null; then
          printf '%s\n' "$pid"
        fi
      fi
      ;;
    touch)
      attempts=0
      if [[ -f "$FAKE_ANDROID_STORAGE/file-attempts" ]]; then
        attempts=$(cat "$FAKE_ANDROID_STORAGE/file-attempts")
      fi
      attempts=$((attempts + 1))
      printf '%s' "$attempts" > "$FAKE_ANDROID_STORAGE/file-attempts"
      if (( attempts < 3 )); then
        echo 'MediaProvider: Volume external_primary not found' >&2
        exit 1
      fi
      touch "$(device_path "$2")"
      ;;
    screenrecord)
      remote="${*: -1}"
      if [[ ! "$remote" =~ ^/sdcard/meowwatch-runtime-[0-9]+-[0-9]+/playback-smoke-[0-9]+\.mp4$ ]]; then
        echo "Unable to open '$remote': Operation not permitted" >&2
        exit 1
      fi
      # The directory can exist before MediaProvider accepts media files.
      if [[ ! -f "$FAKE_ANDROID_STORAGE/file-attempts" ]] ||
         (( $(cat "$FAKE_ANDROID_STORAGE/file-attempts") < 3 )); then
        echo "Unable to open '$remote': Operation not permitted" >&2
        exit 1
      fi
      local_file=$(device_path "$remote")
      printf '%s' "$$" > "$FAKE_SCREENRECORD_PID"
      finish_recording() {
        mkdir -p "$(dirname "$local_file")"
        head -c "${FAKE_RECORDING_BYTES:-8192}" /dev/zero > "$local_file"
        rm -f "$FAKE_SCREENRECORD_PID"
        exit 0
      }
      trap finish_recording INT TERM
      while :; do sleep 0.1; done
      ;;
    rm)
      rm -f "$(device_path "${*: -1}")"
      ;;
    rmdir)
      rmdir "$(device_path "${*: -1}")"
      ;;
    getprop)
      printf '[ro.build.version.sdk]: [35]\n'
      ;;
    dumpsys)
      printf 'fake diagnostic\n'
      ;;
    *) ;;
  esac
  exit 0
fi

case "${1:-}" in
  pull)
    cp "$(device_path "$2")" "$3"
    ;;
  logcat) ;;
  *) ;;
esac
ADB

cat > "$test_root/bin/flutter" <<'FLUTTER'
#!/usr/bin/env bash
set -euo pipefail
sleep 1
printf 'All tests passed.\n'
exit "${FAKE_FLUTTER_EXIT:-0}"
FLUTTER
chmod +x "$test_root/bin/adb" "$test_root/bin/flutter"

(
  cd "$test_root"
  PATH="$test_root/bin:$PATH" \
    FAKE_ADB_LOG="$test_root/adb.log" \
    FAKE_ANDROID_STORAGE="$test_root/device" \
    FAKE_SCREENRECORD_PID="$test_root/screenrecord.pid" \
    GITHUB_RUN_ID=123456 \
    GITHUB_RUN_ATTEMPT=2 \
    bash "$repo_root/tools/android_runtime/playback-smoke.sh"
)

recording="$test_root/build/android-runtime-artifacts/recording/playback-smoke-000.mp4"
test -f "$recording"
test "$(wc -c < "$recording")" -eq 8192
grep -Fq \
  'shell screenrecord --bit-rate 4000000 --time-limit 170 /sdcard/meowwatch-runtime-123456-2/playback-smoke-000.mp4' \
  "$test_root/adb.log"
test ! -e "$test_root/device/sdcard/meowwatch-runtime-123456-2"
test "$(cat "$test_root/device/mkdir-attempts")" -eq 5
test "$(cat "$test_root/device/file-attempts")" -eq 3
grep -Fq $'flutter_drive_exit\t0' \
  "$test_root/build/android-runtime-artifacts/exit-codes.tsv"
grep -Fq $'screenrecord_files\t1' \
  "$test_root/build/android-runtime-artifacts/exit-codes.tsv"
grep -Fq $'final_exit\t0' \
  "$test_root/build/android-runtime-artifacts/exit-codes.tsv"

check_failure() {
  local name="$1" bytes="$2" flutter_exit="$3" expected_exit="$4"
  local case_root="$test_root/$name"
  mkdir -p "$case_root/device"
  set +e
  (
    cd "$case_root"
    PATH="$test_root/bin:$PATH" \
      FAKE_ADB_LOG="$case_root/adb.log" \
      FAKE_ANDROID_STORAGE="$case_root/device" \
      FAKE_SCREENRECORD_PID="$case_root/screenrecord.pid" \
      FAKE_RECORDING_BYTES="$bytes" \
      FAKE_FLUTTER_EXIT="$flutter_exit" \
      GITHUB_RUN_ID=123456 \
      GITHUB_RUN_ATTEMPT=2 \
      bash "$repo_root/tools/android_runtime/playback-smoke.sh"
  )
  local status=$?
  set -e
  test "$status" -eq "$expected_exit"
  grep -Fq $'flutter_drive_exit\t'"$flutter_exit" \
    "$case_root/build/android-runtime-artifacts/exit-codes.tsv"
  grep -Fq $'final_exit\t'"$expected_exit" \
    "$case_root/build/android-runtime-artifacts/exit-codes.tsv"
}

# Storage readiness never turns absent recording or failed native tests green.
check_failure empty-recording 0 0 1
grep -Fq $'screenrecord_files\t0' \
  "$test_root/empty-recording/build/android-runtime-artifacts/exit-codes.tsv"
check_failure native-failure 8192 7 7

echo 'playback smoke recording contract passed'
