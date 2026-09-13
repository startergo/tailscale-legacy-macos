#!/bin/bash
# build-pkg.sh — package the prebuilt binaries as a flat .pkg installer for
# OS X 10.9. Installs to /usr/local/bin (default PATH on 10.9; binaries are
# self-contained — no MacPorts needed) + the launchd daemon, preserving any
# existing state in /var/lib/tailscale.
#
# Usage: ./installer/build-pkg.sh [version]    (default 1.102.4)
# Requires out/tailscale + out/tailscaled from build.sh, and pkgbuild (Xcode CLT).
set -euo pipefail

TSVER="${1:-1.102.4}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="$ROOT/installer/stage"

rm -rf "$STAGE"
mkdir -p "$STAGE/root/usr/local/bin" "$STAGE/root/Library/LaunchDaemons" "$STAGE/scripts"

for f in tailscale tailscaled; do
    [ -x "$ROOT/out/$f" ] || { echo "missing out/$f — run ./build.sh first"; exit 1; }
    cp "$ROOT/out/$f" "$STAGE/root/usr/local/bin/"
done

# plist with the pkg's destination baked in
sed 's|/opt/local/bin/tailscaled|/usr/local/bin/tailscaled|' \
    "$ROOT/deploy/com.tailscale.tailscaled.plist" \
    > "$STAGE/root/Library/LaunchDaemons/com.tailscale.tailscaled.plist"

cp "$ROOT/installer/scripts/"* "$STAGE/scripts/" 2>/dev/null || true

PKG="$ROOT/tailscale-${TSVER}-macos10.9.pkg"
pkgbuild \
    --root "$STAGE/root" \
    --scripts "$STAGE/scripts" \
    --identifier com.startergo.tailscale-legacy \
    --version "$TSVER" \
    --ownership recommended \
    "$PKG"

echo "OK → $PKG"
echo "install on target:  sudo installer -pkg $PKG -target /"
