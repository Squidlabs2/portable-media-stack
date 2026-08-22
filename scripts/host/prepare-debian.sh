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
    echo "Tailscale auth key not provided and no interactive terminal is available; tailnet enrollment cannot continue."
    return 0
  fi

  echo
  echo "Tailscale tailnet enrollment is required for every Squid Media Stack host."
  echo "Paste an auth key to join automatically, or press Enter to authenticate in your browser."
  read -r -p "Tailscale auth key: " TAILSCALE_AUTH_KEY
}

tailscale_connected() {
  tailscale status --json >/dev/null 2>&1
}

configure_user_shell() {
  local bashrc="${HOME}/.bashrc"
  local marker_start="# >>> squid-media host prep >>>"
  local marker_end="# <<< squid-media host prep <<<"

  if [ "$DRY_RUN" = true ]; then
    printf 'DRY RUN: update %q with fastfetch startup and alias v=%q\n' "$bashrc" "ls -hals"
    return 0
  fi

  touch "$bashrc"
  if grep -Fq "$marker_start" "$bashrc"; then
    echo "Shell convenience block already present in $bashrc"
    return 0
  fi

  cat >>"$bashrc" <<'EOF'

# >>> squid-media host prep >>>
if command -v fastfetch >/dev/null 2>&1; then
  fastfetch
fi
alias v='ls -hals'
# <<< squid-media host prep <<<
EOF
  echo "Added fastfetch startup and alias v='ls -hals' to $bashrc"
}

connect_tailscale() {
  [ "$DRY_RUN" = false ] || return 0

  if tailscale_connected; then
    echo "Tailscale is already connected to a tailnet."
    return 0
  fi

  if [ -n "$TAILSCALE_AUTH_KEY" ]; then
    if [ -n "$TAILSCALE_EXTRA_ARGS" ]; then
      run_shell "$SUDO tailscale up --auth-key ${TAILSCALE_AUTH_KEY@Q} $TAILSCALE_EXTRA_ARGS"
    else
      run $SUDO tailscale up --auth-key "$TAILSCALE_AUTH_KEY"
    fi
  elif [ -t 0 ]; then
    echo
    echo "Opening Tailscale login. Follow the URL it prints, authenticate this device, then return here."
    if [ -n "$TAILSCALE_EXTRA_ARGS" ]; then
      run_shell "$SUDO tailscale up $TAILSCALE_EXTRA_ARGS" || true
    else
      run $SUDO tailscale up || true
    fi
  else
    echo "ERROR: Tailscale auth is required for this host. Set TAILSCALE_AUTH_KEY or run this command from an interactive terminal." >&2
    exit 1
  fi

  if ! tailscale_connected; then
    echo "ERROR: Tailscale is installed but not connected to a tailnet." >&2
    echo "Complete the browser login from the URL above, then rerun ./scripts/install.sh from the repository checkout." >&2
    exit 1
  fi

  echo "Tailscale tailnet enrollment verified."
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
run $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin tailscale fastfetch vim
run $SUDO systemctl enable --now docker
run $SUDO systemctl enable --now tailscaled

if [ -n "$SUDO" ] && [ -n "${USER:-}" ] && [ "${USER}" != "root" ]; then
  run $SUDO usermod -aG docker "$USER"
fi

configure_user_shell

prompt_for_tailscale_auth_key
connect_tailscale

echo "Debian host prep complete; Docker is ready and Tailscale tailnet enrollment is verified."
echo "Installed: curl git bash python3 Docker Engine docker compose plugin tailscale fastfetch vim"
if [ -n "$SUDO" ] && [ -n "${USER:-}" ] && [ "${USER}" != "root" ]; then
  echo "The bootstrap refreshes Docker group access before it launches the installer; future SSH sessions still need a new login."
fi
