#!/usr/bin/env bash
# Toolchain smoke tests (Step 2 of the bootstrap). Re-runnable; works in build/preflight/ and
# deletes it at the end (KEEP=1 keeps it). Prints PASS/FAIL/SKIP per step; exit = number of FAILs.
#
#   a  Go build + run + linux/amd64 static cross-compile
#   b  Godot headless GDScript, exit code 0
#   c  Godot headless iOS export → Xcode project          (needs ios.zip export template)
#   d1 xcodebuild for iOS Simulator, install + launch     (needs c)
#   d2 signed device build, devicectl install + launch    (needs c, signing identity, device)
#   e  Blender headless bevelled cube → .glb + 256px PNG, then Godot headless import
#   f  Godot windowed run, viewport screenshot PNG after 2 s
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
GODOT_VER="$(cat "$REPO/godot/VERSION" 2>/dev/null || echo 4.7.2.stable)"
TEMPLATE="$HOME/Library/Application Support/Godot/export_templates/$GODOT_VER/ios.zip"
BUNDLE_ID="${BUNDLE_ID:-com.flappus.ultirace.preflight}"
MIN_IOS="${MIN_IOS:-16.0}"
W="$REPO/build/preflight"
OUT="$REPO/build/preflight-out"   # survives cleanup: screenshots/renders for review
LOG="$W/logs"

fails=0
pass() { printf 'PASS  %-4s %s\n' "$1" "$2"; }
fail() { printf 'FAIL  %-4s %s\n' "$1" "$2"; fails=$((fails + 1)); }
skip() { printf 'SKIP  %-4s %s\n' "$1" "$2"; }

rm -rf "$W"; mkdir -p "$W/go" "$W/godot" "$W/blender" "$W/ios" "$LOG" "$OUT"

# ---------- a: Go ----------
cat > "$W/go/main.go" <<'EOF'
package main

import (
	"fmt"
	"runtime"
)

func main() { fmt.Printf("hello from %s/%s\n", runtime.GOOS, runtime.GOARCH) }
EOF
( cd "$W/go" && go mod init preflight >/dev/null 2>&1 && go build -o hello . && ./hello >"$LOG/go.txt" \
  && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o hello-linux . ) \
  && file "$W/go/hello-linux" | grep -q 'ELF 64-bit.*x86-64.*statically linked' \
  && pass a "go build/run ok ($(cat "$LOG/go.txt")), linux/amd64 static ELF ok" \
  || fail a "go smoke test failed"

# ---------- Godot minimal project ----------
P="$W/godot"
cat > "$P/project.godot" <<'EOF'
config_version=5

[application]

config/name="Preflight"
run/main_scene="res://main.tscn"
config/features=PackedStringArray("4.7", "Mobile")
config/icon="res://icon.png"

[rendering]

renderer/rendering_method="mobile"
textures/vram_compression/import_etc2_astc=true
EOF
cat > "$P/hello.gd" <<'EOF'
extends SceneTree

func _init() -> void:
	var n: int = 6 * 7
	print("godot headless ok: ", n, " ", Engine.get_version_info().string)
	quit(0)
EOF
cat > "$P/make_icon.gd" <<'EOF'
extends SceneTree

## iOS export requires an app icon; without one Godot aborts mid-export and leaves a broken
## .xcodeproj (unreplaced $placeholders) while still exiting 0.
func _init() -> void:
	var img: Image = Image.create(1024, 1024, false, Image.FORMAT_RGB8)
	img.fill(Color(1.0, 0.8, 0.1))
	quit(0 if img.save_png("res://icon.png") == OK else 1)
EOF
cat > "$P/main.gd" <<'EOF'
extends Node3D

## Preflight scene: shows the Blender cube if present; with `-- --shot <path>` saves a
## viewport PNG after 2 s and quits.

var _shot_path: String = ""

func _ready() -> void:
	if ResourceLoader.exists("res://cube.glb"):
		var cube_scene: PackedScene = load("res://cube.glb") as PackedScene
		add_child(cube_scene.instantiate() as Node3D)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = args.find("--shot")
	if i >= 0 and i + 1 < args.size():
		_shot_path = args[i + 1]
		get_tree().create_timer(2.0).timeout.connect(_take_shot)

func _process(delta: float) -> void:
	rotation.y += delta * 0.5

