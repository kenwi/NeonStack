extends RefCounted

## Must match server Shared/ScoreChecksum.cs exactly.
const SHARED_SECRET := "Tetris.Highscores.v1"
const _Config = preload("res://game/highscore/highscore_config.gd")

static var _name_regex: RegEx
static var _mode_regex: RegEx


static func _ensure_regex() -> void:
	if _name_regex == null:
		_name_regex = RegEx.new()
		## Keep in sync with server Shared/ScoreSanitizer.cs.
		## Letters (Latin-1 incl. æøå) + digits + space/_/- + limited punctuation.
		## No markdown/HTML/control chars (@<>*`|\\ etc.) - reduces Discord/log abuse.
		_name_regex.compile("[^A-Za-z0-9À-ÖØ-öø-ÿ _.!?'\\-]")
	if _mode_regex == null:
		_mode_regex = RegEx.new()
		_mode_regex.compile("[^A-Za-z0-9_-]")


static func is_allowed_player_name_char(ch: String) -> bool:
	if ch.length() != 1:
		return false
	var code := ch.unicode_at(0)
	return (
		(code >= 65 and code <= 90)
		or (code >= 97 and code <= 122)
		or (code >= 48 and code <= 57)
		or (code >= 0xC0 and code <= 0xD6)
		or (code >= 0xD8 and code <= 0xF6)
		or (code >= 0xF8 and code <= 0xFF)
		or ch == " "
		or ch == "_"
		or ch == "-"
		or ch == "."
		or ch == "!"
		or ch == "?"
		or ch == "'"
	)


static func sanitize_player_name(name: String) -> String:
	_ensure_regex()
	var trimmed := name.strip_edges()
	if trimmed.is_empty():
		return "Anonymous"
	if trimmed.length() > _Config.MAX_PLAYER_NAME_LENGTH:
		trimmed = trimmed.substr(0, _Config.MAX_PLAYER_NAME_LENGTH)
	var cleaned := _name_regex.sub(trimmed, "", true)
	return "Anonymous" if cleaned.is_empty() else cleaned


static func sanitize_mode_id(mode_id: String) -> String:
	_ensure_regex()
	var trimmed := mode_id.strip_edges()
	if trimmed.is_empty():
		return ""
	if trimmed.length() > 64:
		trimmed = trimmed.substr(0, 64)
	return _mode_regex.sub(trimmed, "", true)


static func compute(
	mode_id: String,
	player_name: String,
	final_score: int,
	lines_cleared: int,
	level: int,
	elapsed_seconds: float
) -> String:
	var canonical := "%s|%s|%d|%d|%d|%.3f|%s" % [
		mode_id,
		player_name,
		final_score,
		lines_cleared,
		level,
		elapsed_seconds,
		SHARED_SECRET,
	]
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(canonical.to_utf8_buffer())
	return ctx.finish().hex_encode()
