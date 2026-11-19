# Progress

A new session must be able to continue from this file alone. Read `CLAUDE.md` and
`docs/GAME_PLAN.md` first, then this file, `docs/HUMAN_TODO.md` and `docs/TOOLCHAIN.md`.

## Current status (2026-11-19)

- Step 1 done: `docs/GAME_PLAN.md` (moved from root), `MILESTONES.md`, `DECISIONS.md`, this file.
- Step 2 (toolchain preflight) mostly done: `scripts/doctor.sh`, `scripts/preflight.sh`,
  `docs/TOOLCHAIN.md`.
  - PASS: Go build + linux/amd64 static cross-compile; Godot headless script; Blender headless
    bevelled cube → .glb + PNG → Godot headless import; Godot windowed screenshot (Metal 4,
    Mobile renderer); Xcode 27.2 + iOS SDK + simulator runtime; Docker.
  - **WAITING FOR HUMAN** (blocks iOS export + device install, `docs/HUMAN_TODO.md` items 1–3):
    Godot 4.7.2 iOS export template, Apple Development signing identity, pairing the
    iPhone 15 Pro Max.
- No game code yet.

## Next steps

1. When the human confirms items 1–3 in HUMAN_TODO: run `scripts/preflight.sh`; steps c, d1
   and d2 must PASS (export, simulator, signed device install + launch). If codesign shows a
   keychain dialog, tell the human in one short message and wait. Then update
   `docs/TOOLCHAIN.md` (mark c/d verified, record the Team ID and min iOS version).
2. M0: Go module + layout (§3.2), `godot/` project with `VERSION`, gdUnit4, iOS preset,
   Makefile targets from TOOLCHAIN.md, `.github/workflows/ci.yml`, empty scene on the iPhone.

## Open questions

- Keep the iPhone 11 low tier (plan §1, §4.2, §8), or raise the minimum device now that the
  high tier is the priority? Until answered, the plan stays as written, tuned on the 15 Pro Max.
- Minimum iOS version: preflight uses 16.0; decide in M0 (plan §7.2).
- Bundle ID: proposal `com.flappus.ultirace`.
- Repo name in the plan is `ultirace-ios`; the actual repo is `ultiRace` (github.com/m0xai/ultiRace).

## Blocked

- iOS export / simulator / device steps: see HUMAN_TODO items 1–3.
