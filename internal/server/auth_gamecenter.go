package server

import (
	"context"
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/m0xai/ultiRace/internal/protocol"
)

// Game Center identity verification (GAME_PLAN §3.4, Apple: GKLocalPlayer
// fetchItems(forIdentityVerificationSignature:)). Checked 2026-11-19 against Apple's docs:
// payload = teamPlayerID (UTF-8) ‖ bundleID (UTF-8) ‖ timestamp (big-endian UInt64) ‖ salt,
// verified with RSASSA-PKCS1-v1_5 (SHA-256) using the certificate at publicKeyURL, which must
// be signed by a trusted authority for Apple.

// GCRequest is the body of POST /api/auth/gamecenter.
type GCRequest struct {
	PublicKeyURL string `json:"publicKeyURL"`
	Signature    string `json:"signature"` // base64
	Salt         string `json:"salt"`      // base64
	Timestamp    uint64 `json:"timestamp"` // ms since epoch
	TeamPlayerID string `json:"teamPlayerID"`
	BundleID     string `json:"bundleID"`
}

// GCVerifier checks Game Center identity signatures.
type GCVerifier struct {
	BundleID string
	MaxAge   time.Duration
	Roots    *x509.CertPool // nil = system roots
	HTTP     *http.Client
	Now      func() time.Time
	// HostOK limits where certificates may be downloaded from (default: *.apple.com over https).
	HostOK func(u *url.URL) bool

	mu    sync.Mutex
	cache map[string]cachedCert
}

type cachedCert struct {
	cert    *x509.Certificate
	expires time.Time
}

var (
	ErrGCHost      = errors.New("gamecenter: public key URL is not an Apple host")
	ErrGCExpired   = errors.New("gamecenter: timestamp too old or in the future")
	ErrGCBundle    = errors.New("gamecenter: wrong bundle id")
	ErrGCCert      = errors.New("gamecenter: certificate not trusted")
	ErrGCSignature = errors.New("gamecenter: signature does not match")
)

func appleHost(u *url.URL) bool {
	h := strings.ToLower(u.Hostname())
	return u.Scheme == "https" && (h == "apple.com" || strings.HasSuffix(h, ".apple.com"))
}

func (v *GCVerifier) now() time.Time {
	if v.Now != nil {
		return v.Now()
	}
	return time.Now()
}

// Verify returns nil if the request proves the player's identity.
func (v *GCVerifier) Verify(ctx context.Context, r GCRequest) error {
	if r.BundleID != v.BundleID || v.BundleID == "" {
		return ErrGCBundle
	}
	u, err := url.Parse(r.PublicKeyURL)
	hostOK := v.HostOK
	if hostOK == nil {
		hostOK = appleHost
	}
	if err != nil || !hostOK(u) {
		return ErrGCHost
	}
	maxAge := v.MaxAge
	if maxAge == 0 {
		maxAge = 5 * time.Minute
	}
	ts := time.UnixMilli(int64(r.Timestamp))
	if now := v.now(); now.Sub(ts) > maxAge || ts.Sub(now) > time.Minute {
		return ErrGCExpired
	}
	sig, err1 := base64.StdEncoding.DecodeString(r.Signature)
	salt, err2 := base64.StdEncoding.DecodeString(r.Salt)
	if err1 != nil || err2 != nil || r.TeamPlayerID == "" {
		return ErrGCSignature
	}
	cert, err := v.certificate(ctx, r.PublicKeyURL)
	if err != nil {
		return err
	}
	pub, ok := cert.PublicKey.(*rsa.PublicKey)
	if !ok {
		return ErrGCCert
	}
	var buf []byte
	buf = append(buf, r.TeamPlayerID...)
	buf = append(buf, r.BundleID...)
	buf = binary.BigEndian.AppendUint64(buf, r.Timestamp)
	buf = append(buf, salt...)
	sum := sha256.Sum256(buf)
	if rsa.VerifyPKCS1v15(pub, crypto.SHA256, sum[:], sig) != nil {
		return ErrGCSignature
	}
	return nil
}

