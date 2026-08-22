#!/usr/bin/env bash
# Install the system-wide weekly OS + portable stack maintenance timer.
set -euo pipefail

stack_dir=
stack_user=
ntfy_server=
ntfy_topic=

while [ $# -gt 0 ]; do
  case "$1" in
    --stack-dir) stack_dir=${2:?missing value}; shift 2 ;;
    --stack-user) stack_user=${2:?missing value}; shift 2 ;;
    --ntfy-server) ntfy_server=${2:?missing value}; shift 2 ;;
    --ntfy-topic) ntfy_topic=${2:?missing value}; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ "$(id -u)" -eq 0 ] || { echo "Run as root" >&2; exit 1; }
[ -d "$stack_dir/.git" ] || { echo "Stack directory is not a Git checkout: $stack_dir" >&2; exit 1; }
id "$stack_user" >/dev/null
case "$ntfy_server" in https://*|http://*) ;; *) echo "ntfy server must be http(s)" >&2; exit 2;; esac
case "$ntfy_topic" in *[!A-Za-z0-9._-]*|'') echo "ntfy topic contains unsupported characters" >&2; exit 2;; esac

install -d -m 0750 /etc/portable-media-stack
cat >/etc/portable-media-stack/maintenance.env <<EOF
STACK_DIR=$stack_dir
STACK_USER=$stack_user
NTFY_SERVER=$ntfy_server
NTFY_TOPIC=$ntfy_topic
EOF
chmod 0640 /etc/portable-media-stack/maintenance.env

install -m 0755 "$(dirname "$0")/weekly-maintenance.sh" /usr/local/sbin/portable-media-stack-weekly-maintenance
install -m 0644 "$(dirname "$0")/portable-media-stack-weekly-maintenance.service" /etc/systemd/system/portable-media-stack-weekly-maintenance.service
install -m 0644 "$(dirname "$0")/portable-media-stack-weekly-maintenance.timer" /etc/systemd/system/portable-media-stack-weekly-maintenance.timer
systemctl daemon-reload
systemctl enable --now portable-media-stack-weekly-maintenance.timer
systemctl list-timers portable-media-stack-weekly-maintenance.timer --all --no-pager
