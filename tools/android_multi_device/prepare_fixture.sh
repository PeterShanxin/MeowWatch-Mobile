#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: prepare_fixture.sh [--output <directory>] [--seconds <15-600>]

Downloads Flutter's CC0 bee.mp4 at its pinned SHA-256 and repeats its original
compressed video and audio packets into a longer MP4 without synthesizing app
frames. Also writes an identical Bee.mp4 alias for production UI recordings.
The default output is build/android-multi-device/fixture.
EOF
}

source_url='https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4'
source_sha256='91d703354b3bb77b42dc49152f82548668e981525c89464654cb4ca9f802fffc'
license_url='https://github.com/flutter/assets-for-api-docs#origin-of-third-party-content'
output_dir='build/android-multi-device/fixture'
seconds=90

while (( $# > 0 )); do
  case "$1" in
    --output) output_dir="${2:-}"; shift 2 ;;
    --seconds) seconds="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! "$seconds" =~ ^[0-9]+$ ]] || (( seconds < 15 || seconds > 600 )); then
  echo '--seconds must be an integer from 15 through 600.' >&2
  exit 2
fi
for tool in curl ffmpeg ffprobe sha256sum; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required fixture tool is unavailable: $tool" >&2
    exit 2
  fi
done

mkdir -p "$output_dir"
if find "$output_dir" -mindepth 1 -print -quit | grep -q .; then
  echo "Fixture output must be empty before generation: $output_dir" >&2
  exit 3
fi
output_dir="$(cd "$output_dir" && pwd -P)"
source_file="$output_dir/bee-source.mp4"
download_file="$output_dir/bee-source.mp4.download"
fixture_file="$output_dir/sync-fixture.mp4"

cleanup_download() {
  rm -f "$download_file"
}
trap cleanup_download EXIT

curl --fail --silent --show-error --location \
  --proto '=https' --tlsv1.2 --retry 3 \
  --output "$download_file" "$source_url"
actual_source_sha256="$(sha256sum "$download_file" | awk '{ print $1 }')"
if [[ "$actual_source_sha256" != "$source_sha256" ]]; then
  echo 'Downloaded bee.mp4 does not match the reviewed source SHA-256.' >&2
  echo "Expected: $source_sha256" >&2
  echo "Actual:   $actual_source_sha256" >&2
  exit 4
fi
mv "$download_file" "$source_file"
trap - EXIT

# Stream copy repeats the source packets; it does not invent or re-encode video
# frames or audio samples. The final partial repetition is cut at the requested
# container duration.
ffmpeg -hide_banner -loglevel error -y \
  -stream_loop -1 \
  -i "$source_file" \
  -map '0:v:0' \
  -map '0:a:0?' \
  -c copy \
  -t "$seconds" \
  -movflags +faststart \
  "$fixture_file"

fixture_duration="$(ffprobe -v error \
  -show_entries format=duration \
  -of default=noprint_wrappers=1:nokey=1 \
  "$fixture_file")"
if ! awk -v actual="$fixture_duration" -v requested="$seconds" \
  'BEGIN { exit !(actual >= requested - 0.5 && actual <= requested + 0.5) }'; then
  echo "Generated fixture duration is unexpected: $fixture_duration seconds" >&2
  exit 5
fi

# A friendly filename changes the real player title, not the recorded pixels.
recording_alias="$output_dir/Bee.mp4"
cp "$fixture_file" "$recording_alias"
cmp -s "$fixture_file" "$recording_alias"
sha256sum "$recording_alias" > "$output_dir/Bee.mp4.sha256"
sha256sum "$source_file" > "$output_dir/bee-source.mp4.sha256"
sha256sum "$fixture_file" > "$output_dir/sync-fixture.mp4.sha256"
ffprobe -v error \
  -show_entries format=duration,size,bit_rate:stream=index,codec_name,codec_type,width,height,r_frame_rate,avg_frame_rate,duration \
  -of json "$source_file" > "$output_dir/bee-source.ffprobe.json"
ffprobe -v error \
  -show_entries format=duration,size,bit_rate:stream=index,codec_name,codec_type,width,height,r_frame_rate,avg_frame_rate,duration \
  -of json "$fixture_file" > "$output_dir/sync-fixture.ffprobe.json"
{
  printf 'source_url\t%s\n' "$source_url"
  printf 'source_license\tCC0 Creative Commons\n'
  printf 'license_evidence\t%s\n' "$license_url"
  printf 'reviewed_source_sha256\t%s\n' "$source_sha256"
  printf 'generation\tffmpeg stream_loop with codec copy\n'
  printf 'recording_alias\tBee.mp4 (byte-identical copy of sync-fixture.mp4)\n'
  printf 'requested_duration_seconds\t%s\n' "$seconds"
  printf 'actual_duration_seconds\t%s\n' "$fixture_duration"
  printf 'generated_utc\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$output_dir/fixture-provenance.tsv"

printf 'Long-form Android test fixture: %s\n' "$fixture_file"
