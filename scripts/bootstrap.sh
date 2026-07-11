#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/Squidlabs2/portable-media-stack.git}"
INSTALL_DIR="${INSTALL_DIR:-${HOME}/portable-media-stack}"
BRANCH="${BRANCH:-main}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

need_cmd git
need_cmd bash
need_cmd curl

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
exec ./scripts/install.sh "$@"
