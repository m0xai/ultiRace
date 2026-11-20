# Progress

A new session must be able to continue from this file alone. Read `CLAUDE.md` and
`docs/GAME_PLAN.md` first, then this file, `docs/HUMAN_TODO.md` and `docs/TOOLCHAIN.md`.

## Current status (2026-11-19)

- Step 1 (docs) and Step 2 (toolchain preflight) done except the signed device install, which
  is waiting for Xcode to finish "Preparing Kerem's iPhone" (developer disk image) after
  Developer Mode was enabled. Simulator is impossible with official 4.7.2 templates (see
  TOOLCHAIN.md) → device-only testing.
- **M0–M7, M9 done** (2026-11-19). **M8** waiting for human visual approval. M10 server side done (client blocked on paid program); M11 done in code (deploy blocked on human). Next: **M12** performance.

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

## A1 — Vehicle art v2 (in progress, 2026-11-20)

- [x] Wheel tumbling fixed (CarView rebuilds wheels from rest basis + axle spin + steer; test).
- [x] `art/blender/lib/carkit2.py`: lofted subdivided bodies, glass canopies, boolean wheel arches,
      lathed tyres + spoked rims, embedded lamps, tubes, glow; PBR materials (Paint clear-coat,
      Accent, Trim, Chrome, Glass, Rubber, Light, TailLight). `art/blender/cars2/*.py` (8 cars),
      `make assets` builds them (CARS_DIR=cars builds the old M8 placeholders). Turntables in
      `art/previews/`, in-game `docs/screenshots/a1_grid.png`.
- [x] CarView keeps imported PBR materials; per-car Paint copy for effects.
- [x] Draw calls: carkit2 `consolidate()` bakes non-paint/glass materials into vertex colours →
      Detail + Lamp (bodies ≤ 4 surfaces, wheels 1); CarView shares those two materials across
      cars. Race view 168 → 109 draw calls.
- [x] Particles: soft radial sprite for flames, wind lines and sparks.
- [x] Flicker fixed: predicted car sub-tick blending, canopy/body z-fighting removed (canopies sunk
      0.22 m), shadow bias raised. Diagnosed with `DevTools --burst N` (consecutive frames in memory).
- [x] Collisions: car-sized boxes + impact response (server); remote cars displayed at the predicted
      time (dead reckoning + smoothing) so contacts look solid. Tests for rear-end and side contact.
- [x] Quality pass 1 toward the references (Traffic Racer trailers): window frames + black
      B-pillar, dished alloys with radial spokes, dark brake discs and centre caps, chrome headlamp
      bezels, taillight surrounds, number plates, mirrors on stalks, door seams + handles.
- [x] Quality pass 2: 12 % smaller wheels on all cars (more realistic proportions).
- [x] A3 road pass toward the references: noise-textured asphalt, white edge lines + dashed lane
      dividers, steel guard rails on posts (Sunny/Frosty; Neon keeps glowing barriers). Draw calls
      108–111 (markings/posts cast no shadows). Screens: `docs/screenshots/a3_*.png`.
- [x] A3 scenery pass: conifers get trunks, street lamps every 36 m alternating sides (one
      MultiMesh, no shadows; tinted glow on Neon). Race draw calls: Sunny 128, Neon 153 (high ≤ 250).
- [x] Clouds on Sunny/Frosty (one unshaded MultiMesh). Low-tier check: 77–108 draw calls on all
      maps (no sun shadows on low), high 115–162 (≤ 250).
- [x] Roadside billboards on Sunny/Frosty (one vertex-coloured mesh, no shadows). High-tier draw
      calls 134–151.
- [x] Detail pass 3 (human: "more details to look realistic", "sometimes flickering"): surface-
      projected headlights (dark housing, chrome reflector, projector, DRL brow), tail-light
      clusters with light bar + reverse lamp, grille slats + badge, intake mesh, fog lamps,
      plates on mounts, diffuser fins, reflectors, hood/trunk shut lines, door gaps, skirts,
      handles, indicator repeaters, wipers, slim wing mirrors, arch liners, red calipers, wheel
      nuts, tread grooves; rounded loft ends; subdivided cabs/canopies now really exported (join
      dropped their subsurf). Chrome/rubber/plastic keep their own shine (`car_detail.gdshader`).
      10–14 k tris per car; race high 252 k tris / 148 draws, low 138 k / 99 draws.
      Flicker: no auto-LOD popping on cars, wheel-spin cap (spoke strobing), tighter first
      shadow split (wing shadow crawl). `res://src/testing/CarLineup.tscn` renders all cars in
      engine (`--car <id> --angle <deg>`).
