// Package server wires the HTTP endpoints (/healthz, /api/*, /ws, links) of the game server.
package server

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"time"
)

// Config holds runtime options parsed from flags/env in cmd/server.
type Config struct {
	Addr      string
	TestMode  bool          // -test: allows test-only features (timeScale); refused in production
	SimLag    time.Duration // artificial one-way latency for netcode testing
	SimJitter time.Duration
	Version   string
}

// Server owns the HTTP mux. Rooms, directory and matchmaker are added in M2.
type Server struct {
	cfg     Config
	log     *slog.Logger
	started time.Time
}

// New returns a Server with its dependencies.
func New(cfg Config, log *slog.Logger) *Server {
	return &Server{cfg: cfg, log: log, started: time.Now()}
}

// Handler returns the root HTTP handler.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.handleHealthz)
	return mux
}

type healthz struct {
	OK       bool   `json:"ok"`
	Version  string `json:"version"`
	UptimeS  int64  `json:"uptimeS"`
	TestMode bool   `json:"testMode"`
}

func (s *Server) handleHealthz(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	_ = json.NewEncoder(w).Encode(healthz{
		OK:       true,
		Version:  s.cfg.Version,
		UptimeS:  int64(time.Since(s.started).Seconds()),
		TestMode: s.cfg.TestMode,
	})
}
