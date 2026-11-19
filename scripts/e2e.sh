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

echo "e2e: OK"
