#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  build_together_apks.sh --room <unique-room> [options]

Options:
  --target <dart-file>   Integration target
                         (default: integration_test/together_smoke_test.dart)
  --output <directory>   APK/provenance directory
                         (default: build/android-multi-device/apks)
  --server <hostname>    Syncplay server (default: syncplay.pl)
  --port <integer>       Syncplay port (default: 8995)
  --video-url <url>      Long-form media URL compiled into both APKs
                         (default: http://10.0.2.2:18765/sync-fixture.mp4)

Builds the host APK completely before building the guest APK. Run this before
launching two AVDs so Gradle does not compete with them for hosted-runner CPU.
EOF
}

room=''
target='integration_test/together_smoke_test.dart'
output_dir='build/android-multi-device/apks'
server='syncplay.pl'
port=8995
video_url="${TOGETHER_VIDEO_URL:-http://10.0.2.2:18765/sync-fixture.mp4}"

while (( $# > 0 )); do
  case "$1" in
    --room) room="${2:-}"; shift 2 ;;
    --target) target="${2:-}"; shift 2 ;;
    --output) output_dir="${2:-}"; shift 2 ;;
    --server) server="${2:-}"; shift 2 ;;
    --port) port="${2:-}"; shift 2 ;;
    --video-url) video_url="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! "$room" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo '--room must contain only letters, numbers, dots, underscores, or hyphens.' >&2
  exit 2
fi
if [[ -z "$server" || "$server" =~ [[:space:]] ]]; then
  echo '--server must be a nonempty hostname without whitespace.' >&2
  exit 2
fi
if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
  echo '--port must be an integer from 1 through 65535.' >&2
  exit 2
fi
if [[ ! "$video_url" =~ ^https?://[^[:space:]]+$ ]]; then
  echo '--video-url must be an HTTP(S) URL without whitespace.' >&2
  exit 2
fi
if [[ ! -f "$target" ]]; then
  echo "Integration target does not exist: $target" >&2
  exit 2
fi

mkdir -p "$output_dir"
if find "$output_dir" -mindepth 1 -print -quit | grep -q .; then
  echo "APK output must be empty before a fresh build: $output_dir" >&2
  exit 3
fi

build_role() {
  local role="$1"
  flutter build apk \
    --debug \
    --target="$target" \
    --dart-define="TOGETHER_ROLE=$role" \
    --dart-define="TOGETHER_ROOM=$room" \
    --dart-define="SYNCPLAY_SERVER=$server" \
    --dart-define="SYNCPLAY_PORT=$port" \
    --dart-define="TOGETHER_VIDEO_URL=$video_url"
  cp build/app/outputs/flutter-apk/app-debug.apk "$output_dir/$role.apk"
  sha256sum "$output_dir/$role.apk" > "$output_dir/$role.apk.sha256"
}

build_role host
build_role guest

{
  printf 'target\t%s\n' "$target"
  printf 'room\t%s\n' "$room"
  printf 'server\t%s\n' "$server"
  printf 'port\t%s\n' "$port"
  printf 'video_url\t%s\n' "$video_url"
  printf 'host_apk\t%s\n' "$output_dir/host.apk"
  printf 'guest_apk\t%s\n' "$output_dir/guest.apk"
  printf 'built_utc\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$output_dir/build-provenance.tsv"

printf 'Host APK:  %s\n' "$output_dir/host.apk"
printf 'Guest APK: %s\n' "$output_dir/guest.apk"
