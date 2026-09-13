#!/bin/bash
# install.sh — tarball installer; run ON the old Mac inside the extracted
# directory (next to the `tailscale`/`tailscaled` binaries and plist).
#
#   sudo ./install.sh              install to /usr/local/bin + launchd
#   sudo AUTHKEY=tskey-... ./install.sh    ... and join immediately
#
# Idempotent; migrates an older /opt/local install; keeps existing state.
set -e
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
cd "$(dirname "$0")"

BIN=/usr/local/bin
PLIST=/Library/LaunchDaemons/com.tailscale.tailscaled.plist
SOCK=/var/run/tailscaled.socket

mkdir -p "$BIN" /var/lib/tailscale
install -m 755 tailscale tailscaled "$BIN/"
touch /var/log/tailscaled.log

# plist with our destination baked in
sed 's|/opt/local/bin/tailscaled|/usr/local/bin/tailscaled|' \
    com.tailscale.tailscaled.plist > "$PLIST"
chown root:wheel "$PLIST"; chmod 644 "$PLIST"

# stop previous daemon (old location or prior install), then load
( launchctl unload "$PLIST" 2>/dev/null || true )
pkill -x tailscaled 2>/dev/null || true
sleep 1
launchctl load "$PLIST"
sleep 5

"$BIN/tailscale" --socket="$SOCK" version | head -2
if [ -n "${AUTHKEY:-}" ]; then
    "$BIN/tailscale" --socket="$SOCK" up --authkey="$AUTHKEY"
fi
"$BIN/tailscale" --socket="$SOCK" status | head -3
echo
echo "installed. without an AUTHKEY, join with:"
echo "  $BIN/tailscale --socket=$SOCK up"
