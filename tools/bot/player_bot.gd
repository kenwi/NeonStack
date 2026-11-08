extends Node

## Editor-only driver. Plans a placement and emits replay actions one tick at a time.
## Not referenced by the game scene. The Web export excludes this directory.

const ReplayActions = preload("res://game/replay/actions.gd")

## Tunable landing score. Higher is better.
const WEIGHT_LINES := 1.0
const WEIGHT_HOLES := -4.5
const WEIGHT_BUMPINESS := -0.25
const WEIGHT_HEIGHT := -0.45
## Level 1 waits a full second between moves. Each higher level trims this by four ticks.
const PACE_LEVEL1_TICKS := 60
const PACE_PER_LEVEL := 4
## At or under this many sim ticks per cell, finish the placement immediately.
const FAST_GRAVITY_TICKS := 3

var _actions: Array[String] = []
var _wait := 0
var _planned_serial := -1
var _plan_y := -999


func clear_plan() -> void:
	_actions.clear()
	_wait = 0
	_planned_serial = -1
	_plan_y = -999


func step(main: Node) -> void:
	if bool(main.game_over) or float(main.clear_timer) > 0.0:
		return
	# A hold replaces the piece, so plan again. Cap that chain; do not cap a burst.
	var replans := 0
	while replans < 3:
		replans += 1
		var serial := int(main.bot_piece_serial)
		var y := int(main.piece_pos.y)
		if serial != _planned_serial:
			_plan(main)
			_wait = _pace_ticks(int(main.bot_pace_level()))
		elif y != _plan_y:
			# Gravity moved the piece while we were pausing. Rebuild from here.
			var wait := _wait
			_plan(main)
			_wait = wait
		if _actions.is_empty():
			return
		var fast := _fast_gravity(main)
		if not fast and _wait > 0:
			_wait -= 1
			return
		var held := false
		while not _actions.is_empty():
			var action := str(_actions.pop_front())
			var serial_before := int(main.bot_piece_serial)
			main.apply_action(action)
			if int(main.bot_piece_serial) != serial_before:
				if action == ReplayActions.HOLD:
					held = true
				else:
					_actions.clear()
				break
			if not fast:
				_wait = _pace_ticks(int(main.bot_pace_level()))
				return
		if not held:
			return


func refresh_pace(main: Node) -> void:
	var ticks := _pace_ticks(int(main.bot_pace_level()))
	if _wait > ticks:
		_wait = ticks


func _pace_ticks(level: int) -> int:
	return maxi(1, PACE_LEVEL1_TICKS - (level - 1) * PACE_PER_LEVEL)


func _fast_gravity(main: Node) -> bool:
	# A slow bot speed stays slow after the game level climbs. Only a fast bot
	# speed skips the pause, and only when gravity is already a few ticks per cell.
	if _pace_ticks(int(main.bot_pace_level())) > 1:
		return false
	var interval := float(main.bot_drop_interval())
	return interval <= float(main.TICK_DT) * float(FAST_GRAVITY_TICKS)


func _plan(main: Node) -> void:
	_planned_serial = int(main.bot_piece_serial)
	_plan_y = int(main.piece_pos.y)
	_actions.clear()
	var pid := str(main.piece_id)
	if pid.is_empty():
		return
	var current := _best_placement(main, pid, main.piece_pos, int(main.piece_rot))
	var best_score := float(current.score)
	var best_actions: Array[String] = current.actions
	if not bool(main.hold_locked):
		var swap := ""
		if str(main.hold_id) != "":
			swap = str(main.hold_id)
		elif main.queue.size() > 0:
			swap = str(main.queue[0])
		if not swap.is_empty():
			var held := _best_placement(main, swap, Vector2i(3, 0), 0)
			if bool(held.ok) and float(held.score) > best_score:
				_actions.append(ReplayActions.HOLD)
				return
	if bool(current.ok):
		_actions = best_actions
		return
	_actions.append(ReplayActions.DROP)


func _best_placement(main: Node, pid: String, start_pos: Vector2i, start_rot: int) -> Dictionary:
	var best := {"ok": false, "score": -1.0e30, "actions": [] as Array[String]}
	var count := int(main.bot_rotation_count(pid))
	if count <= 0:
		return best
	for target in count:
		var path := _rotation_path(main, pid, start_pos, start_rot, target, count)
		if not bool(path.ok):
			continue
		var pos: Vector2i = path.pos
		var rot := int(path.rot)
		var rot_actions: Array[String] = path.actions
		for spot in _reachable_columns(main, pid, pos, rot):
			var landed: Vector2i = spot.pos
			var drop_y := landed.y
			while main.bot_placement_valid(Vector2i(landed.x, drop_y + 1), rot, pid):
				drop_y += 1
			var origin := Vector2i(landed.x, drop_y)
			if not _locks_inside(main, pid, origin, rot):
				continue
			var score := _score_landing(main, pid, origin, rot)
			if score <= float(best.score):
				continue
			var actions: Array[String] = []
			actions.append_array(rot_actions)
			actions.append_array(spot.nudges)
			actions.append(ReplayActions.DROP)
			best = {"ok": true, "score": score, "actions": actions}
	return best


