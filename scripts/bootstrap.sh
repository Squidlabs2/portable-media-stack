#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/Squidlabs2/portable-media-stack.git}"
INSTALL_DIR="${INSTALL_DIR:-${HOME}/portable-media-stack}"
BRANCH="${BRANCH:-main}"
PREPARE_HOST=false
PREPARE_HOST_ARGS=()
INSTALL_ARGS=()
BOOTSTRAP_SOURCE_DIR=
HOST_PREP_DONE=false

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

need_cmd bash
need_cmd curl

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

cleanup() {
  if [ -n "${BOOTSTRAP_SOURCE_DIR:-}" ] && [ -d "$BOOTSTRAP_SOURCE_DIR" ] && [[ "$BOOTSTRAP_SOURCE_DIR" == /tmp/* ]]; then
    rm -rf "$BOOTSTRAP_SOURCE_DIR"
  fi
}

trap cleanup EXIT

github_tarball_url() {
  case "$REPO_URL" in
    https://github.com/*.git)
      printf '%s\n' "${REPO_URL%.git}/archive/refs/heads/${BRANCH}.tar.gz"
      ;;
    https://github.com/*)
      printf '%s\n' "${REPO_URL}/archive/refs/heads/${BRANCH}.tar.gz"
      ;;
    git@github.com:*.git)
      local owner_repo=${REPO_URL#git@github.com:}
      owner_repo=${owner_repo%.git}
      printf 'https://github.com/%s/archive/refs/heads/%s.tar.gz\n' "$owner_repo" "$BRANCH"
      ;;
    *)
      return 1
      ;;
  esac
}

download_repo_archive() {
  need_cmd tar

  local tarball_url tmpdir extracted_dir
  tarball_url=$(github_tarball_url) || {
    echo "Git is required for non-GitHub repo URLs during bootstrap." >&2
    exit 1
  }

  tmpdir=$(mktemp -d /tmp/portable-media-stack-bootstrap-XXXXXX)
  BOOTSTRAP_SOURCE_DIR="$tmpdir"
  echo "Git not found; downloading $BRANCH archive from GitHub bootstrap URL" >&2
  curl -fsSL "$tarball_url" | tar -xzf - -C "$tmpdir"

  extracted_dir=$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d | head -n 1)
  [ -n "$extracted_dir" ] || {
    echo "Failed to unpack bootstrap archive" >&2
    exit 1
  }

  printf '%s\n' "$extracted_dir"
}

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

if have_cmd git; then
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
else
  if [ "$PREPARE_HOST" != true ]; then
    echo "Missing required command: git" >&2
    echo "Either install git first or rerun bootstrap with --prepare-host on a supported Debian host." >&2
    exit 1
  fi

  BOOTSTRAP_SOURCE_DIR=$(download_repo_archive)
  cd "$BOOTSTRAP_SOURCE_DIR"

  ./scripts/prepare-host-debian.sh "${PREPARE_HOST_ARGS[@]}"
  HOST_PREP_DONE=true

  if [ -e "$INSTALL_DIR" ] && [ ! -d "$INSTALL_DIR/.git" ]; then
    echo "Install directory exists but is not a git checkout: $INSTALL_DIR" >&2
    echo "Remove it or choose a different INSTALL_DIR, then rerun bootstrap." >&2
    exit 1
  fi

  echo "Cloning $REPO_URL into $INSTALL_DIR"
  git clone --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
  cd "$INSTALL_DIR"
fi

if [ "$PREPARE_HOST" = true ] && [ "$HOST_PREP_DONE" != true ] && have_cmd git; then
  ./scripts/prepare-host-debian.sh "${PREPARE_HOST_ARGS[@]}"
fi

exec ./scripts/install.sh "${INSTALL_ARGS[@]}"