func _take_shot() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var err: Error = img.save_png(_shot_path)
	print("SCREENSHOT ", _shot_path, " err=", err, " size=", img.get_size())
	get_tree().quit(0 if err == OK else 1)
EOF
cat > "$P/main.tscn" <<'EOF'
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://main.gd" id="1"]

[sub_resource type="Environment" id="env"]
background_mode = 1
background_color = Color(0.3, 0.35, 0.45, 1)
ambient_light_source = 2
ambient_light_color = Color(0.6, 0.6, 0.7, 1)

[node name="Main" type="Node3D"]
script = ExtResource("1")

[node name="Camera3D" type="Camera3D" parent="."]
transform = Transform3D(0.7071, -0.3, 0.64, 0, 0.906, 0.423, -0.7071, -0.3, 0.64, 3.5, 2.8, 3.5)
current = true

[node name="Sun" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.8, -0.4, 0.45, 0, 0.75, 0.66, -0.6, -0.53, 0.6, 0, 5, 0)

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("env")
EOF
cat > "$P/check_glb.gd" <<'EOF'
extends SceneTree

func _init() -> void:
	var ps: PackedScene = load("res://cube.glb") as PackedScene
	var n: Node = ps.instantiate()
	var meshes: Array[Node] = n.find_children("*", "MeshInstance3D", true, false)
	var tris: int = 0
	for m: Node in meshes:
		tris += (m as MeshInstance3D).mesh.get_faces().size() / 3
	print("GLB_OK meshes=", meshes.size(), " tris=", tris)
	n.free()
	quit(0 if meshes.size() > 0 else 1)
EOF

# ---------- b: Godot headless ----------
if "$GODOT" --headless --path "$P" --script res://hello.gd >"$LOG/godot_b.txt" 2>&1 \
   && grep -q 'godot headless ok: 42' "$LOG/godot_b.txt"; then
  pass b "$(grep 'godot headless ok' "$LOG/godot_b.txt")"
else fail b "godot headless script (see $LOG/godot_b.txt)"; fi

# ---------- e: Blender → glb → Godot ----------
cat > "$W/blender/cube.py" <<'EOF'
import bpy, sys, os
out = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=2)
cube = bpy.context.active_object
mod = cube.modifiers.new("bevel", "BEVEL"); mod.width = 0.15; mod.segments = 3
mat = bpy.data.materials.new("Yellow"); mat.use_nodes = True
mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (1.0, 0.8, 0.1, 1)
cube.data.materials.append(mat)
bpy.ops.object.shade_smooth()
bpy.ops.export_scene.gltf(filepath=os.path.join(out, "cube.glb"), export_format="GLB", export_apply=True)
bpy.ops.object.camera_add(location=(4, -4, 3), rotation=(1.1, 0, 0.785))
bpy.context.scene.camera = bpy.context.active_object
bpy.ops.object.light_add(type="SUN", location=(2, -2, 5)); bpy.context.active_object.data.energy = 4
w = bpy.data.worlds.new("w"); bpy.context.scene.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.3, 0.35, 0.45, 1)
s = bpy.context.scene
engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
s.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in engines else "BLENDER_EEVEE_NEXT"
s.render.resolution_x = s.render.resolution_y = 256
s.render.filepath = os.path.join(out, "cube.png")
bpy.ops.render.render(write_still=True)
print("BLENDER_SMOKE_OK", s.render.engine)
EOF
if "$BLENDER" --background --factory-startup --python "$W/blender/cube.py" -- "$W/blender" >"$LOG/blender.txt" 2>&1 \
   && [ -s "$W/blender/cube.glb" ] && [ -s "$W/blender/cube.png" ]; then
  cp "$W/blender/cube.glb" "$P/"; cp "$W/blender/cube.png" "$OUT/blender_cube.png"
  "$GODOT" --headless --path "$P" --import >"$LOG/godot_import.txt" 2>&1
  if "$GODOT" --headless --path "$P" --script res://check_glb.gd >"$LOG/godot_glb.txt" 2>&1 \
     && grep -q GLB_OK "$LOG/godot_glb.txt"; then
    pass e "blender glb+png ok, godot import: $(grep -o 'GLB_OK.*' "$LOG/godot_glb.txt") (render: $OUT/blender_cube.png)"
  else fail e "godot could not load cube.glb (see $LOG/godot_glb.txt)"; fi
