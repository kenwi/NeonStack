# Neon Stack

A stylized neon Tetris clone built with **Godot 4.7**. Play in the browser or on desktop, chase shared daily and weekly seeds, and submit scores with optional bit-exact replays that a headless verifier can check.

| | |
|---|---|
| Engine | Godot 4.7 (GL Compatibility) |
| Client | GDScript (`game/`) |
| Highscores API | ASP.NET (`server/`), Docker-friendly |
| License | MIT |

---

## Features

- Classic Tetris flow: bag randomizer, hold, next queue, soft/hard drop, lock delay
- **Classic** vs **Hardcore** difficulty (Infinity lock resets vs never)
- **Classic / Daily / Weekly** modes with shared UTC seeds for daily and weekly
- Separate desktop and mobile leaderboards
- Private challenge boards (custom name, share link, locked mode/difficulty)
- Touch-primary layout with upper-zone DAS and on-screen controls
- Cycleable color themes, neon backdrops, juice FX, and in-game music
- Live top-10 rank greetings during a run
- Highscore submit with SHA-256 checksums and optional replay upload
- In-game replay viewer (speed, scrub) for uploaded runs
- Headless replay verifier for ops (not shipped in web/Linux exports)

---

## Requirements

- [Godot 4.7+](https://godotengine.org/download) to run or export the client
- [.NET 10 SDK](https://dotnet.microsoft.com/) only if you run the highscores API outside Docker
- [Docker](https://docs.docker.com/get-docker/) optional, for the API stack described in [`server/README.md`](server/README.md)

---

## Quick start (game)

```bash
godot --path .
```

Or open this folder in the Godot editor and press Play. The main scene is `game/main.tscn`.

Point the client at a highscores API by editing `API_BASE_URL` in [`game/highscore/highscore_config.gd`](game/highscore/highscore_config.gd) (default is the public tunnel URL used in production).

---

## Controls

### Keyboard

| Input | Action |
|-------|--------|
| Left / Right | Move |
| Up / X | Rotate |
| Z | Counter-rotate |
| Down | Soft drop |
| Space / Enter | Hard drop |
| C / Shift | Hold |
| Esc | Mode menu / resume |
| R | Restart |
| L | Highscores |
| H | Help |
| S | Score table |
| M / N | Mute / next track |
| PgUp / PgDn | Music volume |
| F / F11 | Fullscreen |
| T | Cycle color theme |
| B | Cycle background |
| J | Toggle juice FX |
| G | Toggle rank greetings |
| Q | Quit |

### Touch

Upper left/right zones hold for DAS. Lower zones and the on-screen pad cover soft drop, hard drop, rotate, and hold. Exact layout is listed in-game under Help (`H`).

---

## Modes and difficulty

Pick difficulty and mode family from the mode menu (Esc).

| Family | Seed | Board ids (classic difficulty) |
|--------|------|--------------------------------|
| Classic | Random each run | `classic`, `classic-mobile` |
| Daily | Shared UTC calendar day | `daily-YYYY-MM-DD`, `…-mobile` |
| Weekly | Shared ISO week (Monday UTC) | `weekly-YYYY-Www`, `…-mobile` |

**Hardcore** prefixes those ids (`hardcore`, `hardcore-daily-…`, `hardcore-weekly-…`) and disables lock-delay resets. Classic difficulty keeps Infinity-style lock resets (capped in-engine). Desktop and touch-primary sessions use separate boards so phone and keyboard runs do not compete on the same list.

### Private challenges

From the mode menu, **CHALLENGE** creates a private leaderboard with a custom name and locked Classic/Daily/Weekly + Classic/Hardcore settings. The API returns an opaque token; share `https://<game>/?c=<token>`. Friends who open the link join that board automatically. Scores use mode ids `c_{token}` / `c_{token}-mobile` (desktop and mobile still split). Daily/Weekly challenges freeze the UTC period seed at create time.

---

## Repository layout

```text
game/                 Client (main scene, systems, UI)
  highscore/          API client, checksum, overlays
  mode/               Board ids, period seeds, difficulty
  replay/             Record / play / JSON format
  touch/              Touch controls
  music/              Tracks + player
  fx/                 Juice FX
  theme/              Color themes
  platform/           Play-device detection (touch vs desktop)
server/               Highscores ASP.NET API + Docker
  scripts/            Ops: verify-highscore, list modes, log tail
tools/verify/         Headless Godot verifier (excluded from exports)
.github/workflows/    Web export → GitHub Pages
```

Server Docker, Cloudflare Tunnel, Discord announcements, and API details live in [`server/README.md`](server/README.md).

---

## Highscores and replays

Scores POST to `/api/scores` with a checksum over:

```text
modeId|playerName|finalScore|linesCleared|level|elapsedSeconds(F3)|Tetris.Highscores.v1
```

(UTF-8, SHA-256, lowercase hex.) The client and server share that formula.

Replays are recorded at a fixed **60 Hz** sim tick with a seeded bag and abstract actions (`left_on` / `drop` / `rot` / …). New recordings also store `arr` (auto-repeat interval) so mobile hold-speed changes stay verifiable. Optional replay JSON uploads after a successful score submit; leaderboard rows can open the in-game viewer.

---

## Verifying scores

From a machine with Godot on `PATH` (or `GODOT=` / `GODOT4=`):

```bash
# One entry
./server/scripts/verify-highscore --checksum <sha256hex>

# Whole classic board (missing replays become SKIP)
./server/scripts/verify-highscore --mode classic --all

# Every board, only entries that have a replay file (quiet filter)
./server/scripts/verify-highscore --all --replays-only
```

Under the hood this runs `tools/verify/headless_verify.gd` against `server/data/highscores.json` and `server/data/replays/`. That tool path is excluded from Web and Linux exports (`export_presets.cfg`).

Useful helpers:

```bash
./server/scripts/list-highscore-modes
./server/scripts/watch-highscore-logs
```

---

## Export and deploy

Export presets:

| Preset | Output |
|--------|--------|
| Web | `build/web/index.html` |
| Linux | `build/linux/NeonStack.x86_64` |

Pushing to `main` (when game/export paths change) runs [`.github/workflows/deploy-pages.yml`](.github/workflows/deploy-pages.yml): Godot 4.7.2 headless web export → GitHub Pages. The highscores API is deployed separately (Docker on your host); see [`server/README.md`](server/README.md).

Local web export:

```bash
mkdir -p build/web
godot --headless --path . --export-release "Web" build/web/index.html
```

---

## Development notes

- Prefer working in vertical slices under `game/` (highscore, replay, mode, touch) rather than sprawling cross-cuts.
- Replay determinism depends on tick order and recorded timings (`arr`). Same-tick events keep recording order (stable sort on load).
- Do not commit `server/data/highscores.json`, `server/.env`, or `build/` (see `.gitignore`).

### Debug tools

Debug tools are on in the Godot editor, and in a web build opened with `?debug=1` (`true` and `yes` also work). Exported desktop builds leave them off.

- FPS counter in the top-left
- **F1** toggles a dump of local player state (user-data path, API URL, player id, active challenge, `highscore.cfg` and `challenge.cfg`)
- **F2** clears that local state: deletes those cfg files, leaves the active challenge, and resets the player name, player id, feature announcement, and hard-drop tip

---

## License

MIT. See [LICENSE](LICENSE).
