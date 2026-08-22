#!/usr/bin/env bash
set -uo pipefail

# shellcheck disable=SC1091
source /etc/portable-media-stack/maintenance.env
log_dir=/var/log/portable-media-stack
mkdir -p "$log_dir"
log="$log_dir/weekly-maintenance-$(date +%F).log"
exec >>"$log" 2>&1

host=$(hostname -s)
started=$(date -Is)
os_status=success
stack_status=success

if ! (apt-get update && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y); then
  os_status=failed
fi

if ! runuser -u "$STACK_USER" -- bash -lc "cd $(printf '%q' "$STACK_DIR") && ./squid-media update"; then
  stack_status=failed
fi

if [ "$os_status" = success ] && [ "$stack_status" = success ]; then
  title="✅ Media stack weekly maintenance: $host"
  priority=3
  tags="white_check_mark,whale,package"
  exit_code=0
else
  title="❌ Media stack weekly maintenance failed: $host"
  priority=5
  tags="warning,whale,package"
  exit_code=1
fi

body="Host: $host
Started: $started
System packages: $os_status
Portable stack: $stack_status
Log: $log
Reboot: not performed"
curl --fail --silent --show-error --max-time 20 \
  -H "Title: $title" -H "Priority: $priority" -H "Tags: $tags" \
  -d "$body" "${NTFY_SERVER%/}/$NTFY_TOPIC" || true
exit "$exit_code"
