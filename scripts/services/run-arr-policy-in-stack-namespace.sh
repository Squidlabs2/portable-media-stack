#!/usr/bin/env bash
# Run an Arr policy helper where a dedicated stack Tailscale namespace can reach it.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

# shellcheck disable=SC1091
source ./.env
# shellcheck disable=SC1091
source ./scripts/installer/compose-args.sh
build_compose_args

policy="${1:?usage: $0 <configure-radarr-quality-policy.py|configure-sonarr-season-pack-policy.py>}"
case "$policy" in
  configure-radarr-quality-policy.py)
    config_dir="${RADARR_CONFIG:-${CONFIG_ROOT:-./config}/radarr}"
    config_env=(--env RADARR_CONFIG=/config --env RADARR_PORT="${RADARR_PORT:-7878}")
    ;;
  configure-sonarr-season-pack-policy.py)
    config_dir="${SONARR_CONFIG:-${CONFIG_ROOT:-./config}/sonarr}"
    config_env=(--env SONARR_CONFIG=/config --env SONARR_PORT="${SONARR_PORT:-8989}")
    ;;
  *)
    echo "Unsupported Arr policy helper: $policy" >&2
    exit 2
    ;;
esac

tailscale_id="$(docker compose "${COMPOSE_FILES[@]}" "${PROFILES[@]}" ps -q tailscale)"
[ -n "$tailscale_id" ] || {
  echo "Dedicated stack Tailscale container is not running" >&2
  exit 1
}

docker run --rm \
  --network "container:${tailscale_id}" \
  "${config_env[@]}" \
  -v "$ROOT_DIR/scripts/services:/scripts:ro" \
  -v "$config_dir:/config:ro" \
  python:3.13-alpine \
  python "/scripts/$policy"
