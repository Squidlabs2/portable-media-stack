#!/usr/bin/env bash
# Install the restricted, Tailscale-bound management API for this stack.
set -euo pipefail

stack_dir=
stack_user=
bind=
token=
token_file=
port=9876
while [ $# -gt 0 ]; do
  case "$1" in
    --stack-dir) stack_dir=$2; shift 2 ;;
    --stack-user) stack_user=$2; shift 2 ;;
    --bind) bind=$2; shift 2 ;;
    --token) token=$2; shift 2 ;;
    --token-file) token_file=$2; shift 2 ;;
    --port) port=$2; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

if [ -n "$token_file" ]; then
  [ -z "$token" ] || { echo "Use only one of --token or --token-file" >&2; exit 2; }
  [ -f "$token_file" ] || { echo "--token-file must exist" >&2; exit 2; }
  token=$(<"$token_file")
fi

[ -n "$stack_dir" ] && [ -d "$stack_dir" ] || { echo "--stack-dir must be an existing directory" >&2; exit 2; }
[ -n "$stack_user" ] && id "$stack_user" >/dev/null 2>&1 || { echo "--stack-user must exist" >&2; exit 2; }
[ -n "$bind" ] || { echo "--bind is required" >&2; exit 2; }
[ -n "$token" ] && [ "${#token}" -ge 32 ] || { echo "--token must contain at least 32 characters" >&2; exit 2; }
case "$port" in *[!0-9]*|'') echo "--port must be numeric" >&2; exit 2;; esac

install -d -m 0750 /etc/portable-media-stack
umask 077
cat > /etc/portable-media-stack/management-agent.env <<EOF
STACK_DIR=$stack_dir
MANAGEMENT_AGENT_BIND=$bind
MANAGEMENT_AGENT_PORT=$port
MANAGEMENT_AGENT_TOKEN=$token
EOF
chmod 0600 /etc/portable-media-stack/management-agent.env

sed -e "s|__STACK_DIR__|$stack_dir|g" -e "s|__STACK_USER__|$stack_user|g" \
  "$(dirname "$0")/portable-media-stack-management-agent.service" \
  > /etc/systemd/system/portable-media-stack-management-agent.service
chmod 0644 /etc/systemd/system/portable-media-stack-management-agent.service
systemctl daemon-reload
systemctl enable --now portable-media-stack-management-agent.service
systemctl status portable-media-stack-management-agent.service --no-pager
