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

if [ "${MODE:-tailnet-only}" != "tailnet-only" ] && [ "${INSTALL_TRAEFIK:-true}" = "true" ]; then
  mkdir -p "${TRAEFIK_CONFIG_DIR:-./config/traefik}"
  acme_file="${TRAEFIK_ACME_FILE:-${TRAEFIK_CONFIG_DIR:-./config/traefik}/acme.json}"
  if [ ! -f "$acme_file" ]; then
    : > "$acme_file"
  fi
  chmod 600 "$acme_file"
fi

echo "Preflight checks passed"
