extends Node2D

## Visual juice for hard drops, locks, line clears, and score callouts.
## Toggleable; when off, all event hooks no-op and nothing is drawn.

const CONFIG_PATH := "user://juice.cfg"
const CLEAR_NAMES := ["", "SINGLE", "DOUBLE", "TRIPLE", "TETRIS"]
## Tuned from live boards: casual breaks early, elite classic runs sit near 75k-100k.
const SCORE_MILESTONES := [1000, 5000, 10000, 25000, 50000, 75000, 100000]

var enabled := true
## When true, FX hooks no-op without changing the user toggle (used for replay seek).
var _silent := false
var _font: Font
var _trail: Array = []
var _impacts: Array = []
var _bursts: Array = []
var _floaters: Array = []
var _banner_text := ""
var _banner_timer := 0.0
var _banner_color := Color("8ef7ff")
var _level_flash_timer := 0.0
var _level_flash_level := 1
var _milestone_flash_timer := 0.0
var _milestone_flash_score := 0
var _milestone_index := 0
var _combo := 0


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_load_prefs()


func is_enabled() -> bool:
	return enabled


func toggle() -> bool:
	enabled = not enabled
	if not enabled:
		_clear_fx()
	_save_prefs()
	queue_redraw()
	return enabled


func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	if not enabled:
		_clear_fx()
	_save_prefs()
	queue_redraw()


func begin_silent() -> void:
	_silent = true
	_clear_fx()


func end_silent() -> void:
	_silent = false


func _fx_on() -> bool:
	return enabled and not _silent


func reset_run() -> void:
	_combo = 0
	_milestone_index = 0
	_clear_fx()


func hard_drop(cells_from: Array, cells_to: Array, color: Color, board_origin: Vector2, cell_size: float) -> void:
	if not _fx_on() or cells_from.is_empty() or cells_to.is_empty():
		return
	var start_y := 0
	var end_y := 0
	for c in cells_from:
		start_y += c.y
	for c in cells_to:
		end_y += c.y
	start_y = int(round(float(start_y) / float(cells_from.size())))
	end_y = int(round(float(end_y) / float(cells_to.size())))
	var fall := maxi(0, end_y - start_y)
	if fall <= 0:
		return
	_trail.append({
		"cells": cells_to.duplicate(),
		"color": color,
		"life": 0.28,
		"max_life": 0.28,
		"fall": fall,
		"origin": board_origin,
		"cell": cell_size,
	})
	queue_redraw()


func lock_impact(cells: Array, color: Color, board_origin: Vector2, cell_size: float) -> void:
	if not _fx_on() or cells.is_empty():
		return
	_impacts.append({
		"cells": cells.duplicate(),
		"color": color,
		"life": 0.22,
		"max_life": 0.22,
		"origin": board_origin,
		"cell": cell_size,
	})
	queue_redraw()


func line_clear_begin(rows: Array, board: Array, colors: Dictionary, board_origin: Vector2, cell_size: float) -> void:
	if not _fx_on() or rows.is_empty():
		return
	for y in rows:
		for x in 10:
			var pid: String = str(board[y][x])
			if pid == "" or not colors.has(pid):
				continue
			var col: Color = colors[pid]
			var center := board_origin + Vector2((float(x) + 0.5) * cell_size, (float(y) + 0.5) * cell_size)
			for _i in 3:
				var dir := Vector2(randf_range(-1.0, 1.0), randf_range(-1.2, 0.4)).normalized()
				_bursts.append({
					"pos": center,
					"vel": dir * randf_range(40.0, 140.0) * maxf(0.6, cell_size / 36.0),
					"color": col,
					"life": randf_range(0.28, 0.55),
					"max_life": 0.55,
					"size": cell_size * randf_range(0.12, 0.28),
				})
	queue_redraw()


func line_clear_scored(cleared: int, points: int, board_center: Vector2) -> void:
	if not _fx_on() or cleared <= 0:
		return
	_combo += 1
	var label: String = CLEAR_NAMES[cleared] if cleared < CLEAR_NAMES.size() else "%d LINES" % cleared
	var color := Color("8ef7ff")
	if cleared >= 4:
		color = Color("ffd166")
		_banner_text = "TETRIS"
		_banner_timer = 0.9
		_banner_color = color
	elif cleared == 3:
		color = Color("c084fc")
	elif cleared == 2:
		color = Color("4ade80")
	_floaters.append({
		"text": label,
		"pos": board_center + Vector2(0, -28.0),
		"vel": Vector2(0, -52.0),
		"color": color,
		"life": 0.95,
		"max_life": 0.95,
		"size": 48 if cleared >= 4 else 40,
	})
	_floaters.append({
		"text": "+%d" % points,
		"pos": board_center + Vector2(0, 18.0),
		"vel": Vector2(0, -42.0),
		"color": Color("e8f7ff"),
		"life": 0.9,
		"max_life": 0.9,
		"size": 36,
	})
	if _combo > 1:
		_floaters.append({
			"text": "COMBO x%d" % _combo,
			"pos": board_center + Vector2(0, 64.0),
			"vel": Vector2(0, -34.0),
			"color": Color("ffd166"),
			"life": 1.0,
			"max_life": 1.0,
			"size": 44,
		})
	queue_redraw()