func _rotation_path(
	main: Node,
	pid: String,
	start_pos: Vector2i,
	start_rot: int,
	target: int,
	count: int
) -> Dictionary:
	var cw := posmod(target - start_rot, count)
	var ccw := posmod(start_rot - target, count)
	var short := _turn_actions(ReplayActions.ROT, cw) if cw <= ccw else _turn_actions(ReplayActions.CCW, ccw)
	var applied := _apply_turns(main, pid, start_pos, start_rot, short)
	if bool(applied.ok):
		return applied
	if cw == ccw:
		return applied
	var long := _turn_actions(ReplayActions.CCW, ccw) if cw <= ccw else _turn_actions(ReplayActions.ROT, cw)
	return _apply_turns(main, pid, start_pos, start_rot, long)


func _turn_actions(action: String, times: int) -> Array[String]:
	var out: Array[String] = []
	for _i in times:
		out.append(action)
	return out


func _apply_turns(
	main: Node,
	pid: String,
	pos: Vector2i,
	rot: int,
	actions: Array[String]
) -> Dictionary:
	var cursor := pos
	var facing := rot
	for action in actions:
		var dir := 1 if action == ReplayActions.ROT else -1
		var turned := _simulate_rotate(main, pid, cursor, facing, dir)
		if not bool(turned.ok):
			return {"ok": false, "pos": pos, "rot": rot, "actions": actions}
		cursor = turned.pos
		facing = int(turned.rot)
	return {"ok": true, "pos": cursor, "rot": facing, "actions": actions}


func _simulate_rotate(main: Node, pid: String, pos: Vector2i, rot: int, dir: int) -> Dictionary:
	var count := int(main.bot_rotation_count(pid))
	var next_rot := posmod(rot + dir, count)
	for kick in main.bot_kicks():
		var origin: Vector2i = pos + kick
		if main.bot_placement_valid(origin, next_rot, pid):
			return {"ok": true, "pos": origin, "rot": next_rot}
	return {"ok": false, "pos": pos, "rot": rot}


func _reachable_columns(main: Node, pid: String, pos: Vector2i, rot: int) -> Array:
	var spots: Array = []
	spots.append({"pos": pos, "nudges": [] as Array[String]})
	var left := pos
	var left_nudges: Array[String] = []
	while true:
		var next := left + Vector2i(-1, 0)
		if not main.bot_placement_valid(next, rot, pid):
			break
		left = next
		left_nudges.append(ReplayActions.NUDGE_LEFT)
		spots.append({"pos": left, "nudges": left_nudges.duplicate()})
	var right := pos
	var right_nudges: Array[String] = []
	while true:
		var next := right + Vector2i(1, 0)
		if not main.bot_placement_valid(next, rot, pid):
			break
		right = next
		right_nudges.append(ReplayActions.NUDGE_RIGHT)
		spots.append({"pos": right, "nudges": right_nudges.duplicate()})
	return spots


func _locks_inside(main: Node, pid: String, origin: Vector2i, rot: int) -> bool:
	for cell in main.bot_cell_list(pid, rot, origin):
		if int(cell.y) < 0:
			return false
	return true


func _score_landing(main: Node, pid: String, origin: Vector2i, rot: int) -> float:
	var cols := int(main.COLS)
	var rows := int(main.ROWS)
	var grid: Array = []
	for row in main.board:
		grid.append((row as Array).duplicate())
	for cell in main.bot_cell_list(pid, rot, origin):
		var x := int(cell.x)
		var cell_y := int(cell.y)
		if x < 0 or x >= cols or cell_y < 0 or cell_y >= rows:
			return -1.0e30
		grid[cell_y][x] = pid
	var cleared := 0
	var y := rows - 1
	while y >= 0:
		var full := true
		for x in cols:
			if str(grid[y][x]).is_empty():
				full = false
				break
		if full:
			grid.remove_at(y)
			var empty: Array = []
			empty.resize(cols)
			empty.fill("")
			grid.push_front(empty)
			cleared += 1
		else:
			y -= 1
	var holes := 0
	var height_sum := 0
	var heights: Array[int] = []
	for x in cols:
		var seen := false
		var height := 0
		for row_y in rows:
			if not str(grid[row_y][x]).is_empty():
				if not seen:
					height = rows - row_y
				seen = true
			elif seen:
				holes += 1
		heights.append(height)
		height_sum += height
	var bumpiness := 0
	for i in heights.size() - 1:
		bumpiness += absi(heights[i] - heights[i + 1])
	return (
		float(cleared) * WEIGHT_LINES
		+ float(holes) * WEIGHT_HOLES
		+ float(bumpiness) * WEIGHT_BUMPINESS
		+ float(height_sum) * WEIGHT_HEIGHT
	)
