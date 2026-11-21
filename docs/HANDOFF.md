# Handoff — continue UltiRace in a new chat

Read this first, then `CLAUDE.md`, `docs/GAME_PLAN.md` (source of truth), `docs/PROGRESS.md`,
`docs/HUMAN_TODO.md` (open human items) and the last entries of `docs/DECISIONS.md`.
Last updated: 2026-11-21.

## Who / how

- The human is the product owner; Claude is the lead developer working autonomously.
- Hard limits (from the human): no sudo; no ssh/scp/rsync and no deploying to `flappus` (prepare
  files + commands only); no force-push or history rewrites; **no deleting files outside `build/`
  and temp folders** (put `git rm` commands into HUMAN_TODO instead); don't edit
  `.claude/settings.json` (propose changes in HUMAN_TODO); never commit secrets/signing files;
  no system setting changes; **no `brew install`** (Python tools live in `build/venv`, see below).
- Commits: small, tests green, message trailer `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`;
  push to `master` (no PR flow).
- Visual/audio judgement belongs to the human: render previews/screenshots, then ask.
- Every asset licence goes into `godot/assets/audio/CREDITS.md` (audio, fonts) or the asset's credits.

## Running things

| What | Command |
|---|---|
| All tests | `make test` (Go `-race` + 40+ gdUnit4 tests) |
| After track/physics/protocol/gamedata changes | `make fixtures && make sync && make test-godot` |
| Dev server (LAN, for the phone) | `go build -o build/e2e/server ./cmd/server && build/e2e/server -addr 0.0.0.0:8090 -test -log-level warn` (restart it after server changes!) |
| Install on the human's iPhone 15 Pro Max | `SERVER_URL=ws://192.168.178.32:8090 make ios-run` (phone must be unlocked to auto-launch) |
| Dev args on the phone | `DEV_ARGS="--auto practice" … make ios-run` (bakes `godot/dev_args.txt`; a normal `make ios-run` removes it — always reinstall a normal build afterwards) |
| Read files the app wrote on the phone | `scripts/ios.sh pull <file>` → `build/device/<file>` (Godot's stdout/stderr do NOT reach `devicectl --console` on iOS; write to `user://` and pull) |
| Desktop race screenshot + perf | `/Applications/Godot.app/Contents/MacOS/Godot --path godot --resolution 1334x750 -- --server ws://127.0.0.1:8090 --auto practice --shot out.png --shot-delay 25` (prints `PERF draw_calls=… primitives=…`) |
| Map art shots | `… res://src/render/MapViewer.tscn -- --map sunny|neon|frosty --cam start --at <s> --near --shot out.png` |
| iPhone 11 performance emulation on the Mac | `make iphone11` (see `docs/IPHONE11_SIM.md`) |
| Simulator | `make ios-sim` builds/launches but the game freezes after the home screen (GL fallback) — not usable |
| Blender assets | `make assets` (`art/blender/cars/<car>.py` → `godot/assets/cars/<car>.glb` + `art/previews/`) |
| Audio | `make audio` (creates `build/venv` with numpy/soundfile; `art/audio/gen_engines.py`, `gen_audio.py`); music re-encode: `art/audio/encode_music.py <download dir> godot/assets/audio/music`; engine listening demo: `art/audio/demo_engines.py` |
| Montage of PNGs | scratch helper: a Godot `-s` script that tiles images (re-create if the scratchpad is gone) |

Budgets (requirements, GAME_PLAN §8): race ≤ 450k triangles, ≤ 250 draw calls (high tier);
app ≤ 120 MB. Last measured race: 129–231 draws, 187–380k tris.

## State (2026-11-21)

Done recently (see PROGRESS.md for the full list):
- UI overhaul (Racing Sans One, Switcher control, simple home, two-column settings) — approved.
- Graphics pass 4 (asphalt shader, curbs, rails, hazard patches, road blocks, start gantry) — approved.
- Audio pass 2: per-car engines from a physical model (`gen_engines.py`, `EngineSound.gd` drivetrain);
  CC0 music (menu Cool City; Sunny Hyper Ultra-Racing; Desert Darkness Road + climax; Frosty Black
  Diamond; result jingles). Volumes default 60/50/50.
- Tilt steering fixed (gravity arrives in portrait axes on the device; live readout in Settings).
- Desert Night map replaces Neon Canyon (map id stays `neon`).
- Race UI: animated steer buttons, yellow ULT button with per-ULT vector icons, minimap fits track.
- Per-car rotated hitboxes (`vehicles.json` `hitbox`).

In progress / next (human's request of 2026-11-21):
1. Engine sound keeps running after the race ends → stop/fade engines on finish and when leaving.
2. ULT bar starts empty (no ULT at the start).
3. Exhaust smoke: per-car exhaust positions (single/dual, left/right/centre), better-looking
   puffs, slightly different per car.
4. **Big task — unified graphics quality:** every visual (tracks, scenery, props, sky, VFX, UI in
   race) should match the detailed cars. Take time; use Blender (real modelling, not only
   primitives), the iPhone-11 emulation for perf, screenshots for the human's review.

See the bottom of this file for the progress log of the current task.

## Gotchas learned

- Godot iOS: `Input.get_gravity()` is in portrait axes even in a landscape-only game.
- `make ios-run` with `DEV_ARGS` leaves the app in that dev mode until a normal install.
- The engine on the Mac (`/Applications/Godot.app`) is 4.7.2; `godot` is not on PATH.
- ffmpeg here has no libvorbis; use `build/venv` + soundfile (write in blocks: libsndfile's Vorbis
  writer segfaults on one huge write).
- Server JSON decoding is strict (`DisallowUnknownFields`): new gamedata fields need Go struct fields.
- The headless Godot audio driver is a dummy; music/engine state can still be logged.

## Progress log (current task)

- [x] 1. Engines fade out after the finish (own 2 s, others 4 s; results 1.5 s) — `5fa0f74`.
- [x] 2. ULT bar starts empty (`balance.json effects.ultStartCharge = 0`) — `5fa0f74`.
- [x] 3. Exhaust: tips modelled per car (`carkit4.exhausts()`, `ExhaustTip_<i>` empties in the
      glb), `godot/src/render/ExhaustFx.gd` smoke + boost flames per car — `533b8f4`.
      Review images: `docs/screenshots/exhaust_*.png`.
- [ ] 4. Unified graphics quality — plan (phases, commit each):
  - A. Audit: race screenshots of all three maps (start, mid, corners), list every visual that
       is below the cars' level. Perf baseline. NOTE: the race grid already peaks at ~420–490k
       triangles because several 108k-tri LOD0 cars sit near the camera at the start →
       tighten car LOD distances (own car LOD0; others LOD1 beyond ~12 m) as part of this task.
  - B. Lighting/post: one consistent look per map (AgX, exposure, fog, glow, SSAO if the
       renderer allows), shadows quality.
  - [x] C. Vegetation kit: `art/blender/env/vegetation.py` → `godot/assets/env/vegetation.glb`
       (Pine/PineSnow/Broadleaf with `_lod1`, Bush, Cactus, Rock0-2; vertex colours = sRGB in a
       byte layer set as active/render colour), `godot/src/render/EnvKit.gd` (100 m cells,
       detailed < 85 m, light beyond; small props hidden > 140 m), `foliage.gdshader` (sway).
       Old: (was) C. Vegetation kit in Blender (pine, snowy pine, broadleaf, bush, cactus/saguaro, grass
       tufts) with LODs → MultiMesh, wind sway shader.
  - [x] D. Buildings kit: `art/blender/env/buildings.py` (+ shared `envlib.py`) → `assets/env/buildings.glb`
       (Farmhouse, Barn, Cabin + `_lod1` + `<Name>Glow` windows), `WorldDressing._kit_houses`.
       Desert keeps the code-built diners/gas stations (could move to the kit later).
       Jump ramps rebuilt as kickers (`TrackBuilder._ramp`).
       Old: (was) D. Buildings kit in Blender (farmhouse, barn, cabin, diner, gas station) replacing boxes.
  - E. Roadside props (lamps, billboards, barriers, cones, grandstands, fences, signs).
  - [x] F1. Horizon: ridged-noise mountain rings + cumulus clouds (`TrackBuilder._mountains`,
       `_clouds`) — `49a826a`. Water/ice/oil patches: smooth normals + depth pull toward the
       camera (z-fighting gave blocky, speckled edges).
  - F. Terrain splat shader (grass/dirt/rock/snow/sand with normal detail), real mountain
       silhouettes, sky with shader clouds.
  - G. VFX polish (sparks, rings, ULT effects) and in-race HUD details.
