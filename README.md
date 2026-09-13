# tailscale-legacy-macos

Run a **current Tailscale client natively on ancient macOS** — proven on OS X
10.9 Mavericks (2013), joining a 2026 tailscale.com tailnet as a first-class
node (WireGuard tunnel, `tailscale up --authkey`, MagicDNS, the works).

Built and tested with tailscale **1.102.4** / Go **1.26.6** targeting
`darwin/amd64`, deploying from a modern Mac (arm64, Xcode clang).

## Why this exists

Official Tailscale needs macOS 10.15+ (Go's floor), and MacPorts' tailscale
port is `known_fail` on 10.9 ("needs Go 1.26, this macOS runs nothing newer
than Go 1.17"). The last version buildable on-target (v1.22.2) can no longer
authenticate: the 2026 control plane rejects its legacy plaintext register
transport (`http 410: auth path not found` / `API key does not exist`).

The twist: modern Go binaries fail on 10.9 for exactly **four** patchable
reasons (see [doc/backport-notes.md](doc/backport-notes.md)). Fix those and
current tailscale runs fine — 17 years of OS underneath, zero spoofing.

## Quickstart

```sh
# on a modern Mac (needs Xcode CLT + go ≥ go.mod's requirement):
./shim/fetch-shim.sh mavericksm          # once: pull MacPorts' compat lib from the target
./build.sh 1.102.4                       # → out/tailscale{,d}
./deploy/install.sh mavericksm tskey-auth-...   # deploy + launchd + join
```

Smoke-test the toolchain against a target before the big build:

```sh
SMOKE_HOST=mavericksm ./build.sh
```

The daemon **must** keep `GODEBUG=x509usefallbackroots=1` in its environment
(handled by the included launchd plist).

## Repo layout

```
build.sh                            one-shot cross-compile
shim/stub.c                         C stubs for post-10.9 libSystem symbols
shim/fetch-shim.sh                  fetch MacPorts legacy-support from the target
patches/001-sign-buildtags.patch    drop 10.14+ keychain register-signing
patches/files/fallbackroots_darwin109.go   embed Mozilla roots, pure-Go TLS verify
deploy/com.tailscale.tailscaled.plist      launchd service (with GODEBUG)
deploy/install.sh                   remote install + join
test/smoke.go                       runtime/networking smoke test
doc/backport-notes.md               the full how-it-works + audit method
```

## Status

| Target | State |
|---|---|
| OS X 10.9 Mavericks (x86_64) | ✅ 1.102.4 running, joined, p2p verified |
| OS X 10.6 Snow Leopard | ⚠️ untested — same method, wider symbol audit needed (10.6 lacks even more libSystem); see notes |

Upgrade path: re-run `./build.sh <new-version>`. If a newer Go drags in new
post-10.9 symbols, the dyld error names the first one — extend `shim/stub.c`
using the audit recipe in the notes.

Not affiliated with Tailscale. Patches here are for personal/legacy-hardware
use; the modified binaries are unsupported upstream.
