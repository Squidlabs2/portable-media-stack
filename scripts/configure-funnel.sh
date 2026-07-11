#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck disable=SC1091
source ./.env

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

validate_port() {
  case "$1" in
    443|8443|10000) ;;
    *)
      echo "Invalid Funnel public port: $1. Allowed values are 443, 8443, and 10000." >&2
      exit 1
      ;;
  esac
}

normalize_path() {
  local value="$1"
  [ -n "$value" ] || value="/"
  case "$value" in
    /*) ;;
    *) value="/$value" ;;
  esac
  value="${value%/}"
  [ -n "$value" ] || value="/"
  printf '%s\n' "$value"
}

public_url() {
  local dns_name="$1"
  local public_port="$2"
  local public_path="${3:-}"
  local base
  case "$public_port" in
    443) base="https://${dns_name}" ;;
    *) base="https://${dns_name}:${public_port}" ;;
  esac
  if [ -n "$public_path" ]; then
    printf '%s%s\n' "$base" "$(normalize_path "$public_path")"
  else
    printf '%s\n' "$base"
  fi
}

print_url_hint() {
  local enabled="$1"
  local public_port="$2"
  local name="$3"
  local dns_name="$4"
  local public_path="${5:-}"

  if [ "$enabled" != "true" ]; then
    return 0
  fi

  validate_port "$public_port"
  echo "$name public URL: $(public_url "$dns_name" "$public_port" "$public_path")"
}

need_cmd tailscale
need_cmd python3

if [ "${MODE:-tailnet-only}" != "tailscale-funnel" ]; then
  echo "MODE is ${MODE:-unset}; nothing to do for Funnel"
  exit 0
fi

if [ "${AUTO_CONFIGURE_FUNNEL:-false}" != "true" ]; then
  echo "AUTO_CONFIGURE_FUNNEL is false; not changing Funnel config"
  echo "If you want public Funnel URLs later, set AUTO_CONFIGURE_FUNNEL=true and rerun ./scripts/configure-funnel.sh"
  exit 0
fi

run_funnel() {
  local enabled="$1"
  local public_port="$2"
  local target_url="$3"
  local name="$4"
  local public_path="${5:-}"

  if [ "$enabled" != "true" ]; then
    return 0
  fi

  validate_port "$public_port"

  if [ -n "$public_path" ]; then
    public_path="$(normalize_path "$public_path")"
    echo "Configuring Funnel for $name on public port $public_port path $public_path -> $target_url"
    tailscale funnel --bg --yes --https="$public_port" --set-path="$public_path" "$target_url"
  else
    echo "Configuring Funnel for $name on public port $public_port -> $target_url"
    tailscale funnel --bg --yes --https="$public_port" "$target_url"
  fi
}

if [ "${FUNNEL_USE_PATHS:-false}" = "true" ]; then
  run_funnel "${FUNNEL_RADARR:-true}" "${FUNNEL_RADARR_PUBLIC_PORT:-443}" "http://127.0.0.1:${RADARR_PORT:-7878}" "radarr" "${FUNNEL_RADARR_PATH:-/radarr}"
  run_funnel "${FUNNEL_SONARR:-true}" "${FUNNEL_SONARR_PUBLIC_PORT:-443}" "http://127.0.0.1:${SONARR_PORT:-8989}" "sonarr" "${FUNNEL_SONARR_PATH:-/sonarr}"
else
  run_funnel "${FUNNEL_RADARR:-true}" "${FUNNEL_RADARR_PUBLIC_PORT:-443}" "http://127.0.0.1:${RADARR_PORT:-7878}" "radarr"
  run_funnel "${FUNNEL_SONARR:-true}" "${FUNNEL_SONARR_PUBLIC_PORT:-8443}" "http://127.0.0.1:${SONARR_PORT:-8989}" "sonarr"
fi
run_funnel "${FUNNEL_JELLYFIN:-false}" "${FUNNEL_JELLYFIN_PUBLIC_PORT:-10000}" "http://127.0.0.1:${JELLYFIN_PORT:-8096}" "jellyfin"

dns_name="$(tailscale status --json | python3 -c 'import sys,json; d=json.load(sys.stdin); print((d.get("Self",{}).get("DNSName","") or "").rstrip("."))')"

echo
echo "Current Funnel status:"
tailscale funnel status
echo
if [ -n "$dns_name" ]; then
  echo "Likely public URLs:"
  if [ "${FUNNEL_USE_PATHS:-false}" = "true" ]; then
    print_url_hint "${FUNNEL_RADARR:-true}" "${FUNNEL_RADARR_PUBLIC_PORT:-443}" "Radarr" "$dns_name" "${FUNNEL_RADARR_PATH:-/radarr}"
    print_url_hint "${FUNNEL_SONARR:-true}" "${FUNNEL_SONARR_PUBLIC_PORT:-443}" "Sonarr" "$dns_name" "${FUNNEL_SONARR_PATH:-/sonarr}"
  else
    print_url_hint "${FUNNEL_RADARR:-true}" "${FUNNEL_RADARR_PUBLIC_PORT:-443}" "Radarr" "$dns_name"
    print_url_hint "${FUNNEL_SONARR:-true}" "${FUNNEL_SONARR_PUBLIC_PORT:-8443}" "Sonarr" "$dns_name"
  fi
  print_url_hint "${FUNNEL_JELLYFIN:-false}" "${FUNNEL_JELLYFIN_PUBLIC_PORT:-10000}" "Jellyfin" "$dns_name"
fi