else fail e "blender script failed (see $LOG/blender.txt)"; fi

# ---------- f: Godot windowed screenshot ----------
SHOT="$OUT/godot_screenshot.png"; rm -f "$SHOT"
"$GODOT" --path "$P" --resolution 640x360 --position 0,0 --quit-after 900 -- --shot "$SHOT" >"$LOG/godot_shot.txt" 2>&1
if [ -s "$SHOT" ]; then pass f "screenshot $SHOT ($(grep -o 'Metal[^-]*- [A-Za-z ]*' "$LOG/godot_shot.txt" | head -1))"
else fail f "no screenshot (see $LOG/godot_shot.txt)"; fi

# ---------- c: Godot iOS export ----------
IDENT=$(security find-identity -v -p codesigning 2>/dev/null | grep 'Apple Development' | head -1)
TEAM_ID=""
if [ -n "$IDENT" ]; then
  CN=$(echo "$IDENT" | sed -n 's/.*"\(.*\)".*/\1/p')
  TEAM_ID=$(security find-certificate -c "$CN" -p 2>/dev/null | openssl x509 -noout -subject -nameopt multiline 2>/dev/null \
            | awk -F' = ' '/organizationalUnitName/ {print $2; exit}')
fi
# No certificate yet: fall back to the team of the Apple ID signed into Xcode;
# xcodebuild -allowProvisioningUpdates then creates the development certificate itself.
if [ -z "$TEAM_ID" ]; then
  TEAM_ID=$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null \
            | sed -n 's/.*teamID = \([A-Z0-9]\{10\}\);.*/\1/p' | head -1)
fi
TEAM_ID="${TEAM_ID_OVERRIDE:-$TEAM_ID}"
# Godot refuses to export without a Team ID even for project-only exports. The simulator build
# is unsigned, so a placeholder works there; d2 (device) still requires the real TEAM_ID.
EXPORT_TEAM="${TEAM_ID:-ABCDE12345}"
cat > "$P/export_presets.cfg" <<EOF
[preset.0]

name="iOS"
platform="iOS"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path="../ios/Preflight.xcodeproj"

[preset.0.options]

application/app_store_team_id="$EXPORT_TEAM"
application/bundle_identifier="$BUNDLE_ID"
application/short_version="0.0.1"
application/version="1"
application/export_project_only=true
application/min_ios_version="$MIN_IOS"
icons/icon_1024x1024="res://icon.png"
application/code_sign_identity_debug="Apple Development"
application/code_sign_identity_release="Apple Development"
EOF
"$GODOT" --headless --path "$P" --script res://make_icon.gd >"$LOG/godot_icon.txt" 2>&1
"$GODOT" --headless --path "$P" --import >>"$LOG/godot_icon.txt" 2>&1
XPROJ="$W/ios/Preflight.xcodeproj"
exported=0
if [ ! -f "$TEMPLATE" ]; then skip c "no iOS export template at $TEMPLATE"
else
  "$GODOT" --headless --path "$P" --export-release "iOS" "$XPROJ" >"$LOG/godot_export.txt" 2>&1
  # Godot exits 0 even on failure; also reject a half-written project with unreplaced $placeholders.
  if [ -d "$XPROJ" ] && ! grep -q 'Project export for preset "iOS" failed' "$LOG/godot_export.txt" \
     && ! grep -qE '^\s*\$(pbx|additional)_' "$XPROJ/project.pbxproj"; then exported=1; pass c "exported $XPROJ (team ${TEAM_ID:-none})"
  else fail c "iOS export failed (see $LOG/godot_export.txt)"; fi
fi

# ---------- d1: simulator build ----------
# Godot 4.7.2's official simulator slice is x86_64-only, and the iOS 27 simulator no longer
# runs x86_64 apps, so on Apple Silicon there is nothing to build until templates ship arm64.
SIMLIB=$(find "$W/ios" -path '*simulator*/libgodot.a' 2>/dev/null | head -1)
SCHEME=$(xcodebuild -list -project "$XPROJ" 2>/dev/null | awk '/Schemes:/ {getline; gsub(/^ +/, ""); print; exit}')
if [ "$exported" -eq 1 ] && [ -n "$SIMLIB" ] && ! lipo -archs "$SIMLIB" 2>/dev/null | grep -q arm64; then
  skip d1 "template simulator libgodot.a is $(lipo -archs "$SIMLIB") only (no arm64 slice); see docs/TOOLCHAIN.md"
