#!/bin/bash
# build.sh — cross-compile a current tailscale for ancient macOS (10.9 Mavericks)
# from a modern Mac. Produces `out/tailscale` + `out/tailscaled` that run natively.
#
# Everything here is load-bearing; the why of each flag is in doc/backport-notes.md.
#
# Usage:  ./build.sh [tailscale-version]        (default 1.102.4)
# Env:
#   GO        go binary to build with      (default: auto-resolved from go.mod)
#   SHIM_HOST ssh host to fetch the MacPorts legacy shim from, if not in shim/
#   SMOKE_HOST optional ssh host to run the smoke-test binary on before building
set -euo pipefail

TSVER="${1:-1.102.4}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# --- prerequisites -----------------------------------------------------------
command -v clang >/dev/null || { echo "need clang (Xcode CLT)"; exit 1; }

if [ ! -f shim/libMacportsLegacySupport.a ]; then
    if [ -n "${SHIM_HOST:-}" ]; then
        ./shim/fetch-shim.sh "$SHIM_HOST"
    else
        echo "missing shim/libMacportsLegacySupport.a — run: ./shim/fetch-shim.sh <target-host>"
        exit 1
    fi
fi
SHIM_A="$ROOT/shim/libMacportsLegacySupport.a"

# --- stub + toolchain --------------------------------------------------------
clang -arch x86_64 -mmacosx-version-min=10.9 -c shim/stub.c -o shim/stub.o
STUB_O="$ROOT/shim/stub.o"

SRC="$ROOT/src/tailscale-$TSVER"
if [ ! -d "$SRC" ]; then
    mkdir -p src
    curl -sL -o "src/ts-$TSVER.tar.gz" \
        "https://github.com/tailscale/tailscale/archive/refs/tags/v$TSVER.tar.gz"
    tar xzf "src/ts-$TSVER.tar.gz" -C src
fi
cd "$SRC"

# --- apply patches -----------------------------------------------------------
# 1) drop enterprise keychain register-signing (needs 10.14+ Security.framework;
#    unused on standard tailnets)
git apply --check "$ROOT/patches/001-sign-buildtags.patch" 2>/dev/null \
    && git apply "$ROOT/patches/001-sign-buildtags.patch" \
    || echo "patch 001 already applied or tree dirty — skipping"

# 2) pure-Go TLS root verification (crypto/x509's system verifier needs 10.14+)
cp "$ROOT/patches/files/fallbackroots_darwin109.go" cmd/tailscaled/
cp /etc/ssl/cert.pem cmd/tailscaled/fallback-roots.pem   # Mozilla bundle

# --- resolve Go toolchain: go.mod's requirement wins -------------------------
REQ_GO=$(grep -m1 '^go ' go.mod | awk '{print $2}')
GO="${GO:-go}"
have=$("$GO" version 2>/dev/null | grep -oE 'go[0-9.]+' | head -1 | tr -d go) || true
if [ -z "$have" ] || [ "$(printf '%s\n' "$REQ_GO" "$have" | sort -V | head -1)" != "$REQ_GO" ]; then
    CAND="$HOME/go/bin/go${REQ_GO}"
    if [ ! -x "$CAND" ]; then
        echo "need Go >= $REQ_GO (have ${have:-none}). Installing $CAND..."
        go install "golang.org/dl/go${REQ_GO}@latest"
        "$CAND" download
    fi
    GO="$CAND"
fi
echo "building tailscale $TSVER with $GO ($(basename "$SRC"))"

# --- the incantation ---------------------------------------------------------
#  CGO_CFLAGS min-version  -> gates cgo #if __MAC_OS_X_VERSION_MIN_REQUIRED
#                             (kIOMainPortDefault -> kIOMasterPortDefault)
#  -buildmode=exe          -> PIE external links bind undefineds to the host
#                             SDK dylibs before pulling archives; exe doesn't
#  -Wl,-force_load         -> the shim archive MUST come in whole
#  stub.o                  -> object files always link; archives need -u tricks
LDFLAGS="-linkmode external -extldflags '-arch x86_64 -mmacosx-version-min=10.9 -Wl,-force_load,$SHIM_A $STUB_O' -X tailscale.com/version.longStamp=$TSVER -X tailscale.com/version.shortStamp=$TSVER -X tailscale.com/version.gitCommitStamp=non-git"

# NB: no GOTOOLCHAIN=local — go.mod's toolchain directive auto-switches to the
# required version; the dl-wrapper fallback below covers offline setups.
ENVC="CGO_ENABLED=1 GOOS=darwin GOARCH=amd64 CC=clang CGO_CFLAGS=-mmacosx-version-min=10.9"

# --- optional smoke test: prove the toolchain produces 10.9-runnable code ----
if [ -n "${SMOKE_HOST:-}" ]; then
    echo "== smoke test on $SMOKE_HOST =="
    ( cd "$ROOT/test" && env $ENVC "$GO" build -buildmode=exe \
        -ldflags "-linkmode external -extldflags '-arch x86_64 -mmacosx-version-min=10.9 -Wl,-force_load,$SHIM_A $STUB_O'" \
        -o /tmp/tsmoke smoke.go )
    scp -q /tmp/tsmoke "$SMOKE_HOST:/tmp/tsmoke"
    ssh "$SMOKE_HOST" 'chmod +x /tmp/tsmoke && /tmp/tsmoke' \
        || { echo "SMOKE TEST FAILED on $SMOKE_HOST"; exit 1; }
fi

# --- build -------------------------------------------------------------------
mkdir -p "$ROOT/out"
for cmd in tailscaled tailscale; do
    echo "== building $cmd =="
    env $ENVC "$GO" build -tags darwin_10_9 -buildmode=exe -ldflags "$LDFLAGS" \
        -o "$ROOT/out/$cmd" "./cmd/$cmd"
done

echo "OK → $ROOT/out/ (copy to /opt/local/bin on the target; see deploy/)"
