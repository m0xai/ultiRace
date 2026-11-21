# Human TODO

Things only the human can do. Claude adds items with exact steps; tick them when done.

## Open

### Reviews (2026-11-21)

24. [x] (approved 2026-11-21: "looks really nice") **Review the UI overhaul** (on the phone or `docs/screenshots/ui2_*.png`): Racing Sans One
    font, home with the Quick Play / Practice / Rooms switcher, settings in two columns (scrolling
    should no longer be needed), switchers instead of dropdowns in lobby and room browser.
25. [x] (approved 2026-11-21) **Review graphics pass 4**: `docs/screenshots/gfx4_*.png` (asphalt, raised curbs, W-beam
    rails, ice/water/oil patches, new road blocks with chevron signs, start gantry).
27. [ ] **Listen check, audio pass 2** (on the phone):
    - Engines: every car has its own engine now (Bolt V10, Rhino V8, Glacier turbo I6, Volt
      electric, Hook rally turbo I4 with pops, Goo boxer, Phantom V12, Twister rotary) with gears,
      shift cuts, a rev limiter on boosts and over-run crackle when you lift/brake. Quick listen
      on the Mac: `afplay build/engine_demo.mp3` (each car: idle → full throttle through the gears
      → limiter → lift off; regenerate with `build/venv/bin/python art/audio/demo_engines.py
      godot/assets/audio build/engine_demo.wav`). Say per car what to change ("Rhino too boomy",
      "Bolt too thin"). If they still sound synthetic, Claude switches to the CC0 recordings of
      muted.io's *Performance Cars* pack (needs a per-RPM loop edit).
    - Music (CC0 by MintoDog, OpenGameArt): menu *Cool City*, Sunny *Pure Raceway*, Neon *Neon
      Sign Circuit*, Frosty *Blossom Mountain*; each switches to its faster **climax** mix on the
      final lap; results play *Racing Game Result* best/good/bad. Alternatives already checked as
      CC0: *Racing Game Menu* (more energetic menu), *Darkness Road*, *City on Speed*, *Hyperflight
      Racing*.
28. [ ] **Tilt check:** Settings → Tilt to steer. The steer buttons are gone in tilt mode (your thumb
    on the left button was the "always left"), and tilt now works held upright or nearly flat.
29. [ ] **Delete the old generated audio** (Claude may not delete repo files): `git rm
    godot/assets/audio/engine_*.wav* godot/assets/audio/music_*.wav*` — unused since audio pass 2
    and already excluded from the export.
26. [ ] **FYI, Simulator:** `make ios-sim` builds and launches on an iPhone 11 simulator, but the game
    freezes after the home screen (OpenGL ES fallback, see `docs/IPHONE11_SIM.md`); skipped as you
    said. `make iphone11` (Mac emulation) and the real phone remain the test paths.

### Blocking M11 (server live)

17. [ ] **Deploy the server to flappus** following `docs/DEPLOY.md` (DNS record
    `ultirace.flappus.com`, docker build, `.env` with a random `ID_SECRET`, compose up, Caddy
    snippet + reload). Tell Claude when `https://ultirace.flappus.com/healthz` answers; Claude then
    switches the app's default server and runs the public-play e2e against it.

### Blocking M10 (Game Center) and M13/M14 (TestFlight / App Store)

15. [ ] **Join the paid Apple Developer Program** (99 USD/year): developer.apple.com → Account →
    Enroll. Needed for Game Center, Associated Domains (room links), TestFlight and the App Store.
    Then tell Claude the new **Team ID** (Membership details).
16. [ ] After enrolling, in **App Store Connect** (appstoreconnect.apple.com → Apps → +): create the
    app with bundle ID `com.flappus.ultirace`, enable **Game Center**, and create:
    leaderboards `best_lap_sunny`, `best_lap_neon`, `best_lap_frosty` (time, low to high),
    `weekly_wins` (integer, high to low, recurring weekly); achievements are listed in
    `docs/DEPLOY.md` when M10 is unblocked.

### Blocking iOS export / device install (Step 2 preflight)

00. [x] **Trust the developer on the iPhone** (done) (blocks app launch; install already works):
    *Settings → General → VPN & Device Management → Apple Development: m0xai@icloud.com → Trust*.
    Free Personal Team profiles expire after 7 days: re-run `make ios-run` then.

