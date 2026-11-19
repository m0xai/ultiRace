// Command server is the authoritative UltiRace game server.
package main

import (
	"context"
	"errors"
	"flag"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/m0xai/ultiRace/internal/server"
)

// version is set at build time: -ldflags "-X main.version=..."
var version = "dev"

func main() {
	addr := flag.String("addr", envOr("ADDR", "127.0.0.1:"+envOr("PORT", "8090")), "listen address")
	test := flag.Bool("test", false, "enable test-only features (timeScale); never in production")
	simLag := flag.Duration("sim-lag", 0, "artificial one-way latency, e.g. 120ms (dev only)")
	simJitter := flag.Duration("sim-jitter", 0, "artificial latency jitter, e.g. 40ms (dev only)")
	logLevel := flag.String("log-level", envOr("LOG_LEVEL", "info"), "debug|info|warn|error")
	timeScale := flag.Float64("time-scale", 1, "test mode only: run rooms up to 10× faster")
	dataDir := flag.String("data", envOr("DATA_DIR", ""), "directory for reports.jsonl (empty = discard)")
	maxRooms := flag.Int("max-rooms", 2000, "maximum concurrent rooms")
	flag.Parse()

	var lvl slog.Level
	if err := lvl.UnmarshalText([]byte(*logLevel)); err != nil {
		lvl = slog.LevelInfo
	}
	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: lvl}))

	if *timeScale != 1 && !*test {
		log.Error("-time-scale needs -test")
		os.Exit(2)
	}
	cfg := server.Config{Addr: *addr, TestMode: *test, TimeScale: *timeScale, SimLag: *simLag, SimJitter: *simJitter,
		Version: version, IDSecret: os.Getenv("ID_SECRET"), DataDir: *dataDir, MaxRooms: *maxRooms}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	roomsCtx, stopRooms := context.WithCancel(context.Background())
	defer stopRooms()

	srv, err := server.New(roomsCtx, cfg, log)
	if err != nil {
		log.Error("init", "err", err)
		os.Exit(1)
	}
	httpSrv := &http.Server{
		Addr:              cfg.Addr,
		Handler:           srv.Handler(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	errc := make(chan error, 1)
	go func() {
		log.Info("listening", "addr", cfg.Addr, "version", version, "test", cfg.TestMode)
		errc <- httpSrv.ListenAndServe()
	}()

	select {
	case err := <-errc:
		if !errors.Is(err, http.ErrServerClosed) {
			log.Error("server failed", "err", err)
			os.Exit(1)
		}
	case <-ctx.Done():
		log.Info("shutting down")
		shutCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := httpSrv.Shutdown(shutCtx); err != nil {
			log.Error("shutdown", "err", err)
		}
		stopRooms()
		srv.Rooms.Wait()
	}
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
