# Toolchain

Checked 2026-11-19 on the Mac mini (Apple M2 Pro, 10 cores, 16 GB, macOS 26.6.2).
Re-check anytime: `scripts/doctor.sh` (versions, PASS/FAIL) and `scripts/preflight.sh`
(real smoke tests in `build/preflight/`, deleted afterwards; review images land in
`build/preflight-out/`, which is git-ignored).

## Tools and paths

| Tool | Path | Version | Status |
|---|---|---|---|
| Go | `/usr/local/go/bin/go` | 1.24.2 | ✅ |
| git | `/opt/homebrew/bin/git` | 2.56.1; origin `git@github.com:m0xai/ultiRace.git` reachable over SSH | ✅ |
| gh | — | not installed | ❌ human (optional; git over SSH works for push) |
| Godot | `/Applications/Godot.app/Contents/MacOS/Godot` | 4.7.2.stable.official.ed1daf0bf, Metal 4.0 | ✅ |
| Godot iOS export template | `~/Library/Application Support/Godot/export_templates/4.7.2.stable/ios.zip` | — | ❌ missing, human |
| Blender | `/Applications/Blender.app/Contents/MacOS/Blender` | 5.3.0 (plan says 4.x; 5.x works, see below) | ✅ |
| Xcode | `/Applications/Xcode.app/Contents/Developer` | Xcode 27.2 (27B52), iOS SDK 27.2, simulator runtime iOS 27.2 | ✅ |
| Signing | `security find-identity -v -p codesigning` | 0 identities | ❌ human |
| Device | `xcrun devicectl list devices` | only an iPhone 7 Plus (`iPhone9,4`, pairingState `unsupported`) | ❌ human: pair the iPhone 15 Pro Max |
| Docker | `/usr/local/bin/docker` | 28.1.1 | ✅ (for `deploy/` image builds) |
| make | `/usr/bin/make` | GNU Make 3.81 (old: no `.ONESHELL`, no `file` function) | ✅ |
| python3, openssl, curl, unzip | Homebrew / system | — | ✅ |

## Working commands (become Makefile targets)

```bash
G=/Applications/Godot.app/Contents/MacOS/Godot
B=/Applications/Blender.app/Contents/MacOS/Blender

# Go: build, run, static linux/amd64 (server image)
go build ./... && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o build/server-linux ./cmd/server

# Godot headless script (exit code from quit(n) is propagated)
$G --headless --path godot --script res://path/to/script.gd

# Godot headless import (needed before first headless run / after new assets)
$G --headless --path godot --import

# Godot windowed run + screenshot (the project's script reads `-- --shot <png>`)
$G --path godot --resolution 1280x720 --position 0,0 --quit-after 900 -- --shot docs/screenshots/x.png

# Blender headless asset script (args after `--`)
$B --background --factory-startup --python art/blender/cars/bolt.py -- <outdir>

# Godot iOS export → Xcode project (needs ios.zip template; preset "iOS" in export_presets.cfg)
$G --headless --path godot --export-release "iOS" build/ios/UltiRace.xcodeproj

# Simulator build (no signing)
xcodebuild -project build/ios/UltiRace.xcodeproj -scheme UltiRace -configuration Release \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/dd-sim CODE_SIGNING_ALLOWED=NO build
xcrun simctl boot <UDID>; xcrun simctl install <UDID> <App.app>; xcrun simctl launch <UDID> <bundle-id>
xcrun simctl io <UDID> screenshot out.png

# Signed device build + install + launch
TEAM_ID=$(security find-certificate -c "Apple Development: …" -p | openssl x509 -noout -subject -nameopt multiline | awk -F' = ' '/organizationalUnitName/{print $2}')
xcodebuild -project build/ios/UltiRace.xcodeproj -scheme UltiRace -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/dd-dev -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=$TEAM_ID CODE_SIGN_STYLE=Automatic build
xcrun devicectl device install app --device <identifier> build/dd-dev/Build/Products/Release-iphoneos/UltiRace.app
xcrun devicectl device process launch --device <identifier> <bundle-id>
```

Steps c/d (export, simulator, device) are written in `scripts/preflight.sh` but **not yet
verified** (template, signing and device missing). Update this file once they pass.

## Surprises / gotchas

- **No `timeout`/`gtimeout` on macOS.** Use Godot's own `--quit-after <frames>` and
  `get_tree().quit(code)` instead of wrapping commands.
- **Godot `--export-release` returns exit 0 even when the export fails** (e.g. missing
  template). Check that the output `.xcodeproj` exists instead of trusting the exit code.
- Godot iOS presets need `include_filter` / `exclude_filter` keys or Godot logs config errors.
- zsh is the login shell: `PIPESTATUS` doesn't exist (it's `pipestatus`); scripts use bash shebangs.
- Blender 5.3: `bpy.ops.wm.read_factory_settings(use_empty=True)` + `--factory-startup` gives a
  clean deterministic scene; EEVEE engine id is `BLENDER_EEVEE` (older versions: `BLENDER_EEVEE_NEXT`
  — the script picks whichever exists). Render of a 256 px still takes ~4 s.
- Windowed Godot runs open a real window on the Mac's screen for ~2 s (needs a logged-in GUI
  session; works from Claude's shell).
- The connected iPhone 7 Plus can't be used: CoreDevice reports `pairingState: unsupported`
  (devicectl needs iOS 17+). Development device is the **iPhone 15 Pro Max**.
- Team ID is the certificate's **OU** field, not the 10-char suffix in the identity name.
