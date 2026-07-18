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
  [ -n "$value" ] || value="/seerr"
  case "$value" in
    /*) ;;
    *) value="/$value" ;;
  esac
  value="${value%/}"
  [ -n "$value" ] || value="/seerr"
  printf '%s\n' "$value"
}

if [ "${ENABLE_SEERR:-false}" != "true" ]; then
  echo "Skipping Seerr subpath proxy config generation because Seerr is disabled"
  exit 0
fi

config_file="${SEERR_WEB_CONFIG:-${CONFIG_ROOT:-./config}/seerr-web/nginx.conf}"
config_dir="$(dirname "$config_file")"
seerr_path="$(normalize_path "${FUNNEL_SEERR_PATH:-/seerr}")"
mkdir -p "$config_dir"

cat > "$config_file" <<EOF
map \$http_x_forwarded_proto \$seerr_x_forwarded_proto {
    default \$http_x_forwarded_proto;
    "" \$scheme;
}

server {
    listen 80;
    server_name _;

    location ^~ ${seerr_path} {
        set \$app '${seerr_path#/}';
        rewrite ^${seerr_path}/?(.*)\$ /\$1 break;
        proxy_pass http://seerr:5055;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$seerr_x_forwarded_proto;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_redirect ~^http://([^/]+)/(.*)\$ https://\$1/\$app/\$2;
        proxy_redirect ^ /\$app;
        proxy_redirect /setup /\$app/setup;
        proxy_redirect /login /\$app/login;
        proxy_set_header Accept-Encoding "";
        sub_filter_once off;
        sub_filter_types *;
        sub_filter 'href="/"' 'href="/\$app"';
        sub_filter 'href="/login"' 'href="/\$app/login"';
        sub_filter 'href:"/"' 'href:"/\$app"';
        sub_filter '/_next' '/\$app/_next';
        sub_filter '/api/v1' '/\$app/api/v1';
        sub_filter '/login/plex/loading' '/\$app/login/plex/loading';
        sub_filter '/images/' '/\$app/images/';
        sub_filter '/android-' '/\$app/android-';
        sub_filter '/apple-' '/\$app/apple-';
        sub_filter '/favicon' '/\$app/favicon';
        sub_filter '/logo.png' '/\$app/logo.png';
        sub_filter '/site.webmanifest' '/\$app/site.webmanifest';
    }
}
EOF

echo "Wrote Seerr subpath proxy config to $config_file"
