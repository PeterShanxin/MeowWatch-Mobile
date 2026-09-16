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
adb shell mkdir -p "$remote_recording_dir" \
  >> "$artifact_dir/screenrecord.log" 2>&1
if [ "$?" -ne 0 ]; then
  echo "Could not create the owned Android recording directory." \
    >> "$artifact_dir/screenrecord.log"
  touch "$recording_failure_file"
fi

record_screen_segments() {
  segment=0
  while [ ! -e "$recording_stop_file" ]; do
    segment_name=$(printf 'playback-smoke-%03d.mp4' "$segment")
    remote_segment="$remote_recording_dir/$segment_name"
    adb shell screenrecord \
      --bit-rate 4000000 \
      --time-limit 170 \
      "$remote_segment" \
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
      adb shell rm -f "$remote_segment" \
        >> "$artifact_dir/screenrecord.log" 2>&1
      break
    fi

    wait "$screenrecord_adb_pid"
    : > "$recording_pid_file"
    adb pull "$remote_segment" "$recording_dir/$segment_name" \
      >> "$artifact_dir/screenrecord.log" 2>&1
    pull_status=$?
    adb shell rm -f "$remote_segment" \
      >> "$artifact_dir/screenrecord.log" 2>&1
    remove_status=$?
    if [ "$pull_status" -ne 0 ] || [ "$remove_status" -ne 0 ]; then
      echo "Could not transfer or remove owned Android recording: $remote_segment" \
        >> "$artifact_dir/screenrecord.log"
      touch "$recording_failure_file"
      break
    fi
    segment=$((segment + 1))
  done
}

adb logcat -c
existing_recorder=$(adb shell pidof screenrecord 2>/dev/null | tr -d '\r\n')
if [ -n "$existing_recorder" ]; then
  echo "Refusing to interfere with existing screenrecord PID(s): $existing_recorder" \
    >> "$artifact_dir/screenrecord.log"
  touch "$recording_failure_file"
  recorder_loop_pid=''
else
  record_screen_segments &
  recorder_loop_pid=$!
fi

timeout --signal=INT --kill-after=30s 15m flutter drive \
  --no-pub \
  --driver=test_driver/playback_smoke_driver.dart \
  --target=integration_test/playback_smoke_test.dart \
  --use-application-binary=build/app/outputs/flutter-apk/app-debug.apk \
  -d emulator-5554 2>&1 | tee "$artifact_dir/flutter-drive.log"
flutter_drive_status=${PIPESTATUS[0]}
test_status=$flutter_drive_status

touch "$recording_stop_file"
if [ -n "$recorder_loop_pid" ]; then
  for _ in $(seq 1 80); do
    if ! kill -0 "$recorder_loop_pid" 2>/dev/null; then
      break
    fi
    remote_pid=$(tr -d '\r\n' < "$recording_pid_file")
    active_pid=$(adb shell pidof screenrecord 2>/dev/null | tr -d '\r\n')
    if [[ "$remote_pid" =~ ^[0-9]+$ && "$active_pid" == "$remote_pid" ]]; then
      adb shell "kill -2 $remote_pid" >> "$artifact_dir/screenrecord.log" 2>&1
    fi
    sleep 0.25
  done
  if kill -0 "$recorder_loop_pid" 2>/dev/null; then
    remote_pid=$(tr -d '\r\n' < "$recording_pid_file")
    active_pid=$(adb shell pidof screenrecord 2>/dev/null | tr -d '\r\n')
    if [[ "$remote_pid" =~ ^[0-9]+$ && "$active_pid" == "$remote_pid" ]]; then
      adb shell "kill -15 $remote_pid" >> "$artifact_dir/screenrecord.log" 2>&1
    fi
  fi
  wait "$recorder_loop_pid"
fi
adb shell rmdir "$remote_recording_dir" \
  >> "$artifact_dir/screenrecord.log" 2>&1
recording_count=$(find "$recording_dir" -type f -name 'playback-smoke-*.mp4' -size +4096c | wc -l)
if [ "$recording_count" -eq 0 ] || \
   [ -e "$recording_failure_file" ]; then
  echo "Android screen recording evidence is missing or invalid." \
    >> "$artifact_dir/screenrecord.log"
  if [ "$test_status" -eq 0 ]; then
    test_status=1
  fi
fi

adb logcat -d -v threadtime > "$artifact_dir/logcat.txt"
adb shell getprop > "$artifact_dir/device-properties.txt"
adb shell dumpsys media.codec > "$artifact_dir/media-codec.txt" 2> "$artifact_dir/media-codec.stderr.txt"
media_codec_status=$?
adb shell dumpsys SurfaceFlinger --list > "$artifact_dir/surfaceflinger-layers.txt" 2> "$artifact_dir/surfaceflinger.stderr.txt"
surfaceflinger_status=$?
{
  printf 'flutter_drive_exit\t%s\n' "$flutter_drive_status"
  printf 'screenrecord_files\t%s\n' "$recording_count"
  printf 'media_codec_diagnostic_exit\t%s\n' "$media_codec_status"
  printf 'surfaceflinger_diagnostic_exit\t%s\n' "$surfaceflinger_status"
  printf 'final_exit\t%s\n' "$test_status"
} > "$artifact_dir/exit-codes.tsv"
exit "$test_status"
