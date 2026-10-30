extends RefCounted

## Public API via Cloudflare Tunnel (local Docker still reachable on :5090).
const API_BASE_URL := "https://neonstack-highscores.m0b.tech"
const MODE_ID := "classic"
const MODE_ID_MOBILE := "classic-mobile"
const DEFAULT_TOP_COUNT := 100
const LEADERBOARD_PAGE_SIZE := 20
const LIVE_RANK_TOP_COUNT := 10
const MAX_PLAYER_NAME_LENGTH := 16
const PLAYER_NAME_PATH := "user://highscore.cfg"
const PLAYER_NAME_SECTION := "player"
const PLAYER_NAME_KEY := "name"
const GREETINGS_SECTION := "greetings"
const GREETINGS_ENABLED_KEY := "enabled"


## Space thousand separators: 10000 -> "10 000".
static func format_score(value: int) -> String:
	var prefix := "-" if value < 0 else ""
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			out = " " + out
		out = digits.substr(i, 1) + out
		count += 1
	return prefix + out
