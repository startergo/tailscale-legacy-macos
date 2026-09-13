# Backport notes: modern Go/tailscale on OS X 10.9

Working notes from the original port (2026-09-13, tailscale 1.102.4, Go 1.26.6,
target = 2009-era MacBook on 10.9.5). Everything below is encoded in `build.sh`,
but the *reasoning* matters when something breaks after an upgrade.

## The four blockers

A stock Go ≥1.18 `darwin/amd64` binary dies on 10.9 for four independent
reasons. Each has its own fix; all four are needed.

### 1. Post-10.9 libSystem symbols (dyld, hard references)

Go's runtime references libSystem symbols via `cgo_import_dynamic` — these are
**hard** dynamic bindings, and dyld reports only the *first* missing one, so
iterate. Symbols found in practice:

| Symbol | Added in | Used by | Fix |
|---|---|---|---|
| `clock_gettime` (+`_nsec_np`) | 10.12 | `runtime.walltime` | MacPorts legacy-support shim, `-force_load` |
| `notify_is_valid_token` | 10.15 | os/signal drain | `shim/stub.c` (return 0) |

The shim: MacPorts' `legacy-support` port ships
`/opt/local/lib/libMacportsLegacySupport.a` with compat implementations of
10.10–10.13-era libSystem calls. We link it **statically** on the build host.

**Audit method** (do this for every new Go/tailscale version):

```sh
# needs side:
nm -u <binary> | awk '{print $2}' | sed 's/^_//' | sort -u
# provides side (on the target; libSystem.B.dylib is an umbrella — enumerate!)
for f in /usr/lib/libSystem.B.dylib /usr/lib/system/*.dylib /usr/lib/libresolv.9.dylib; \
    do nm -gU "$f"; done | awk '/ T /{print $3}' | sed 's/^_//' | sort -u
# delta = comm -23 needs provides   (mind LC_ALL=C on both)
```

Anything in the delta gets either a shim implementation or a stub in
`shim/stub.c`.

### 2. PIE external links defeat archive resolution

Go defaults to `-buildmode=pie` on darwin. Under PIE, the external linker
bindies undefined symbols against the **build host's SDK dylibs** (which have
everything) before it pulls archive members — so the shim silently doesn't get
linked, and you get a runtime lazy-binding crash instead of a build error.

Fix: `-buildmode=exe` + `-Wl,-force_load,<shim.a>`. Object files (like
`stub.o`) always link; archives need `-force_load` (plain `-Wl,-u,_sym` proved
unreliable here).

Related trap: `CGO_LDFLAGS` is sanitized by cmd/go — absolute `.a` paths are
silently **dropped**. Put archives/objects in `-extldflags` (passed through
verbatim). The nested quoting works because cmd/go's flag splitter honors
inner single quotes.

### 3. macOS-12 IOKit symbol in cgo code

`posture/serialnumber_macos.go` calls `IOServiceGetMatchingService
(kIOMainPortDefault, ...)` — `kIOMainPortDefault` only exists on macOS 12+.
The file *already has* a compat `#define kIOMainPortDefault kIOMasterPortDefault`
gated on `__MAC_OS_X_VERSION_MIN_REQUIRED < 120000` — but that's a **cgo
compile-time** check, and the min-version must be passed to the C compiler,
not just the linker:

```
CGO_CFLAGS=-mmacosx-version-min=10.9
```

With that set, the source's own ifdef does the right thing. (10.9's
`kIOMasterPortDefault` is ancient and fine.)

### 4. crypto/x509 system verifier needs 10.14+

On darwin+cgo, TLS certificate verification goes through the Security
framework (`SecTrustEvaluateWithError`, macOS 10.14+). It fires the first time
tailscaled talks TLS to the control plane — instant SIGTRAP.

Fix (no source-level verifier hacking, real validation preserved): embed the
Mozilla CA bundle and register it as x509 *fallback roots*
(`patches/files/fallbackroots_darwin109.go`), launched with
`GODEBUG=x509usefallbackroots=1`. Go then verifies chains in pure Go against
a real root store and skips the platform verifier entirely
(crypto/x509/verify.go refuses `systemVerify` when the fallback pool replaced
the system pool).