elif [ "$exported" -eq 1 ]; then
  if xcodebuild -project "$XPROJ" -scheme "$SCHEME" -configuration Release -sdk iphonesimulator \
       -destination 'generic/platform=iOS Simulator' -derivedDataPath "$W/dd-sim" \
       CODE_SIGNING_ALLOWED=NO build >"$LOG/xcode_sim.txt" 2>&1; then
    APP=$(find "$W/dd-sim/Build/Products" -maxdepth 2 -name '*.app' | head -1)
    SIM=$(xcrun simctl list devices available 2>/dev/null | grep -E 'iPhone' | head -1 | grep -oE '[0-9A-F-]{36}')
    if [ -n "$SIM" ] && xcrun simctl boot "$SIM" >/dev/null 2>&1; [ -n "$SIM" ] \
       && xcrun simctl install "$SIM" "$APP" >>"$LOG/xcode_sim.txt" 2>&1 \
       && xcrun simctl launch "$SIM" "$BUNDLE_ID" >>"$LOG/xcode_sim.txt" 2>&1; then
      sleep 5; xcrun simctl io "$SIM" screenshot "$OUT/simulator.png" >/dev/null 2>&1
      xcrun simctl terminate "$SIM" "$BUNDLE_ID" >/dev/null 2>&1; xcrun simctl shutdown "$SIM" >/dev/null 2>&1
      pass d1 "simulator build + install + launch ok (screenshot $OUT/simulator.png)"
    else fail d1 "simulator build ok, install/launch failed (see $LOG/xcode_sim.txt)"; fi
  else fail d1 "simulator build failed (see $LOG/xcode_sim.txt)"; fi
else skip d1 "needs step c"; fi

# ---------- d2: signed device build ----------
DEV=$(xcrun devicectl list devices --json-output "$W/devices.json" >/dev/null 2>&1; \
      python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["result"]["devices"]
ok=[x for x in d if x.get("hardwareProperties",{}).get("deviceType")=="iPhone" and x.get("hardwareProperties",{}).get("reality")!="simulated" and x.get("connectionProperties",{}).get("pairingState")=="paired"]
print(ok[0]["identifier"] + " " + ok[0]["hardwareProperties"]["udid"] if ok else "")' "$W/devices.json" 2>/dev/null)
DEV_UDID="${DEV#* }"; DEV="${DEV%% *}"
if [ "$exported" -ne 1 ]; then skip d2 "needs step c"
elif [ -z "$TEAM_ID" ]; then skip d2 "no Apple Development signing identity / Team ID"
elif [ -z "$DEV" ]; then skip d2 "no paired iPhone (devicectl pairingState=paired)"
else
  # A concrete device destination + -allowProvisioningDeviceRegistration lets a free Personal
  # Team register the iPhone and create its development profile automatically.
  if xcodebuild -project "$XPROJ" -scheme "$SCHEME" -configuration Release -destination "id=$DEV_UDID" \
       -derivedDataPath "$W/dd-dev" -allowProvisioningUpdates -allowProvisioningDeviceRegistration DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
       PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" build >"$LOG/xcode_dev.txt" 2>&1; then
    APP=$(find "$W/dd-dev/Build/Products" -maxdepth 2 -name '*.app' | head -1)
    if xcrun devicectl device install app --device "$DEV" "$APP" >>"$LOG/xcode_dev.txt" 2>&1 \
       && xcrun devicectl device process launch --device "$DEV" "$BUNDLE_ID" >>"$LOG/xcode_dev.txt" 2>&1; then
      pass d2 "signed build installed + launched on device $DEV"
    else fail d2 "device install/launch failed (see $LOG/xcode_dev.txt)"; fi
  else fail d2 "signed device build failed (see $LOG/xcode_dev.txt)"; fi
fi

echo
if [ "$fails" -eq 0 ]; then echo "preflight: no failures (check SKIPs above)"; else echo "preflight: $fails failure(s); logs in $LOG"; fi
if [ "${KEEP:-0}" != 1 ]; then
  [ "$fails" -eq 0 ] && rm -rf "$W" || echo "keeping $W for inspection (failures)"
fi
exit "$fails"
