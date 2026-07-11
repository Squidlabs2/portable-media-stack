#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

git pull --ff-only

set -a
# shellcheck disable=SC1091
source ./.env
set +a

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
if [ "${ENABLE_NZBDAV:-false}" = "true" ]; then
  PROFILES+=(--profile nzbdav)
fi

if [ "${MODE:-tailnet-only}" = "tailscale-funnel" ] && [ "${FUNNEL_USE_PATHS:-false}" = "true" ] && [ "${INSTALL_TRAEFIK:-true}" = "true" ]; then
  ./scripts/write-funnel-traefik-config.sh
fi

docker compose "${COMPOSE_FILES[@]}" "${PROFILES[@]}" pull
docker compose "${COMPOSE_FILES[@]}" "${PROFILES[@]}" up -d

echo "Update complete"
