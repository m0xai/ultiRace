#!/usr/bin/env bash
# End-to-end: real server binary (test mode, 10× time) + headless clients.
# M2: Go bot clients (Quick Play). Headless Godot clients are added in M4 (BotClient.gd).
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-18090}"
BIN="$REPO/build/e2e"
mkdir -p "$BIN" "$REPO/build/logs"

go build -o "$BIN/server" "$REPO/cmd/server"
go build -o "$BIN/botclient" "$REPO/cmd/botclient"

"$BIN/server" -addr "127.0.0.1:$PORT" -test -time-scale 10 -log-level warn >"$REPO/build/logs/e2e_server.txt" 2>&1 &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT

for _ in $(seq 1 50); do
  curl -sf "http://127.0.0.1:$PORT/healthz" >/dev/null && break
  sleep 0.1
done

echo "== 6 Go clients press Quick Play at once =="
"$BIN/botclient" -url "ws://127.0.0.1:$PORT" -clients 6 -races 2 -stagger 10ms -timeout 3m

echo "== 4 headless Godot clients Quick Play together (M4) =="
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
"$GODOT" --headless --path "$REPO/godot" --import >/dev/null 2>&1 || true
pids=()
for n in A B C D; do
  "$GODOT" --headless --path "$REPO/godot" res://src/testing/BotClient.tscn -- --server "ws://127.0.0.1:$PORT" --name "Godot $n" --mode quick --timeout 120 \
    >"$REPO/build/logs/e2e_godot_$n.txt" 2>&1 &
  pids+=($!)
  sleep 0.2
done
fail=0
for p in "${pids[@]}"; do wait "$p" || fail=1; done
grep -h "BOTCLIENT RESULT" "$REPO"/build/logs/e2e_godot_*.txt || true
rooms=$(grep -h "BOTCLIENT RESULT" "$REPO"/build/logs/e2e_godot_*.txt | sed 's/.*room=\([A-Z]*\).*/\1/' | sort -u | wc -l | tr -d ' ')
results=$(grep -h "BOTCLIENT RESULT" "$REPO"/build/logs/e2e_godot_*.txt | wc -l | tr -d ' ')
if [ "$fail" -ne 0 ] || [ "$results" -ne 4 ] || [ "$rooms" -ne 1 ]; then
  echo "godot e2e failed: results=$results rooms=$rooms"; exit 1
fi

echo "== Practice race =="
"$BIN/botclient" -url "ws://127.0.0.1:$PORT" -clients 1 -practice -races 1 -timeout 2m

echo "== Quick Play under -sim-lag=150ms -sim-jitter=40ms (5x time = ~750 ms game-time lag; race must complete, finishing needs M7 prediction) =="
kill $SERVER_PID 2>/dev/null || true
wait $SERVER_PID 2>/dev/null || true
"$BIN/server" -addr "127.0.0.1:$PORT" -test -time-scale 5 -sim-lag 150ms -sim-jitter 40ms -log-level warn >"$REPO/build/logs/e2e_server_lag.txt" 2>&1 &
SERVER_PID=$!
for _ in $(seq 1 50); do
  curl -sf "http://127.0.0.1:$PORT/healthz" >/dev/null && break
  sleep 0.1
done
"$BIN/botclient" -url "ws://127.0.0.1:$PORT" -clients 3 -races 1 -timeout 3m

echo "== M7: headless Godot client drives with prediction under -sim-lag=150ms (real time) =="
kill $SERVER_PID 2>/dev/null || true
wait $SERVER_PID 2>/dev/null || true
"$BIN/server" -addr "127.0.0.1:$PORT" -test -sim-lag 150ms -sim-jitter 40ms -log-level warn >"$REPO/build/logs/e2e_server_pred.txt" 2>&1 &
SERVER_PID=$!
for _ in $(seq 1 50); do curl -sf "http://127.0.0.1:$PORT/healthz" >/dev/null && break; sleep 0.1; done
"$GODOT" --headless --path "$REPO/godot" res://src/testing/BotClient.tscn -- --server "ws://127.0.0.1:$PORT" --name "Pred" \
  --mode practice --drive --timeout 240 >"$REPO/build/logs/e2e_godot_pred.txt" 2>&1 || { tail -5 "$REPO/build/logs/e2e_godot_pred.txt"; exit 1; }
line=$(grep "BOTCLIENT RESULT" "$REPO/build/logs/e2e_godot_pred.txt")
echo "$line"
echo "$line" | grep -q "finished=true" || { echo "predicted driver did not finish under lag"; exit 1; }
avg=$(echo "$line" | sed 's/.*pred_err_avg=\([0-9.]*\).*/\1/')
awk -v a="$avg" 'BEGIN { exit !(a < 0.5) }' || { echo "prediction error too high: avg $avg m"; exit 1; }

echo "e2e: OK"