func (v *GCVerifier) fetch(ctx context.Context, raw string) ([]byte, http.Header, error) {
	client := v.HTTP
	if client == nil {
		client = &http.Client{Timeout: 5 * time.Second}
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, raw, nil)
	if err != nil {
		return nil, nil, err
	}
	res, err := client.Do(req)
	if err != nil {
		return nil, nil, err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return nil, nil, fmt.Errorf("gamecenter: GET %s: %s", raw, res.Status)
	}
	b, err := io.ReadAll(io.LimitReader(res.Body, 64<<10))
	return b, res.Header, err
}

// certificate downloads (and caches) the signing certificate and verifies its chain, fetching
// intermediates from the certificate's AIA URLs.
func (v *GCVerifier) certificate(ctx context.Context, raw string) (*x509.Certificate, error) {
	v.mu.Lock()
	if v.cache == nil {
		v.cache = map[string]cachedCert{}
	}
	if c, ok := v.cache[raw]; ok && v.now().Before(c.expires) {
		v.mu.Unlock()
		return c.cert, nil
	}
	v.mu.Unlock()
	der, hdr, err := v.fetch(ctx, raw)
	if err != nil {
		return nil, err
	}
	cert, err := x509.ParseCertificate(der)
	if err != nil {
		return nil, ErrGCCert
	}
	inter := x509.NewCertPool()
	for _, aia := range cert.IssuingCertificateURL {
		if b, _, err := v.fetch(ctx, aia); err == nil {
			if ic, err := x509.ParseCertificate(b); err == nil {
				inter.AddCert(ic)
			}
		}
	}
	opts := x509.VerifyOptions{Roots: v.Roots, Intermediates: inter, CurrentTime: v.now(), KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageAny}}
	if _, err := cert.Verify(opts); err != nil {
		return nil, ErrGCCert
	}
	if !slices.Contains(cert.Subject.Organization, "Apple Inc.") {
		return nil, ErrGCCert
	}
	ttl := time.Hour
	if d, err := time.ParseDuration(maxAgeOf(hdr.Get("Cache-Control")) + "s"); err == nil && d > 0 {
		ttl = d
	}
	v.mu.Lock()
	v.cache[raw] = cachedCert{cert: cert, expires: v.now().Add(ttl)}
	v.mu.Unlock()
	return cert, nil
}

func maxAgeOf(cc string) string {
	for _, part := range strings.Split(cc, ",") {
		part = strings.TrimSpace(part)
		if strings.HasPrefix(part, "max-age=") {
			return strings.TrimPrefix(part, "max-age=")
		}
	}
	return ""
}

// ---------- sessions ----------

// sessions maps session tokens to verified identities ("gc:<teamPlayerID>"). Guests keep
// their client-generated token as identity.
type sessions struct {
	mu sync.Mutex
	m  map[string]string
}

func (s *sessions) put(token, identity string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.m == nil {
		s.m = map[string]string{}
	}
	s.m[token] = identity
}

func (s *sessions) identity(token string) (string, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	id, ok := s.m[token]
	return id, ok
}

type gcResp struct {
	Token string `json:"token"`
}

// POST /api/auth/gamecenter — verify the signature, return a session token whose player id is
// derived from the Game Center teamPlayerID (stable across devices, never exposed).
func (s *Server) handleGameCenterAuth(w http.ResponseWriter, r *http.Request) {
	if s.limited(w, r, s.apiLimit) {
		return
	}
	if s.gc == nil {
		writeJSON(w, http.StatusServiceUnavailable, protocol.Err{T: protocol.TErr, Code: protocol.ErrServer, Msg: "game center not configured"})
		return
	}
	var req GCRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<10)).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, protocol.Err{T: protocol.TErr, Code: protocol.ErrBadMessage, Msg: "bad body"})
		return
	}
	if err := s.gc.Verify(r.Context(), req); err != nil {
		s.log.Info("gamecenter auth rejected", "err", err)
		writeJSON(w, http.StatusUnauthorized, protocol.Err{T: protocol.TErr, Code: "auth", Msg: "verification failed"})
		return
	}
	token := newToken()
	s.sessions.put(token, "gc:"+req.TeamPlayerID)
	writeJSON(w, http.StatusOK, gcResp{Token: token})
}
