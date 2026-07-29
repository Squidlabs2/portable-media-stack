#!/usr/bin/env bash
# Shared Docker Compose file/profile resolution for install/update flows.

funnel_path_mode_enabled() {
  [ "${MODE:-tailnet-only}" = "tailscale-funnel" ] && \
    [ "${FUNNEL_USE_PATHS:-false}" = "true" ] && \
    [ "${INSTALL_TRAEFIK:-true}" = "true" ]
}

build_compose_args() {
  COMPOSE_FILES=(-f compose.yml)

  case "${MODE:-tailnet-only}" in
    traefik-private-dns|traefik-public-dns)
      COMPOSE_FILES+=(-f compose.traefik.yml)
      if [ "${INSTALL_TRAEFIK:-true}" = "true" ]; then
        COMPOSE_FILES+=(-f compose.traefik-bundled.yml)
        if [ "${MODE:-tailnet-only}" = "traefik-public-dns" ] && [ "${TRAEFIK_ACME_CHALLENGE:-http}" = "cloudflare-dns" ]; then
          COMPOSE_FILES+=(-f compose.cloudflare-dns.yml)
        fi
      else
        COMPOSE_FILES+=(-f compose.traefik-external.yml)
      fi
      ;;
    tailscale-funnel)
      if funnel_path_mode_enabled; then
        COMPOSE_FILES+=(-f compose.funnel-traefik.yml)
        COMPOSE_FILES+=(-f compose.funnel-traefik-bundled.yml)
      fi
      ;;
    cloudflare-tunnel)
      COMPOSE_FILES+=(-f compose.cloudflare-tunnel.yml)
      ;;
  esac

  PROFILES=()
  if [ "${ENABLE_SABNZBD:-true}" = "true" ]; then
    PROFILES+=(--profile sabnzbd)
  fi
  if [ "${ENABLE_NZBDAV:-false}" = "true" ]; then
    PROFILES+=(--profile nzbdav)
  fi
  if [ "${ENABLE_SEERR:-false}" = "true" ]; then
    PROFILES+=(--profile seerr)
    if funnel_path_mode_enabled; then
      PROFILES+=(--profile seerr-web)
    fi
  fi
  if [ "${ENABLE_JELLYFIN_INTEL_GPU:-false}" = "true" ]; then
    COMPOSE_FILES+=(-f compose.jellyfin-intel-gpu.yml)
  fi
}
