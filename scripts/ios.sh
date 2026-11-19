#!/usr/bin/env bash
# iOS build helper. Usage: scripts/ios.sh <export|device|run|archive|compile-check>
#   export         Godot headless export → build/ios/UltiRace.xcodeproj (validated)
#   device         export + signed Release build for the connected iPhone
#   run            device + devicectl install + launch
#   archive        export + xcodebuild archive (TestFlight path, M13)
#   compile-check  export + unsigned generic iOS build (CI)
# Env: GODOT, TEAM_ID (default: preset / Xcode personal team), DEVICE_UDID (default: first paired iPhone),
#      CONFIG (Release|Debug, default Release)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
OUT="$REPO/build/ios"
XPROJ="$OUT/UltiRace.xcodeproj"
SCHEME="UltiRace"
CONFIG="${CONFIG:-Release}"
BUNDLE_ID=$(sed -n 's/^application\/bundle_identifier="\(.*\)"/\1/p' "$REPO/godot/export_presets.cfg")
TEAM_ID="${TEAM_ID:-$(sed -n 's/^application\/app_store_team_id="\(.*\)"/\1/p' "$REPO/godot/export_presets.cfg")}"
LOG="$REPO/build/logs"; mkdir -p "$LOG"

die() { echo "ios.sh: $*" >&2; exit 1; }

do_export() {
  rm -rf "$OUT"; mkdir -p "$OUT"
  "$GODOT" --headless --path "$REPO/godot" --import >"$LOG/godot_import.txt" 2>&1 || true
  "$GODOT" --headless --path "$REPO/godot" --export-release "iOS" "$XPROJ" >"$LOG/godot_export.txt" 2>&1 || true
  # Godot exits 0 on failed exports and may leave a half-written project behind.
  [ -d "$XPROJ" ] || die "export failed, see $LOG/godot_export.txt"
  if grep -q 'Project export for preset "iOS" failed' "$LOG/godot_export.txt" \
     || grep -qE '^\s*\$(pbx|additional)_' "$XPROJ/project.pbxproj"; then
    grep -E 'ERROR' "$LOG/godot_export.txt" | head -5 >&2
    die "export failed, see $LOG/godot_export.txt"
  fi
  echo "exported $XPROJ"
}

device_ids() {  # prints "<coredevice-id> <udid>" of the first paired physical iPhone
  xcrun devicectl list devices --json-output "$REPO/build/devices.json" >/dev/null 2>&1 || true
  python3 - "$REPO/build/devices.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))["result"]["devices"]
ok = [x for x in d
      if x.get("hardwareProperties", {}).get("deviceType") == "iPhone"
      and x.get("hardwareProperties", {}).get("reality") != "simulated"
      and x.get("connectionProperties", {}).get("pairingState") == "paired"]
print(ok[0]["identifier"] + " " + ok[0]["hardwareProperties"]["udid"] if ok else "")
EOF
}

do_device() {
  do_export
  local ids; ids=$(device_ids); [ -n "$ids" ] || die "no paired iPhone found (xcrun devicectl list devices)"
  DEVICE_UDID="${DEVICE_UDID:-${ids#* }}"
  xcodebuild -project "$XPROJ" -scheme "$SCHEME" -configuration "$CONFIG" -destination "id=$DEVICE_UDID" \
    -derivedDataPath "$REPO/build/dd-dev" -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
    PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" build >"$LOG/xcode_device.txt" 2>&1 \
    || { grep -E 'error:' "$LOG/xcode_device.txt" | sort -u | head -5 >&2; die "device build failed, see $LOG/xcode_device.txt"; }
  echo "built for device $DEVICE_UDID"
}

do_run() {
  do_device
  local ids dev app; ids=$(device_ids); dev="${ids%% *}"
  app="$REPO/build/dd-dev/Build/Products/$CONFIG-iphoneos/$SCHEME.app"
  [ -d "$app" ] || app=$(find "$REPO/build/dd-dev/Build/Products" -maxdepth 2 -name '*.app' | head -1)
  xcrun devicectl device install app --device "$dev" "$app" >"$LOG/devicectl.txt" 2>&1 \
    || { tail -5 "$LOG/devicectl.txt" >&2; die "install failed"; }
  xcrun devicectl device process launch --terminate-existing --device "$dev" "$BUNDLE_ID" >>"$LOG/devicectl.txt" 2>&1 \
    || { tail -5 "$LOG/devicectl.txt" >&2; die "launch failed (first run: trust the developer in Settings → General → VPN & Device Management)"; }
  echo "installed and launched $BUNDLE_ID on $dev"
}

do_archive() {
  do_export
  xcodebuild -project "$XPROJ" -scheme "$SCHEME" -configuration Release -destination 'generic/platform=iOS' \
    -archivePath "$REPO/build/UltiRace.xcarchive" -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic archive >"$LOG/xcode_archive.txt" 2>&1 \
    || die "archive failed, see $LOG/xcode_archive.txt"
  echo "archived build/UltiRace.xcarchive"
}

do_compile_check() {
  do_export
  xcodebuild -project "$XPROJ" -scheme "$SCHEME" -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath "$REPO/build/dd-check" CODE_SIGNING_ALLOWED=NO build >"$LOG/xcode_check.txt" 2>&1 \
    || { grep -E 'error:' "$LOG/xcode_check.txt" | sort -u | head -5 >&2; die "compile check failed"; }
  echo "unsigned iOS compile ok"
}

case "${1:-}" in
  export) do_export;; device) do_device;; run) do_run;; archive) do_archive;;
  compile-check) do_compile_check;;
  *) die "usage: $0 <export|device|run|archive|compile-check>";;
esac
