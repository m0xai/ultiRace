# Progress

A new session must be able to continue from this file alone. Read `CLAUDE.md` and
`docs/GAME_PLAN.md` first, then this file, `docs/HUMAN_TODO.md` and `docs/TOOLCHAIN.md`.

## Current status (2026-11-19)

- Step 1 (docs) and Step 2 (toolchain preflight) done except the signed device install, which
  is waiting for Xcode to finish "Preparing Kerem's iPhone" (developer disk image) after
  Developer Mode was enabled. Simulator is impossible with official 4.7.2 templates (see
  TOOLCHAIN.md) → device-only testing.
- **M0–M7, M9 done** (2026-11-19). **M8** waiting for human visual approval. Next: **M10** Game Center (needs paid Apple Developer Program) / **M11** public play & deploy.

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

## M2 plan — Rooms & bots (Go)

Done when: protocol, rooms, state machine, bots, public/private visibility, room directory
API, matchmaker; Go bot clients Quick Play into rooms and finish races over WebSocket.

- [x] `internal/protocol`: all §3.7 messages, strict decoding, binary snapshots (18 B/car,
      per-client ack prefix), fixture `gamedata/fixtures/protocol/messages.json`.
- [x] `internal/bots`: racing line from curvature, avoidance, difficulty; 8 bots finish every map.
- [x] `internal/room`: `Core` state machine (public/private timers, first-lock-wins, bot fill,
      reverse grid, disconnect→bot + reconnect, AFK, kick ban, host migration, spectators),
      `Room` goroutine, `Manager`, `Directory` (cached/ETag, 80-row cap), `Matchmaker`.
- [x] `internal/moderation`: name filter + `blocked_words.txt`, `reports.jsonl`.
- [x] `internal/server`: `/ws`, `/api/rooms`, `/api/stats`, `/api/quickplay`, per-IP and
      per-player rate limits, XFF only from loopback, `-sim-lag/-sim-jitter`, `-time-scale`.
- [x] `internal/botclient` + `cmd/botclient`; `make e2e` (real binary): 6 Quick Play clients →
      1 room, 2 races each; Practice; 3 clients under 150 ms ± 40 ms lag (race completes).
- [x] Budgets: room tick ≈ 2 µs (≤ 0.2 ms); listing 1,000 rooms ≈ 1.3 ms, < 30 KB.

Not done in M2 (deliberately later): Quick Play rule 3 (spectate a running race that ends
within 30 s) → M11; Game Center auth → M10; AASA/`/r/{code}` links and `bans.json` → M11;
server capacity soak (≥ 300 rooms/vCPU) → M12; ULTs and effects → M6.

## M3 plan — Mirror (Godot)

Done when: `Track.gd` + `Physics.gd` pass all fixtures; 3 maps render from JSON with a free camera.

- [x] `godot/src/sim/`: `MathX.gd`, `Rng.gd` (mulberry32), `GameData.gd`, `Track.gd`, `Physics.gd`.
- [x] Conformance (gdUnit4): track samples incl. wrap, 6 physics scenarios with events, rng → all within 1e-4.
- [x] `godot/src/render/TrackBuilder.gd` (road, curbs, walls, skirts/pillars, ramps, start
      line/gate, ground, placeholder scenery, themed sky/sun/fog) + `MapViewer.tscn` free camera.
- [x] Screenshots `docs/screenshots/m3_{sunny,neon,frosty}_{overview,start}.png`, `m3_neon_bridge.png`.
      Budgets: ≤ 38 draw calls, ≤ 113k triangles per view (`DevTools --shot` prints PERF).

## M4 plan — Connect & watch

Done when: Godot client joins a room; all cars interpolated (no prediction); protocol fixtures pass.

- [x] `godot/src/net/Protocol.gd` (+ conformance vs `fixtures/protocol/messages.json`),
      `Connection.gd`, `Interpolation.gd` (+ unit tests: blend, s wrap, delay, jitter).
- [x] `godot/src/render/CarView.tscn` (one scene for all cars), `godot/src/app/Watch.tscn`.
- [x] `godot/src/testing/BotClient.tscn`; `make e2e` runs 4 headless Godot clients in one
      Quick Play room (all finish); e2e added to the CI Linux job.
- [x] On device: iPhone 15 Pro Max joined the Mac's LAN dev server, raced, ping 8 ms
      (`docs/screenshots/m4_device.png`).

Known issue: the "▼ name" tag of your car rendered far from the car on device → fix with the
M5 HUD name tags.

## M5 plan — Play

