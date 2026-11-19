# Milestones

Source: `docs/GAME_PLAN.md` §10. Tick a box only when every "done when" criterion is verified.
Each milestone ends with a demo and an updated `docs/PROGRESS.md`.

- [x] **M0 — Setup.** (done 2026-11-19: CI green on 930f1e8, Boot scene runs on iPhone 15 Pro Max) Repo, Go module, Godot project pinned, Makefile, CI green; empty Godot scene runs on a real iPhone via Xcode
- [x] **M1 — Sim core (Go).** (done 2026-11-19) Track building + car physics + laps/ranking, determinism test, fixtures written
- [x] **M2 — Rooms & bots (Go).** (done 2026-11-19) Protocol, rooms, state machine, bots, public/private visibility, room directory API, matchmaker; Go bot clients Quick Play into rooms and finish races over WebSocket
- [x] **M3 — Mirror (Godot).** (done 2026-11-19) `Track.gd` + `Physics.gd` pass all fixtures; 3 maps render from JSON with a free camera
- [x] **M4 — Connect & watch.** (done 2026-11-19, verified on iPhone 15 Pro Max over LAN) Godot client joins a room; all cars interpolated (no prediction); protocol fixtures pass
- [x] **M5 — Play.** (done 2026-11-19; device race verified, human feel check in HUMAN_TODO #10) Touch controls, HUD, lobby, vehicle select, countdown, results; full race vs bots on device
- [x] **M6 — ULTs & balance.** (done 2026-11-19; 7/8 balance targets over 6000 races, Bolt avg position 5.15 vs ≤ 5.1 → follow-up in M12) All 8 ULTs, effects, CC rules, catch-up; balance report within targets
- [x] **M7 — Prediction.** (done 2026-11-19: e2e predicted driver under 150 ms ± 40 ms lag, avg correction 5.6 cm; feel check on device in HUMAN_TODO) Own-car prediction + reconciliation; instant feel with `-sim-lag=150ms`
- [ ] **M8 — Art pass.** 8 Blender cars approved, props, baked lightmaps, VFX, cosmetic suspension, camera polish
- [x] **M9 — Audio & haptics.** (done 2026-11-19; procedural CC0 audio; human listening/feel check in HUMAN_TODO) Engine layers, SFX, music, mix, haptics, settings
- [ ] **M10 — Game Center.** Sign-in + server verification, leaderboards, achievements
- [ ] **M11 — Public play & deploy.** Room browser screen, Quick Play, lobby timer, kick/report/block, name filter; server live on flappus behind native Caddy; Universal Links, share sheet, landing page; strangers can find and join each other
- [ ] **M12 — Performance.** Tiers tuned on oldest and newest test devices; all §8 budgets met
- [ ] **M13 — TestFlight.** Signed build, friends play a full group session, crash-free ≥ 99 %
- [ ] **M14 — App Store.** Store page, screenshots, privacy answers, submitted for review
