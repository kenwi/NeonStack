extends RefCounted

## Versioned replay JSON helpers.

const VERSION := 1
const TICK_HZ := 60
const MAX_BYTES := 1_048_576


static func build(
	mode_id: String,
	run_seed: int,
	events: Array,
	final_score: int,
	lines_cleared: int,
	level: int,
	elapsed_seconds: float
) -> Dictionary:
	return {
		"v": VERSION,
		"modeId": mode_id,
		"seed": run_seed,
		"tickHz": TICK_HZ,
		"events": events,
		"finalScore": final_score,
		"linesCleared": lines_cleared,
		"level": level,
		"elapsedSeconds": elapsed_seconds,
	}


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