0. [x] **Enable Developer Mode on the iPhone 15 Pro Max** (done): iPhone →
   *Settings → Privacy & Security → Developer Mode* → on → restart → confirm *Turn On* after
   reboot. (If the toggle is missing, open Xcode → *Window → Devices and Simulators* with the
   phone connected once; it appears then.) The phone is already paired.
   After the first install, iOS may also need: *Settings → General → VPN & Device Management →
   Apple Development: … → Trust*.

1. [x] ~~Install the Godot 4.7.2 export templates~~ (done by Claude 2026-11-19, SHA-512 verified):
   Godot editor → *Editor → Manage Export Templates… → Download and Install* (Official 4.7.2).
   Or in a terminal:
   ```bash
   cd ~/Downloads && curl -LO https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz
   mkdir -p ~/Library/Application\ Support/Godot/export_templates/4.7.2.stable
   unzip -j Godot_v4.7.2-stable_export_templates.tpz 'templates/*' -d ~/Library/Application\ Support/Godot/export_templates/4.7.2.stable
   ```
2. [ ] (probably not needed: xcodebuild `-allowProvisioningUpdates` should create it via the
   Personal Team already signed in to Xcode; check after item 0) **Create an Apple Development signing identity**: Xcode → *Settings… → Accounts* → `+` →
   Apple ID → select the team → *Manage Certificates…* → `+` → *Apple Development*.
   Check: `security find-identity -v -p codesigning` lists "Apple Development: …".
   A free Personal Team works for device testing (7-day profiles); the paid Apple Developer
   Program is needed later for Game Center, TestFlight and Associated Domains.
3. [x] ~~Pair the iPhone 15 Pro Max~~ (paired, `00008130-001125A80A20001C`): connect by USB, unlock, tap *Trust*; enable
   *Settings → Privacy & Security → Developer Mode* (restart the phone). Open Xcode →
   *Window → Devices and Simulators* once so it prepares the device. Check:
   `xcrun devicectl list devices` shows it with state `available (paired)`.
   Optional: *Connect via network* in that window for cable-free installs.
4. [ ] When the first signed build runs, macOS may show a **keychain prompt** for
   `codesign`: click *Always Allow*.

After 1–3: run `scripts/preflight.sh` (or tell Claude to continue).

### Not blocking