func note_no_clear() -> void:
	_combo = 0


func level_up(level: int, board_center: Vector2) -> void:
	if not _fx_on():
		return
	_level_flash_level = level
	_level_flash_timer = 1.1
	_floaters.append({
		"text": "LEVEL %d" % level,
		"pos": board_center + Vector2(0, -72.0),
		"vel": Vector2(0, -28.0),
		"color": Color("ffd166"),
		"life": 1.2,
		"max_life": 1.2,
		"size": 52,
	})
	queue_redraw()


func note_score(score: int, board_center: Vector2) -> void:
	if not _fx_on() or score <= 0:
		return
	var fired := false
	while _milestone_index < SCORE_MILESTONES.size() and score >= int(SCORE_MILESTONES[_milestone_index]):
		_milestone_flash_score = int(SCORE_MILESTONES[_milestone_index])
		_milestone_index += 1
		fired = true
	if not fired:
		return
	_milestone_flash_timer = 1.0
	_floaters.append({
		"text": _format_milestone(_milestone_flash_score),
		"pos": board_center + Vector2(0, 96.0),
		"vel": Vector2(0, -40.0),
		"color": Color("8ef7ff"),
		"life": 1.15,
		"max_life": 1.15,
		"size": 48,
	})
	queue_redraw()


func _format_milestone(score: int) -> String:
	if score >= 1000 and score % 1000 == 0:
		return "%dK!" % int(score / 1000.0)
	return "%d!" % score


func active_pulse_scale(grounded: bool, lock_timer: float, lock_limit: float = 0.5) -> float:
	if not _fx_on() or not grounded or lock_limit <= 0.0:
		return 1.0
	var t := clampf(lock_timer / lock_limit, 0.0, 1.0)
	# Quicker pulse as lock nears commit.
	var speed := 6.0 + t * 10.0
	return 1.0 - 0.08 * t - 0.06 * t * absf(sin(Time.get_ticks_msec() * 0.001 * speed))


func tick(delta: float) -> void:
	if not _fx_on():
		return
	_tick_list(_trail, delta)
	_tick_list(_impacts, delta)
	var alive_bursts: Array = []
	for item in _bursts:
		item.life = float(item.life) - delta
		if float(item.life) <= 0.0:
			continue
		item.pos = item.pos + item.vel * delta
		item.vel = item.vel + Vector2(0, 180.0) * delta
		alive_bursts.append(item)
	_bursts = alive_bursts
	var alive_floaters: Array = []
	for item in _floaters:
		item.life = float(item.life) - delta
		if float(item.life) <= 0.0:
			continue
		item.pos = item.pos + item.vel * delta
		alive_floaters.append(item)
	_floaters = alive_floaters
	if _banner_timer > 0.0:
		_banner_timer = maxf(0.0, _banner_timer - delta)
	if _level_flash_timer > 0.0:
		_level_flash_timer = maxf(0.0, _level_flash_timer - delta)
	if _milestone_flash_timer > 0.0:
		_milestone_flash_timer = maxf(0.0, _milestone_flash_timer - delta)
	if (
		not _trail.is_empty()
		or not _impacts.is_empty()
		or not _bursts.is_empty()
		or not _floaters.is_empty()
		or _banner_timer > 0.0
		or _level_flash_timer > 0.0
		or _milestone_flash_timer > 0.0
	):
		queue_redraw()


