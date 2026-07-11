#!/usr/bin/env bash
set -euo pipefail

SKIP_UPGRADE=false
DRY_RUN=false
TAILSCALE_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"
TAILSCALE_EXTRA_ARGS="${TAILSCALE_EXTRA_ARGS:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-upgrade) SKIP_UPGRADE=true ;;
    --dry-run) DRY_RUN=true ;;
    --tailscale-auth-key)
      shift
      TAILSCALE_AUTH_KEY="${1:-}"
      ;;
    --tailscale-extra-args)
      shift
      TAILSCALE_EXTRA_ARGS="${1:-}"
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
  shift
done

if [ -f /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  if [ "${ID:-}" != "debian" ]; then
    echo "This host prep script currently supports Debian only. Detected: ${PRETTY_NAME:-unknown}" >&2
    exit 1
  fi
fi

if [ "$(id -u)" -ne 0 ]; then
  SUDO=sudo
else
  SUDO=
fi

run() {
  if [ "$DRY_RUN" = true ]; then
    printf 'DRY RUN: '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

run_shell() {
  if [ "$DRY_RUN" = true ]; then
    printf 'DRY RUN: bash -lc %q\n' "$1"
    return 0
  fi
  bash -lc "$1"
}

prompt_for_tailscale_auth_key() {
  if [ "$DRY_RUN" = true ] || [ -n "$TAILSCALE_AUTH_KEY" ]; then
    return 0
  fi

  if [ ! -t 0 ]; then
    echo "Tailscale auth key not provided and no interactive terminal is available; skipping automatic tailnet join."
    return 0
  fi

  echo
  echo "Optional: paste a Tailscale auth key to automatically join this host to your tailnet."
  echo "Press Enter to skip and run 'sudo tailscale up' manually later."
  read -r -p "Tailscale auth key: " TAILSCALE_AUTH_KEY
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command for host prep: $1" >&2
    exit 1
  }
}

need_cmd apt-get
need_cmd install
need_cmd tee
need_cmd bash
need_cmd curl
need_cmd systemctl

export DEBIAN_FRONTEND=noninteractive

run $SUDO install -d -m 0755 /etc/apt/keyrings
run $SUDO apt-get update
if [ "$SKIP_UPGRADE" = false ]; then
  run $SUDO apt-get upgrade -y
fi
run $SUDO apt-get install -y ca-certificates curl git bash python3 gnupg lsb-release apt-transport-https sudo

if [ ! -f /etc/apt/keyrings/docker.asc ]; then
  run_shell "curl -fsSL https://download.docker.com/linux/debian/gpg | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.asc"
fi
run $SUDO chmod a+r /etc/apt/keyrings/docker.asc
run_shell "echo 'deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable' | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null"

if [ ! -f /usr/share/keyrings/tailscale-archive-keyring.gpg ]; then
  run_shell "curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | $SUDO tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null"
fi
run_shell "curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | $SUDO tee /etc/apt/sources.list.d/tailscale.list >/dev/null"

run $SUDO apt-get update
run $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin tailscale
run $SUDO systemctl enable --now docker
run $SUDO systemctl enable --now tailscaled

if [ -n "$SUDO" ] && [ -n "${USER:-}" ] && [ "${USER}" != "root" ]; then
  run $SUDO usermod -aG docker "$USER"
fi

prompt_for_tailscale_auth_key

if [ -n "$TAILSCALE_AUTH_KEY" ]; then
  if [ -n "$TAILSCALE_EXTRA_ARGS" ]; then
    run_shell "$SUDO tailscale up --auth-key ${TAILSCALE_AUTH_KEY@Q} $TAILSCALE_EXTRA_ARGS"
  else
    run_shell "$SUDO tailscale up --auth-key ${TAILSCALE_AUTH_KEY@Q}"
  fi
else
  echo "Tailscale installed and tailscaled started. Run 'sudo tailscale up' to join the tailnet before using TAILSCALE_REQUIRED=true modes."
fi

echo "Debian host prep complete."
echo "Installed: curl git bash python3 Docker Engine docker compose plugin tailscale"
if [ -n "$SUDO" ] && [ -n "${USER:-}" ] && [ "${USER}" != "root" ]; then
  echo "Note: log out and back in before using docker without sudo."
fi
