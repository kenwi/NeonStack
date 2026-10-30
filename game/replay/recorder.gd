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
	return ReplayFormat.build(
		PlayDevice.score_mode_id(),
		seed_value,
		events.duplicate(true),
		int(main.score),
		int(main.lines_cleared),
		int(main.level),
		float(main.elapsed_seconds)
	)


func export_json(main: Node) -> String:
	return ReplayFormat.to_json(export_dict(main))


func has_events() -> bool:
	return not events.is_empty()
