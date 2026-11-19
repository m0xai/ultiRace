#!/usr/bin/env bash
# Toolchain doctor: re-runnable, prints PASS/FAIL per item. Exit code = number of FAILs.
# Usage: scripts/doctor.sh
set -u

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_WANT="$(cat "$REPO_ROOT/godot/VERSION" 2>/dev/null || echo 4.7.2.stable)"
TEMPLATES_DIR="$HOME/Library/Application Support/Godot/export_templates/$GODOT_WANT"
GO_MIN="1.24"

fails=0
pass() { printf 'PASS  %-22s %s\n' "$1" "$2"; }
fail() { printf 'FAIL  %-22s %s\n' "$1" "$2"; fails=$((fails + 1)); }
info() { printf 'INFO  %-22s %s\n' "$1" "$2"; }

# version_ge A B: true if A >= B (dotted numeric)
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

# --- System ---
info "macOS" "$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
info "CPU" "$(sysctl -n machdep.cpu.brand_string), $(sysctl -n hw.ncpu) cores, $(( $(sysctl -n hw.memsize) / 1073741824 )) GB RAM"
free_gb=$(df -g / | awk 'NR==2 {print $4}')
if [ "${free_gb:-0}" -ge 20 ]; then pass "disk free" "${free_gb} GB"; else fail "disk free" "${free_gb} GB (< 20 GB)"; fi

# --- Go / git / gh ---
if command -v go >/dev/null; then
  gov=$(go env GOVERSION | sed 's/^go//')
  if version_ge "$gov" "$GO_MIN"; then pass "go" "$gov"; else fail "go" "$gov (< $GO_MIN)"; fi
else fail "go" "not found"; fi
if command -v git >/dev/null; then pass "git" "$(git --version | awk '{print $3}')"; else fail "git" "not found"; fi
if command -v gh >/dev/null; then
  if gh auth status >/dev/null 2>&1; then pass "gh auth" "$(gh --version | head -1)"; else fail "gh auth" "not logged in (run: gh auth login)"; fi
else fail "gh" "not installed"; fi
if git -C "$REPO_ROOT" ls-remote --heads origin >/dev/null 2>&1; then pass "git remote" "$(git -C "$REPO_ROOT" remote get-url origin) reachable"; else fail "git remote" "origin not reachable"; fi

# --- Godot ---
if [ -x "$GODOT" ]; then
  gv=$("$GODOT" --version 2>/dev/null | tail -1)
  case "$gv" in "$GODOT_WANT"*) pass "godot" "$gv";; *) fail "godot" "$gv (want $GODOT_WANT)";; esac
else fail "godot" "not found at $GODOT"; fi
if [ -f "$TEMPLATES_DIR/ios.zip" ]; then pass "godot ios template" "$TEMPLATES_DIR/ios.zip"
else fail "godot ios template" "missing $TEMPLATES_DIR/ios.zip"; fi

# --- Blender ---
if [ -x "$BLENDER" ]; then pass "blender" "$("$BLENDER" --version 2>/dev/null | head -1)"
else fail "blender" "not found at $BLENDER"; fi

# --- Xcode ---
if xp=$(xcode-select -p 2>/dev/null); then
  case "$xp" in *Xcode.app*) pass "xcode-select" "$xp";; *) fail "xcode-select" "$xp (CommandLineTools only, need Xcode.app)";; esac
else fail "xcode-select" "not set"; fi
if xv=$(xcodebuild -version 2>/dev/null | tr '\n' ' '); then pass "xcodebuild" "$xv"; else fail "xcodebuild" "not working (license accepted?)"; fi
sdk=$(xcodebuild -showsdks 2>/dev/null | grep -o '\-sdk iphoneos[0-9.]*' | head -1)
if [ -n "$sdk" ]; then pass "iOS SDK" "${sdk#-sdk }"; else fail "iOS SDK" "none"; fi
rt=$(xcrun simctl list runtimes 2>/dev/null | grep -E '^iOS' | head -1)
if [ -n "$rt" ]; then pass "iOS sim runtime" "$rt"; else fail "iOS sim runtime" "none installed"; fi

# --- Signing ---
ident=$(security find-identity -v -p codesigning 2>/dev/null | grep 'Apple Development' | head -1)
if [ -n "$ident" ]; then
  team=$(echo "$ident" | sed -n 's/.*(\([A-Z0-9]\{10\}\)).*/\1/p')
  pass "signing identity" "$(echo "$ident" | sed 's/^ *[0-9]*) [0-9A-F]* //')"
  info "team (from cert)" "${team:-unknown} (note: cert suffix is the user ID; the Team ID is the OU field)"
else fail "signing identity" "no Apple Development identity in keychain"; fi

# --- Device ---
devs=$(xcrun devicectl list devices 2>/dev/null | awk 'NR>2' | grep -v 'simulated' | grep -v '^ *$')
if echo "$devs" | grep -q 'iPhone'; then
  if echo "$devs" | grep -Eq 'available|connected'; then pass "iPhone" "$(echo "$devs" | head -1 | tr -s ' ')"
  else fail "iPhone" "listed but not available: $(echo "$devs" | head -1 | tr -s ' ')"; fi
else fail "iPhone" "no physical iPhone in devicectl"; fi

echo
if [ "$fails" -eq 0 ]; then echo "doctor: all checks passed"; else echo "doctor: $fails check(s) failed"; fi
exit "$fails"
