#!/usr/bin/env bash
# Builds every car (art/blender/cars2 = A1 models; CARS_DIR=cars for the M8 placeholders) with Blender headless → godot/assets/cars/<id>.glb + art/previews/<id>.png
# Usage: art/export.sh [car ...]   (default: all)
set -euo pipefail
ART="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$ART/.." && pwd)"
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
cars=("$@")
[ ${#cars[@]} -eq 0 ] && cars=(bolt rhino glacier volt hook goo phantom twister)
mkdir -p "$REPO/godot/assets/cars" "$ART/previews" "$REPO/build/logs"
fail=0
for c in "${cars[@]}"; do
  log="$REPO/build/logs/blender_$c.txt"
  if "$BLENDER" --background --factory-startup --python "$ART/blender/${CARS_DIR:-cars3}/$c.py" -- \
       "$REPO/godot/assets/cars/$c.glb" "$ART/previews/$c.png" >"$log" 2>&1 && grep -q CAR_OK "$log"; then
    tris=$(grep -o 'CAR_TRIS [0-9]*' "$log" | awk '{print $2}')
    status=ok; [ "$tris" -gt 16000 ] && status="OVER BUDGET (LOD0 ≤ 16000)" && fail=1
    printf '%-8s %6s tris  %s\n' "$c" "$tris" "$status"
  else
    echo "$c FAILED (see $log)"; grep -E "Error|Traceback" -A3 "$log" | head -8; fail=1
  fi
done
exit $fail
