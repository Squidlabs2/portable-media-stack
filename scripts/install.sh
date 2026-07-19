#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

NON_INTERACTIVE=false
DRY_RUN=false

usage() {
  echo "Usage: $0 [--non-interactive] [--dry-run]" >&2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --non-interactive) NON_INTERACTIVE=true ;;
    --dry-run) DRY_RUN=true ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 1
      ;;
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
      printf ', Seerr at %s' "${FUNNEL_SEERR_PATH:-/seerr}"
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

prepare_seerr_config() {
  [ "${ENABLE_SEERR:-false}" = "true" ] || return 0
  local seerr_config
  seerr_config="${SEERR_CONFIG:-./config/seerr}"
  mkdir -p "$seerr_config"
  chown "${PUID:-1000}:${PGID:-1000}" "$seerr_config" 2>/dev/null || true
}

prepare_generated_configs() {
  if funnel_path_mode_enabled; then
    ./scripts/write-seerr-subpath-nginx-config.sh
    ./scripts/write-funnel-traefik-config.sh
  fi

  prepare_seerr_config
}

recreate_seerr_web_if_needed() {
  if funnel_path_mode_enabled && [ "${ENABLE_SEERR:-false}" = "true" ]; then
    docker compose "${COMPOSE_FILES[@]}" "${PROFILES[@]}" up -d --force-recreate seerr-web
  fi
}

configure_download_clients() {
  if [ "${ENABLE_SABNZBD:-true}" = "true" ]; then
    ./scripts/configure-sab-paths.sh
  fi
  if [ "${ENABLE_NZBDAV:-false}" = "true" ]; then
    ./scripts/configure-nzbdav-paths.sh
  fi
}

configure_ingress() {
  [ "$MODE" = "tailscale-funnel" ] || return 0

  ./scripts/configure-arr-url-bases.sh
  ./scripts/configure-funnel.sh
}

apply_bootstrap_data_if_enabled() {
  [ "${AUTO_APPLY_BOOTSTRAP_DATA:-false}" = "true" ] || return 0

  BOOTSTRAP_INPUT="$(resolve_bootstrap_data_file)"
  ./scripts/apply-bootstrap-data.sh --input "$BOOTSTRAP_INPUT" --timeout "${BOOTSTRAP_WAIT_SECONDS:-180}"
}

print_local_urls() {
  local host
  host="$(hostname -s)"

  echo "Jellyfin: http://${host}:${JELLYFIN_PORT}"
  echo "Radarr:   http://${host}:${RADARR_PORT}"
  echo "Sonarr:   http://${host}:${SONARR_PORT}"
  echo "Prowlarr: http://${host}:${PROWLARR_PORT}"
  if [ "${ENABLE_SABNZBD:-true}" = "true" ]; then
    echo "SABnzbd:  http://${host}:${SABNZBD_PORT}"
  fi
  if [ "${ENABLE_NZBDAV:-false}" = "true" ]; then
    echo "NZBDAV:   http://${host}:${NZBDAV_PORT}"
  fi
  if [ "${ENABLE_SEERR:-false}" = "true" ]; then
    echo "Seerr:    http://${host}:${SEERR_PORT}"
  fi
}

print_public_app_urls() {
  printf 'Public URLs: https://%s, https://%s' "$RADARR_HOST" "$SONARR_HOST"
  if [ "${ENABLE_SEERR:-false}" = "true" ]; then
    printf ', https://%s' "$SEERR_HOST"
  fi
  printf '\n'
}

print_traefik_summary() {
  [ "$MODE" = "traefik-private-dns" ] || [ "$MODE" = "traefik-public-dns" ] || return 0

  echo "Traefik:  https://${TRAEFIK_DASHBOARD_HOST}"
  if [ "$MODE" = "traefik-public-dns" ]; then
    print_public_app_urls
  fi
}

print_funnel_summary() {
  [ "$MODE" = "tailscale-funnel" ] || return 0

  echo "Funnel auto-config: ${AUTO_CONFIGURE_FUNNEL:-false}"
  if funnel_path_mode_enabled; then
    echo "Traefik front door: http://$(hostname -s):${TRAEFIK_FUNNEL_PORT:-8088}"
  fi
  echo "Funnel helper: ./scripts/configure-funnel.sh"
  if [ "${AUTO_CONFIGURE_FUNNEL:-false}" = "true" ]; then
    funnel_expected_summary
  fi
}

