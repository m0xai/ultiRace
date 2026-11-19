# CLAUDE.md — UltiRace (iOS game: Go server + Godot client)

Read `docs/GAME_PLAN.md` before starting any task. It is the source of truth. If a decision
changes, update the plan and add an entry to `docs/DECISIONS.md` (date, decision, reason,
alternatives considered).

## Golden rules

1. **The Go server is authoritative.** Collisions, ULTs, effects, laps, ranking and bots exist
   only in Go. The Godot client only mirrors **track building and own-car physics** for
   prediction. Never add game rules to the client.
2. **One data source.** All tunable numbers live in `gamedata/*.json`. Never hard-code balance
   values in Go or GDScript.
3. **Fixtures keep the mirror honest.** After any change to track, physics or protocol code:
   `make fixtures` (Go regenerates) → `make sync` (copies into `godot/gamedata/`) → run Godot
   tests. Values must match within `1e-4`.
4. **Protocol changes** start in `internal/protocol`; bump the version if not backwards
   compatible, then update `godot/src/net/Protocol.gd` and regenerate fixtures.
5. **Performance budgets are requirements** (`GAME_PLAN.md` §8). Check draw calls, triangles
   and frame time whenever you add visuals.
6. **Typed GDScript only.** Declare types everywhere; no untyped declarations.
7. **Ask the human** for anything that needs their Apple ID, payment, App Store Connect,
   signing, DNS, server SSH, or a judgement on how something looks or feels. Don't guess on
   visuals: render previews/screenshots and ask.

## Repo map

- `cmd/server`, `cmd/balance`, `cmd/botclient`, `internal/*`: Go server, balance sim, load tool
- `gamedata/`: balance, vehicles, maps, Go-generated fixtures (source of truth)
- `godot/`: Godot 4.7.x iOS client (`src/`, `test/`, `assets/`, `tracks/`, synced `gamedata/`)
- `art/blender/`: Blender Python scripts that generate all 3D assets → `godot/assets/*.glb`
- `deploy/`: Dockerfile, compose file, Caddy snippet
- `docs/`: plan, milestones, progress, decisions, balance report, deploy guide

## Commands

```bash
make test         # go test -race ./... + Godot gdUnit4 tests (headless)
make fixtures     # Go writes gamedata/fixtures
make sync         # copy gamedata into godot/gamedata
make server       # go run ./cmd/server -test (dev flags: -sim-lag=120ms -sim-jitter=40ms)
make balance      # go run ./cmd/balance -races 500 → docs/BALANCE_REPORT.md
make assets       # ./art/export.sh: Blender headless → .glb + turntable previews
make e2e          # real server binary + headless Godot bot clients
make ios          # Godot headless export → Xcode project → xcodebuild archive
```

Underlying tools: `godot --headless --path godot …` (pinned version only, see `godot/VERSION`),
`blender --background --python <script>`, `xcodebuild`.

## Working style

- Work milestone by milestone (`docs/MILESTONES.md`). Meet a milestone's "done when" criteria
  before starting the next; update `docs/PROGRESS.md` at the end of each session.
- Small, focused commits; tests green before committing.
- Godot scenes are `.tscn` text with scripts attached; keep trees shallow and reuse scenes
  (one `CarView.tscn` for all 8 cars, configured from `vehicles.json`).
- Blender scripts are deterministic and run headless; every car gets a turntable preview in
  `art/previews/` for human review.
- Log source and licence of every audio file in `godot/assets/audio/CREDITS.md`.
- Never commit secrets (`.env`, signing files, Apple keys).

## Deployment target

The game server runs on the human's Debian 12 host `flappus` in Docker behind the central
Caddy proxy that runs natively as the systemd service `caddy` (not Docker), config in `/etc/caddy/` (`ultirace.flappus.com` → `127.0.0.1:8090`). Reload with `sudo systemctl reload caddy`. Prepare files and commands; the human
runs anything that needs SSH access unless they say otherwise.

## Public play

Rooms are public by default and listed in the room browser; Quick Play matchmaking puts
strangers together. Treat everything another player can see (names, reports) as untrusted
input: validate, filter and rate-limit it on the server. No chat, no free-text room names.
