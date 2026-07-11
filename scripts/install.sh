#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

NON_INTERACTIVE=false
DRY_RUN=false
EXTRA_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --non-interactive) NON_INTERACTIVE=true ;;
    --dry-run) DRY_RUN=true ;;
    *) EXTRA_ARGS+=("$1") ;;
  esac
  shift
done

if [ "$NON_INTERACTIVE" = true ]; then
  ./scripts/configure.sh --non-interactive
else
  ./scripts/configure.sh
fi

set -a
# shellcheck disable=SC1091
source ./.env
set +a

./scripts/preflight.sh
./scripts/create-networks.sh

COMPOSE_FILES=(-f compose.yml)
if [ "$MODE" = "traefik-private-dns" ] || [ "$MODE" = "traefik-public-dns" ]; then
  COMPOSE_FILES+=(-f compose.traefik.yml)
  if [ "${INSTALL_TRAEFIK:-true}" = "true" ]; then
    COMPOSE_FILES+=(-f compose.traefik-bundled.yml)
  else
    COMPOSE_FILES+=(-f compose.traefik-external.yml)
  fi
fi

PROFILES=()
if [ "${ENABLE_NZBDAV:-false}" = "true" ]; then
  PROFILES+=(--profile nzbdav)
fi

if [ "$DRY_RUN" = true ]; then
  echo "Dry run only. Resolved compose command:"
  cmd=(docker compose "${COMPOSE_FILES[@]}" "${PROFILES[@]}" up -d)
  printf '%q ' "${cmd[@]}"
  printf '\n'
  docker compose "${COMPOSE_FILES[@]}" "${PROFILES[@]}" config >/dev/null
  if [ "$MODE" = "tailscale-funnel" ]; then
    echo "Dry run note: Funnel would be configured via ./scripts/configure-funnel.sh"
    if [ "${AUTO_CONFIGURE_FUNNEL:-false}" = "true" ]; then
      echo "Expected public mapping: Radarr on ${FUNNEL_RADARR_PUBLIC_PORT:-443}, Sonarr on ${FUNNEL_SONARR_PUBLIC_PORT:-8443}, Jellyfin on ${FUNNEL_JELLYFIN_PUBLIC_PORT:-10000} if enabled"
    fi
  fi
  exit 0
fi

docker compose "${COMPOSE_FILES[@]}" "${PROFILES[@]}" up -d

if [ "$MODE" = "tailscale-funnel" ]; then
  ./scripts/configure-funnel.sh
fi

echo
echo "Stack started."
echo "Local config: $ROOT_DIR/.env"
echo "Mode: $MODE"
echo "Bundled Traefik: ${INSTALL_TRAEFIK:-true}"
echo "Jellyfin: http://$(hostname -s):${JELLYFIN_PORT}"
echo "Radarr:   http://$(hostname -s):${RADARR_PORT}"
echo "Sonarr:   http://$(hostname -s):${SONARR_PORT}"
echo "Prowlarr: http://$(hostname -s):${PROWLARR_PORT}"
echo "SABnzbd:  http://$(hostname -s):${SABNZBD_PORT}"
if [ "${ENABLE_NZBDAV:-false}" = "true" ]; then
  echo "NZBDAV:   http://$(hostname -s):${NZBDAV_PORT}"
fi
if [ "$MODE" = "traefik-private-dns" ] || [ "$MODE" = "traefik-public-dns" ]; then
  echo "Traefik:  https://${TRAEFIK_DASHBOARD_HOST}"
fi
if [ "$MODE" = "tailscale-funnel" ]; then
  echo "Funnel auto-config: ${AUTO_CONFIGURE_FUNNEL:-false}"
  echo "Funnel helper: ./scripts/configure-funnel.sh"
  if [ "${AUTO_CONFIGURE_FUNNEL:-false}" = "true" ]; then
    echo "Expected public mapping: Radarr on ${FUNNEL_RADARR_PUBLIC_PORT:-443}, Sonarr on ${FUNNEL_SONARR_PUBLIC_PORT:-8443}, Jellyfin on ${FUNNEL_JELLYFIN_PUBLIC_PORT:-10000} if enabled"
  fi
fi
