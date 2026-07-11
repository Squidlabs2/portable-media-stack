#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ROOT_DIR}/.env"
ENV_TEMPLATE="${ROOT_DIR}/.env.example"
NON_INTERACTIVE=false

while [ $# -gt 0 ]; do
  case "$1" in
    --non-interactive) NON_INTERACTIVE=true ;;
  esac
  shift
done

[ -f "$ENV_TEMPLATE" ] || { echo "Missing template: $ENV_TEMPLATE" >&2; exit 1; }

if [ ! -f "$ENV_FILE" ]; then
  cp "$ENV_TEMPLATE" "$ENV_FILE"
fi

legacy_or_empty() {
  local value="$1"
  shift
  [ -z "$value" ] && return 0
  local candidate
  for candidate in "$@"; do
    [ "$value" = "$candidate" ] && return 0
  done
  return 1
}

set_kv() {
  local key="$1"
  local value="$2"
  python3 - "$ENV_FILE" "$key" "$value" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
key = sys.argv[2]
value = sys.argv[3]
lines = path.read_text().splitlines()
out = []
found = False
for line in lines:
    if line.startswith(f"{key}="):
        out.append(f"{key}={value}")
        found = True
    else:
        out.append(line)
if not found:
    out.append(f"{key}={value}")
path.write_text("\n".join(out) + "\n")
PY
}

get_value() {
  local key="$1"
  grep -E "^${key}=" "$ENV_FILE" | head -n1 | cut -d= -f2-
}

apply_path_defaults() {
  local home_dir config_default downloads_default movies_default tv_default
  home_dir="${HOME:-$ROOT_DIR}"
  config_default="$ROOT_DIR/config"
  downloads_default="$home_dir/downloads"
  movies_default="$home_dir/media/movies"
  tv_default="$home_dir/media/tv"

  if legacy_or_empty "$(get_value CONFIG_ROOT)" "./config"; then
    set_kv CONFIG_ROOT "$config_default"
  fi
  if legacy_or_empty "$(get_value DOWNLOADS_PATH)" "/srv/downloads"; then
    set_kv DOWNLOADS_PATH "$downloads_default"
  fi
  if legacy_or_empty "$(get_value MOVIES_PATH)" "/srv/media/movies"; then
    set_kv MOVIES_PATH "$movies_default"
  fi
  if legacy_or_empty "$(get_value TV_PATH)" "/srv/media/tv"; then
    set_kv TV_PATH "$tv_default"
  fi
}

prompt_value() {
  local key="$1"
  local prompt="$2"
  local current
  local answer
  current="$(get_value "$key")"

  if [ "$NON_INTERACTIVE" = true ]; then
    answer="${!key:-$current}"
  else
    read -r -p "$prompt [$current]: " answer
    answer="${answer:-$current}"
  fi

  set_kv "$key" "$answer"
}

apply_mode_defaults() {
  local mode
  mode="$(get_value MODE)"

  case "$mode" in
    tailscale-funnel)
      set_kv INSTALL_TRAEFIK false
      set_kv ENABLE_PUBLIC_HOSTNAMES false
      set_kv AUTO_CONFIGURE_FUNNEL true
      set_kv FUNNEL_RADARR true
      set_kv FUNNEL_SONARR true
      set_kv FUNNEL_JELLYFIN false
      set_kv FUNNEL_RADARR_PUBLIC_PORT 443
      set_kv FUNNEL_SONARR_PUBLIC_PORT 8443
      set_kv FUNNEL_JELLYFIN_PUBLIC_PORT 10000
      ;;
    traefik-private-dns|traefik-public-dns)
      set_kv INSTALL_TRAEFIK true
      set_kv AUTO_CONFIGURE_FUNNEL false
      ;;
    tailnet-only)
      set_kv AUTO_CONFIGURE_FUNNEL false
      ;;
  esac
}

apply_path_defaults

prompt_value MODE "Deployment mode (tailnet-only|tailscale-funnel|traefik-private-dns|traefik-public-dns)"
apply_mode_defaults

if [ "$NON_INTERACTIVE" = false ]; then
  case "$(get_value MODE)" in
    tailscale-funnel)
      echo "Recommended Funnel defaults loaded: bundled Traefik off, Radarr on 443, Sonarr on 8443, Jellyfin off."
      ;;
    traefik-private-dns|traefik-public-dns)
      echo "Recommended Traefik defaults loaded: bundled Traefik on, Funnel auto-config off."
      ;;
  esac
fi

prompt_value STACK_NAME "Stack name"
prompt_value TZ "Timezone"
prompt_value PUID "PUID"
prompt_value PGID "PGID"
prompt_value DOWNLOADS_PATH "Downloads path"
prompt_value MOVIES_PATH "Movies path"
prompt_value TV_PATH "TV path"
prompt_value CONFIG_ROOT "Local config root"
prompt_value AUTO_APPLY_BOOTSTRAP_DATA "Auto-apply bootstrap data after install (true|false)"
if [ "$(get_value AUTO_APPLY_BOOTSTRAP_DATA)" = "true" ]; then
  prompt_value BOOTSTRAP_DATA_FILE "Bootstrap data file path"
  prompt_value BOOTSTRAP_WAIT_SECONDS "Bootstrap apply wait timeout (seconds)"
fi
prompt_value ENABLE_NZBDAV "Enable NZBDAV (true|false)"
prompt_value JELLYFIN_HOST "Jellyfin hostname"
prompt_value RADARR_HOST "Radarr hostname"
prompt_value SONARR_HOST "Sonarr hostname"
prompt_value PROWLARR_HOST "Prowlarr hostname"
prompt_value SABNZBD_HOST "SABnzbd hostname"
prompt_value NZBDAV_HOST "NZBDAV hostname"

MODE_VALUE="$(get_value MODE)"
if [ "$MODE_VALUE" = "tailscale-funnel" ]; then
  prompt_value AUTO_CONFIGURE_FUNNEL "Auto-configure Tailscale Funnel during install (recommended: true)"
  prompt_value FUNNEL_RADARR "Expose Radarr through Funnel (recommended: true)"
  prompt_value FUNNEL_SONARR "Expose Sonarr through Funnel (recommended: true)"
  prompt_value FUNNEL_JELLYFIN "Expose Jellyfin through Funnel (recommended: false)"
  prompt_value FUNNEL_RADARR_PUBLIC_PORT "Public Funnel port for Radarr (recommended: 443)"
  prompt_value FUNNEL_SONARR_PUBLIC_PORT "Public Funnel port for Sonarr (recommended: 8443)"
  prompt_value FUNNEL_JELLYFIN_PUBLIC_PORT "Public Funnel port for Jellyfin (recommended: 10000 if enabled)"
elif [ "$MODE_VALUE" = "traefik-private-dns" ] || [ "$MODE_VALUE" = "traefik-public-dns" ]; then
  prompt_value INSTALL_TRAEFIK "Install bundled Traefik (recommended: true)"
  prompt_value TRAEFIK_HTTP_PORT "Traefik HTTP port"
  prompt_value TRAEFIK_HTTPS_PORT "Traefik HTTPS port"
  prompt_value TRAEFIK_CERTRESOLVER "Traefik certificate resolver name"
  prompt_value TRAEFIK_ACME_EMAIL "Traefik ACME email"
  prompt_value TRAEFIK_DASHBOARD_HOST "Traefik dashboard hostname"
  prompt_value PROXY_NETWORK "Traefik proxy network"
else
  set_kv INSTALL_TRAEFIK false
  set_kv AUTO_CONFIGURE_FUNNEL false
fi

echo "Wrote configuration to $ENV_FILE"
