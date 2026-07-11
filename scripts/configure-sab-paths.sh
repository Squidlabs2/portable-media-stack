#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

set -a
# shellcheck disable=SC1091
source ./.env
set +a

SAB_CONFIG_DIR="${SABNZBD_CONFIG:-./config/sabnzbd}"
SAB_CONFIG_FILE="$SAB_CONFIG_DIR/sabnzbd.ini"
DOWNLOADS_ROOT="${DOWNLOADS_PATH:-$HOME/downloads}"
TARGET_INCOMPLETE_DIR="${SABNZBD_INCOMPLETE_DIR:-/downloads/incomplete}"
TARGET_COMPLETE_DIR="${SABNZBD_COMPLETE_DIR:-/downloads}"

[ -f "$SAB_CONFIG_FILE" ] || {
  echo "SAB config not found yet: $SAB_CONFIG_FILE" >&2
  exit 1
}

mkdir -p "$DOWNLOADS_ROOT/incomplete"
if [ "$TARGET_COMPLETE_DIR" != "/downloads" ]; then
  complete_host_suffix="${TARGET_COMPLETE_DIR#/downloads/}"
  mkdir -p "$DOWNLOADS_ROOT/$complete_host_suffix"
fi

changed=$(python3 - "$SAB_CONFIG_FILE" "$TARGET_INCOMPLETE_DIR" "$TARGET_COMPLETE_DIR" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
target_incomplete = sys.argv[2]
target_complete = sys.argv[3]
lines = path.read_text().splitlines()
out = []
changed = False
found_download = False
found_complete = False

for line in lines:
    if line.startswith('download_dir ='):
        found_download = True
        current = line.split('=', 1)[1].strip().strip('"')
        if current in ('', '/incomplete-downloads'):
            out.append(f'download_dir = {target_incomplete}')
            changed = True
        else:
            out.append(line)
    elif line.startswith('complete_dir ='):
        found_complete = True
        current = line.split('=', 1)[1].strip().strip('"')
        if current in ('', '/complete-downloads'):
            out.append(f'complete_dir = {target_complete}')
            changed = True
        else:
            out.append(line)
    else:
        out.append(line)

if not found_download:
    out.append(f'download_dir = {target_incomplete}')
    changed = True
if not found_complete:
    out.append(f'complete_dir = {target_complete}')
    changed = True

if changed:
    path.write_text('\n'.join(out) + '\n')

print('true' if changed else 'false')
PY
)

current_download_dir=$(grep '^download_dir =' "$SAB_CONFIG_FILE" | cut -d= -f2- | xargs)
current_complete_dir=$(grep '^complete_dir =' "$SAB_CONFIG_FILE" | cut -d= -f2- | xargs)

echo "SAB paths: download_dir=$current_download_dir complete_dir=$current_complete_dir"

if [ "$changed" = "true" ]; then
  docker compose restart sabnzbd >/dev/null
  echo "Restarted SABnzbd"
else
  echo "No SAB path changes needed"
fi