func draw_fx(host: CanvasItem) -> void:
	if not _fx_on() or _font == null:
		return
	if _level_flash_timer > 0.0:
		var life := clampf(_level_flash_timer / 1.1, 0.0, 1.0)
		# Two-beat flash: bright hit, brief dip, second wash.
		var beat := absf(sin((1.0 - life) * PI * 2.0))
		var wash := Color("ffd166", 0.12 + 0.22 * beat * life)
		host.draw_rect(Rect2(Vector2.ZERO, host.get_viewport_rect().size), wash, true, -1.0, true)
		var frame_parent := get_parent()
		if frame_parent != null and "board_origin" in frame_parent and "cell_size" in frame_parent:
			var origin: Vector2 = frame_parent.board_origin
			var cell: float = float(frame_parent.cell_size)
			var board := Rect2(origin, Vector2(10.0 * cell, 20.0 * cell))
			var rim := Color("8ef7ff", 0.35 + 0.55 * beat * life)
			host.draw_rect(board.grow(6.0 + 10.0 * beat), rim, false, 3.0 + 4.0 * beat, true)
	if _milestone_flash_timer > 0.0:
		var m_life := clampf(_milestone_flash_timer / 1.0, 0.0, 1.0)
		var m_beat := absf(sin((1.0 - m_life) * PI * 2.0))
		var m_wash := Color("8ef7ff", 0.10 + 0.20 * m_beat * m_life)
		host.draw_rect(Rect2(Vector2.ZERO, host.get_viewport_rect().size), m_wash, true, -1.0, true)
		var m_parent := get_parent()
		if m_parent != null and "board_origin" in m_parent and "cell_size" in m_parent:
			var m_origin: Vector2 = m_parent.board_origin
			var m_cell: float = float(m_parent.cell_size)
			var m_board := Rect2(m_origin, Vector2(10.0 * m_cell, 20.0 * m_cell))
			var m_rim := Color("ffd166", 0.30 + 0.50 * m_beat * m_life)
			host.draw_rect(m_board.grow(5.0 + 8.0 * m_beat), m_rim, false, 2.5 + 3.0 * m_beat, true)
	for item in _trail:
		var life := float(item.life) / float(item.max_life)
		var origin: Vector2 = item.origin
		var cell: float = item.cell
		var col: Color = item.color
		var fall: int = int(item.fall)
		for c in item.cells:
			for step in mini(fall, 8):
				var t := float(step + 1) / float(mini(fall, 8) + 1)
				var y := float(c.y) - float(fall) * (1.0 - life) * (1.0 - t) * 0.35 - float(step) * 0.35
				var alpha := 0.18 * life * (1.0 - t)
				var rect := _cell_rect(origin, cell, Vector2(c.x, y), 0.85)
				var streak := col
				streak.a = alpha
				host.draw_rect(rect, streak, true, -1.0, true)
	for item in _impacts:
		var life := float(item.life) / float(item.max_life)
		var origin: Vector2 = item.origin
		var cell: float = item.cell
		var col: Color = item.color
		for c in item.cells:
			if c.y < 0:
				continue
			var rect := _cell_rect(origin, cell, Vector2(c.x, c.y), 1.0)
			var flash := Color.WHITE
			flash.a = 0.55 * life
			host.draw_rect(rect.grow(3.0 * life), flash, false, 2.0, true)
			var fill := col
			fill.a = 0.35 * life
			host.draw_rect(rect, fill, true, -1.0, true)
	for item in _bursts:
		var life := float(item.life) / maxf(0.001, float(item.max_life))
		var col: Color = item.color
		col.a = 0.85 * life
		var size: float = float(item.size) * (0.6 + 0.4 * life)
		var pos: Vector2 = item.pos
		host.draw_rect(Rect2(pos - Vector2(size, size) * 0.5, Vector2(size, size)), col, true, -1.0, true)
	for item in _floaters:
		var life := float(item.life) / float(item.max_life)
		var col: Color = item.color
		col.a = life
		_draw_centered(host, item.pos, str(item.text), int(item.size), col)
	if _banner_timer > 0.0:
		var life := clampf(_banner_timer / 0.9, 0.0, 1.0)
		var pop := 1.0 + 0.15 * sin((1.0 - life) * PI)
		var col := _banner_color
		col.a = life
		var parent := get_parent()
		var center := Vector2.ZERO
		if parent != null and parent.has_method("_board_center"):
			center = parent._board_center()
		else:
			center = get_viewport_rect().size * 0.5
		_draw_centered(host, center + Vector2(0, -cell_guess(parent) * 2.0), _banner_text, int(42.0 * pop), col)


func cell_guess(parent: Node) -> float:
	if parent != null and "cell_size" in parent:
		return float(parent.cell_size)
	return 36.0


func _cell_rect(origin: Vector2, cell: float, grid: Vector2, scale_mul: float) -> Rect2:
	var gap := 2.0
	var size := (cell - gap * 2.0) * scale_mul
	var inset := (cell - size) * 0.5
	return Rect2(origin + Vector2(grid.x * cell + inset, grid.y * cell + inset), Vector2(size, size))


func _draw_centered(host: CanvasItem, center: Vector2, text: String, size: int, color: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	host.draw_string(
		_font,
		Vector2(center.x - w * 0.5, center.y + _font.get_ascent(size) * 0.35),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		size,
		color
	)


func _tick_list(list: Array, delta: float) -> void:
	var alive: Array = []
	for item in list:
		item.life = float(item.life) - delta
		if float(item.life) > 0.0:
			alive.append(item)
	list.clear()
	list.append_array(alive)


func _clear_fx() -> void:
	_trail.clear()
	_impacts.clear()
	_bursts.clear()
	_floaters.clear()
	_banner_text = ""
	_banner_timer = 0.0
	_level_flash_timer = 0.0
	_milestone_flash_timer = 0.0
	queue_redraw()


func _load_prefs() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	enabled = bool(cfg.get_value("fx", "enabled", true))


func _save_prefs() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("fx", "enabled", enabled)
	cfg.save(CONFIG_PATH)
