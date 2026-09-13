//go:build darwin_10_9

// Embedded fallback CA bundle for the 10.9 build: the system verifier path
// (SecTrustEvaluateWithError) requires macOS 10.14+, so we register the
// Mozilla bundle and run with GODEBUG=x509usefallbackroots=1 to verify TLS
// in pure Go instead.
package main

import (
	"crypto/x509"
	_ "embed"
)

//go:embed fallback-roots.pem
var fallbackPEM []byte

func init() {
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(fallbackPEM) {
		panic("darwin_10_9: fallback-roots.pem contains no certificates")
	}
	x509.SetFallbackRoots(pool)
}