Done when: touch controls, HUD, lobby, vehicle select, countdown, results; full race vs bots on device.

- [x] Server: race position in snapshot flags bits 12–15 (ranking stays Go-only); fixtures regenerated.
- [x] `src/app/App.tscn` (main scene) state machine; `Profile.gd` (name, token, blocks, settings);
      screens in `src/app/screens/` (Ui kit with safe area, Home, Lobby, Select, Results, RaceHud);
      `src/input/TouchControls.gd` + `InputSetup.gd`; `src/render/RaceView.gd`.
- [x] Desktop screenshots `docs/screenshots/m5_{home,lobby,select,race}.png`; tests: touch
      multi-touch, CarView placement (20 Godot tests).
- [x] On device: auto-played practice race on the iPhone 15 Pro Max (`docs/screenshots/m5_device.png`:
      1/8, lap 2/3, minimap, controls inside the safe area).
- Dev args for the app (desktop `-- …` or device `DEV_ARGS=…`): `--auto quick|practice`,
  `--auto-nolock`, `--join quick|practice`, `--server <url>`, `--shot <png> --shot-delay <s>`.

Deferred from M5 on purpose: settings screen (M9 with haptics/audio), Browse Rooms + report/
block/kick UI (M11), countdown start boost + ULT logic (M6), prediction (M7: own car still
interpolated ~100 ms behind → steering feels laggy until M7).

## M6 — done (ULTs & balance)

All ULTs/effects/catch-up in Go, client visuals, balance tooling. Final balance over 6000 races:
7/8 targets pass; Bolt avg position 5.15 (≤ 5.1) is the one miss (see DECISIONS). Tuning
workflow: `build/balance -tune-pace N`, `-tune N -tune-all`, `-tune-trim N` (writes -tune-out),
check with `-races 2000 -seed {1,3,7}`, then copy to gamedata/balance.json and `make fixtures sync test balance`.

## M7 — done (prediction)

Server input FIFO + exact ack; `godot/src/net/Prediction.gd`; RaceView renders own car predicted;
e2e predicted driver under 150 ms ± 40 ms lag: avg correction 5.6 cm. Human feel check: HUMAN_TODO #11.

## M8 status — Art pass (waiting for human approval)

- [x] Scripted Blender cars (`art/blender/lib/carkit.py`, `art/blender/cars/*.py`, `make assets`),
      turntables `art/previews/`, CarView loads glb, wheel roll/steer.
- [x] VFX (`godot/src/render/Vfx.gd`), camera shake, cosmetic suspension, rim light, Neon brightened.
- [ ] Human approval of cars/visuals (HUMAN_TODO #12). Props as Blender glb (trees/pines/buildings)
      and baked lighting deferred (see DECISIONS).

## M9 — done (audio & haptics)

`art/audio/gen_audio.py` → `godot/assets/audio/*.wav` (+ CREDITS.md); `src/audio/AudioDirector.gd`
(autoload: buses + limiter, music per screen/map, SFX pool, ducking); `src/audio/EngineSound.gd`
(3 layers per class, own 2D + 4 nearest 3D); `src/platform/Haptics.gd`; Settings screen
(`src/app/screens/SettingsScreen.gd`: auto-accelerate, swap sides, button size, tilt + sensitivity,
haptics, reduce motion, volumes). Dev arg `--settings` opens it.

## Next steps

1. M10 — Game Center: blocked on the paid Apple Developer Program (Game Center capability,
   App Store Connect leaderboards/achievements) → HUMAN_TODO. Prepare without it: server-side
   `POST /api/auth/gamecenter` verification (check Apple's current
   `fetchItems(forIdentityVerificationSignature:)` docs first; tests with self-signed certs),
   `platform/GameServices.gd` interface with a guest fallback, plugin spike (GameCenterKit vs
   godot-ios-plugins).
2. M11 — public play & deploy: Room browser screen, report/block/kick UI, name filter in UI,
   Quick Play rule 3, AASA + `/r/{code}` landing page, `bans.json` + SIGHUP, `deploy/`
   (Dockerfile, compose.yaml, Caddyfile.snippet, DEPLOY.md with the exact commands for the human).

## Open questions

- Keep the iPhone 11 low tier (plan §1, §4.2, §8), or raise the minimum device now that the
  high tier is the priority? Until answered the plan stays as written; tuning happens on the
  15 Pro Max.
- Repo name in the plan is `ultirace-ios`; the actual repo is `ultiRace` (github.com/m0xai/ultiRace).

## Blocked

- Nothing blocked by the human right now (Developer Mode is on).
