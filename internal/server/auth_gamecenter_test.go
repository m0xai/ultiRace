package server

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"math/big"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
	"time"
)

type gcFixture struct {
	key   *rsa.PrivateKey
	roots *x509.CertPool
	srv   *httptest.Server
	now   time.Time
}

// newGCFixture: a test CA ("Apple Root") signing a leaf for "Apple Inc.", served over HTTP.
func newGCFixture(t *testing.T, org string) *gcFixture {
	t.Helper()
	caKey, _ := rsa.GenerateKey(rand.Reader, 2048)
	now := time.Unix(1_800_000_000, 0)
	caTmpl := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "Test Apple Root"},
		NotBefore: now.Add(-time.Hour), NotAfter: now.Add(24 * time.Hour), IsCA: true, BasicConstraintsValid: true,
		KeyUsage: x509.KeyUsageCertSign}
	caDER, _ := x509.CreateCertificate(rand.Reader, caTmpl, caTmpl, &caKey.PublicKey, caKey)
	ca, _ := x509.ParseCertificate(caDER)
	leafKey, _ := rsa.GenerateKey(rand.Reader, 2048)
	leafTmpl := &x509.Certificate{SerialNumber: big.NewInt(2), Subject: pkix.Name{CommonName: "gc-prod", Organization: []string{org}},
		NotBefore: now.Add(-time.Hour), NotAfter: now.Add(24 * time.Hour), KeyUsage: x509.KeyUsageDigitalSignature}
	leafDER, _ := x509.CreateCertificate(rand.Reader, leafTmpl, ca, &leafKey.PublicKey, caKey)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "max-age=600")
		_, _ = w.Write(leafDER)
	}))
	t.Cleanup(srv.Close)
	roots := x509.NewCertPool()
	roots.AddCert(ca)
	return &gcFixture{key: leafKey, roots: roots, srv: srv, now: now}
}

func (f *gcFixture) verifier(bundle string) *GCVerifier {
	return &GCVerifier{BundleID: bundle, Roots: f.roots, Now: func() time.Time { return f.now },
		HostOK: func(u *url.URL) bool { return u.Host == f.srv.Listener.Addr().String() }}
}

func (f *gcFixture) request(player, bundle string, ts time.Time) GCRequest {
	salt := []byte("0123456789abcdef")
	var buf []byte
	buf = append(buf, player...)
	buf = append(buf, bundle...)
	buf = binary.BigEndian.AppendUint64(buf, uint64(ts.UnixMilli()))
	buf = append(buf, salt...)
	sum := sha256.Sum256(buf)
	sig, _ := rsa.SignPKCS1v15(rand.Reader, f.key, crypto.SHA256, sum[:])
	return GCRequest{PublicKeyURL: f.srv.URL + "/public/gc-prod-10.cer", Signature: base64.StdEncoding.EncodeToString(sig),
		Salt: base64.StdEncoding.EncodeToString(salt), Timestamp: uint64(ts.UnixMilli()), TeamPlayerID: player, BundleID: bundle}
}

func TestGameCenterVerification(t *testing.T) {
	f := newGCFixture(t, "Apple Inc.")
	v := f.verifier("com.flappus.ultirace")
	ctx := context.Background()
	ok := f.request("T:_abc123", "com.flappus.ultirace", f.now.Add(-30*time.Second))
	if err := v.Verify(ctx, ok); err != nil {
		t.Fatalf("valid signature rejected: %v", err)
	}
	cases := []struct {
		name string
		req  GCRequest
		want error
	}{
		{"wrong bundle", f.request("T:_abc123", "com.evil.app", f.now), ErrGCBundle},
		{"expired", f.request("T:_abc123", "com.flappus.ultirace", f.now.Add(-6*time.Minute)), ErrGCExpired},
		{"future", f.request("T:_abc123", "com.flappus.ultirace", f.now.Add(5*time.Minute)), ErrGCExpired},
	}
	tampered := ok
	tampered.TeamPlayerID = "T:_someoneElse"
	cases = append(cases, struct {
		name string
		req  GCRequest
		want error
	}{"tampered player", tampered, ErrGCSignature})
	foreign := ok
	foreign.PublicKeyURL = "https://evil.example.com/gc.cer"
	cases = append(cases, struct {
		name string
		req  GCRequest
		want error
	}{"foreign key host", foreign, ErrGCHost})
	for _, c := range cases {
		if err := v.Verify(ctx, c.req); !errors.Is(err, c.want) {
			t.Errorf("%s: got %v, want %v", c.name, err, c.want)
		}
	}
}

func TestGameCenterRejectsNonAppleCertAndDefaultHosts(t *testing.T) {
	f := newGCFixture(t, "Not Apple Ltd")
	v := f.verifier("com.flappus.ultirace")
	if err := v.Verify(context.Background(), f.request("T:_x", "com.flappus.ultirace", f.now)); !errors.Is(err, ErrGCCert) {
		t.Fatalf("non-Apple organisation accepted: %v", err)
	}
	for raw, want := range map[string]bool{
		"https://static.gc.apple.com/public-key/gc-prod-10.cer": true,
		"http://static.gc.apple.com/x.cer":                      false,
		"https://apple.com.evil.net/x.cer":                      false,
		"https://evilapple.com/x.cer":                           false,
	} {
		u, _ := url.Parse(raw)
		if appleHost(u) != want {
			t.Errorf("appleHost(%s) = %v", raw, !want)
		}
	}
}
