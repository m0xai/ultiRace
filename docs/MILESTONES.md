# Milestones

Source: `docs/GAME_PLAN.md` §10. Tick a box only when every "done when" criterion is verified.
Each milestone ends with a demo and an updated `docs/PROGRESS.md`.

- [ ] **M0 — Setup.** Repo, Go module, Godot project pinned, Makefile, CI green; empty Godot scene runs on a real iPhone via Xcode
- [ ] **M1 — Sim core (Go).** Track building + car physics + laps/ranking, determinism test, fixtures written
- [ ] **M2 — Rooms & bots (Go).** Protocol, rooms, state machine, bots, public/private visibility, room directory API, matchmaker; Go bot clients Quick Play into rooms and finish races over WebSocket
- [ ] **M3 — Mirror (Godot).** `Track.gd` + `Physics.gd` pass all fixtures; 3 maps render from JSON with a free camera
- [ ] **M4 — Connect & watch.** Godot client joins a room; all cars interpolated (no prediction); protocol fixtures pass
- [ ] **M5 — Play.** Touch controls, HUD, lobby, vehicle select, countdown, results; full race vs bots on device
- [ ] **M6 — ULTs & balance.** All 8 ULTs, effects, CC rules, catch-up; balance report within targets
- [ ] **M7 — Prediction.** Own-car prediction + reconciliation; instant feel with `-sim-lag=150ms`
- [ ] **M8 — Art pass.** 8 Blender cars approved, props, baked lightmaps, VFX, cosmetic suspension, camera polish
- [ ] **M9 — Audio & haptics.** Engine layers, SFX, music, mix, haptics, settings
- [ ] **M10 — Game Center.** Sign-in + server verification, leaderboards, achievements
- [ ] **M11 — Public play & deploy.** Room browser screen, Quick Play, lobby timer, kick/report/block, name filter; server live on flappus behind native Caddy; Universal Links, share sheet, landing page; strangers can find and join each other
- [ ] **M12 — Performance.** Tiers tuned on oldest and newest test devices; all §8 budgets met
- [ ] **M13 — TestFlight.** Signed build, friends play a full group session, crash-free ≥ 99 %
- [ ] **M14 — App Store.** Store page, screenshots, privacy answers, submitted for review
