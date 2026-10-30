extends Node

## Injects recorded actions at matching sim ticks during playback.

const ReplayFormat = preload("res://game/replay/replay_format.gd")
const ReplayActions = preload("res://game/replay/actions.gd")

signal finished(matched: bool)

var playing := false
var _events: Array = []
var _index := 0
var _expected_score := -1
var _expected_lines := -1
var _expected_level := -1
var _seed := 0
var _duration_seconds := 0.0
var _last_event_tick := 0


func is_playing() -> bool:
	return playing


func get_seed() -> int:
	return _seed


func get_duration_seconds() -> float:
	return maxf(0.0, _duration_seconds)


func get_total_ticks() -> int:
	var from_duration := int(ceil(_duration_seconds * float(ReplayFormat.TICK_HZ)))
	return maxi(_last_event_tick, from_duration)


func load_replay(data: Dictionary) -> bool:
	if not ReplayFormat.is_valid(data):
		return false
	_events = []
	_last_event_tick = 0
	for item in data.get("events", []):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var action := str(item.get("a", ""))
		if not ReplayActions.is_known(action):
			continue
		var tick := int(item.get("t", 0))
		_events.append({"t": tick, "a": action})
		if tick > _last_event_tick:
			_last_event_tick = tick
	_events.sort_custom(func(a, b): return int(a.t) < int(b.t))
	_index = 0
	_seed = int(data.get("seed", 0))
	_expected_score = int(data.get("finalScore", -1))
	_expected_lines = int(data.get("linesCleared", -1))
	_expected_level = int(data.get("level", -1))
	_duration_seconds = maxf(0.0, float(data.get("elapsedSeconds", 0.0)))
	if _duration_seconds <= 0.0 and _last_event_tick > 0:
		_duration_seconds = float(_last_event_tick) / float(ReplayFormat.TICK_HZ)
	playing = true
	return true


func stop() -> void:
	playing = false
	_events.clear()
	_index = 0
	_duration_seconds = 0.0
	_last_event_tick = 0


func rewind() -> void:
	_index = 0
	playing = true


func inject_for_tick(tick: int, main: Node) -> void:
	if not playing:
		return
	while _index < _events.size() and int(_events[_index].t) <= tick:
		main.apply_action(str(_events[_index].a), false)
		_index += 1


func notify_game_over(main: Node) -> void:
	if not playing:
		return
	playing = false
	var matched := (
		_expected_score < 0
		or (
			int(main.score) == _expected_score
			and int(main.lines_cleared) == _expected_lines
			and int(main.level) == _expected_level
		)
	)
	if not matched:
		push_warning(
			"Replay mismatch: got score=%s lines=%s level=%s expected score=%s lines=%s level=%s"
			% [main.score, main.lines_cleared, main.level, _expected_score, _expected_lines, _expected_level]
		)
	finished.emit(matched)
