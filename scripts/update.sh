#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

git pull --ff-only

./scripts/configure.sh --non-interactive

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

COMPOSE_FILES=(-f compose.yml)
if [ "${MODE:-tailnet-only}" = "traefik-private-dns" ] || [ "${MODE:-tailnet-only}" = "traefik-public-dns" ]; then
  COMPOSE_FILES+=(-f compose.traefik.yml)
  if [ "${INSTALL_TRAEFIK:-true}" = "true" ]; then
    COMPOSE_FILES+=(-f compose.traefik-bundled.yml)
  else
    COMPOSE_FILES+=(-f compose.traefik-external.yml)
  fi
elif [ "${MODE:-tailnet-only}" = "tailscale-funnel" ] && [ "${FUNNEL_USE_PATHS:-false}" = "true" ] && [ "${INSTALL_TRAEFIK:-true}" = "true" ]; then
  COMPOSE_FILES+=(-f compose.funnel-traefik.yml)
  COMPOSE_FILES+=(-f compose.funnel-traefik-bundled.yml)
fi

PROFILES=()
if [ "${ENABLE_SABNZBD:-true}" = "true" ]; then
  PROFILES+=(--profile sabnzbd)
fi
if [ "${ENABLE_NZBDAV:-false}" = "true" ]; then
  PROFILES+=(--profile nzbdav)
fi
if [ "${ENABLE_SEERR:-false}" = "true" ]; then
  PROFILES+=(--profile seerr)
fi

if [ "${MODE:-tailnet-only}" = "tailscale-funnel" ] && [ "${FUNNEL_USE_PATHS:-false}" = "true" ] && [ "${INSTALL_TRAEFIK:-true}" = "true" ]; then
  ./scripts/write-seerr-subpath-nginx-config.sh
  ./scripts/write-funnel-traefik-config.sh
fi

prepare_seerr_config

docker compose "${COMPOSE_FILES[@]}" "${PROFILES[@]}" pull
docker compose "${COMPOSE_FILES[@]}" "${PROFILES[@]}" up -d
if [ "${ENABLE_SABNZBD:-true}" = "true" ]; then
  ./scripts/configure-sab-paths.sh
fi
if [ "${ENABLE_NZBDAV:-false}" = "true" ]; then
  ./scripts/configure-nzbdav-paths.sh
fi
if [ "${MODE:-tailnet-only}" = "tailscale-funnel" ]; then
  ./scripts/configure-arr-url-bases.sh
  ./scripts/configure-funnel.sh
fi

echo "Update complete"
