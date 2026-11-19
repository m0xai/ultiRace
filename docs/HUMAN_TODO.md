# Human TODO

Things only the human can do. Claude adds items with exact steps; tick them when done.

## Open

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