- [ ] A3 open: Neon billboards on building faces (overpass has no ground beside it); human
      review of the A3 look (`docs/screenshots/a3_*.png`).
- [ ] Polish: boolean seam shading on Rhino/Hook rear, Phantom fins, trim ~6–6.8k tris → ≤ 6k.
- [ ] Human approval of the 8 cars (HUMAN_TODO #12, updated).

Then A2 — Game UI & feel (research → docs/UI_STYLE.md: display font, colour/shape language,
animated buttons and transitions, 3D car showroom on Home/Select, juicy countdown/results).

## Next steps

1. M10 — Game Center: **server side done** (`internal/server/auth_gamecenter.go`,
   `POST /api/auth/gamecenter`, env `APPLE_BUNDLE_ID`, tests). Client side BLOCKED on the paid
   Apple Developer Program (HUMAN_TODO #15/#16): GameServices.gd + plugin spike (GameCenterKit vs
   godot-ios-plugins vs migueldeicaza/GodotApplePlugins), leaderboards, achievements.
2. M11 — public play & deploy: DONE in code (room browser `RoomBrowserScreen.gd`, report/block/
   kick in lobby + results, share = copy link, AASA + `/r/{code}`, `bans.json` + SIGHUP, `deploy/`,
   `docs/DEPLOY.md`, CI docker job). BLOCKED on the human: deploy to flappus (HUMAN_TODO #17),
   Associated Domains + Team ID (paid program #15). After deploy: switch nothing (prod URL is
   already the default in release builds), run `make e2e`-style public play test against
   `wss://ultirace.flappus.com` with `cmd/botclient -url wss://ultirace.flappus.com`.
3. M12 — IN PROGRESS. Done: `-pprof` flag; test mode lifts per-IP limits; soak 100 practice
   rooms on the Mac = ~50 % of one core, 30 MB flat (profile: game logic ≈ 3 %, rest macOS
   kevent/syscalls with clients on the same machine → re-measure on Linux/flappus); `Quality.gd`
   autoload (tiers by model, adaptive render scale, 120 Hz on ProMotion, plist
   CADisableMinimumFrameDurationOnPhone); `DebugOverlay.gd` (F3 / two-finger triple tap, `--overlay`).
   OPEN ISSUES: (a) on the Mac the adaptive scaler dropped render scale to 0.70 because the target
   was 120 fps but vsync caps frames at 60 → only treat frame time as "slow" when FPS < target
   and frame time > display interval; (b) draw calls rose to 154 / 321 objects in race (budget 150
   low / 250 high) — check per-car GPUParticles trails (8 emitters) and hazard meshes, pool them.
   Remaining M12 work: debug overlay (FPS, frame ms, draw calls, tris, tier, ping, kbps),
   `Quality.gd` tiers (iPhone 11 low / 15 Pro Max high, adaptive render scale), server capacity
   soak with `cmd/botclient -practice -clients N`, memory flat over 5 races, Bolt balance follow-up.

## Open questions

- Keep the iPhone 11 low tier (plan §1, §4.2, §8), or raise the minimum device now that the
  high tier is the priority? Until answered the plan stays as written; tuning happens on the
  15 Pro Max.
- Repo name in the plan is `ultirace-ios`; the actual repo is `ultiRace` (github.com/m0xai/ultiRace).

## Blocked

- Nothing blocked by the human right now (Developer Mode is on).

## A2 — Game UI & feel (started 2026-11-20)

- [x] Style guide `docs/UI_STYLE.md` (references + rules); Lilita One display font (OFL) as default.
- [x] `Ui.gd`: chunky lip buttons (yellow primary / blue secondary), outlined text, bordered
      panels and inputs, gradient + speed-stripe backgrounds on all screens, squash-on-press and
      pop-in animations. Screens: `docs/screenshots/a2_*.png`.
- [x] Settings: chunky code-drawn switches, yellow sliders, rows on cards, styled dropdown.
- [x] Vehicle Select: 3D showroom (real car model spinning on a platform, drop-in bounce on pick;
      renders only while visible), 2-column car cards, name/ULT/stats under the model.
- [x] Home showroom (cycles through the cars), countdown punch-in (3 red → 2 orange → 1 yellow →
      GO! green), results: podium medal colours, staggered rows, "YOU WON!"/"P2 — PODIUM!" title,
      confetti on podium finishes (tested).
- [ ] Human approval of A2 (HUMAN_TODO #19), juicy countdown/results, human approval.