Note the chain: the GODEBUG has **no effect unless the program called
`x509.SetFallbackRoots` first** (crypto/x509/root.go), which tailscale doesn't
do — hence the patch file.

### 4b. Enterprise register-signing (tailscale-specific)

`control/controlclient/sign_supported.go` (tag `darwin && cgo`) pulls
`certstore` → Security.framework constants like
`kSecKeyAlgorithmECDSASignatureDigestX962SHA256` (10.12+). The feature —
machine-certificate-signed RegisterRequests — only activates under an MDM
`MachineCertificateSubject` policy, and can't work on 10.9 anyway
(`SecKeyCreateSignature` is 10.12+). The patch narrows its build tag to
`windows`, making darwin use the stock `sign_unsupported.go` fallback.

## The auth problem this repo sidesteps (and why v1.22 is dead)

The obvious approach — build the newest tailscale that MacPorts' go-1.17 can
compile (v1.22.2, May 2022; v1.24+ needs Go 1.18) — runs beautifully on 10.9
and **cannot log in**:

- Interactive URL auth: browser flow completes, then the client's register poll
  gets `http 410: auth path not found`.
- Auth key: `invalid key: API key does not exist` — with the very same key
  working instantly from a 1.102 client (verified with a userspace-mode
  `tailscaled` instance on the build host).
- Spoofing `RegisterRequest.Version` (capability int 1 → 142) does **not**
  help — v1.22 has no ts2021 noise transport; the legacy plaintext register
  path is what the modern control plane won't serve.

On-the-box v1.22.2 build recipe (still useful for *other* Go programs on 10.9,
or for headscale):

```
CGO_ENABLED=1 CGO_LDFLAGS="-L/opt/local/lib -lMacportsLegacySupport" \
    /opt/local/bin/go-1.17 build -ldflags "-X tailscale.com/version.Long=… -X tailscale.com/version.Short=…"
```

(built binaries then need the legacy-support dylib present at runtime —
it is, via MacPorts).

## Deploy notes

- Daemon flags: `--state=/var/lib/tailscale/tailscaled.state
  --socket=/var/run/tailscaled.socket`; on darwin `--tun` defaults to utun,
  which works on 10.9.
- launchd plist carries `GODEBUG=x509usefallbackroots=1` — losing it revives
  blocker #4 on the first TLS connection.
- Verify end-to-end: `tailscale status`, `tailscale ip -4`, then ping the
  node's 100.x address from another tailnet device.
- Log: `/var/log/tailscaled.log`.

## Snow Leopard (10.6): blocker #0 — the CPU, not the OS

First failure on a real SL Mac is `Illegal instruction` (SIGILL), before any
dyld error: **Go ≥1.26's default amd64 baseline emits POPCNT/SSE4.2**, and
SL-era Macs carry Core 2 CPUs (POPCNT is Nehalem+). Confirmed by disassembly:
a default build contains ~340 POPCNT/CRC32 sites; `GOAMD64=v1` removes the
unconditional ones (the few dozen that remain live inside CPU-feature-
dispatched multi-version functions and never execute on a Core 2).

`MACOS_MIN=10.6 ./build.sh` sets `GOAMD64=v1` + `-mmacosx-version-min=10.6`
automatically.

Known 10.6 symbol gap (beyond the 10.9 set): `arc4random_buf` (10.7+) —
stubbed in `shim/stub.c` via the ancient `arc4random()`. Go's darwin netpoller
uses plain `kevent` (not 10.9-only `kevent64`), so no kqueue problem.

## Snow Leopard (10.6) outlook (remaining work)

Same architecture; expect a longer delta list (10.6 libSystem predates even
more: `arc4random_buf`?, `pthread_chdir`?, etc. — MacPorts legacy-support
covers a lot). The audit method above is the workflow: build hello → run →
read the dyld error → stub/shim → repeat, then cross-check with the nm delta.
The MacPorts `go-1.17` port also builds on 10.6, so the on-box fallback path
exists there too.
