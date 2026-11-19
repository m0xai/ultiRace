# Decisions log

Append-only. Format: date, decision, reason, alternatives considered.
Key decisions D1–D10 from the original plan live in `docs/GAME_PLAN.md` §0.

| Date | Decision | Reason | Alternatives |
|---|---|---|---|
| 2026-11-19 | Moved `GAME_PLAN.md` from repo root to `docs/GAME_PLAN.md` | CLAUDE.md and plan §3.2 both reference `docs/GAME_PLAN.md` | Keep at root and fix references |
| 2026-11-19 | Development/test device = **iPhone 15 Pro Max**; the high graphics tier is the primary target. The iPhone 7 Plus is not supported | Human's call: wants high-end graphics, old devices are not a priority. The iPhone 7 Plus also can't pair with devicectl (iOS 15 max) | Keep iPhone 11 as the main tuning device (the plan's low tier stays for now; whether to drop it is an open question) |
| 2026-11-19 | Blender 5.3 instead of the plan's "Blender 4.x" | Installed version; preflight glb export + render works | Install 4.x alongside |
| 2026-11-19 | Toolchain smoke tests live in `scripts/preflight.sh` (re-runnable) instead of a one-off folder | Re-run after the human fixes templates/signing/device without redoing work | Manual one-off commands |
