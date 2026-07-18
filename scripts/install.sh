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

funnel_expected_summary() {
  if [ "${FUNNEL_USE_PATHS:-false}" = "true" ]; then
    printf 'Expected public mapping: Radarr at %s, Sonarr at %s' \
      "${FUNNEL_RADARR_PATH:-/radarr}" "${FUNNEL_SONARR_PATH:-/sonarr}"
    if [ "${FUNNEL_JELLYFIN:-false}" = "true" ]; then
      printf ', Jellyfin on port %s' "${FUNNEL_JELLYFIN_PUBLIC_PORT:-10000}"
    fi
    if [ "${FUNNEL_SEERR:-false}" = "true" ]; then
      printf ', Seerr on port %s' "${FUNNEL_SEERR_PUBLIC_PORT:-10000}"
    fi
    printf '\n'
  else
    echo "Expected public mapping: Radarr on ${FUNNEL_RADARR_PUBLIC_PORT:-443}, Sonarr on ${FUNNEL_SONARR_PUBLIC_PORT:-8443}, Jellyfin on ${FUNNEL_JELLYFIN_PUBLIC_PORT:-10000} if enabled, Seerr on ${FUNNEL_SEERR_PUBLIC_PORT:-10000} if enabled"
  fi
}

resolve_bootstrap_data_file() {
  local configured fallback_home fallback_repo candidate
  configured="${BOOTSTRAP_DATA_FILE:-}"
  fallback_home="${BOOTSTRAP_LIBRARY_DIR:-${HOME}/.local/share/portable-media-stack/bootstrap-data}/latest-bootstrap-data.json"
  fallback_repo="./bootstrap-data/local/bootstrap-data.json"

  for candidate in "$configured" "$fallback_home" "$fallback_repo"; do
    [ -n "$candidate" ] || continue
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  echo "ERROR: AUTO_APPLY_BOOTSTRAP_DATA=true but no bootstrap data file was found. Checked: ${configured:-<empty>}, $fallback_home, $fallback_repo" >&2
  return 1
}

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
elif [ "$MODE" = "tailscale-funnel" ] && [ "${FUNNEL_USE_PATHS:-false}" = "true" ] && [ "${INSTALL_TRAEFIK:-true}" = "true" ]; then
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

if [ "$DRY_RUN" = true ]; then
  echo "Dry run only. Resolved compose command:"
  cmd=(docker compose "${COMPOSE_FILES[@]}" "${PROFILES[@]}" up -d)
  printf '%q ' "${cmd[@]}"
  printf '\n'
  docker compose "${COMPOSE_FILES[@]}" "${PROFILES[@]}" config >/dev/null
  if [ "$MODE" = "tailscale-funnel" ]; then
    echo "Dry run note: Funnel would be configured via ./scripts/configure-funnel.sh"
    if [ "${AUTO_CONFIGURE_FUNNEL:-false}" = "true" ]; then
      funnel_expected_summary
    fi
  fi
  if [ "${AUTO_APPLY_BOOTSTRAP_DATA:-false}" = "true" ]; then
    echo "Dry run note: Bootstrap data would be applied from ${BOOTSTRAP_DATA_FILE:-./bootstrap-data/local/bootstrap-data.json}"
  fi
  exit 0
fi

if [ "$MODE" = "tailscale-funnel" ] && [ "${FUNNEL_USE_PATHS:-false}" = "true" ] && [ "${INSTALL_TRAEFIK:-true}" = "true" ]; then
  ./scripts/write-funnel-traefik-config.sh
fi

docker compose "${COMPOSE_FILES[@]}" "${PROFILES[@]}" up -d
if [ "${ENABLE_SABNZBD:-true}" = "true" ]; then
  ./scripts/configure-sab-paths.sh
fi
if [ "${ENABLE_NZBDAV:-false}" = "true" ]; then
  ./scripts/configure-nzbdav-paths.sh
fi

if [ "$MODE" = "tailscale-funnel" ]; then
  ./scripts/configure-arr-url-bases.sh
  ./scripts/configure-funnel.sh
fi

if [ "${AUTO_APPLY_BOOTSTRAP_DATA:-false}" = "true" ]; then
  BOOTSTRAP_INPUT="$(resolve_bootstrap_data_file)"
  ./scripts/apply-bootstrap-data.sh --input "$BOOTSTRAP_INPUT" --timeout "${BOOTSTRAP_WAIT_SECONDS:-180}"
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
if [ "${ENABLE_SABNZBD:-true}" = "true" ]; then
  echo "SABnzbd:  http://$(hostname -s):${SABNZBD_PORT}"
fi
if [ "${ENABLE_NZBDAV:-false}" = "true" ]; then
  echo "NZBDAV:   http://$(hostname -s):${NZBDAV_PORT}"
fi
if [ "${ENABLE_SEERR:-false}" = "true" ]; then
  echo "Seerr:    http://$(hostname -s):${SEERR_PORT}"
fi
if [ "$MODE" = "traefik-private-dns" ] || [ "$MODE" = "traefik-public-dns" ]; then
  echo "Traefik:  https://${TRAEFIK_DASHBOARD_HOST}"
fi
if [ "$MODE" = "tailscale-funnel" ]; then
  echo "Funnel auto-config: ${AUTO_CONFIGURE_FUNNEL:-false}"
  if [ "${FUNNEL_USE_PATHS:-false}" = "true" ] && [ "${INSTALL_TRAEFIK:-true}" = "true" ]; then
    echo "Traefik front door: http://$(hostname -s):${TRAEFIK_FUNNEL_PORT:-8088}"
  fi
  echo "Funnel helper: ./scripts/configure-funnel.sh"
  if [ "${AUTO_CONFIGURE_FUNNEL:-false}" = "true" ]; then
    funnel_expected_summary
  fi
fi
if [ "${AUTO_APPLY_BOOTSTRAP_DATA:-false}" = "true" ]; then
  echo "Bootstrap data applied from: $BOOTSTRAP_INPUT"
fi
