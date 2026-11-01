extends Node

## Records abstract actions with sim tick indices for bit-exact replay.

const ReplayFormat = preload("res://game/replay/replay_format.gd")
const PlayDevice = preload("res://game/platform/play_device.gd")

var active := false
var seed_value := 0
var events: Array = []


func begin(run_seed: int) -> void:
	active = true
	seed_value = run_seed
	events.clear()


func stop() -> void:
	active = false


func clear() -> void:
	active = false
	seed_value = 0
	events.clear()


func record(tick: int, action: String) -> void:
	if not active:
		return
	events.append({"t": tick, "a": action})


func export_dict(main: Node) -> Dictionary:
	var mode_id := PlayDevice.score_mode_id()
	var highscores = main.get("highscores")
	if highscores != null and str(highscores.get("submit_mode_id")) != "":
		mode_id = str(highscores.submit_mode_id)
	elif main.get("game_mode") != null and str(main.game_mode) != "":
		var diff := str(main.get("difficulty"))
		mode_id = PlayDevice.score_mode_id_for(str(main.game_mode), -1, diff)
	var arr := (
		ReplayFormat.ARR_TOUCH if PlayDevice.is_touch_primary() else ReplayFormat.ARR_DESKTOP
	)
	return ReplayFormat.build(
		mode_id,
		seed_value,
		events.duplicate(true),
		int(main.score),
		int(main.lines_cleared),
		int(main.level),
		float(main.elapsed_seconds),
		arr
	)


func export_json(main: Node) -> String:
	return ReplayFormat.to_json(export_dict(main))


func has_events() -> bool:
	return not events.is_empty()
