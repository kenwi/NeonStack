extends RefCounted

const API_BASE_URL := "https://neonstack-highscores.m0b.tech"
## Legacy classic-difficulty board ids (unchanged). Period/hardcore boards live in GameModes.
const MODE_ID := "classic"
const MODE_ID_MOBILE := "classic-mobile"
const DEFAULT_TOP_COUNT := 100
const LEADERBOARD_PAGE_SIZE := 20
const LIVE_RANK_TOP_COUNT := 10
const MAX_PLAYER_NAME_LENGTH := 16
const PLAYER_NAME_PATH := "user://highscore.cfg"
const PLAYER_NAME_SECTION := "player"
const PLAYER_NAME_KEY := "name"
const PLAYER_ID_KEY := "id"
const PLAYER_ID_LENGTH := 22
const GREETINGS_SECTION := "greetings"
const GREETINGS_ENABLED_KEY := "enabled"

const _PLAYER_ID_ALPHABET := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-"


## Load or create a once-per-device opaque player id (persisted in highscore.cfg).
static func ensure_player_id() -> String:
	var cfg := ConfigFile.new()
	cfg.load(PLAYER_NAME_PATH)
	var existing := sanitize_player_id(str(cfg.get_value(PLAYER_NAME_SECTION, PLAYER_ID_KEY, "")))
	if not existing.is_empty():
		return existing
	var generated := _generate_player_id()
	cfg.set_value(PLAYER_NAME_SECTION, PLAYER_ID_KEY, generated)
	cfg.save(PLAYER_NAME_PATH)
	return generated


static func sanitize_player_id(raw: String) -> String:
	var trimmed := raw.strip_edges()
	var out := ""
	for i in trimmed.length():
		var ch := trimmed.substr(i, 1)
		if _PLAYER_ID_ALPHABET.find(ch) < 0:
			continue
		out += ch
		if out.length() >= PLAYER_ID_LENGTH:
			break
	return out if out.length() == PLAYER_ID_LENGTH else ""


static func _generate_player_id() -> String:
	var out := ""
	var alphabet_len := _PLAYER_ID_ALPHABET.length()
	for _i in PLAYER_ID_LENGTH:
		out += _PLAYER_ID_ALPHABET.substr(randi() % alphabet_len, 1)
	return out


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
