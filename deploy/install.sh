#!/bin/bash
# install.sh — deploy freshly built binaries + launchd service to an old Mac.
#
# Usage: ./deploy/install.sh <ssh-host> [authkey]
#   authkey optional: run `tailscale up --authkey=...` after install.
#                     (generate in admin console; reusable recommended)
#
# The target needs: sudo rights for the invoking ssh user, /opt/local (MacPorts).
# Non-interactive sudo: export TS_SUDO_PW if the target asks for a password.
set -euo pipefail

HOST="${1:?usage: install.sh <ssh-host> [authkey]}"
AUTHKEY="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

SUDO="sudo"
if [ -n "${TS_SUDO_PW:-}" ]; then
    run_root() { printf '%s\n' "$TS_SUDO_PW" | ssh "$HOST" "sudo -S -p '' $1"; }
else
    run_root() { ssh "$HOST" "sudo -n $1" 2>/dev/null || ssh -t "$HOST" "sudo $1"; }
fi

scp -q "$ROOT/out/tailscale" "$ROOT/out/tailscaled" "$HOST":/tmp/
scp -q "$ROOT/deploy/com.tailscale.tailscaled.plist" "$HOST":/tmp/

run_root 'pkill -x tailscaled || true; sleep 1'
run_root 'install -m 755 /tmp/tailscale /tmp/tailscaled /opt/local/bin/'
run_root 'mkdir -p /var/lib/tailscale'
run_root 'cp /tmp/com.tailscale.tailscaled.plist /Library/LaunchDaemons/ && chown root:wheel /Library/LaunchDaemons/com.tailscale.tailscaled.plist && chmod 644 /Library/LaunchDaemons/com.tailscale.tailscaled.plist'
run_root 'launchctl unload /Library/LaunchDaemons/com.tailscale.tailscaled.plist 2>/dev/null || true; launchctl load /Library/LaunchDaemons/com.tailscale.tailscaled.plist'

sleep 8
ssh "$HOST" 'ps aux | grep -q [t]ailscaled' || { echo "tailscaled did not start — check /var/log/tailscaled.log on target"; exit 1; }
ssh "$HOST" /opt/local/bin/tailscale --socket=/var/run/tailscaled.socket version | head -2

if [ -n "$AUTHKEY" ]; then
    ssh "$HOST" /opt/local/bin/tailscale --socket=/var/run/tailscaled.socket up --authkey="$AUTHKEY"
fi
ssh "$HOST" /opt/local/bin/tailscale --socket=/var/run/tailscaled.socket status | head -3
