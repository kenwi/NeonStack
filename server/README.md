# Highscores server - Docker

Run the Neon Stack highscores API in Docker with persistent data on the host and optional Cloudflare Tunnel exposure.

## Layout

| Path | Purpose |
|------|---------|
| `data/appsettings.json` | Runtime config (CORS origins, log levels). Mounted at `/data/appsettings.json` in the container. |
| `data/highscores.json` | Leaderboard storage. Created automatically on first score if missing. |
| `.env` | Local secrets and ports (`TUNNEL_TOKEN`, `HIGHSCORES_PORT`, `TZ`). |

Optional starter score file:

```bash
cp data/highscores.json.example data/highscores.json
```

## Quick start (local only)

From `server/`:

```bash
cp .env.example .env
docker compose up -d --build
```

API:

- `GET  http://localhost:5090/api/scores/classic?top=10`
- `GET  http://localhost:5090/api/scores/classic-mobile?top=10`
- `GET  http://localhost:5090/api/scores/daily-2026-10-31?top=10`
- `GET  http://localhost:5090/api/scores/weekly-2026-W44-mobile?top=10`
- `POST http://localhost:5090/api/scores`

Game modes:

| Mode | Desktop `modeId` | Mobile `modeId` | Seed |
|------|------------------|-----------------|------|
| Classic | `classic` | `classic-mobile` | Random each run |
| Daily | `daily-YYYY-MM-DD` | `daily-YYYY-MM-DD-mobile` | Shared UTC day |
| Weekly | `weekly-YYYY-Www` | `weekly-YYYY-Www-mobile` | Shared ISO week (Monday UTC) |

Each period has its own board (desktop and mobile separated). The checksum includes the mode id. Existing classic scores stay on the classic boards.

### Submit body

```json
{
  "modeId": "classic",
  "playerName": "Alice",
  "finalScore": 12345,
  "linesCleared": 42,
  "level": 5,
  "elapsedSeconds": 312.456,
  "checksum": "<sha256 hex>"
}
```

Checksum canonical string (UTF-8, SHA-256, lowercase hex):

```text
modeId|playerName|finalScore|linesCleared|level|elapsedSeconds(F3)|Tetris.Highscores.v1
```

## Discord score announcements

When a score is accepted, the server can post an embed to a Discord channel via webhook.

Configure in `.env`:

```bash
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...
DISCORD_GAME_URL=https://example.com/neon-stack
DISCORD_ANNOUNCE_TOP_RANKS=0
```

Leave `DISCORD_WEBHOOK_URL` empty to disable. Announcements never block score submission.

## Timezone

Score `SubmittedAt` timestamps use the container's OS timezone. Set `TZ` in `.env`:

```bash
TZ=Europe/Amsterdam
```

## Cloudflare Tunnel

Cloudflare Tunnel exposes the API without opening inbound ports. TLS terminates at Cloudflare; `cloudflared` forwards HTTP to the `highscores` container.

### 1. Create a tunnel

1. Open [Cloudflare Zero Trust](https://one.dash.cloudflare.com/) > **Networks** > **Tunnels**.
2. **Create a tunnel** > choose **Cloudflared**.
3. Name the tunnel (for example `tetris-highscores`).
4. Copy the **tunnel token**.

### 2. Configure `.env`

```bash
TUNNEL_TOKEN=eyJhIjoi...
HIGHSCORES_PORT=5090
```

### 3. Start server + tunnel

```bash
docker compose --profile tunnel up -d --build
```

### 4. Add a public hostname

In the tunnel's **Public Hostname** settings:

| Field | Value |
|-------|-------|
| Subdomain | e.g. `tetris-scores` |
| Domain | your Cloudflare zone |
| Type | HTTP |
| URL | `highscores:5090` |

Use the Docker Compose service name (`highscores`), not `localhost`. Both containers share the `tetris-highscores` network.

### 5. CORS

Add your public game URL to `Cors:Origins` in `data/appsettings.json`, then restart:

```bash
docker compose restart highscores
```

The server reloads `/data/appsettings.json` when the file changes. Point the game client's `API_BASE_URL` at the tunnel hostname when ready.

## Operations

```bash
# Logs
docker compose logs -f highscores
docker compose logs -f cloudflared

# Stop
docker compose --profile tunnel down

# Rebuild after code changes
docker compose up -d --build
```

## Notes

- The app listens on HTTP inside the container. Cloudflare handles HTTPS for public clients.
- Forwarded headers (`X-Forwarded-Proto`) are enabled so HTTPS redirection behaves correctly behind the tunnel.
- Keep `data/highscores.json` backed up; it is gitignored by default.
