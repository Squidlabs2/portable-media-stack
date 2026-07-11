#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck disable=SC1091
source ./.env

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

normalize_path() {
  local value="$1"
  [ -n "$value" ] || value="/"
  case "$value" in
    /*) ;;
    *) value="/$value" ;;
  esac
  value="${value%/}"
  [ -n "$value" ] || value="/"
  printf '%s\n' "$value"
}

wait_for_file() {
  local path="$1"
  local timeout_seconds="${2:-60}"
  local elapsed=0
  while [ "$elapsed" -lt "$timeout_seconds" ]; do
    if [ -f "$path" ]; then
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  echo "Timed out waiting for config file: $path" >&2
  return 1
}

set_url_base() {
  local path="$1"
  local desired="$2"
  python3 - "$path" "$desired" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

path = Path(sys.argv[1])
desired = sys.argv[2]
tree = ET.parse(path)
root = tree.getroot()
node = root.find('UrlBase')
if node is None:
    node = ET.SubElement(root, 'UrlBase')
current = (node.text or '').strip()
if current == desired:
    print('unchanged')
    raise SystemExit(0)
node.text = desired
ET.indent(tree, space='  ')
tree.write(path, encoding='utf-8', xml_declaration=False)
print('changed')
PY
}

need_cmd docker
need_cmd python3

radarr_base=""
sonarr_base=""
if [ "${MODE:-tailnet-only}" = "tailscale-funnel" ] && [ "${FUNNEL_USE_PATHS:-false}" = "true" ]; then
  if [ "${FUNNEL_RADARR:-true}" = "true" ]; then
    radarr_base="$(normalize_path "${FUNNEL_RADARR_PATH:-/radarr}")"
  fi
  if [ "${FUNNEL_SONARR:-true}" = "true" ]; then
    sonarr_base="$(normalize_path "${FUNNEL_SONARR_PATH:-/sonarr}")"
  fi
fi

changed_services=()
for service_spec in \
  "radarr:${RADARR_CONFIG:-${CONFIG_ROOT:-./config}/radarr}/config.xml:$radarr_base" \
  "sonarr:${SONARR_CONFIG:-${CONFIG_ROOT:-./config}/sonarr}/config.xml:$sonarr_base"
do
  IFS=: read -r service config_file desired_base <<<"$service_spec"
  wait_for_file "$config_file" 60
  result=$(set_url_base "$config_file" "$desired_base")
  if [ "$result" = "changed" ]; then
    changed_services+=("$service")
    echo "Updated $service UrlBase to '${desired_base}'"
  else
    echo "$service UrlBase already '${desired_base}'"
  fi
done

if [ ${#changed_services[@]} -gt 0 ]; then
  echo "Restarting services to apply UrlBase changes: ${changed_services[*]}"
  docker compose restart "${changed_services[@]}"
fi
