#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/Squidlabs2/portable-media-stack.git}"
INSTALL_DIR="${INSTALL_DIR:-${HOME}/portable-media-stack}"
BRANCH="${BRANCH:-main}"
PREPARE_HOST=false
PREPARE_HOST_ARGS=()
INSTALL_ARGS=()

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

need_cmd git
need_cmd bash
need_cmd curl

while [ $# -gt 0 ]; do
  case "$1" in
    --prepare-host)
      PREPARE_HOST=true
      ;;
    --skip-upgrade)
      PREPARE_HOST_ARGS+=("$1")
      ;;
    --dry-run)
      PREPARE_HOST_ARGS+=("$1")
      INSTALL_ARGS+=("$1")
      ;;
    --tailscale-auth-key|--tailscale-extra-args)
      PREPARE_HOST=true
      PREPARE_HOST_ARGS+=("$1")
      shift
      [ $# -gt 0 ] || {
        echo "Missing value for host prep argument" >&2
        exit 1
      }
      PREPARE_HOST_ARGS+=("$1")
      ;;
    *)
      INSTALL_ARGS+=("$1")
      ;;
  esac
  shift
done

if [ ! -d "$INSTALL_DIR/.git" ]; then
  echo "Cloning $REPO_URL into $INSTALL_DIR"
  git clone --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
else
  echo "Updating existing repo in $INSTALL_DIR"
  git -C "$INSTALL_DIR" fetch origin "$BRANCH"
  git -C "$INSTALL_DIR" checkout "$BRANCH"
  git -C "$INSTALL_DIR" pull --ff-only origin "$BRANCH"
fi

cd "$INSTALL_DIR"

if [ "$PREPARE_HOST" = true ]; then
  ./scripts/prepare-host-debian.sh "${PREPARE_HOST_ARGS[@]}"
fi

exec ./scripts/install.sh "${INSTALL_ARGS[@]}"
