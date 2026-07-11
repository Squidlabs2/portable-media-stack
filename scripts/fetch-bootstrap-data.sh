#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage: ./scripts/fetch-bootstrap-data.sh <user@source-host> [remote-path] [local-path]

Defaults:
  remote-path: ~/.local/share/portable-media-stack/bootstrap-data/latest-bootstrap-data.json
  local-path:  ./bootstrap-data/local/bootstrap-data.json
EOF
}

if [ $# -lt 1 ] || [ $# -gt 3 ]; then
  usage >&2
  exit 1
fi

SOURCE_HOST="$1"
REMOTE_PATH="${2:-~/.local/share/portable-media-stack/bootstrap-data/latest-bootstrap-data.json}"
LOCAL_PATH="${3:-./bootstrap-data/local/bootstrap-data.json}"

mkdir -p "$(dirname "$LOCAL_PATH")"
scp -q "$SOURCE_HOST:$REMOTE_PATH" "$LOCAL_PATH"
echo "Fetched bootstrap data to $LOCAL_PATH"
