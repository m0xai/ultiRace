#!/usr/bin/env bash
# iOS build helper. Usage: scripts/ios.sh <export|device|run|archive|compile-check>
#   export         Godot headless export → build/ios/UltiRace.xcodeproj (validated)
#   device         export + signed Release build for the connected iPhone
#   run            device + devicectl install + launch
#   archive        export + xcodebuild archive (TestFlight path, M13)
#   compile-check  export + unsigned generic iOS build (CI)
#   sim            export + Simulator build, boots an "UltiRace iPhone" simulator, installs, launches
#                  (needs build/tools/build_godot_sim.sh once: the official template's simulator
#                  library is x86_64 only, Apple-silicon simulators need arm64)
# Env: GODOT, TEAM_ID (default: preset / Xcode personal team), DEVICE_UDID (default: first paired iPhone),
#      CONFIG (Release|Debug, default Release),
#      SERVER_URL (dev only, e.g. ws://192.168.178.32:8090): baked into res://dev_server.txt and adds
#      NSLocalNetworkUsageDescription to the exported Info.plist. Never set for App Store builds.
#      DEV_ARGS (dev only): user args baked into res://dev_args.txt, e.g. "--watch --shot user://x.png"
#      (iOS does not pass launch arguments to Godot). Fetch files with: scripts/ios.sh pull <name>
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
  if [ -n "${SERVER_URL:-}" ]; then printf '%s\n' "$SERVER_URL" > "$REPO/godot/dev_server.txt"; else rm -f "$REPO/godot/dev_server.txt"; fi
  if [ -n "${DEV_ARGS:-}" ]; then printf '%s\n' "$DEV_ARGS" > "$REPO/godot/dev_args.txt"; else rm -f "$REPO/godot/dev_args.txt"; fi
  "$GODOT" --headless --path "$REPO/godot" --import >"$LOG/godot_import.txt" 2>&1 || true
  "$GODOT" --headless --path "$REPO/godot" --export-release "iOS" "$XPROJ" >"$LOG/godot_export.txt" 2>&1 || true
  # Godot exits 0 on failed exports and may leave a half-written project behind.
  [ -d "$XPROJ" ] || die "export failed, see $LOG/godot_export.txt"
  if grep -q 'Project export for preset "iOS" failed' "$LOG/godot_export.txt" \
     || grep -qE '^\s*\$(pbx|additional)_' "$XPROJ/project.pbxproj"; then
    grep -E 'ERROR' "$LOG/godot_export.txt" | head -5 >&2
    die "export failed, see $LOG/godot_export.txt"
  fi
  if [ -n "${SERVER_URL:-}" ]; then
    local plist; plist=$(find "$OUT" -maxdepth 2 -name '*-Info.plist' | head -1)
    plutil -replace NSLocalNetworkUsageDescription -string "Connect to a development game server on your local network." "$plist"
    echo "dev build: server $SERVER_URL"
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

SIM_LIB="$REPO/build/tools/godot-src/bin/libgodot.ios.template_release.arm64.simulator.a"
SIM_NAME="UltiRace iPhone"

sim_udid() {  # existing or new simulator: iPhone 11 if this Xcode still has it, else the oldest available iPhone
  local u; u=$(xcrun simctl list devices available | grep -F "$SIM_NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
  if [ -z "$u" ]; then
    local rt; rt=$(xcrun simctl list runtimes | grep -E '^iOS' | tail -1 | sed -E 's/.* - (com\.apple\.CoreSimulator\.SimRuntime\.[^ ]+).*/\1/')
    for t in iPhone-11 iPhone-12 iPhone-SE-3rd-generation iPhone-13; do
      u=$(xcrun simctl create "$SIM_NAME" "com.apple.CoreSimulator.SimDeviceType.$t" "$rt" 2>/dev/null) && break
    done
  fi
  echo "$u"
}

do_sim() {
  [ -f "$SIM_LIB" ] || die "arm64 simulator library missing: run build/tools/build_godot_sim.sh first"
  do_export
  local slice; slice=$(find "$OUT/UltiRace.xcframework" -maxdepth 1 -type d -name '*simulator' | head -1)
  [ -n "$slice" ] || die "no simulator slice in UltiRace.xcframework"
  # fat simulator library: the template's x86_64 slice + our arm64 build
  local x86="$OUT/libgodot_sim_x86_64.a"
  lipo "$slice/libgodot.a" -thin x86_64 -output "$x86" 2>/dev/null || cp "$slice/libgodot.a" "$x86"
  lipo -create "$x86" "$SIM_LIB" -output "$slice/libgodot.a"
  rm -f "$x86"
  local udid; udid=$(sim_udid); [ -n "$udid" ] || die "could not create a simulator (xcrun simctl list devicetypes)"
  xcodebuild -project "$XPROJ" -scheme "$SCHEME" -configuration "$CONFIG" -sdk iphonesimulator \
    -destination "id=$udid" -derivedDataPath "$REPO/build/dd-sim" ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" build >"$LOG/xcode_sim.txt" 2>&1 \
    || { grep -E 'error:' "$LOG/xcode_sim.txt" | sort -u | head -5 >&2; die "simulator build failed, see $LOG/xcode_sim.txt"; }
  local app; app=$(find "$REPO/build/dd-sim/Build/Products" -maxdepth 2 -name '*.app' | head -1)
  xcrun simctl boot "$udid" 2>/dev/null || true
  open -a Simulator --args -CurrentDeviceUDID "$udid" 2>/dev/null || echo "(no Simulator app: running headless; screenshot with xcrun simctl io $udid screenshot out.png)"
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl install "$udid" "$app"
  xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" >/dev/null
  echo "running on simulator $SIM_NAME ($udid)"
}

do_pull() {  # copy a file from the app's Documents (user://) to build/device/
  local ids dev; ids=$(device_ids); dev="${ids%% *}"
  mkdir -p "$REPO/build/device"
  xcrun devicectl device copy from --device "$dev" --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
    --source "Documents/$2" --destination "$REPO/build/device/$2" >"$LOG/devicectl_pull.txt" 2>&1 \
    || { tail -3 "$LOG/devicectl_pull.txt" >&2; die "pull failed"; }
  echo "pulled build/device/$2"
}

case "${1:-}" in
  export) do_export;; device) do_device;; run) do_run;; archive) do_archive;;
  compile-check) do_compile_check;;
  sim) do_sim;;
  pull) do_pull "$@";;
  *) die "usage: $0 <export|device|run|archive|compile-check|sim|pull <file>>";;
esac
