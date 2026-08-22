#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

git pull --ff-only

./scripts/installer/configure.sh --non-interactive

set -a
# shellcheck disable=SC1091
source ./.env
set +a

prepare_seerr_config() {
  [ "${ENABLE_SEERR:-false}" = "true" ] || return 0
  local seerr_config
  seerr_config="${SEERR_CONFIG:-./config/seerr}"
  mkdir -p "$seerr_config"
  chown "${PUID:-1000}:${PGID:-1000}" "$seerr_config" 2>/dev/null || true
}

# shellcheck disable=SC1091
source ./scripts/installer/compose-args.sh
build_compose_args

if funnel_path_mode_enabled; then
  ./scripts/ingress/write-seerr-subpath-nginx-config.sh
  ./scripts/ingress/write-funnel-traefik-config.sh
fi

prepare_seerr_config

docker compose "${COMPOSE_FILES[@]}" "${PROFILES[@]}" pull
docker compose "${COMPOSE_FILES[@]}" "${PROFILES[@]}" up -d
if [ "${MODE:-tailnet-only}" = "tailscale-funnel" ]; then
  ./scripts/services/run-arr-policy-in-stack-namespace.sh configure-radarr-quality-policy.py
  ./scripts/services/run-arr-policy-in-stack-namespace.sh configure-sonarr-season-pack-policy.py
else
  ./scripts/services/configure-radarr-quality-policy.py
  ./scripts/services/configure-sonarr-season-pack-policy.py
fi
if funnel_path_mode_enabled && [ "${ENABLE_SEERR:-false}" = "true" ]; then
  docker compose "${COMPOSE_FILES[@]}" "${PROFILES[@]}" up -d --force-recreate seerr-web
fi
if [ "${ENABLE_SABNZBD:-true}" = "true" ]; then
  ./scripts/services/configure-sab-paths.sh
fi
if [ "${ENABLE_NZBDAV:-false}" = "true" ]; then
  ./scripts/services/configure-nzbdav-paths.sh
fi
if [ "${MODE:-tailnet-only}" = "tailscale-funnel" ]; then
  ./scripts/ingress/configure-arr-url-bases.sh
  ./scripts/ingress/configure-funnel.sh
fi

echo "Update complete"
