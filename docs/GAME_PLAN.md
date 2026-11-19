# UltiRace — Game Design & Technical Plan (iOS)

> In-game, each vehicle's unique ability is called its **ULT** (ultimate), like in MOBAs;
> that's where the name UltiRace comes from.

> Status: v1 plan. This is the source of truth for design and architecture. If you change a
> decision, record it in `docs/DECISIONS.md` and update this file.

---

## 0. Key decisions

| # | Decision | Why |
|---|---|---|
| D1 | **Native iOS app built with Godot 4.7.x** (pinned, Mobile renderer, Metal) | Scenes and scripts are text files Claude Code can create and edit end to end; free; headless CLI for export and tests; Android later is a small step |
| D2 | **Go backend, server-authoritative** | Cheap goroutine-per-room concurrency, fast sim for the server and the balance tool, one static binary |
| D3 | **One repo** (`ultirace-ios`): Go server + Godot client + Blender asset scripts + shared `gamedata/` | One source of truth for data, fixtures and protocol; one CI |
| D4 | **Client language: typed GDScript**; GDExtension only for native iOS plugins | Fast iteration, no compile step, plenty of speed for one predicted car |
| D5 | **Game Center = identity + leaderboards + achievements**; race traffic on our own WebSocket | The server must stay authoritative; GKMatch transport would bypass it |
| D6 | **Social via room links** (Universal Links) shared through the iOS share sheet, plus Game Center | Works in any messenger; no third-party SDKs or logins |
| D7 | **Assets: scripted Blender** (`blender --background --python`) → glTF | Repeatable, versioned in git, consistent style |
| D8 | **Hosting: `flappus` (Debian 12).** Game server in Docker on `127.0.0.1:8090`; **Caddy runs natively as a systemd service** (not in Docker) and reverse-proxies to it | Existing infrastructure; Caddy handles TLS and WebSockets for all games centrally |
| D9 | **Global public rooms:** rooms are **public by default**, listed in a room browser; **Quick Play** matchmaking drops you into the best open public room. Private rooms stay possible (code/link only) | Strangers can race real players anytime, not only friend groups |
| D10 | **No text chat** and **no free-text room names** | Keeps user-generated content (and App Store moderation duties) to player names only |

---

## 1. Vision

A **short, chaotic, friendly kart-style racer** for everyone with an iPhone: groups of
friends in a private room, or anyone in the world jumping into a **public room** with real
players. A race takes
**2–3 minutes**. Abilities cause big funny moments (spin-outs, ice slides, tornadoes), and
catch-up mechanics keep every player in the race until the finish line. It should feel like a
**premium native game**: rich lighting, juicy effects, designed sound, haptics, Game Center.

**Pillars**
1. **Instant fun.** App launch → in a race in under 30 s. Three inputs, no tutorial needed.
2. **Smooth first.** 60 fps steady on an iPhone 11; 120 fps on ProMotion devices when there is
   headroom. A frame drop is worse than a missing effect.
3. **Everyone has a chance.** Balanced vehicles, crowd-control limits and catch-up help so that
   last place still feels it can win.
4. **Social & global.** One tap on Quick Play puts you in a race with real people from
   anywhere; share a link and friends join you. Quick rematch. Bots fill empty seats so a race
   always starts.

**Non-goals for v1:** Android, in-app purchases, accounts beyond Game Center/guest,
progression or unlocks, item pickups, track editor, voice chat, text chat, ranked/skill-based matchmaking,
multiple server regions (single server first, see §3.6), third-party integrations (e.g. Discord),
more than 8 players, offline single-player (Practice uses a server room with bots),
iPad-specific layouts beyond scaling.

---

## 2. Core gameplay

### 2.1 Controls

| Action | Touch (landscape, default) | Tilt (optional) | Game controller |
|---|---|---|---|
| Steer left/right | two big buttons bottom-left (≥ 80 pt, multi-touch) | device roll, dead zone 4°, full lock at 25° | left stick / d-pad |
| Accelerate | **auto-accelerate ON by default**; optional button bottom-right | same | RT / A / Cross |
| Ability (ULT) | round button bottom-right with a cooldown ring | button | X / RB / Square |

- Releasing Accelerate makes the car coast. There is **no brake and no reverse**. The track
  has walls, and an auto-align force turns the car back, so it never gets stuck.
- Tilt maps to the same `steer ∈ {-1, 0, 1}` input as the buttons (analog steer is backlog).
- Settings: swap sides, button size (S/M/L), tilt on/off + sensitivity, auto-accelerate,
  haptics on/off, reduce motion.
- Respect the safe area (Dynamic Island, notch, home indicator). Landscape only.
- Controllers: Godot joypad input; show the right glyphs per controller family.

### 2.2 Haptics

| Event | Haptic |
|---|---|
| Countdown beeps / GO | light / heavy tap |
| Wall hit | medium, scaled by impact speed |
| Hard CC received | heavy + short buzz |
| ULT ready | light tap |
| Start boost success | double tap |

v1: `Input.vibrate_handheld(duration_ms, amplitude)`. Core Haptics patterns are backlog.

### 2.3 Game flow

```
Launch → Game Center sign-in (silent) → Home
   → [Quick Play | Browse Rooms | Create Room | Join code/link | Practice]
   → Lobby → Vehicle Select → Countdown (3-2-1-GO) → Race → Results → (Rematch → Lobby)
```

- **Home:** big **Quick Play** button with a live "N players online" counter, **Browse Rooms**,
  **Create Room**, room-code field, **Practice** (private room with 7 bots), Game Center access
  point, settings; the last-used vehicle turns on a 3D podium.
- **Lobby:** player list (avatar, name, ping bar, ready state) and room settings set
  by the **host**: visibility (**Public** default / Private), map (3), laps (2 or 3), fill empty
  slots with bots (default on). "Share" opens the iOS share sheet with the room link.
  Start rules differ by visibility (see §2.3.1).
