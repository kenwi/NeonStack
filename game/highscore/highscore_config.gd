extends RefCounted

## Public API via Cloudflare Tunnel (local Docker still reachable on :5090).
const API_BASE_URL := "https://neonstack-highscores.m0b.tech"
const MODE_ID := "classic"
const MODE_ID_MOBILE := "classic-mobile"
const DEFAULT_TOP_COUNT := 20
const MAX_PLAYER_NAME_LENGTH := 16
const PLAYER_NAME_PATH := "user://highscore.cfg"
const PLAYER_NAME_SECTION := "player"
const PLAYER_NAME_KEY := "name"
