# Human TODO

Things only the human can do. Claude adds items with exact steps; tick them when done.

## Open

### Blocking iOS export / device install (Step 2 preflight)

1. [ ] **Install the Godot 4.7.2 export templates** (needs `ios.zip`):
   Godot editor → *Editor → Manage Export Templates… → Download and Install* (Official 4.7.2).
   Or in a terminal:
   ```bash
   cd ~/Downloads && curl -LO https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz
   mkdir -p ~/Library/Application\ Support/Godot/export_templates/4.7.2.stable
   unzip -j Godot_v4.7.2-stable_export_templates.tpz 'templates/*' -d ~/Library/Application\ Support/Godot/export_templates/4.7.2.stable
   ```
2. [ ] **Create an Apple Development signing identity**: Xcode → *Settings… → Accounts* → `+` →
   Apple ID → select the team → *Manage Certificates…* → `+` → *Apple Development*.
   Check: `security find-identity -v -p codesigning` lists "Apple Development: …".
   A free Personal Team works for device testing (7-day profiles); the paid Apple Developer
   Program is needed later for Game Center, TestFlight and Associated Domains.
3. [ ] **Pair the iPhone 15 Pro Max**: connect by USB, unlock, tap *Trust*; enable
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

## Done

(none yet)
