#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

set -a
# shellcheck disable=SC1091
source ./.env
set +a

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

if [ "${MODE:-tailnet-only}" != "tailscale-funnel" ] || [ "${FUNNEL_USE_PATHS:-false}" != "true" ] || [ "${INSTALL_TRAEFIK:-true}" != "true" ]; then
  echo "Skipping Funnel Traefik config generation for current mode"
  exit 0
fi

config_dir="${TRAEFIK_FUNNEL_CONFIG_DIR:-${CONFIG_ROOT:-./config}/traefik-funnel}"
config_file="$config_dir/dynamic.yml"
mkdir -p "$config_dir"

radarr_path="$(normalize_path "${FUNNEL_RADARR_PATH:-/radarr}")"
sonarr_path="$(normalize_path "${FUNNEL_SONARR_PATH:-/sonarr}")"
seerr_path="$(normalize_path "${FUNNEL_SEERR_PATH:-/seerr}")"

cat > "$config_file" <<EOF
http:
  routers:
    funnel-radarr:
      entryPoints:
        - funnel
      rule: PathPrefix(\`${radarr_path}\`)
      service: funnel-radarr
    funnel-sonarr:
      entryPoints:
        - funnel
      rule: PathPrefix(\`${sonarr_path}\`)
      service: funnel-sonarr
    funnel-seerr:
      entryPoints:
        - funnel
      rule: PathPrefix(\`${seerr_path}\`)
      service: funnel-seerr
  services:
    funnel-radarr:
      loadBalancer:
        servers:
          - url: http://radarr:7878
    funnel-sonarr:
      loadBalancer:
        servers:
          - url: http://sonarr:8989
    funnel-seerr:
      loadBalancer:
        servers:
          - url: http://seerr:5055
EOF

echo "Wrote Funnel Traefik config to $config_file"
