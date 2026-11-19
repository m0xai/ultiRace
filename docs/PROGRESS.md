# Progress

A new session must be able to continue from this file alone. Read `CLAUDE.md` and
`docs/GAME_PLAN.md` first, then this file, `docs/HUMAN_TODO.md` and `docs/TOOLCHAIN.md`.

## Current status (2026-11-19)

- Step 1 (docs) and Step 2 (toolchain preflight) done except the signed device install, which
  is waiting for Xcode to finish "Preparing Kerem's iPhone" (developer disk image) after
  Developer Mode was enabled. Simulator is impossible with official 4.7.2 templates (see
  TOOLCHAIN.md) → device-only testing.
- **M0 done**, **M1 done** (2026-11-19). Next: **M2**.

## M0 plan — Setup

Done when: repo, Go module, Godot project pinned, Makefile, CI green; empty Godot scene runs
on a real iPhone via Xcode.

- [x] Go module `github.com/m0xai/ultiRace` (go 1.24), `cmd/server` with `/healthz`, flags
      (`-test`, `-sim-lag`, `-sim-jitter`), graceful shutdown; `internal/server` test.
- [x] `godot/` project: `VERSION` 4.7.2.stable, Mobile renderer, landscape, untyped
      declarations = error, `Boot.tscn`, `DevTools` autoload (`-- --shot <png>`),
      gdUnit4 6.2.3, iOS preset (team R984A9U2G4, `com.flappus.ultirace`, iOS 17.0),
      placeholder icon.
- [x] Makefile (`make help`), `scripts/ios.sh`, `.github/workflows/ci.yml` (Linux: lint, Go
      race tests, fixtures/sync checks, Godot tests; macOS: iOS export + unsigned compile).
- [x] Local: `make test`, `make lint`, `make check-sync`, `make ios-check`, `make screenshot`
      (docs/screenshots/boot.png, looks right).
- [x] CI green on GitHub (run 44512690544) (repo is public: check via
      `curl -s https://api.github.com/repos/m0xai/ultiRace/actions/runs?per_page=1`).
- [x] `make ios-run` installs + launches on the iPhone 15 Pro Max (human confirmed it opens).

## M1 plan — Sim core (Go)

Done when: track building + car physics + laps/ranking, determinism test, fixtures written.

- [x] `gamedata/`: `balance.json`, `vehicles.json` (8 cars, stats sum 12), `maps/{sunny,neon,frosty}.json`
      (from `scripts/genmaps.py`), `embed.go` loader (unknown JSON fields = error).
- [x] `internal/mathx`: Vec3, wrap helpers, mulberry32 (checked against the JS reference), Catmull-Rom + derivatives.
- [x] `internal/track`: arc-length table, frames, signed curvature, width/bank, `World(s,d,y)`;
      tests: plan bounds, Frenet identity, orthonormal frames, seam continuity, Neon bridge ≥ 8 m.
      `ULTIRACE_PREVIEW_DIR=… go test ./internal/track -run Previews` renders top-down PNGs.
- [x] `internal/sim`: `StepCar` (mirrored), `World` (grid, collisions, laps, finish window, ranking, hash).
      Tests: accel time, coasting, mods cap, walls, ramps, curvature drift, every vehicle finishes
      every map (lap 34–37 s), collisions, laps can't be farmed, ranking, finish window,
      determinism across goroutines. Benchmark: 8-car tick ≈ 2.4 µs (budget 0.2 ms).
- [x] Fixtures: `gamedata/fixtures/track_*.json` (200 samples + wrap cases), `physics_*.json`
      (6 scenarios × 300 ticks); `TestFixtures` fails when stale; synced to `godot/gamedata`.

## Next steps

1. M2: protocol (`internal/protocol`), rooms (goroutine per room, state machine, fake clock),
   bots (`internal/bots`: racing line from curvature, avoidance), directory + `/api/rooms`,
   matchmaker (`/api/quickplay`), moderation (names), WebSocket (`/ws`), `cmd/botclient`
   Quick Play e2e.

## Open questions

- Keep the iPhone 11 low tier (plan §1, §4.2, §8), or raise the minimum device now that the
  high tier is the priority? Until answered the plan stays as written; tuning happens on the
  15 Pro Max.
- Repo name in the plan is `ultirace-ios`; the actual repo is `ultiRace` (github.com/m0xai/ultiRace).

## Blocked

- Nothing blocked by the human right now (Developer Mode is on).
