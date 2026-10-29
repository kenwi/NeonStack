extends RefCounted

## Must match server Shared/ScoreChecksum.cs exactly.
const SHARED_SECRET := "Tetris.Highscores.v1"
const _Config = preload("res://game/highscore/highscore_config.gd")

static var _name_regex: RegEx
static var _mode_regex: RegEx


static func _ensure_regex() -> void:
	if _name_regex == null:
		_name_regex = RegEx.new()
		_name_regex.compile("[^A-Za-z0-9 _-]")
	if _mode_regex == null:
		_mode_regex = RegEx.new()
		_mode_regex.compile("[^A-Za-z0-9_-]")


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
