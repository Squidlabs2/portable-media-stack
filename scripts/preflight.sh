#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

need_cmd docker
need_cmd bash
need_cmd cp
need_cmd mkdir
need_cmd python3

if ! docker compose version >/dev/null 2>&1; then
  fail "Docker Compose plugin is required"
fi

TAILSCALE_REQUIRED="${TAILSCALE_REQUIRED:-true}"
if [ "$TAILSCALE_REQUIRED" = "true" ]; then
  need_cmd tailscale
  tailscale status >/dev/null 2>&1 || fail "Tailscale is installed but not connected"
fi

for dir_var in DOWNLOADS_PATH MOVIES_PATH TV_PATH; do
  dir_value="${!dir_var:-}"
  [ -n "$dir_value" ] || continue
  mkdir -p "$dir_value"
done

mkdir -p "${CONFIG_ROOT:-./config}"

if [ "${AUTO_APPLY_BOOTSTRAP_DATA:-false}" = "true" ]; then
  bootstrap_file="${BOOTSTRAP_DATA_FILE:-./bootstrap-data/local/bootstrap-data.json}"
  [ -f "$bootstrap_file" ] || fail "AUTO_APPLY_BOOTSTRAP_DATA=true but bootstrap data file is missing: $bootstrap_file"
fi

if [ "${MODE:-tailnet-only}" = "cloudflare-tunnel" ]; then
  token_file="${CLOUDFLARE_TUNNEL_TOKEN_FILE:-./secrets/cloudflare-tunnel-token}"
  if [ ! -s "$token_file" ] && [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
    token_dir="${token_file%/*}"
    [ "$token_dir" != "$token_file" ] || token_dir="."
    mkdir -p "$token_dir"
    printf '%s' "$CLOUDFLARE_TUNNEL_TOKEN" > "$token_file"
    chmod 644 "$token_file"
    echo "Wrote Cloudflare Tunnel token file: $token_file"
  fi
  [ -s "$token_file" ] || fail "Cloudflare Tunnel token file is required for MODE=cloudflare-tunnel: $token_file"
fi

if [ "${MODE:-tailnet-only}" != "tailnet-only" ] && [ "${INSTALL_TRAEFIK:-true}" = "true" ]; then
  if [ "${MODE:-tailnet-only}" = "traefik-public-dns" ] && [ "${TRAEFIK_ACME_CHALLENGE:-http}" = "cloudflare-dns" ] && [ -z "${CLOUDFLARE_DNS_API_TOKEN:-}" ]; then
    fail "CLOUDFLARE_DNS_API_TOKEN is required for traefik-public-dns with TRAEFIK_ACME_CHALLENGE=cloudflare-dns"
  fi
  mkdir -p "${TRAEFIK_CONFIG_DIR:-./config/traefik}"
  acme_file="${TRAEFIK_ACME_FILE:-${TRAEFIK_CONFIG_DIR:-./config/traefik}/acme.json}"
  if [ ! -f "$acme_file" ]; then
    : > "$acme_file"
  fi
  chmod 600 "$acme_file"
fi

if [ "${MODE:-tailnet-only}" = "tailscale-funnel" ] && [ "${FUNNEL_USE_PATHS:-false}" = "true" ] && [ "${INSTALL_TRAEFIK:-true}" = "true" ]; then
  mkdir -p "${TRAEFIK_FUNNEL_CONFIG_DIR:-./config/traefik-funnel}"
fi

echo "Preflight checks passed"
