#!/usr/bin/env bash
set -euo pipefail

MODE="${MODE:-tailnet-only}"
PROXY_NETWORK="${PROXY_NETWORK:-proxy}"
INSTALL_TRAEFIK="${INSTALL_TRAEFIK:-true}"

if [ "$MODE" = "traefik-private-dns" ] || [ "$MODE" = "traefik-public-dns" ]; then
  if [ "$INSTALL_TRAEFIK" = "true" ]; then
    echo "Bundled Traefik enabled; proxy network will be created by Docker Compose"
  else
    if ! docker network inspect "$PROXY_NETWORK" >/dev/null 2>&1; then
      echo "Creating external Docker network: $PROXY_NETWORK"
      docker network create "$PROXY_NETWORK" >/dev/null
    else
      echo "Docker network $PROXY_NETWORK already exists"
    fi
  fi
else
  echo "Skipping external proxy network creation for non-Traefik mode"
fi
