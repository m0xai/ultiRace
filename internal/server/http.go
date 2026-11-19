// Package server wires the HTTP endpoints (/healthz, /api/*, /ws) of the game server.
package server

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/m0xai/ultiRace/internal/moderation"
	"github.com/m0xai/ultiRace/internal/protocol"
	"github.com/m0xai/ultiRace/internal/room"
)

// Config holds runtime options parsed from flags/env in cmd/server.
type Config struct {
	Addr      string
	TestMode  bool          // -test: allows test-only features (time scale); refused in production
	TimeScale float64       // test mode only: rooms tick this many times faster (1–10)
	SimLag    time.Duration // artificial one-way latency for netcode testing
	SimJitter time.Duration
	Version   string
	IDSecret  string // keeps anonymous player IDs stable across restarts
	DataDir   string // reports.jsonl lives here ("" = discard)
	MaxRooms  int
}

// Server owns the HTTP mux and the room manager.
type Server struct {
	cfg     Config
	log     *slog.Logger
	started time.Time

	Rooms *room.Manager
	Dir   *room.Directory
	MM    *room.Matchmaker

	connLimit   *limiter // new WebSocket connections per IP
	createLimit *limiter // room creations / quick plays per IP
	apiLimit    *limiter // HTTP API calls per IP
	msgLimit    *limiter // WebSocket messages per player
}

// New returns a Server. Rooms stop when ctx is cancelled.
func New(ctx context.Context, cfg Config, log *slog.Logger) (*Server, error) {
	data, err := room.LoadData()
	if err != nil {
		return nil, err
	}
	if cfg.IDSecret == "" {
		var b [16]byte
		_, _ = rand.Read(b[:])
		cfg.IDSecret = hex.EncodeToString(b[:])
	}
	tick := time.Second / time.Duration(data.Bal.TickRate)
	scale := 1.0
	if cfg.TestMode && cfg.TimeScale > 1 {
		scale = min(cfg.TimeScale, 10)
		tick = time.Duration(float64(tick) / scale)
	}
	var reports *moderation.ReportLog
	if cfg.DataDir != "" {
		reports = moderation.NewReportLog(cfg.DataDir + "/reports.jsonl")
	}
	dir := room.NewDirectory(nil)
	mgr := room.NewManager(ctx, data, dir, reports, tick)
	if cfg.MaxRooms > 0 {
		mgr.MaxRooms = cfg.MaxRooms
	}
	return &Server{
		cfg: cfg, log: log, started: time.Now(),
		Rooms: mgr, Dir: dir, MM: room.NewMatchmaker(mgr),
		connLimit:   newLimiter(2, 20),
		createLimit: newLimiter(0.2, 5),
		apiLimit:    newLimiter(5, 30),
		msgLimit:    newLimiter(msgRatePerSec*scale, msgBurst*scale), // inputs speed up with the time scale
	}, nil
}

// Handler returns the root HTTP handler.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.handleHealthz)
	mux.HandleFunc("GET /api/rooms", s.handleRooms)
	mux.HandleFunc("GET /api/stats", s.handleStats)
	mux.HandleFunc("POST /api/quickplay", s.handleQuickPlay)
	mux.HandleFunc("GET /ws", s.handleWS)
	return mux
}

// playerID derives a stable anonymous id from a session token (GAME_PLAN §3.7).
func (s *Server) playerID(token string) string {
	h := sha256.Sum256([]byte(s.cfg.IDSecret + "|" + token))
	return "p" + hex.EncodeToString(h[:6])
}

func newToken() string {
	var b [18]byte
	_, _ = rand.Read(b[:])
	return hex.EncodeToString(b[:])
}

type healthz struct {
	OK       bool   `json:"ok"`
	Version  string `json:"version"`
	UptimeS  int64  `json:"uptimeS"`
	TestMode bool   `json:"testMode"`
	Rooms    int    `json:"rooms"`
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func (s *Server) handleHealthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, healthz{OK: true, Version: s.cfg.Version, UptimeS: int64(time.Since(s.started).Seconds()),
		TestMode: s.cfg.TestMode, Rooms: s.Rooms.Count()})
}

func (s *Server) limited(w http.ResponseWriter, r *http.Request, l *limiter) bool {
	if l.Allow(clientIP(r)) {
		return false
	}
	writeJSON(w, http.StatusTooManyRequests, protocol.Err{T: protocol.TErr, Code: protocol.ErrRateLimited, Msg: "slow down"})
	return true
}

// GET /api/rooms?map=&laps= — cached listing with ETag.
func (s *Server) handleRooms(w http.ResponseWriter, r *http.Request) {
	if s.limited(w, r, s.apiLimit) {
		return
	}
	laps, _ := strconv.Atoi(r.URL.Query().Get("laps"))
	body, etag := s.Dir.ListJSON(r.URL.Query().Get("map"), laps)
	w.Header().Set("ETag", etag)
	w.Header().Set("Cache-Control", "no-cache")
	if r.Header.Get("If-None-Match") == etag {
		w.WriteHeader(http.StatusNotModified)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write(body)
}

// GET /api/stats — Home screen counter.
func (s *Server) handleStats(w http.ResponseWriter, r *http.Request) {
	if s.limited(w, r, s.apiLimit) {
		return
	}
	writeJSON(w, http.StatusOK, s.Dir.Stats())
}

type quickPlayReq struct {
	Blocked []string `json:"blocked"`
}

type quickPlayResp struct {
	Room string `json:"room"`
}

// POST /api/quickplay — pick a room (seat reserved for a few seconds), then join via /ws.
func (s *Server) handleQuickPlay(w http.ResponseWriter, r *http.Request) {
	if s.limited(w, r, s.createLimit) {
		return
	}
	var req quickPlayReq
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&req); err != nil && err.Error() != "EOF" {
		writeJSON(w, http.StatusBadRequest, protocol.Err{T: protocol.TErr, Code: protocol.ErrBadMessage, Msg: "bad body"})
		return
	}
	code, err := s.MM.Pick(req.Blocked, nil)
	if err != nil {
		writeJSON(w, http.StatusServiceUnavailable, protocol.Err{T: protocol.TErr, Code: protocol.ErrServer, Msg: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, quickPlayResp{Room: code})
}
