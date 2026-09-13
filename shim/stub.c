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

/* arc4random_buf: 10.7+ (missing on Snow Leopard). arc4random() itself is
 * ancient, so implement the buffered variant on top of it. Used by crypto/rand
 * seeding; correct everywhere, so unconditionally linking this stub is safe. */
#include <stdint.h>
extern uint32_t arc4random(void);
void arc4random_buf(void *buf, unsigned long n) {
    unsigned char *p = (unsigned char *)buf;
    while (n > 0) {
        uint32_t r = arc4random();
        unsigned long take = n < 4 ? n : 4;
        for (unsigned long i = 0; i < take; i++) { *p++ = (unsigned char)(r & 0xff); r >>= 8; }
        n -= take;
    }
}

/* xpc_date_create_from_current: 10.8+ (no public XPC on 10.6). Called by Go's
 * runtime osinit_hack (sys_darwin.go) purely as a workaround for an Apple
 * fork+exec libc bug — the return value is discarded, so NULL is fine. */
void *xpc_date_create_from_current(void) {
    return 0;
}

/* pthread_main_thread_np: not exported from 10.6 libSystem. Return the real
 * main thread's handle, cached by a constructor (constructors run on the
 * main thread before main). */
#include <pthread.h>
static pthread_t stub_main_thread;
__attribute__((constructor)) static void stub_cache_main_thread(void) {
    stub_main_thread = pthread_self();
}
pthread_t pthread_main_thread_np(void) {
    return stub_main_thread;
}

/* strnlen / dirfd: POSIX but absent from 10.6 libSystem (the $UNIX2003 era).
 * Implementations are trivial and correct on every version. */
#include <stddef.h>
#include <dirent.h>
#undef strnlen
#undef dirfd
size_t strnlen(const char *s, size_t maxlen) {
    const char *p = s;
    while (maxlen-- > 0 && *p) p++;
    return (size_t)(p - s);
}
int dirfd(DIR *dirp) {
    return dirp ? dirp->__dd_fd : -1;
}