print_cloudflare_tunnel_summary() {
  [ "$MODE" = "cloudflare-tunnel" ] || return 0

  echo "Cloudflare Tunnel: enabled"
  print_public_app_urls
  printf 'Cloudflare routes should point to internal services: %s -> http://radarr:7878, %s -> http://sonarr:8989' "$RADARR_HOST" "$SONARR_HOST"
  if [ "${ENABLE_SEERR:-false}" = "true" ]; then
    printf ', %s -> http://seerr:5055' "$SEERR_HOST"
  fi
  printf '\n'
}

print_next_steps() {
  local ps_cmd

  echo
  echo "Next steps:"
  ps_cmd=(docker compose "${COMPOSE_FILES[@]}" "${PROFILES[@]}" ps)
  printf '  1) Check container status: '
  printf '%q ' "${ps_cmd[@]}"
  printf '\n'
  echo "  2) Open the local URLs above and finish the first-run setup screens."
  if [ "${ENABLE_SEERR:-false}" = "true" ]; then
    echo "  3) In Seerr, connect Jellyfin plus Radarr/Sonarr, then keep requests approval-based until you are ready to automate approvals."
  else
    echo "  3) Connect Jellyfin plus Radarr/Sonarr/Prowlarr as needed."
  fi

  case "$MODE" in
    tailnet-only)
      echo "  4) Access apps privately over Tailscale or your LAN using the local URLs above."
      ;;
    tailscale-funnel)
      echo "  4) Verify Funnel routes: tailscale funnel status"
      echo "  5) Test the public Funnel paths, then keep private/admin apps off Funnel unless you intentionally expose them."
      ;;
    cloudflare-tunnel)
      echo "  4) In Cloudflare Zero Trust, confirm this tunnel is healthy."
      echo "  5) Add Public Hostname routes for this tunnel:"
      echo "     - ${RADARR_HOST} -> http://radarr:7878"
      echo "     - ${SONARR_HOST} -> http://sonarr:8989"
      if [ "${ENABLE_SEERR:-false}" = "true" ]; then
        echo "     - ${SEERR_HOST} -> http://seerr:5055"
      fi
      echo "  6) Test the public URLs above."
      ;;
    traefik-private-dns)
      echo "  4) Point your private DNS names at this host, then test the Traefik URLs above."
      ;;
    traefik-public-dns)
      if [ "${TRAEFIK_ACME_CHALLENGE:-http}" = "cloudflare-dns" ]; then
        echo "  4) Confirm public DNS points at this host; DNS-01 can issue certs without inbound 80/443, but users still need a reachable route."
      else
        echo "  4) Confirm public DNS points at this host and ports 80/443 are reachable."
      fi
      echo "  5) Watch Traefik issue certificates, then test the public URLs above."
      ;;
  esac

  if [ "${AUTO_APPLY_BOOTSTRAP_DATA:-false}" != "true" ]; then
    echo "  Optional) Apply exported bootstrap data later: ./scripts/apply-bootstrap-data.sh --input <bootstrap-data.json>"
  fi
}

print_install_summary() {
  echo
  echo "Stack started."
  echo "Local config: $ROOT_DIR/.env"
  echo "Mode: $MODE"
  echo "Bundled Traefik: ${INSTALL_TRAEFIK:-true}"
  print_local_urls
  print_traefik_summary
  print_funnel_summary
  print_cloudflare_tunnel_summary
  print_next_steps
  if [ "${AUTO_APPLY_BOOTSTRAP_DATA:-false}" = "true" ]; then
    echo "Bootstrap data applied from: $BOOTSTRAP_INPUT"
  fi
}

# shellcheck disable=SC1091
source ./scripts/compose-args.sh

./scripts/preflight.sh
./scripts/create-networks.sh

build_compose_args

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

prepare_generated_configs

docker compose "${COMPOSE_FILES[@]}" "${PROFILES[@]}" up -d
recreate_seerr_web_if_needed
configure_download_clients
configure_ingress
apply_bootstrap_data_if_enabled

print_install_summary