5. [ ] (optional) Install GitHub CLI: `brew install gh && gh auth login` (pushes work over SSH without it; `gh` is only for CI status/PRs).
6. [ ] Add the Claude Code permission rules below to `.claude/settings.json` (file doesn't exist yet).

### Permission rules to add (`.claude/settings.json`)

```json
{
  "permissions": {
    "allow": [
      "Bash(go:*)", "Bash(gofmt:*)", "Bash(make:*)",
      "Bash(git status:*)", "Bash(git diff:*)", "Bash(git log:*)", "Bash(git show:*)",
      "Bash(git add:*)", "Bash(git commit:*)", "Bash(git mv:*)", "Bash(git rm:*)",
      "Bash(git push origin:*)", "Bash(git fetch:*)", "Bash(git ls-remote:*)",
      "Bash(gh run:*)", "Bash(gh pr:*)", "Bash(gh auth status)",
      "Bash(/Applications/Godot.app/Contents/MacOS/Godot:*)",
      "Bash(/Applications/Blender.app/Contents/MacOS/Blender:*)",
      "Bash(xcodebuild:*)", "Bash(xcrun simctl:*)", "Bash(xcrun devicectl:*)",
      "Bash(security find-identity:*)", "Bash(security find-certificate:*)",
      "Bash(openssl x509:*)",
      "Bash(scripts/doctor.sh:*)", "Bash(scripts/preflight.sh:*)", "Bash(./art/export.sh:*)",
      "Bash(docker build:*)", "Bash(docker run --rm:*)", "Bash(docker compose config:*)",
      "Bash(curl -s http://127.0.0.1:*)", "Bash(curl -s http://localhost:*)",
      "Bash(python3:*)", "Bash(file:*)", "Bash(unzip:*)", "Bash(shasum:*)",
      "Bash(rm -rf build/:*)", "Bash(mkdir:*)", "Bash(chmod +x:*)", "Bash(ls:*)", "Bash(find:*)"
    ],
    "deny": [
      "Bash(sudo:*)", "Bash(ssh:*)", "Bash(scp:*)", "Bash(rsync:*)",
      "Bash(git push --force:*)", "Bash(git push -f:*)", "Bash(git reset --hard:*)",
      "Bash(git rebase:*)", "Bash(brew:*)"
    ]
  }
}
```

### Dev-session convenience (not blocking)

9. [ ] While Claude works on the app, keep the iPhone **unlocked, on the same Wi-Fi and
   connected** (e.g. *Settings → Display & Brightness → Auto-Lock → Never* while charging, set it
   back afterwards). iOS refuses to launch apps on a locked phone, so on-device checks wait.

### Reviews (not blocking)

13. [ ] **Listen/feel check M9** on the phone: engine sounds, effects, music per map, haptics
    (countdown, wall hits, spin-outs, ULT ready, start boost). Also check the **silent switch**:
    with it on, the game should be silent (iOS "Ambient" audio session) and your own music app
    should keep playing. All sounds are generated by `art/audio/gen_audio.py` — tell Claude what
    to change (e.g. "engine too buzzy", "music too loud").
14. [ ] **Support contact for App Store guideline 1.2:** which email address should be shown in
    Settings for abuse reports / help? (Set `SUPPORT_CONTACT` in `godot/src/app/screens/SettingsScreen.gd`
    or tell Claude.)

19. [ ] **Review the A2 menus** on the phone (Home, Settings, Choose your car with the 3D
    showroom, countdown, results with confetti) or `docs/screenshots/a2_*.png`. Say what to
    change (font, colours, button style, animations).

18. [ ] **Review the A3 track look** on the phone or in `docs/screenshots/a3_*.png`: Neon city
    (lit windows, neon signs, skyline, stars), day maps (pine/leafy trees, snow-capped
    mountains and hills on the horizon, grass texture), asphalt, lane lines, guard rails, lamps,
    clouds, billboards. Say what to change (colours, density, anything that looks off).

23. [ ] **Review the high-poly cars (v5)** on the phone (showroom + your own car in races) or
    `docs/screenshots/a1_v5*.png`. Also tell Claude if races stay smooth on the iPhone 15 Pro Max.

22. [ ] (superseded by 23) **Review the mid-poly cars (v4)** on the phone or `docs/screenshots/a1_v4.png` /
    `art/previews/*.png`: shape per car, proportions, details, wheels, colours.

21. [ ] (superseded by 22) **Review the boxy cars (v3)** on the phone or `docs/screenshots/a1_boxy.png` and
    `art/previews/*.png`: proportions per car, colours, how boxy/voxel they should be, lighting.
    (The old smooth cars can still be built with `CARS_DIR=cars2 make assets`.)

20. [ ] (superseded by 21) **Review the car detail pass** on the phone or in `docs/screenshots/a1_detail.png` /
    `art/previews/*.png`: headlights, tail lights, grilles, plates, panel lines, mirrors,
    wipers, calipers. Also tell Claude whether the cars still flicker in races (and when:
    near/far cars, in turns, on which map).

12. [ ] **Review A1 cars (v2):** turntables `art/previews/<car>.png` (4 angles each) and
    in-game `docs/screenshots/a1_grid.png`. Say per car what to change (shape, proportions,
    colours, signature part). Cars are generated by `art/blender/cars/<car>.py`; Claude edits
    the script and re-runs `make assets`.

7. [ ] **Review M3 visuals** (placeholder look, final art comes in M8): `docs/screenshots/m3_*.png`.
   Try it yourself: `/Applications/Godot.app/Contents/MacOS/Godot --path godot res://src/render/MapViewer.tscn`
   (WASD/QE fly, right-drag look, keys 1/2/3 switch maps). Tell Claude anything about track
   shapes, widths, corners or the bridge you want changed.
11. [ ] **Feel check M7 (prediction):** the build on your phone now predicts your own car
    (steering should react instantly). Steering direction was fixed. Tell Claude if the car
    jitters/rubber-bands, especially when hit by ULTs or bumping into cars.
10. [ ] **Play a race on the phone (feel check, M5):** Home → Practice vs bots → READY → pick a car
    → race with the two steer buttons. Known: your car reacts ~100 ms late until M7 adds
    prediction. Tell Claude what feels off (button size/position, camera, speed, steering).
    Install: `SERVER_URL=ws://<Mac IP>:8090 make ios-run` with the dev server running
    (`go run ./cmd/server -addr 0.0.0.0:8090`).
8. [x] (answered 2026-11-19: keep the iPhone 11 low tier for now) **Decide:** keep the iPhone 11 "low" graphics tier, or target only recent iPhones
   (you said high-end graphics matter more)? Until answered the plan stays as written.

## Done

(none yet)
