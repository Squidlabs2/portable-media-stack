#!/usr/bin/env bash
# Configure Seerr's Arr services where the dedicated stack Tailscale namespace can reach them.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
source ./.env
source ./scripts/installer/compose-args.sh
build_compose_args

tailscale_id="$(docker compose "${COMPOSE_FILES[@]}" "${PROFILES[@]}" ps -q tailscale)"
[ -n "$tailscale_id" ] || { echo "Dedicated stack Tailscale container is not running" >&2; exit 1; }

config_root="${CONFIG_ROOT:-$ROOT_DIR/config}"
docker run --rm \
  --network "container:${tailscale_id}" \
  --env SEERR_CONFIG=/config/seerr \
  --env RADARR_CONFIG=/config/radarr \
  --env SONARR_CONFIG=/config/sonarr \
  --env RADARR_URL="http://127.0.0.1:${RADARR_PORT:-7878}" \
  --env SONARR_URL="http://127.0.0.1:${SONARR_PORT:-8989}" \
  --env SEERR_QUALITY_PROFILE="${SEERR_QUALITY_PROFILE:-}" \
  --env SEERR_ROOT_FOLDER="${SEERR_ROOT_FOLDER:-}" \
  -v "$ROOT_DIR/scripts/services:/scripts:ro" \
  -v "$config_root/seerr:/config/seerr" \
  -v "$config_root/radarr:/config/radarr:ro" \
  -v "$config_root/sonarr:/config/sonarr:ro" \
  python:3.13-alpine \
  python /scripts/configure-seerr-arr-services.py

docker compose "${COMPOSE_FILES[@]}" "${PROFILES[@]}" restart seerr
