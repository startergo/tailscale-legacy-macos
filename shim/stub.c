/*
 * stub.c — macOS symbols a modern Go runtime references that OS X 10.9 lacks.
 *
 * Resolved at static-link time via -force_load / plain object inclusion.
 * Each symbol below is a dormant code path on a headless CLI node; the stubs
 * only satisfy dyld. Audit with `nm -u <binary>` against the target's
 * exports (`nm -gU` over the sub-dylibs of /usr/lib/system) before adding more.
 */

/* notify_is_valid_token: 10.15+, used by os/signal drain (Go 1.20+).
 * Returns 0 = "token invalid",
 * so the runtime falls back to its non-notify path. Harmless. */
int notify_is_valid_token(int token) {
    (void)token;
    return 0;
}
