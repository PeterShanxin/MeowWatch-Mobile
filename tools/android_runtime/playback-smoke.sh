#!/usr/bin/env bash
# Run as one shell: emulator-runner executes each inline script line separately.
set +e
artifact_dir=build/android-runtime-artifacts
recording_dir="$artifact_dir/recording"
recording_control_dir="$artifact_dir/screenrecord-control-${GITHUB_RUN_ATTEMPT}"
recording_stop_file="$recording_control_dir/stop"
recording_pid_file="$recording_control_dir/remote-pid"
recording_failure_file="$recording_control_dir/failed"
remote_recording_dir="/sdcard/meowwatch-runtime-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
mkdir -p "$recording_dir" "$recording_control_dir"
adb shell mkdir -p "$remote_recording_dir"

record_screen_segments() {
  segment=0
  while [ ! -e "$recording_stop_file" ]; do
    segment_name=$(printf 'playback-smoke-%03d.mp4' "$segment")
    adb shell screenrecord \
      --bit-rate 4000000 \
      --time-limit 170 \
      "$remote_recording_dir/$segment_name" \
      >> "$artifact_dir/screenrecord.log" 2>&1 &
    screenrecord_adb_pid=$!

    remote_pid=""
    for _ in $(seq 1 40); do
      remote_pid=$(adb shell pidof screenrecord 2>/dev/null | tr -d '\r\n')
      if [[ "$remote_pid" =~ ^[0-9]+$ ]]; then
        break
      fi
      sleep 0.25
    done
    printf '%s' "$remote_pid" > "$recording_pid_file"

    if [[ ! "$remote_pid" =~ ^[0-9]+$ ]]; then
      echo "Could not identify the owned Android screenrecord process." \
        >> "$artifact_dir/screenrecord.log"
      touch "$recording_failure_file"
      wait "$screenrecord_adb_pid"
      break
    fi

    wait "$screenrecord_adb_pid"
    segment=$((segment + 1))
  done
}

adb logcat -c
record_screen_segments &
recorder_loop_pid=$!

timeout --signal=INT --kill-after=30s 15m flutter drive \
  --driver=test_driver/playback_smoke_driver.dart \
  --target=integration_test/playback_smoke_test.dart \
  --use-application-binary=build/app/outputs/flutter-apk/app-debug.apk \
  -d emulator-5554 2>&1 | tee "$artifact_dir/flutter-drive.log"
test_status=${PIPESTATUS[0]}

touch "$recording_stop_file"
remote_pid=$(tr -d '\r\n' < "$recording_pid_file")
if [[ "$remote_pid" =~ ^[0-9]+$ ]]; then
  adb shell "kill -2 $remote_pid" >> "$artifact_dir/screenrecord.log" 2>&1
fi
wait "$recorder_loop_pid"
adb pull "$remote_recording_dir" "$recording_dir" \
  >> "$artifact_dir/screenrecord.log" 2>&1
recording_pull_status=$?
recording_count=$(find "$recording_dir" -type f -name 'playback-smoke-*.mp4' -size +4096c | wc -l)
if [ "$recording_pull_status" -ne 0 ] || \
   [ "$recording_count" -eq 0 ] || \
   [ -e "$recording_failure_file" ]; then
  echo "Android screen recording evidence is missing or invalid." \
    >> "$artifact_dir/screenrecord.log"
  if [ "$test_status" -eq 0 ]; then
    test_status=1
  fi
fi

adb logcat -d -v threadtime > "$artifact_dir/logcat.txt"
adb shell getprop > "$artifact_dir/device-properties.txt"
adb shell dumpsys media.codec > "$artifact_dir/media-codec.txt"
adb shell dumpsys SurfaceFlinger --list > "$artifact_dir/surfaceflinger-layers.txt"
exit "$test_status"
