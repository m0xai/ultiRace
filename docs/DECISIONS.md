# Decisions log

Append-only. Format: date, decision, reason, alternatives considered.
Key decisions D1–D10 from the original plan live in `docs/GAME_PLAN.md` §0.

| Date | Decision | Reason | Alternatives |
|---|---|---|---|
| 2026-11-19 | Moved `GAME_PLAN.md` from repo root to `docs/GAME_PLAN.md` | CLAUDE.md and plan §3.2 both reference `docs/GAME_PLAN.md` | Keep at root and fix references |
| 2026-11-19 | Development/test device = **iPhone 15 Pro Max**; the high graphics tier is the primary target. The iPhone 7 Plus is not supported | Human's call: wants high-end graphics, old devices are not a priority. The iPhone 7 Plus also can't pair with devicectl (iOS 15 max) | Keep iPhone 11 as the main tuning device (the plan's low tier stays for now; whether to drop it is an open question) |
| 2026-11-19 | Blender 5.3 instead of the plan's "Blender 4.x" | Installed version; preflight glb export + render works | Install 4.x alongside |
| 2026-11-19 | No iOS Simulator in the loop; iPhone 15 Pro Max for all app runs, unsigned generic-iOS compile in CI | Official 4.7.2 template's simulator slice is x86_64-only and iOS 27 simulator rejects x86_64 apps | Build custom arm64-simulator templates from Godot source (slow, maintenance); revisit if templates are fixed |
| 2026-11-19 | Free Personal Team `R984A9U2G4` for device builds until M10 | Already signed in to Xcode; enough for M0–M9 | Paid Apple Developer Program now (human decision, needed for Game Center/TestFlight) |
| 2026-11-19 | Minimum iOS **17.0**, bundle ID `com.flappus.ultirace`, iPhone + iPad device family | iOS 17 covers iPhone XS/11 and newer (plan's device floor) and matches devicectl support; bundle ID follows the server domain | iOS 16 (no benefit for A13+ devices) |
| 2026-11-19 | gdUnit4 **v6.2.3** vendored in `godot/addons/gdUnit4` (from github.com/godot-gdunit-labs/gdUnit4, MIT) | Latest release, fixes Godot 4.7 issues; CLI runner `runtest.sh` propagates exit codes | Git submodule (extra step for CI and new sessions) |
| 2026-11-19 | iOS build steps live in `scripts/ios.sh` (export / device / run / archive / compile-check), Makefile calls it | Needs logic (device discovery, Godot's exit-0-on-failure export validation) that is awkward in Make 3.81 | Inline Makefile recipes |
| 2026-11-19 | Toolchain smoke tests live in `scripts/preflight.sh` (re-runnable) instead of a one-off folder | Re-run after the human fixes templates/signing/device without redoing work | Manual one-off commands |