- **Vehicle Select (simultaneous pick, first lock wins):** everyone sees 8 vehicle cards and a
  20 s timer. Tapping a card previews it in 3D (stats and ULT); **LOCK** claims it. The server
  decides ties by message arrival order; claimed cards turn grey with the owner's avatar.
  When the timer ends, unlocked players get a random remaining vehicle, then bots take what
  is left. Moves on early once every human has locked.
- **Countdown:** grid order is the reverse of the last race's results (random for the first
  race). Accelerating within 0.0–0.25 s after GO gives a **start boost** (with auto-accelerate,
  tapping the screen in that window counts).
- **Race:** 2 or 3 laps. ULTs unlock 3 s after GO.
- **Results:** podium with the top 3 cars in 3D, a table of all finish times, achievements
  earned, "Rematch" and "Leave". The race ends **20 s after the first finisher**; unfinished
  players are ranked by progress.
- **Late joiners** watch as spectators (camera follows the leader) and join at the next lobby.

### 2.3.1 Public rooms, room browser and Quick Play

**Visibility**

| | Public (default) | Private |
|---|---|---|
| Listed in the room browser | ✅ | ❌ |
| Quick Play can put strangers in | ✅ | ❌ |
| Join by code / link | ✅ | ✅ |
| Start | **lobby timer**: 30 s countdown starts when the room has ≥ 2 humans (or 60 s with 1 human, then the race starts with bots); resets to at least 10 s when someone joins in the last 10 s; host may start early once all humans are ready | host presses Start when all humans are ready (auto-start 3 s after everyone is ready) |
| After Results | back to lobby automatically, timer restarts (endless loop of races) | back to lobby, host decides |
| Host can kick | ✅ (kicked player can't rejoin that room for 10 min) | ✅ |

The host can switch visibility in the lobby at any time. Ready buttons stay, but in public
rooms they only make the timer shorter (all humans ready → 5 s).

**Room browser (Browse Rooms screen)**
- Lists public rooms that are **not full**, sorted by: rooms in LOBBY first, then most humans,
  then newest. Rooms in RACING are shown greyed with "race in progress, joins next race"
  (you spectate until the next lobby).
- Each row: room name, host name, map thumbnail + laps, humans `3/8` (bots shown separately),
  state + time left, a "Join" button. Your own ping to the server is shown once in the header
  (single server).
- **Room names are generated, not typed:** `<Map> · <laps> laps · #<code>` plus a fun random
  tag from a fixed word list ("Turbo", "Slippery", …). No free text (D10).
- Filters: map, laps. Pull to refresh; auto-refresh every 3 s while the screen is open.
- Empty list → big "Create a public room" and "Quick Play" buttons.

**Quick Play (matchmaking, simple and fair)**
1. Ask the server for a public room in LOBBY that has a free human seat; prefer rooms with
   **more humans** and **less time left** on the lobby timer (fastest real race), and skip
   rooms that contain a player you blocked.
2. If none exists, the server creates a new public room for you with bots enabled, so the
   race starts within 60 s even when nobody else is online; anyone who joins before Vehicle
   Select replaces a bot.
3. If a race is running in a room with a free seat, you may join as a spectator for the next
   race only when no lobby room exists and the race ends within 30 s.

**Who gets a seat:** max 8 cars, humans always replace bots during LOBBY. A full room (8
humans) shows "Full" in the browser; extra people joining by link spectate.

**Fair play basics for strangers**
- Player names: Game Center alias, or a guest name passed through a profanity filter (word
  list in `gamedata/blocked_words.txt`, plus length and character rules). Rejected names get
  a random fun name ("Speedy Otter 42").
- **Report** and **Block** on every player row (lobby, results). Block hides their name
  (shown as "Player") and Quick Play avoids rooms with them. Reports are logged server-side
  with room and player IDs for review.
- AFK: a human with no input for 20 s during a race is handed to a bot; 2 AFK races in a row
  in a public room → moved back to Home.
- Rate limits: max 1 hosted room per player, room creation limited per IP.

### 2.4 Track model ("track-space")

Every track is a **closed 3D Catmull-Rom spline** with per-point width, bank and height.
Car physics run in **track-space coordinates**:

- `s`: distance along the centreline (0…trackLength, wraps)
- `d`: lateral offset from the centreline (−halfWidth…+halfWidth)
- `yawRel`: heading relative to the track tangent
- `y`: height above the road surface (jumps)

Why: walls become one clamp, lap counting and ranking are trivial (`progress = lap * L + s`),
bots only pick a target `d`, there are no shortcuts to cheat, physics cost is tiny
(8 cars × 30 Hz), and overpasses or figure-8 crossings work naturally because cars on
different `s` never interact even when their world positions overlap.

The road, curbs, walls and start gate are **generated from the spline** in Godot
(`TrackBuilder.gd`), then saved as a scene with baked lighting and placed props.

### 2.5 Car physics (arcade, deterministic; Go is the reference, GDScript is a mirror)

Fixed timestep `dt = 1/30 s`. Units: metres and seconds. Each tick:

1. `speed += accel(stat) * throttle * dt`, then drag; cap at `topSpeed * speedMultiplier`.
2. `yawRel += steer * steerRate(stat, speed) * dt`; a strong auto-align force pulls `yawRel`
   toward 0 (feels "on rails", but you still have to steer).
3. `s += speed * cos(yawRel) * dt / (1 − d·κ)`; `d += speed * sin(yawRel) * dt`;
   `yawRel −= κ · Δs` (the tangent turns under the car, so corners need steering).
   The Frenet correction gives the inside line its real geometric advantage, nothing more.
4. Wall: if `|d| > halfWidth − carHalfWidth`, clamp, `speed *= 0.75`, reflect `yawRel`,
   emit a `wallHit` event (sparks + haptic).
5. Car–car: circles in (s, d) space, radius 1.4 m; push apart by inverse weight, exchange some
   speed. Bump only, no damage.
6. Jumps: ramps in the track data set `vy`; gravity 25 m/s²; steering at 40 % in the air.
7. Status effects modify `speedMultiplier`, steering and input (§2.7).

Base numbers (all in `gamedata/balance.json`): track width 18–22 m, top speed ≈ 34–42 m/s,
0→top in about 3–4 s, lap length 1100–1500 m, so a lap takes about 35–45 s.

### 2.6 Vehicles (8, one per player, unique)

Every vehicle has **4 stats on a 1–5 scale that sum to 12** plus one ULT. Linear mapping in
`gamedata/balance.json`:

- **Speed:** top speed `34 + 1.6·stat` m/s
- **Accel:** time to top speed `4.4 − 0.3·stat` s
- **Handling:** steer rate and wall-bounce recovery
- **Weight:** collision push, plus hard-CC duration −5 % per point above 3

| # | Name | Spd | Acc | Hnd | Wgt | ULT | Effect (initial numbers) | Cooldown |
|---|---|---|---|---|---|---|---|---|
| 1 | **Bolt** | 5 | 3 | 2 | 2 | **Nitro** (self) | +35 % top speed, +60 % accel for 2.0 s | 9 s |
| 2 | **Rhino** | 2 | 2 | 3 | 5 | **Ram Charge** (contact) | 0.6 s dash at +50 %; first car hit spins out 1.0 s and is knocked sideways | 10 s |
| 3 | **Glacier** | 3 | 3 | 3 | 3 | **Ice Slick** (trap) | 8 m ice patch behind (8 s, max 2); car on it: steering ×0.25, −15 % speed for 1.2 s | 9 s |
| 4 | **Volt** | 3 | 4 | 3 | 2 | **EMP Pulse** (area) | opponents within 18 m slowed 35 % for 1.8 s | 11 s |
| 5 | **Hook** | 3 | 3 | 4 | 2 | **Grapple** (target) | tethers to nearest car ahead within 70 m; 0.8 s: Hook +40 %, target −25 % | 10 s |
| 6 | **Goo** | 3 | 2 | 3 | 4 | **Goo Bomb** (lob) | lands 40 m ahead, 10 m puddle for 4 s; −40 % speed inside | 10 s |
| 7 | **Phantom** | 4 | 3 | 3 | 2 | **Phase** (defensive) | 2.5 s ghost: CC immune, passes through cars and traps, +10 % speed, clears effects | 12 s |
| 8 | **Twister** | 2 | 4 | 4 | 2 | **Tornado** (projectile) | flies down the track at 1.3× speed, homes sideways on nearest car ahead; first hit spins out 1.2 s; lasts 4 s | 11 s |

Each vehicle needs a **distinct silhouette and colour** readable at 30 m on a phone: Bolt low
wedge (yellow), Rhino wide boxy truck (grey/orange), Glacier rounded (ice blue), Volt angular
with antennas (purple), Hook crane arm (green), Goo tanker (lime), Phantom sleek translucent
(white), Twister buggy with a fan (teal).

### 2.7 Status effects and anti-frustration rules

| Effect | Type | Behaviour |
|---|---|---|
| `spinout` | **hard CC** | input disabled, 360° spin, speed drops to 40 % then recovers |
| `slow` | soft | `speedMultiplier *= (1 − x)`; slows **don't stack**, strongest applies |
| `slide` | soft | steering × factor, small speed loss |
| `boost` | buff | top speed and accel multipliers stack additively, capped at +50 % |
| `ghost` | buff | CC immune, no car collisions |

- **CC immunity:** 1.5 s after a hard CC ends (shimmer shows it).
- A target can't be hard-CC'd more than once every 4 s from any source.
- Total slow capped at 50 %.
- No ULTs during the countdown or the first 3 s.
- No self-hits (your own ice and goo don't affect you).
- Every ULT has a **clear telegraph** (wind-up, visible projectile, ground ring), a sound and,
  for the victim, a haptic, so players understand what hit them.

### 2.8 Catch-up mechanics (subtle)

- **ULT recharge by position:** 1st ×0.85 … last ×1.35 (linear).
- **Drafting:** within 15 m behind a car and `|Δd| < 3 m` for 0.7 s → +8 % top speed (wind lines).
- **Comeback boost:** more than 150 m behind the leader → +4 % top speed (not shown).
- **Start boost** rewards timing.

### 2.9 Balance targets (checked by the balance sim)

`make balance RACES=500`: 8 equal-skill bots, random vehicle per slot, all 3 maps, 3 laps.

| Metric | Target |
|---|---|
| Win rate per vehicle | 12.5 % ± 4 % |
| Average finish position per vehicle | 4.5 ± 0.6 |
| Share of race time hard-CC'd | ≤ 8 % average, ≤ 15 % worst player |
| Hard CCs received per player per lap | ≤ 1.5 |
| Lead changes per race | ≥ 3 |
| Gap 1st → last at the finish | ≤ 12 s median |

Bots use a simple heuristic per ULT (Ram when a car is within 10 m ahead, EMP when ≥ 2 cars
within 18 m, Ice when a car is within 30 m behind, …). The tuner may only change numbers in
`gamedata/balance.json`. The sim (`cmd/balance`) runs races in parallel goroutines and writes
`docs/BALANCE_REPORT.md`.

### 2.10 Maps (3)

Closed loops with walls on both sides, 1100–1500 m, no dead ends. Each map is one JSON file in
`gamedata/maps/` (control points `[x, y, z, width, bank]`, ramps, racing-line hints, prop
placement, theme). Go and Godot read the same file.

1. **Sunny Circuit** (beginner): wide (22 m) flat loop, 3 sweeping corners, one chicane;
   green hills, trees, grandstands; warm afternoon light.
2. **Neon Overpass** (intermediate): **figure-8 with a bridge**, night city, emissive edge
   strips with glow, wet-road reflections on the high tier, 2 tight hairpins, 20 m wide.
3. **Frosty Peaks** (advanced): elevation changes, **2 jump ramps**, banked turns, snow, pines,
   narrow (18 m) sections where ULTs matter more; falling-snow particles.

---

## 3. Technical architecture

### 3.1 Stack

| Layer | Choice |
|---|---|
| Backend | **Go 1.24+** (pinned in `go.mod`), `net/http` (1.22+ routing), `github.com/coder/websocket`, `log/slog` |
| Engine | **Godot 4.7.x**, Mobile renderer (Metal), exact version in `godot/VERSION` and CI |
| Client language | typed GDScript (untyped declarations = error) |
| Networking (client) | `WebSocketPeer`; binary snapshots via `PackedByteArray.decode_*`; JSON otherwise |
| Game Center | GameCenterKit GDExtension or the godot-ios-plugins GameCenter plugin; choose after a spike in M10, wrapped in `GameServices.gd` |
| Assets | Blender 4.x Python scripts → `.glb` |
| Audio | Godot audio buses, `AudioStreamPlayer3D`, OGG samples |
| Tests | `go test -race`; **gdUnit4** headless; headless Godot bot clients for e2e |
| Build | `make` targets; Godot headless export → Xcode project → `xcodebuild archive` → TestFlight |

### 3.2 Repository layout

```
ultirace-ios/
├─ CLAUDE.md  README.md  Makefile  go.mod  go.sum
├─ docs/  GAME_PLAN.md  MILESTONES.md  PROGRESS.md  DECISIONS.md  BALANCE_REPORT.md  DEPLOY.md
├─ gamedata/                     # ONE source of truth, read by Go AND Godot
│  ├─ embed.go                   # package gamedata: //go:embed *.json maps/*.json
│  ├─ balance.json  vehicles.json
│  ├─ maps/ sunny.json neon.json frosty.json
│  └─ fixtures/                  # generated by Go tests, checked by Godot tests
├─ cmd/
│  ├─ server/main.go             # production server
│  ├─ balance/main.go            # headless balance sim → docs/BALANCE_REPORT.md
│  └─ botclient/main.go          # headless WS clients for load and soak tests
├─ internal/
│  ├─ mathx/      rng.go (mulberry32) spline.go vec.go
│  ├─ track/      track.go (arc-length table, frames, curvature)
│  ├─ sim/        world.go car.go physics.go collisions.go race.go effects.go
│  ├─ abilities/  registry.go + one file per ULT
│  ├─ bots/       bot.go (racing line, avoidance, ULT heuristics)
│  ├─ protocol/   messages.go codec.go (source of truth for message shapes)
│  ├─ room/       manager.go room.go directory.go matchmaker.go (goroutine per room, state machine, 30 Hz loop)
│  ├─ moderation/ names.go (profanity filter) reports.go (append-only reports log)
│  └─ server/     http.go ws.go conn.go ratelimit.go rooms_api.go auth_gamecenter.go links.go (AASA + /r/ landing)
├─ godot/                        # the iOS client
│  ├─ project.godot  export_presets.cfg  VERSION
│  ├─ addons/  gdUnit4/  gamecenter/
│  ├─ gamedata/                  # synced copy of ../gamedata (make sync), checked in CI
│  ├─ assets/  cars/*.glb  props/*.glb  audio/  fonts/  ui/
│  ├─ tracks/  sunny.tscn neon.tscn frosty.tscn
│  ├─ src/
│  │  ├─ app/       App.gd (state machine)  screens/ (Home, RoomBrowser, Lobby, Select, Race, Results, Settings)
│  │  ├─ sim/       Track.gd  Physics.gd           # mirror of Go track + car physics
│  │  ├─ net/       Protocol.gd  Connection.gd  Snapshot.gd  Prediction.gd  Interpolation.gd
│  │  ├─ render/    TrackBuilder.gd  CarView.tscn|gd  CameraRig.gd  Vfx/  Quality.gd
│  │  ├─ input/     TouchControls.tscn  Tilt.gd  InputState.gd
│  │  ├─ audio/     AudioDirector.gd  EngineSound.gd
│  │  ├─ platform/  GameServices.gd  Haptics.gd  Share.gd  DeepLinks.gd
│  │  └─ testing/   BotClient.gd  DebugOverlay.tscn
│  └─ test/         *_test.gd
├─ art/
│  ├─ blender/  lib/  cars/*.py  props/*.py
│  ├─ previews/                  # turntable renders for human review
│  └─ export.sh
├─ deploy/  Dockerfile  compose.yaml  Caddyfile.snippet
└─ .github/workflows/ci.yml
```

### 3.3 What runs where

| Logic | Go server | Godot client |
|---|---|---|
| Track building (spline, arc length, frames) | ✅ reference | ✅ mirror (mesh + prediction) |
| Car physics (throttle, steering, walls, jumps) | ✅ reference | ✅ mirror (**own car prediction only**) |
| Collisions, ULTs, effects, projectiles, traps | ✅ only | ❌ shown from snapshots and events |
| Laps, ranking, race state, results, bots, balance sim | ✅ only | ❌ |
| Data | `gamedata/*.json` embedded | synced copy in `godot/gamedata/` |

**Conformance tests keep the mirror honest:** Go tests write `fixtures/track_<map>.json`
(sampled positions and curvature at fixed `s`), `fixtures/physics_*.json` (start state,
300-tick input sequence, expected state per tick) and `fixtures/protocol/*.json` (one example
per message type, incl. binary snapshots as base64). gdUnit4 tests run the GDScript mirror on
them; values must match within `1e-4` (GDScript `float` is 64-bit like Go `float64`).
`make fixtures` regenerates them; CI fails if fixtures or the Godot copy are stale.

*Rejected alternative:* running the sim on device and syncing peers (no server). Cheating,
desync and NAT problems; we want one authoritative sim.

### 3.4 Server design (Go)

- **One goroutine per room** owns all of that room's state (no mutexes on game state).
  `time.Ticker` at 30 Hz: drain inbound channel, step `sim.World`, send a snapshot on 2 of
  every 3 ticks (20 Hz).
- **Per connection:** reader goroutine (decode, validate, rate-limit → room channel) and writer
  goroutine (buffered `chan []byte`, size 64; full buffer → drop the client, it reconnects).
- `RoomManager`: `map[string]*Room` behind a mutex, only for create/join/delete.
- **Room directory** (public listing): each room goroutine pushes a small `RoomSummary`
  (code, name, map, laps, humans, bots, state, timer deadline, visibility) to the directory on
  every change. The directory keeps a sorted slice behind an `RWMutex`, rebuilds a cached JSON
  body at most twice per second, and serves it with an `ETag`. No room state is ever read
  from outside its goroutine.
- **Matchmaker** (`POST /api/quickplay` or `hello{quick:true}`): picks a room from the
  directory by the Quick Play rules (§2.3.1), reserves a seat for 5 s (so two players can't
  take the last seat), else creates a new public room. Excludes rooms with blocked players
  (the client sends its block list).
- **Moderation:** name filter on `hello`; `report` messages appended as JSON lines to
  `/data/reports.jsonl` (Docker volume) with room code, reporter, target, reason, time;
  per-IP rate limits for connections, room creation and quick-play requests.
- Snapshots encoded **once per room per tick**; per-client `ack` in a tiny prefix.
- Context cancellation everywhere; graceful shutdown on SIGTERM (tell rooms, drain ≤ 10 s).
- Room logic tested with a fake clock. `net/http/pprof` only on a debug port in dev.
- **Game Center auth** (`POST /api/auth/gamecenter`): the client sends `publicKeyURL,
  signature, salt, timestamp, teamPlayerID, bundleID`. The server checks the key URL host is
  an Apple Game Center host, downloads and caches the certificate, verifies the chain and the
  signature over `teamPlayerID + bundleID + timestamp (big-endian u64) + salt`, rejects
  timestamps older than 5 min and wrong bundle IDs, then returns a session token.
  **Check Apple's current `fetchItems(forIdentityVerificationSignature:)` docs first.**
  Guests get a token without verification.
- **Links:** `/.well-known/apple-app-site-association` (200, `application/json`, no redirect)
  for paths `/r/*`. `GET /r/{code}` without the app installed shows a small embedded landing
  page: game name, room code, App Store / TestFlight button.

### 3.5 Networking model

**Server-authoritative simulation with client-side prediction for your own car.**

- Server sim at **30 Hz**; clients send inputs `{seq, steer: -1|0|1, thr: 0|1, ab: bool}` at 30 Hz.
- Server sends **snapshots at 20 Hz**: per car quantised `[id, s, d, yawRel, y, speed,
  effectsBitmask]`, plus projectiles, traps and `ack`. Binary (`encoding/binary` ↔
  `decode_*`). Target ≤ 4 KB/s down per client.
- **Own car:** predicted with the GDScript mirror; on each snapshot reset to server state and
  replay unacknowledged inputs. Small errors smoothed over 100 ms; > 5 m snaps. Effects come
  from the snapshot and are applied to the predicted car.
- **Other cars:** interpolated ~100 ms in the past in track-space (handle the `s` wrap). The
  buffer adapts up to 160 ms when jitter is high.
- **ULTs and hits:** decided only by the server. The client plays an instant local activation
  animation and sound; outcomes come from events.
- **Events** (reliable, ordered, same socket): `abilityUsed`, `hit`, `wallHit`, `lap`,
  `finished`, `state`.
- **iOS lifecycle:** app paused mid-race → keep the socket up to 10 s while a bot drives;
  then close and reconnect with the token on resume (30 s server window). Network switch
  (Wi-Fi ↔ cellular): detect via 2 missed pongs at 1 Hz, reconnect automatically, show a
  small "Reconnecting…" pill.
- **Latency testing:** server flags `-sim-lag=120ms -sim-jitter=40ms`.
- **Phasing for safety:** first build everything with no prediction (all cars interpolated),
  add prediction in its own milestone.

### 3.6 Rooms and lifecycle

- Room key: 4-letter code (`ABCD`), shared as `https://ultirace.flappus.com/r/ABCD`.
  Codes avoid ambiguous letters and a short list of bad words.
- Visibility: `public` (default) or `private`, changeable by the host in LOBBY.
- "Practice" creates a private room with 7 bots; "Quick Play" uses the matchmaker (§3.4).
- States: `LOBBY → SELECT → COUNTDOWN → RACING → RESULTS → LOBBY`. Only the server changes state.
- Host = first human who joined; next human takes over if the host leaves.
- Disconnect during a race: a bot drives; reconnecting within 30 s with the token takes it back.
- Room destroyed 60 s after the last human leaves (public rooms: immediately removed from the
  listing). Max 8 cars; a 9th person spectates.
- **Global reach, one server:** v1 runs one server in Germany. Players far away (e.g. US west
  coast, Asia) will see 150–250 ms ping; prediction keeps their own car instant, and the
  room browser shows ping so players know. The protocol and `RoomSummary` carry a `region`
  field from day one so more servers (e.g. US, Asia) can be added later with a region picker,
  without a protocol change.

### 3.7 Protocol (`internal/protocol` is the source of truth, `Protocol.gd` mirrors it)

Every message is `{"t": "<type>", ...}`.

Client → Server: `hello{v, name, token?, room?, quick?, practice?, create?{visibility},
blocked?[playerIds], auth?{provider:"gamecenter"|"guest"}}`, `ready{ready}`,
`settings{map, laps, bots, visibility}` (host), `start` (host), `kick{playerId}` (host),
`preview{vehicle}`, `lock{vehicle}`, `in{seq, steer, thr, ab}`, `rematch`,
`report{playerId, reason}`, `ping{t}`.

HTTP: `GET /api/rooms?map=&laps=` → `{online, rooms:[RoomSummary]}` (ETag, cached);
`GET /api/stats` → `{online, racing}` for the Home counter.

Server → Client: `welcome{playerId, token, room}`, `room{...}`, `select{claims, deadline}`,
`raceStart{seed, map, laps, grid, startAt}`, `snap{tick, ack, cars, proj, traps}` (binary),
`ev{...}`, `results{rows, verified}`, `kicked{reason}`, `pong{t}`, `err{code, msg}`.

Player IDs exposed to other clients are **stable per player but anonymous** (a server-side
hash of the Game Center `teamPlayerID` or guest token), so blocks survive across rooms
without revealing Game Center IDs.

`results.verified` holds each player's server-confirmed best lap and race time; the client
submits only these to Game Center. `hello.v` mismatch → `err{code:"version"}` → the app shows
"Please update".

### 3.8 Bots (Go only)

`bots.Controller` returns the same input struct as a human: follow the map's racing line
(target `d(s)` precomputed from curvature), shift `d` to avoid traps and cars ahead, use ULT
heuristics (§2.9). No physics advantages; difficulty only changes reaction delay and line
noise. Used for empty slots, disconnected players, Practice, public rooms with few humans, the balance sim and tests.

---

## 4. Rendering & art direction

### 4.1 Style

**"Toy-like premium low-poly."** Clean bevelled shapes, saturated palette per map, and
lighting doing the heavy lifting: baked GI, soft shadows, rim light on cars, glow on
emissives, light fog for depth.

### 4.2 Renderer setup (Godot Mobile renderer)

| Feature | Low tier | High tier |
|---|---|---|
| Render scale | 0.7–0.85 + FSR 1 upscale | 1.0 (0.85 at 120 Hz) |
| Static lighting | **baked LightmapGI** per track | same |
| Dynamic shadows | blob shadows | 1 directional light, 2 cascades, ≤ 60 m, soft PCF low |
| Glow | off | on |
| Car reflections | matcap-style fake env | ReflectionProbes per track section |
| Particles | GPUParticles at 50 % | full |
| MSAA | off | 2× |
| Target fps | 60 | 60, or 120 on ProMotion when frame time allows |

- **No shader stutter:** use Godot's shader baker for the iOS export and warm up all VFX
  materials on the loading screen.
- Textures: one shared palette/gradient atlas + a small trim sheet; ASTC compression.
- `Quality.gd` picks the start tier from the device model, then adapts at runtime (rolling
  frame time → step render scale → drop tier; raise slowly when there is headroom; cap at
  60 fps when the thermal state is "serious"). Manual setting: Auto / High / Low.

### 4.3 Asset pipeline (Blender, scripted)

- Each car is a Python script in `art/blender/cars/` building the model from parametric parts
  (body, cabin, wheels, spoiler, signature part) with shared helpers (bevel, mirror, UV to the
  palette atlas, LOD decimate). Deterministic (fixed seeds).
- `art/export.sh` runs `blender --background --python` for every asset → `godot/assets/*.glb`,
  plus a turntable PNG per car in `art/previews/` for human approval.
- **Budgets per car:** LOD0 ≤ 6 k tris, LOD1 ≤ 2 k, LOD2 ≤ 600; 1 material (+1 glass/emissive);
  separate wheel meshes (spin + steer).
- Tracks: road/curbs/walls generated from map JSON by `TrackBuilder.gd`, saved as `.tscn` with
  baked lightmaps; scenery props from Blender, drawn with MultiMesh.

### 4.4 VFX & camera

- Pooled GPUParticles: boost flames, sparks, drift smoke, ice shards, goo splats, tornado
  debris, EMP ring (shader), grapple cable (stretched mesh), wind lines when drafting.
- **Cosmetic physics on the client only** (never affects the sim): suspension bounce from `y`
  and speed changes, body roll in turns, wheel steer angle, squash on landing, bouncy antennas.
- Camera: spring-follow chase cam ~6 m behind, 2.6 m up, look-ahead on turns, FOV kick 70→80
  on boost, short hit shake (off with "reduce motion").

### 4.5 HUD (Godot Control nodes)

Position (big "3/8"), lap "2/3", race timer, ULT icon with cooldown ring, minimap (track
polyline + coloured dots, 10 Hz), finish timer, floating name tags (≤ 4 nearest), reconnect
pill. All touch targets ≥ 44 pt; text readable on an iPhone SE.

---

## 5. Audio

| Layer | Approach |
|---|---|
| Engine | 3 looped samples per car class (idle/mid/high), cross-faded and pitch-shifted by speed; own car 2D, others `AudioStreamPlayer3D` (max 4 nearest) |
| SFX | designed sample bank (OGG, ≤ 1.5 MB): countdown, boost, wall hit, spin-out, ice, EMP, grapple, splat, tornado, lap chime, finish fanfare, UI |
| Music | one loop per map + menu theme, ducked under SFX |
| Mix | buses Master → Music / SFX / Engine / UI; limiter on Master; volume sliders |
| iOS | "ambient" audio session by default (respects the silent switch and other apps' music) |

Every audio file's source and licence goes in `godot/assets/audio/CREDITS.md` (CC0 packs,
generated sfxr-style sounds, or commissioned).

---

## 6. Platform services

### 6.1 Game Center

- **Sign-in:** silent at launch; on failure or decline, continue as guest (name prompt +
  random colour). Never block play.
- **Identity to server:** fetch the identity verification signature and exchange it at
  `/api/auth/gamecenter` (§3.4).
- **Leaderboards** (submit only `results.verified` values): best lap per map (3, lower is
  better), race wins (recurring, weekly).
- **Achievements (initial ~12):** first race, first win, win with every vehicle (progress),
  10 perfect start boosts, 3 ULT hits in one race, win after being last on lap 1, clean race
  (no wall hits), 50 races, win on every map, …
- **Access point** on Home only (hidden in races).
- Known limit: Game Center submissions come from the client. Accepted for v1; a server-side
  leaderboard is backlog.

### 6.2 Sharing & public play

- Room links via the iOS share sheet (Messages, WhatsApp, any app); friends tap the link and
  land in the room. No third-party SDKs or third-party logins.
- Public rooms and Quick Play (§2.3.1) let anyone race strangers. The only user-generated
  content is player names (no chat, no free-text room names).

### 6.3 Privacy & App Store

- No ads, no tracking, no analytics SDK in v1. Declare the player name and Game Center ID
  used for gameplay accurately in App Store Connect.
- Ship a `PrivacyInfo.xcprivacy`; check the Godot export and every plugin include one.
- Age rating: mild cartoon violence. Answer the age-rating questions about **user
  interaction with strangers** honestly (online multiplayer with unknown players).
- **App Store Review Guideline 1.2 (user-generated content)** applies because strangers see
  each other's names. Required and planned: name filtering (§2.3.1), **Report** and **Block**
  on every player, host kick, and a published contact address (in Settings and on the store
  page) for abuse reports. Check the current wording of 1.2 before submission.
- Reports are reviewed by the human from `/data/reports.jsonl`; a ban list
  (`/data/bans.json`, by anonymous player ID) is loaded by the server and reloaded on SIGHUP.

---

## 7. Deployment

### 7.1 Server

- `deploy/Dockerfile`: `golang:1.24-alpine` → `CGO_ENABLED=0 go build -trimpath
  -ldflags="-s -w" ./cmd/server` → `gcr.io/distroless/static`. Image ≈ 15–25 MB.
- On **flappus** (Debian 12): `/opt/ultirace/compose.yaml`, `restart: unless-stopped`,
  env in `/opt/ultirace/.env` (`PORT`, `LOG_LEVEL`, `MAX_ROOMS`, `APPLE_BUNDLE_ID`,
  `APPLE_TEAM_ID`), a volume for `/data` (reports, bans), port published only on the host
  loopback: `127.0.0.1:8090:8090`.
- **Caddy runs natively on the host as the systemd service `caddy`** (Debian package, not
  Docker) and serves all games centrally. Add a site block to `/etc/caddy/Caddyfile` (or an
  imported file such as `/etc/caddy/sites/ultirace.caddy`, if the central config uses
  `import`):

  ```caddy
  ultirace.flappus.com {
      encode zstd gzip
      reverse_proxy 127.0.0.1:8090
  }
  ```

  Then `sudo caddy validate --config /etc/caddy/Caddyfile` and `sudo systemctl reload caddy`.
  Caddy gets the TLS certificate automatically and proxies WebSocket upgrades without extra
  config. Because Caddy runs on the host, it reaches the container through the loopback
  port; no shared Docker network is needed. `deploy/Caddyfile.snippet` holds the block.
- The Go server trusts `X-Forwarded-For` **only** from `127.0.0.1` (Caddy) for per-IP rate
  limits.
- Endpoints: `/ws`, `/api/*`, `/healthz`, `/.well-known/apple-app-site-association`, `/r/{code}`.
- Graceful shutdown on SIGTERM. One instance with in-memory rooms; one vCPU should hold
  hundreds of rooms (verified with `cmd/botclient`). Shard by room code later if needed.
- Fix the final domain before the links milestone: Universal Links and the app's Associated
  Domains entitlement depend on it.

### 7.2 iOS app

- **Human-only steps** (go in `docs/DEPLOY.md`): Apple Developer Program membership, App ID +
  bundle ID, Game Center capability, Associated Domains (`applinks:ultirace.flappus.com`),
  App Store Connect record, leaderboards and achievements created in App Store Connect,
  signing (Xcode automatic signing), TestFlight testers, DNS record for the domain.
- **Build:** `make ios` → `godot --headless --export-release "iOS" build/ios/UltiRace.xcodeproj`
  → `xcodebuild … archive` → `xcodebuild -exportArchive` → upload to TestFlight (Organizer,
  `xcrun altool` or fastlane; decide when we get there).
- Minimum iOS version: decide in M0 from Godot 4.7 export and plugin requirements; target
  devices from iPhone 11 (A13) upward.
- Version from git tag; build number = CI run number.
- CI: Linux runner for Go tests, Godot headless tests and balance smoke; macOS runner for the
  iOS export + `xcodebuild` compile check (no signing).

---

## 8. Performance budget (enforced)

| Budget | Target | Check |
|---|---|---|
| Frame rate | 60 fps steady on iPhone 11 (low tier); 120 fps on ProMotion (high tier) where possible | on-device debug overlay + Instruments per milestone |
| Client CPU per frame (scripts + mirror + net) | ≤ 3 ms on iPhone 11 | Godot profiler |
| Draw calls in race | ≤ 250 high, ≤ 150 low | `Performance` monitors, headless check per map |
| Triangles in view | ≤ 300 k high, ≤ 150 k low | same |
| App download size | ≤ 120 MB | export step |
| Cold start → Home | ≤ 3 s on iPhone 11 | measured each milestone |
| Memory | ≤ 600 MB, flat over a 5-race session | Instruments |
| Thermal | no drop below 50 fps after 15 min of racing on iPhone 11 | device soak |
| Server room tick (8 cars incl. bots) | ≤ 0.2 ms avg | `go test -bench` |
| Server capacity | ≥ 300 concurrent 8-car rooms per vCPU | `cmd/botclient` |
| Room list API | ≤ 5 ms p99 with 1,000 rooms, ≤ 30 KB response | `go test -bench`, load test |
| Quick Play → in a lobby | ≤ 1 s on a good connection | e2e timing |
| Network down | ≤ 4 KB/s per client | server counter, debug overlay |

`DebugOverlay` (triple-tap with two fingers in dev builds): FPS, frame ms, draw calls,
triangles, tier, ping, kbps.

---

## 9. Testing strategy

- **Go unit tests (`go test -race ./...`):** spline arc length, track-space ↔ world, wall
  clamp, collisions, lap counting incl. wrap and backwards driving, ranking, every ULT's
  effect and cooldown, CC rules, slow cap, determinism (same seed + inputs = same state hash),
  protocol round trip, a bot finishes 3 laps on every map, Game Center signature verification
  (valid, wrong bundle, expired, foreign key host), room tick benchmark.
- **Room/server tests:** state machine (fake clock), first-lock-wins claims, timeout
  auto-assign, host migration, reconnect, rate limiting, malformed messages; `httptest` server
  with real WebSocket clients.
- **Godot unit tests (gdUnit4, headless):** conformance against Go fixtures (track, physics,
  protocol), interpolation incl. `s` wrap, prediction and reconciliation, input mapping incl.
  tilt, quality controller.
- **Test-only time scale:** server `-test` flag lets rooms accept `timeScale` 1–10; refused in
  production.
- **E2E (CI, no device):** headless Godot bot clients (`BotClient.gd`) against the real server
  binary: solo Practice race finishes; 4 clients join one room, lock different vehicles at once
  (uniqueness), race, all see the same results; two clients lock the same car at the same
  instant → exactly one gets it; `-sim-lag=150ms` race completes.
- **On device, per milestone:** launch, Game Center sign-in, Quick Play, room browser, Practice, touch / tilt /
  controller, haptics, background + resume mid-race, Wi-Fi → cellular, room link from Messages.
- **Visual review:** screenshots of every screen and map at iPhone SE, current iPhone and iPad
  sizes saved for review; car turntables in `art/previews/`.
- **Public rooms & matchmaking tests (Go):** directory stays consistent under concurrent
  joins/leaves (`-race`), two Quick Play requests for the last seat → only one gets it,
  private rooms never appear in the listing, kick + 10 min rejoin block, blocked players
  avoided, lobby timer rules (≥ 2 humans, reset on late join, 1-human fallback with bots),
  name filter cases, rate limits.
- **E2E public play:** 6 headless Godot clients press Quick Play at once → they end up
  together in as few rooms as possible and race; a client browsing rooms sees the room
  appear and fill up.
- **Load/soak:** `go run ./cmd/botclient -rooms 50 -duration 2m` (tick time, memory,
  goroutines back to baseline).
- **Balance:** `make balance` (§2.9); a 50-race version runs as a Go test with loose bounds.

---

## 10. Milestones (each ends with a demo and an updated `docs/PROGRESS.md`)

| M | Goal | Done when |
|---|---|---|
| M0 | Setup | Repo, Go module, Godot project pinned, Makefile, CI green; empty Godot scene runs on a real iPhone via Xcode |
| M1 | Sim core (Go) | Track building + car physics + laps/ranking, determinism test, fixtures written |
| M2 | Rooms & bots (Go) | Protocol, rooms, state machine, bots, public/private visibility, room directory API, matchmaker; Go bot clients Quick Play into rooms and finish races over WebSocket |
| M3 | Mirror (Godot) | `Track.gd` + `Physics.gd` pass all fixtures; 3 maps render from JSON with a free camera |
| M4 | Connect & watch | Godot client joins a room; all cars interpolated (no prediction); protocol fixtures pass |
| M5 | Play | Touch controls, HUD, lobby, vehicle select, countdown, results; full race vs bots on device |
| M6 | ULTs & balance | All 8 ULTs, effects, CC rules, catch-up; balance report within targets |
| M7 | Prediction | Own-car prediction + reconciliation; instant feel with `-sim-lag=150ms` |
| M8 | Art pass | 8 Blender cars approved, props, baked lightmaps, VFX, cosmetic suspension, camera polish |
| M9 | Audio & haptics | Engine layers, SFX, music, mix, haptics, settings |
| M10 | Game Center | Sign-in + server verification, leaderboards, achievements |
| M11 | Public play & deploy | Room browser screen, Quick Play, lobby timer, kick/report/block, name filter; server live on flappus behind native Caddy; Universal Links, share sheet, landing page; strangers can find and join each other |
| M12 | Performance | Tiers tuned on oldest and newest test devices; all §8 budgets met |
| M13 | TestFlight | Signed build, friends play a full group session, crash-free ≥ 99 % |
| M14 | App Store | Store page, screenshots, privacy answers, submitted for review |

Backlog: more server regions + region picker, skill-based matchmaking, friends list /
"play with recent players", analog tilt steering (protocol v2), Core Haptics patterns,
server-side leaderboard, cosmetic skins, Android build, iPad split controls, replays/ghosts,
more maps.

---

## 11. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Go and GDScript physics drift apart | Only track + car physics are mirrored; Go fixtures checked by gdUnit4; CI fails on stale fixtures |
| Godot iOS plugin gaps (Game Center, haptics) | All platform calls behind `platform/*.gd`; spike before building on a plugin; a small custom GDExtension (Swift/Obj-C) is the fallback |
| Shader compile stutter | Shader baker + material warm-up on the loading screen |
| Thermal throttling | 120 fps only on the high tier with headroom; adaptive render scale; cap at 60 when hot |
| Mobile network drops | Token reconnect, bot takeover, adaptive interpolation buffer |
| Netcode jitter | Build without prediction first; artificial-lag tests |
| Ability balance spirals | One balance file, automated sim, CC rules, catch-up |
| Claude Code can't judge visuals alone | Turntables and screenshots reviewed by the human at each art milestone |
| App Store review | Privacy and login guidelines from day one; TestFlight external review before M14 |
| Single server on flappus | Health check + restart policy; portable Docker image |
| Empty public rooms at launch (too few players online) | Bots fill every race; Quick Play merges players into the same room; "N players online" counter; lobby fallback start after 60 s |
| Griefing / offensive names from strangers | No chat, generated room names, name filter, report/block/kick, ban list, AFK handover |
| High ping for players far from Germany | Prediction for own car, ping shown in the browser, `region` field ready for more servers |
| Room list load as players grow | Cached, ETag'd listing rebuilt ≤ 2×/s; clients poll only while the browser is open |
