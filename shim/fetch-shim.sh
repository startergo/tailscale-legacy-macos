#!/bin/bash
# fetch-shim.sh — copy MacPorts' legacy-support compatibility library from the
# target Mac. It provides libSystem symbols missing on 10.9 (clock_gettime
# & friends) as a static archive we -force_load into the binary.
#
# Requires MacPorts on the target (sudo port install legacy-support — it
# comes in as a dependency of go-1.17 if that's installed).
#
# Usage: ./shim/fetch-shim.sh <ssh-host> [destdir]
set -euo pipefail

HOST="${1:?usage: fetch-shim.sh <ssh-host> [destdir]}"
DEST="${2:-$(cd "$(dirname "$0")/.." && pwd)/shim}"

mkdir -p "$DEST"
for f in libMacportsLegacySupport.a libMacportsLegacySupport.dylib; do
    scp "$HOST:/opt/local/lib/$f" "$DEST/$f"
done
echo "shim fetched to $DEST"
