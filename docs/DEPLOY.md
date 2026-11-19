# Deploy guide

Claude prepares files and commands; **the human runs everything on `flappus`** (SSH, sudo, DNS).
Server design: GAME_PLAN §7.1. Files: `deploy/`.

## 0. DNS (once)

Create an `A` (and `AAAA` if IPv6) record: `ultirace.flappus.com` → flappus' public IP.
Check: `dig +short ultirace.flappus.com`.

## 1. First install on flappus (Debian 12)

```bash
sudo mkdir -p /opt/ultirace/data && sudo chown "$USER" /opt/ultirace /opt/ultirace/data
cd /opt/ultirace
git clone https://github.com/m0xai/ultiRace.git src          # or: git -C src pull
docker build -f src/deploy/Dockerfile --build-arg VERSION=$(git -C src rev-parse --short HEAD) -t ultirace-server:latest src
cp src/deploy/compose.yaml compose.yaml
cp src/deploy/env.example .env && chmod 600 .env
# edit .env: set ID_SECRET to a long random string:  openssl rand -hex 32
#            APPLE_TEAM_ID / APP_STORE_URL once known (Universal Links, landing page)
sudo chown 65532:65532 data                                    # distroless "nonroot" user writes reports.jsonl
docker compose up -d
curl -s http://127.0.0.1:8090/healthz                          # → {"ok":true,...}
```

## 2. Caddy (native systemd service)

```bash
sudo cp /opt/ultirace/src/deploy/Caddyfile.snippet /etc/caddy/sites/ultirace.caddy
#   (or paste the block into /etc/caddy/Caddyfile if the main file does not `import sites/*`)
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
curl -s https://ultirace.flappus.com/healthz
curl -sI https://ultirace.flappus.com/.well-known/apple-app-site-association   # 200 application/json (after APPLE_TEAM_ID is set)
```

## 3. Update to a new version

```bash
cd /opt/ultirace && git -C src pull
docker build -f src/deploy/Dockerfile --build-arg VERSION=$(git -C src rev-parse --short HEAD) -t ultirace-server:latest src
docker compose up -d          # recreates the container; rooms drain ≤ 10 s on SIGTERM
```

## 4. Moderation

- Reports: `/opt/ultirace/data/reports.jsonl` (one JSON line per report: room, reporter, target, name, reason).
- Ban a player: add the anonymous id (`"target"` in a report) to `/opt/ultirace/data/bans.json`:
  `{"players": ["p1a2b3c4d5e6"]}` then `docker kill -s HUP ultirace` (reloads without restart).

## 5. Logs and health

```bash
docker logs -f --since 10m ultirace     # JSON logs (slog)
docker compose ps                       # healthcheck status
```

## iOS: human-only steps (GAME_PLAN §7.2)

See `docs/HUMAN_TODO.md` for the current list: Apple Developer Program, App ID + capabilities
(Game Center, Associated Domains `applinks:ultirace.flappus.com`), App Store Connect record,
leaderboards/achievements, TestFlight testers.
