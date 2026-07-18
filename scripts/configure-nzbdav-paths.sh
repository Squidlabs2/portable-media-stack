#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

set -a
# shellcheck disable=SC1091
source ./.env
set +a

DOWNLOADS_ROOT="${DOWNLOADS_PATH:-$HOME/downloads}"
TARGET_COMPLETED_DIR="${TARGET_NZBDAV_COMPLETED_DOWNLOADS_DIR:-/downloads/nzbdav-completed}"
CATEGORIES="${NZBDAV_COMPLETED_CATEGORIES:-movies,tv,audio,software}"

case "$TARGET_COMPLETED_DIR" in
  /downloads) completed_host_dir="$DOWNLOADS_ROOT" ;;
  /downloads/*) completed_host_dir="$DOWNLOADS_ROOT/${TARGET_COMPLETED_DIR#/downloads/}" ;;
  *)
    echo "NZBDAV completed dir must be inside the mounted /downloads volume: $TARGET_COMPLETED_DIR" >&2
    exit 1
    ;;
esac

mkdir -p "$completed_host_dir"

IFS=',' read -r -a category_list <<< "$CATEGORIES"
for category in "${category_list[@]}"; do
  category="$(printf '%s' "$category" | xargs)"
  [ -n "$category" ] || continue
  mkdir -p "$completed_host_dir/$category"
done

echo "NZBDAV completed paths ready under $completed_host_dir"