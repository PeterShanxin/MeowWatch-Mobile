#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == '-h' || "${1:-}" == '--help' ]]; then
  cat <<'EOF'
Usage: ci_together.sh

Runs the prepared host/guest APKs on two task-owned AVDs, records both native
displays for the full smoke, creates a side-by-side review video when possible,
and cleans up only the server and AVDs described by this run's state files.
EOF
  exit 0
fi
if [[ $# -ne 0 ]]; then
  echo 'ci_together.sh takes no arguments.' >&2
  exit 2
fi

runtime_root='build/android-multi-device'
fixture_file="$runtime_root/fixture/sync-fixture.mp4"
provenance_file="$runtime_root/apks/build-provenance.tsv"
host_apk="$runtime_root/apks/host.apk"
guest_apk="$runtime_root/apks/guest.apk"
server_state="$runtime_root/fixture-server"
server_env="$server_state/server.env"
sessions_root="$runtime_root/sessions"
result_file="$runtime_root/ci-result.tsv"
session_file=''
current_stage='preflight'
launch_status='not-run'
smoke_status='not-run'
composition_status='not-run'

field() {
  local name="$1"
  awk -F '\t' -v name="$name" '$1 == name { print $2; exit }' "$provenance_file"
}

for required in "$fixture_file" "$provenance_file" "$host_apk" "$guest_apk"; do
  if [[ ! -s "$required" ]]; then
    echo "Prepared runtime input is missing or empty: $required" >&2
    exit 2
  fi
done

room="$(field room)"
server="$(field server)"
port="$(field port)"
video_url="$(field video_url)"
if [[ ! "$room" =~ ^[A-Za-z0-9._-]+$ || -z "$server" || \
      ! "$port" =~ ^[0-9]+$ ]]; then
  echo 'APK build provenance is incomplete or invalid.' >&2
  exit 3
fi
expected_video_url='http://10.0.2.2:18765/sync-fixture.mp4'
if [[ "$video_url" != "$expected_video_url" ]]; then
  echo "Prepared APK video URL does not match the scoped fixture: $video_url" >&2
  exit 3
fi

mkdir -p "$sessions_root"
if find "$sessions_root" -mindepth 1 -print -quit | grep -q .; then
  echo "AVD session output must be empty: $sessions_root" >&2
  exit 3
fi

on_exit() {
  local primary_status=$?
  trap - EXIT INT TERM
  set +e
  local avd_cleanup_status=0
  local server_cleanup_status=0
  if [[ -n "$session_file" && -f "$session_file" ]]; then
    bash tools/android_multi_device/stop_two_avds.sh \
      "$session_file" --delete-avds
    avd_cleanup_status=$?
  fi
  if [[ -f "$server_env" ]]; then
    bash tools/android_multi_device/stop_fixture_server.sh "$server_env"
    server_cleanup_status=$?
  fi
  mkdir -p "$runtime_root"
  {
    printf 'last_stage\t%s\n' "$current_stage"
    printf 'primary_exit\t%s\n' "$primary_status"
    printf 'launch_exit\t%s\n' "$launch_status"
    printf 'smoke_exit\t%s\n' "$smoke_status"
    printf 'composition_exit\t%s\n' "$composition_status"
    printf 'avd_cleanup_exit\t%s\n' "$avd_cleanup_status"
    printf 'server_cleanup_exit\t%s\n' "$server_cleanup_status"
    printf 'finished_utc\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$result_file"
  local final_status="$primary_status"
  if [[ "$final_status" -eq 0 && "$avd_cleanup_status" -ne 0 ]]; then
    final_status="$avd_cleanup_status"
  fi
  if [[ "$final_status" -eq 0 && "$server_cleanup_status" -ne 0 ]]; then
    final_status="$server_cleanup_status"
  fi
  exit "$final_status"
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

current_stage='fixture-server'
bash tools/android_multi_device/start_fixture_server.sh \
  --fixture "$fixture_file" \
  --state "$server_state" \
  --port 18765

current_stage='avd-launch'
set +e
bash tools/android_multi_device/launch_two_avds.sh "$sessions_root" \
  2>&1 | tee "$runtime_root/avd-launch.log"
launch_status="${PIPESTATUS[0]}"
set -e
mapfile -t session_files < <(find "$sessions_root" -type f -name session.env -print)
if [[ "${#session_files[@]}" -eq 1 ]]; then
  session_file="${session_files[0]}"
fi
if [[ "$launch_status" -ne 0 ]]; then
  exit "$launch_status"
fi
if [[ -z "$session_file" ]]; then
  echo 'AVD launcher did not produce exactly one session.env.' >&2
  exit 4
fi

session_dir="$(dirname "$session_file")"
current_stage='recorded-smoke'
set +e
bash tools/android_multi_device/record_two_devices.sh \
  --session "$session_file" \
  --seconds 360 \
  -- bash tools/android_multi_device/run_together_smoke.sh \
    --session "$session_file" \
    --host-apk "$host_apk" \
    --guest-apk "$guest_apk" \
    --driver test_driver/together_smoke_driver.dart \
    --target integration_test/together_smoke_test.dart \
    --room "$room" \
    --server "$server" \
    --port "$port" \
    --video-url "$video_url"
smoke_status=$?
set -e

current_stage='composition'
phone_video="$session_dir/evidence/phone-emulator-5554/native.mp4"
tablet_video="$session_dir/evidence/tablet-emulator-5556/native.mp4"
timing_file="$session_dir/evidence/recording-session.tsv"
composition_status=0
if [[ -s "$phone_video" && -s "$tablet_video" && -s "$timing_file" ]]; then
  set +e
  bash tools/android_multi_device/compose_side_by_side.sh \
    "$phone_video" \
    "$tablet_video" \
    "$timing_file" \
    "$session_dir/evidence/meowwatch-two-device.mp4"
  composition_status=$?
  set -e
elif [[ "$smoke_status" -eq 0 ]]; then
  echo 'Smoke passed but native videos are incomplete; composition is required.' >&2
  composition_status=5
fi

if [[ "$smoke_status" -ne 0 ]]; then
  exit "$smoke_status"
fi
if [[ "$composition_status" -ne 0 ]]; then
  exit "$composition_status"
fi
current_stage='complete'
