#!/bin/bash
# uninstall.sh — remove the tailscale-legacy install (pkg flavor at
# /usr/local, tarball flavor at /opt/local). Run with sudo ON the old Mac.
set -e
PLIST=/Library/LaunchDaemons/com.tailscale.tailscaled.plist

launchctl unload "$PLIST" 2>/dev/null || true
pkill -x tailscaled 2>/dev/null || true
rm -f "$PLIST"
rm -f /usr/local/bin/tailscale /usr/local/bin/tailscaled
rm -f /opt/local/bin/tailscale /opt/local/bin/tailscaled

# state (machine identity + login) — keep unless you pass --purge
if [ "${1:-}" = "--purge" ]; then
    rm -rf /var/lib/tailscale
    rm -f /var/log/tailscaled.log
    echo "state purged (device will need re-auth if reinstalled)"
else
    echo "kept /var/lib/tailscale/tailscaled.state (use --purge to drop identity)"
fi
echo "uninstalled."
