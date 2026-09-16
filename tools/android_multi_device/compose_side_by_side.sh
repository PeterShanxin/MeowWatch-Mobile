#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: compose_side_by_side.sh <phone.mp4> <tablet.mp4> <recording-session.tsv> <output.mp4>

Creates a 1920x1080, constant-30-fps side-by-side presentation. It only scales,
pads, labels, and frame-rate-normalizes the two native Android recordings.
EOF
}

if [[ "${1:-}" == '--help' || "${1:-}" == '-h' ]]; then
  usage
  exit 0
fi
if [[ $# -ne 4 ]]; then
  usage >&2
  exit 2
fi

phone_video="$1"
tablet_video="$2"
timing_file="$3"
output_video="$4"
for input in "$phone_video" "$tablet_video"; do
  if [[ ! -s "$input" ]]; then
    echo "Input recording is missing or empty: $input" >&2
    exit 2
  fi
done
if [[ ! -f "$timing_file" ]]; then
  echo "Recording timing evidence is missing: $timing_file" >&2
  exit 2
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo 'ffmpeg is required for composition.' >&2
  exit 2
fi

mkdir -p "$(dirname "$output_video")"
font_file="${FONT_FILE:-/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf}"
if [[ ! -f "$font_file" ]]; then
  echo "Label font is unavailable: $font_file" >&2
  exit 2
fi

phone_start_ns="$(awk -F '\t' '$1 == "phone_first_segment_ns" { print $2 }' "$timing_file")"
tablet_start_ns="$(awk -F '\t' '$1 == "tablet_first_segment_ns" { print $2 }' "$timing_file")"
if [[ ! "$phone_start_ns" =~ ^[0-9]+$ || ! "$tablet_start_ns" =~ ^[0-9]+$ ]]; then
  echo 'Recording timing file does not contain valid recorder start timestamps.' >&2
  exit 2
fi
if (( phone_start_ns <= tablet_start_ns )); then
  phone_delay_ms=0
  tablet_delay_ms=$(( (tablet_start_ns - phone_start_ns) / 1000000 ))
else
  phone_delay_ms=$(( (phone_start_ns - tablet_start_ns) / 1000000 ))
  tablet_delay_ms=0
fi
phone_delay_seconds="$(awk -v ms="$phone_delay_ms" 'BEGIN { printf "%.3f", ms / 1000 }')"
tablet_delay_seconds="$(awk -v ms="$tablet_delay_ms" 'BEGIN { printf "%.3f", ms / 1000 }')"

filter="[0:v]fps=30,setpts=PTS-STARTPTS,tpad=start_mode=add:color=black:start_duration=${phone_delay_seconds},scale=680:880:force_original_aspect_ratio=decrease,pad=760:960:(ow-iw)/2:(oh-ih)/2:color=0x11151c,setsar=1,drawbox=x=0:y=0:w=iw:h=ih:color=0x38404d:t=2,drawtext=fontfile=${font_file}:text='PHONE  emulator-5554':fontcolor=white:fontsize=28:x=(w-text_w)/2:y=18[left];[1:v]fps=30,setpts=PTS-STARTPTS,tpad=start_mode=add:color=black:start_duration=${tablet_delay_seconds},scale=1000:880:force_original_aspect_ratio=decrease,pad=1080:960:(ow-iw)/2:(oh-ih)/2:color=0x11151c,setsar=1,drawbox=x=0:y=0:w=iw:h=ih:color=0x38404d:t=2,drawtext=fontfile=${font_file}:text='TABLET  emulator-5556':fontcolor=white:fontsize=28:x=(w-text_w)/2:y=18[right];[left][right]hstack=inputs=2:shortest=1[devices];[devices]pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=0x080a0f[out]"

ffmpeg -hide_banner -y \
  -i "$phone_video" \
  -i "$tablet_video" \
  -filter_complex "$filter" \
  -map '[out]' \
  -shortest \
  -an \
  -r 30 \
  -c:v libx264 \
  -preset medium \
  -crf 18 \
  -pix_fmt yuv420p \
  -movflags +faststart \
  "$output_video"

sha256sum "$output_video" > "$output_video.sha256"
if command -v ffprobe >/dev/null 2>&1; then
  ffprobe -v error \
    -select_streams v:0 \
    -show_entries stream=codec_name,width,height,r_frame_rate,avg_frame_rate,duration \
    -of json \
    "$output_video" \
    > "$output_video.ffprobe.json"
fi

printf 'Side-by-side recording: %s\n' "$output_video"
