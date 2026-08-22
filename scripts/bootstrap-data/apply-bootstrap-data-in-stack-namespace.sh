#!/usr/bin/env bash
# Apply bootstrap data where a dedicated Tailscale namespace can reach the apps.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

if [ ! -f ./.env ]; then
  echo "ERROR: Missing $ROOT_DIR/.env. Run ./scripts/install.sh first." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source ./.env
set +a
# shellcheck disable=SC1091
source ./scripts/installer/compose-args.sh
build_compose_args

if [ "${MODE:-tailnet-only}" != "tailscale-funnel" ]; then
  exec ./scripts/bootstrap-data/apply-bootstrap-data.sh "$@"
fi

input="${BOOTSTRAP_DATA_FILE:-$ROOT_DIR/bootstrap-data/local/bootstrap-data.json}"
timeout="${BOOTSTRAP_WAIT_SECONDS:-180}"
while [ $# -gt 0 ]; do
  case "$1" in
    --input)
      input="${2:?--input requires a path}"
      shift 2
      ;;
    --timeout)
      timeout="${2:?--timeout requires seconds}"
      shift 2
      ;;
    *)
      echo "ERROR: Unsupported argument: $1" >&2
      exit 2
      ;;
  esac
done

[ -f "$input" ] || {
  echo "ERROR: Bootstrap data file not found: $input" >&2
  exit 1
}

tailscale_id="$(docker compose "${COMPOSE_FILES[@]}" "${PROFILES[@]}" ps -q tailscale)"
[ -n "$tailscale_id" ] || {
  echo "ERROR: Dedicated stack Tailscale container is not running" >&2
  exit 1
}

config_root="${CONFIG_ROOT:-$ROOT_DIR/config}"
mounts=(
  -v "$ROOT_DIR/scripts/bootstrap-data:/scripts:ro"
  -v "$config_root/prowlarr:/config/prowlarr"
  -v "$config_root/sonarr:/config/sonarr"
  -v "$config_root/radarr:/config/radarr"
)
downloader_env=(--env ENABLE_NZBDAV="${ENABLE_NZBDAV:-false}")
if [ "${ENABLE_NZBDAV:-false}" = "true" ]; then
  mounts+=(-v "$config_root/nzbdav:/config/nzbdav")
  downloader_env+=(
    --env NZBDAV_CONFIG=/config/nzbdav
    --env TARGET_NZBDAV_URL="http://127.0.0.1:${NZBDAV_PORT:-3000}"
    --env TARGET_NZBDAV_BASE_URL="http://127.0.0.1:${NZBDAV_PORT:-3000}"
    --env TARGET_INTERNAL_NZBDAV_HOST=127.0.0.1
    --env TARGET_INTERNAL_NZBDAV_PORT="${NZBDAV_PORT:-3000}"
  )
else
  mounts+=(-v "$config_root/sabnzbd:/config/sabnzbd")
  downloader_env+=(
    --env SABNZBD_CONFIG=/config/sabnzbd
    --env TARGET_SABNZBD_URL="http://127.0.0.1:${SABNZBD_PORT:-8080}"
    --env TARGET_INTERNAL_SABNZBD_HOST=127.0.0.1
    --env TARGET_INTERNAL_SABNZBD_PORT="${SABNZBD_PORT:-8080}"
  )
fi

docker run --rm \
  --network "container:${tailscale_id}" \
  --env BOOTSTRAP_SKIP_DOWNLOADER_RESTART=true \
  --env PROWLARR_CONFIG=/config/prowlarr \
  --env SONARR_CONFIG=/config/sonarr \
  --env RADARR_CONFIG=/config/radarr \
  --env PROWLARR_PORT="${PROWLARR_PORT:-9696}" \
  --env SONARR_PORT="${SONARR_PORT:-8989}" \
  --env RADARR_PORT="${RADARR_PORT:-7878}" \
  --env TARGET_PROWLARR_URL="http://127.0.0.1:${PROWLARR_PORT:-9696}" \
  --env TARGET_SONARR_URL="http://127.0.0.1:${SONARR_PORT:-8989}" \
  --env TARGET_RADARR_URL="http://127.0.0.1:${RADARR_PORT:-7878}" \
  --env TARGET_INTERNAL_PROWLARR_URL="http://127.0.0.1:${PROWLARR_PORT:-9696}" \
  --env TARGET_INTERNAL_SONARR_URL="http://127.0.0.1:${SONARR_PORT:-8989}" \
  --env TARGET_INTERNAL_RADARR_URL="http://127.0.0.1:${RADARR_PORT:-7878}" \
  "${downloader_env[@]}" \
  "${mounts[@]}" \
  -v "$(cd "$(dirname "$input")" && pwd)/$(basename "$input"):/bootstrap-data.json:ro" \
  python:3.13-alpine \
  python /scripts/bootstrap-data.py apply --input /bootstrap-data.json --timeout "$timeout"

if [ "${ENABLE_NZBDAV:-false}" = "true" ]; then
  docker compose "${COMPOSE_FILES[@]}" "${PROFILES[@]}" restart nzbdav
fi
