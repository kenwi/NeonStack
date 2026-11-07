extends RefCounted

## Versioned replay JSON helpers.

const GameModes = preload("res://game/mode/game_modes.gd")

const VERSION := 1
const TICK_HZ := 60
const MAX_BYTES := 1_048_576
## Auto-repeat interval while holding left/right (seconds per cell after DAS).
const ARR_DESKTOP := 0.03
const ARR_TOUCH := 0.016


static func build(
	mode_id: String,
	run_seed: int,
	events: Array,
	final_score: int,
	lines_cleared: int,
	level: int,
	elapsed_seconds: float,
	arr_interval: float = ARR_DESKTOP,
	max_level: int = GameModes.MAX_LEVEL_CLASSIC
) -> Dictionary:
	return {
		"v": VERSION,
		"modeId": mode_id,
		"seed": run_seed,
		"tickHz": TICK_HZ,
		"arr": arr_interval,
		"events": events,
		"finalScore": final_score,
		"linesCleared": lines_cleared,
		"level": level,
		"elapsedSeconds": elapsed_seconds,
		"maxLevel": max_level,
	}


## Old replays omit maxLevel and were recorded at the classic cap.
static func recorded_max_level(data: Dictionary) -> int:
	if not data.has("maxLevel"):
		return GameModes.MAX_LEVEL_CLASSIC
	return int(data.get("maxLevel", GameModes.MAX_LEVEL_CLASSIC))


## Touch ARR shipped 2026-10-31 ~13:55 +01:00; older mobile replays used desktop ARR.
const ARR_TOUCH_CUTOVER_PREFIX := "2026-10-31T13:55:00"


## ARR for playback. Prefer embedded `arr`; else desktop (legacy omission).
static func arr_from_replay(data: Dictionary) -> float:
	if data.has("arr"):
		var arr := float(data.get("arr", ARR_DESKTOP))
		if arr > 0.0:
			return arr
	return ARR_DESKTOP


## Fill missing `arr` using board id + highscore SubmittedAt (verify / ops).
static func ensure_arr_for_legacy(
	data: Dictionary,
	board_id: String,
	submitted_at: String
) -> void:
	if data.has("arr") and float(data.get("arr", 0.0)) > 0.0:
		return
	if GameModes.is_mobile_board(board_id):
		var stamp := submitted_at.substr(0, ARR_TOUCH_CUTOVER_PREFIX.length())
		if not stamp.is_empty() and stamp >= ARR_TOUCH_CUTOVER_PREFIX:
			data["arr"] = ARR_TOUCH
			return
	data["arr"] = ARR_DESKTOP


static func to_json(data: Dictionary) -> String:
	return JSON.stringify(data)


static func parse(text: String) -> Dictionary:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


static func is_valid(data: Dictionary) -> bool:
	if int(data.get("v", 0)) != VERSION:
		return false
	if not data.has("seed") or not data.has("tickHz") or not data.has("events"):
		return false
	if int(data.get("tickHz", 0)) != TICK_HZ:
		return false
	if typeof(data.get("events")) != TYPE_ARRAY:
		return false
	return true


static func fits_size_limit(json_text: String) -> bool:
	return json_text.to_utf8_buffer().size() <= MAX_BYTES
