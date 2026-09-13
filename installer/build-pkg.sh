#!/bin/bash
# build-pkg.sh — package the prebuilt binaries as a flat .pkg installer for
# OS X 10.9. Installs to /usr/local/bin (default PATH on 10.9; binaries are
# self-contained — no MacPorts needed) + the launchd daemon, preserving any
# existing state in /var/lib/tailscale.
#
# Usage: ./installer/build-pkg.sh [version]    (default 1.102.4)
#   MACOS_MIN=10.6  packages the GOAMD64=v1 flavor from out-macos10.6/ instead
# Requires out/ (or out-macos10.6/) binaries from build.sh, and pkgbuild (Xcode CLT).
#
# Replaces prior installs: same identifier -> Installer overwrites the payload
# files; postinstall pkills any running tailscaled (either flavor) and reloads.
# Never touches /opt/local copies or /var/lib/tailscale state.
set -euo pipefail

TSVER="${1:-1.102.4}"
MACOS_MIN="${MACOS_MIN:-10.9}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="$ROOT/installer/stage"
OUTDIR="$ROOT/out"
[ "$MACOS_MIN" = 10.6 ] && OUTDIR="$ROOT/out-macos10.6"

rm -rf "$STAGE"
mkdir -p "$STAGE/root/usr/local/bin" "$STAGE/root/Library/LaunchDaemons" "$STAGE/scripts"

for f in tailscale tailscaled; do
    [ -x "$OUTDIR/$f" ] || { echo "missing $OUTDIR/$f — run ./build.sh first"; exit 1; }
    cp "$OUTDIR/$f" "$STAGE/root/usr/local/bin/"
done

# plist with the pkg's destination baked in
sed 's|/opt/local/bin/tailscaled|/usr/local/bin/tailscaled|' \
    "$ROOT/deploy/com.tailscale.tailscaled.plist" \
    > "$STAGE/root/Library/LaunchDaemons/com.tailscale.tailscaled.plist"

cp "$ROOT/installer/scripts/"* "$STAGE/scripts/" 2>/dev/null || true

PKG="$ROOT/tailscale-${TSVER}-macos${MACOS_MIN}.pkg"
pkgbuild \
    --root "$STAGE/root" \
    --scripts "$STAGE/scripts" \
    --identifier com.startergo.tailscale-legacy \
    --version "$TSVER" \
    --ownership recommended \
    "$PKG"

echo "OK → $PKG"
echo "install on target:  sudo installer -pkg $PKG -target /"
