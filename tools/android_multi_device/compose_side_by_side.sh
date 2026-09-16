#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: compose_side_by_side.sh <phone.mp4> <tablet.mp4> <recording-session.tsv> <output.mp4>

Creates a timestamp-aligned 1920x1080 framed presentation from the two native
Android recordings. Use compose_side_by_side.py directly for optional labels.
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

python_bin="${PYTHON:-python3}"
if ! command -v "$python_bin" >/dev/null 2>&1; then
  echo "Python is required for composition: $python_bin" >&2
  exit 2
fi

exec "$python_bin" tools/android_multi_device/compose_side_by_side.py "$@"
