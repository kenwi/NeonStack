extends Node2D

## On-screen buttons for touch-primary sessions (phone and tablet browsers).
## Held move and soft-drop buttons drive the same input actions as the arrow keys.
## Taps call the existing rotate, hard-drop, and hold paths.
## A tap that misses the buttons is one of four screen quadrants.

const PlayDevice = preload("res://game/platform/play_device.gd")

const GAP := 8.0
const MIN_BUTTON := 44.0
const MAX_BUTTON := 68.0
const SIDE_MARGIN := 10.0
const SCALE_MIN := 1
const SCALE_MAX := 4
const SCALE_DEFAULT := 2
const CONFIG_PATH := "user://touch.cfg"

const HOLD_ACTIONS := {
	"left": "ui_left",
	"right": "ui_right",
	"down": "ui_down",
}
const TAP_ACTIONS := ["rot", "ccw", "drop", "hold"]
const UTILITY := ["pause", "help", "scores", "restart", "mute", "scale_down", "scale_up"]
const LABELS := {
	"left": "<",
	"right": ">",
	"down": "DOWN",
	"rot": "ROT",
	"ccw": "CCW",
	"drop": "DROP",
	"hold": "HOLD",
	"pause": "PAUSE",
	"help": "HELP",
	"scores": "SCORES",
	"restart": "RESTART",
	"mute": "MUTE",
}

var _font: Font
var _fingers: Dictionary = {}
var _hold_counts := {"ui_left": 0, "ui_right": 0, "ui_down": 0}
var _rects: Dictionary = {}
var _scale := SCALE_DEFAULT
var _metric_key := ""
var _metric: Dictionary = {}


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_load_scale()


func reserves_layout() -> bool:
	return PlayDevice.is_touch_primary()


func utility_height() -> float:
	if not reserves_layout():
		return 0.0
	return float(_metrics().utility_h)


func band_height(_width: float) -> float:
	if not reserves_layout():
		return 0.0
	return float(_metrics().band_h)


func toast_bottom_inset() -> float:
	if not reserves_layout():
		return 18.0
	return band_height(get_viewport_rect().size.x) + 12.0


func handle_input(event: InputEvent) -> bool:
	if not _controls_visible():
		_release_all()
		return false
	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			return _begin_finger(touch_event.index, touch_event.position)
		return _end_finger(touch_event.index)
	if event is InputEventScreenDrag:
		var drag_event := event as InputEventScreenDrag
		if not _fingers.has(drag_event.index):
			return false
		_retarget(drag_event.index, drag_event.position)
		return true
	return false


func _process(_delta: float) -> void:
	if not _controls_visible():
		_release_all()
	queue_redraw()


func _controls_visible() -> bool:
	if not PlayDevice.is_touch_primary():
		return false
	var main := get_parent()
	if main == null:
		return false
	if main.help_open or main.score_open or main.game_over:
		return false
	if main.highscores != null and main.highscores.is_showing_overlay():
		return false
	return true


func _begin_finger(index: int, pos: Vector2) -> bool:
	_rebuild_rects()
	var id := _hit(pos)
	if id == "":
		if _tap_quadrant(pos):
			_fingers[index] = ""
			return true
		return false
	var main := get_parent()
	if main.paused and _is_gameplay(id):
		main.paused = false
		main.queue_redraw()
		_fingers[index] = ""
		queue_redraw()
		return true
	_fingers[index] = id
	_on_press(id)
	queue_redraw()
	return true


func _end_finger(index: int) -> bool:
	if not _fingers.has(index):
		return false
	var id: String = _fingers[index]
	_fingers.erase(index)
	if HOLD_ACTIONS.has(id):
		_set_hold(str(HOLD_ACTIONS[id]), false)
	queue_redraw()
	return true


func _retarget(index: int, pos: Vector2) -> void:
	var prev: String = _fingers[index]
	if prev == "":
		return
	_rebuild_rects()
	var next := _hit(pos)
	if next == prev:
		return
	if HOLD_ACTIONS.has(prev):
		_set_hold(str(HOLD_ACTIONS[prev]), false)
	# Sliding onto a tap button must not fire it. Only held move buttons retarget.
	if next != "" and HOLD_ACTIONS.has(next):
		_set_hold(str(HOLD_ACTIONS[next]), true)
		_fingers[index] = next
	else:
		_fingers.erase(index)
	queue_redraw()


func _on_press(id: String) -> void:
	if HOLD_ACTIONS.has(id):
		_set_hold(str(HOLD_ACTIONS[id]), true)
		return
	var main := get_parent()
	if id == "rot" and _can_play():
		main._try_rotate(1)
	elif id == "ccw" and _can_play():
		main._try_rotate(-1)
	elif id == "drop":
		main._hard_drop()
	elif id == "hold":
		main._hold()
	elif id == "pause":
		main.paused = not main.paused
		main.queue_redraw()
	elif id == "help":
		main.help_open = true
		main.score_open = false
		if main.highscores != null:
			main.highscores.close_overlay()
		main.queue_redraw()
	elif id == "scores":
		main.help_open = false
		main.score_open = false
		if main.highscores != null:
			main.highscores.open_leaderboard()
		main.queue_redraw()
	elif id == "restart":
		main._new_game()
	elif id == "mute":
		var music := main.get_node_or_null("Music")
		if music != null:
			music.toggle_mute()
	elif id == "scale_down":
		_set_scale(_scale - 1)
	elif id == "scale_up":
		_set_scale(_scale + 1)


func _tap_quadrant(pos: Vector2) -> bool:
	# Upper half nudges one column. Lower half rotates or hard-drops.
	# Buttons already won the hit test, so this is only the open screen.
	if not _can_play():
		return false
	var main := get_parent()
	var vp := get_viewport_rect().size
	var left := pos.x < vp.x * 0.5
	var upper := pos.y < vp.y * 0.5
	if upper:
		main._try_move(-1 if left else 1, 0)
	elif left:
		main._try_rotate(1)
	else:
		main._hard_drop()
	return true


func _can_play() -> bool:
	var main := get_parent()
	return (
		not main.game_over
		and not main.paused
		and not main.help_open
		and not main.score_open
		and main.clear_timer <= 0.0
		and not main._highscores_open()
	)


func _is_gameplay(id: String) -> bool:
	return HOLD_ACTIONS.has(id) or id in TAP_ACTIONS


func _set_hold(action: String, down: bool) -> void:
	var count: int = int(_hold_counts[action])
	if down:
		if count == 0:
			Input.action_press(action)
		_hold_counts[action] = count + 1
	else:
		count = maxi(0, count - 1)
		_hold_counts[action] = count
		if count == 0:
			Input.action_release(action)


func _release_all() -> void:
	if _fingers.is_empty() and int(_hold_counts["ui_left"]) == 0 and int(_hold_counts["ui_right"]) == 0 and int(_hold_counts["ui_down"]) == 0:
		return
	_fingers.clear()
	for action in _hold_counts.keys():
		if int(_hold_counts[action]) > 0:
			Input.action_release(action)
		_hold_counts[action] = 0
	queue_redraw()


func _set_scale(next: int) -> void:
	next = clampi(next, SCALE_MIN, SCALE_MAX)
	if next == _scale:
		return
	_scale = next
	_metric_key = ""
	_save_scale()
	var main := get_parent()
	if main != null and main.has_method("_layout"):
		main._layout()
	queue_redraw()


func _load_scale() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	_scale = clampi(int(cfg.get_value("ui", "scale", SCALE_DEFAULT)), SCALE_MIN, SCALE_MAX)


func _save_scale() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "scale", _scale)
	cfg.save(CONFIG_PATH)


func _hit(pos: Vector2) -> String:
	for id in _rects.keys():
		var rect: Rect2 = _rects[id]
		if rect.has_point(pos):
			return str(id)
	return ""


func _base_button(width: float) -> float:
	var fit := (width - SIDE_MARGIN * 2.0 - GAP * 6.0) / 7.0
	if fit < MIN_BUTTON:
		var narrow := (width - SIDE_MARGIN * 2.0 - GAP * 3.0) / 4.0
		return clampf(narrow, 36.0, MIN_BUTTON)
	return clampf(fit, MIN_BUTTON, MAX_BUTTON)


func _chrome_limit(height: float) -> float:
	# Leave a 20-row board at the touch minimum cell, plus the title and frame.
	var min_cell := 6.0
	var frame_outer := 17.0
	var title_gap := 8.0
	var margin := 12.0
	var title_size := maxi(18, int(round(28.0 * min_cell / 36.0)))
	var title_block := 22.0
	if _font != null:
		title_block = _font.get_ascent(title_size) + _font.get_descent(title_size)
	var stack := title_block + title_gap + frame_outer * 2.0 + 20.0 * min_cell
	return maxf(96.0, height - stack - margin * 2.0 - 8.0)


func _metrics() -> Dictionary:
	var vp := get_viewport_rect().size
	var key := "%d|%d|%d" % [int(vp.x), int(vp.y), _scale]
	if key == _metric_key and not _metric.is_empty():
		return _metric
	var height := _base_button(vp.x) * float(_scale)
	var limit := _chrome_limit(vp.y)
	var chosen := _measure_dict(height, vp)
	var guard := 0
	while float(chosen.chrome) > limit and height > 36.0 and guard < 240:
		height -= 1.0
		chosen = _measure_dict(height, vp)
		guard += 1
	_metric = chosen
	_metric_key = key
	return _metric


func _measure_dict(height: float, vp: Vector2) -> Dictionary:
	var gap := GAP
	var margin := SIDE_MARGIN
	var inner := maxf(40.0, vp.x - margin * 2.0)
	var slot4 := (inner - gap * 3.0) / 4.0
	var button_w := minf(height, maxf(36.0, slot4))
	var left_span := _span(3, button_w, gap)
	var right_span := _span(4, button_w, gap)
	var one_row := left_span + gap + right_span <= inner + 0.5
	var play_rows := 1 if one_row else 2
	var band_h := margin + float(play_rows) * height + float(play_rows - 1) * gap + margin
	var util_floor := minf(64.0, height)
	var per := maxi(1, int(floor((inner + gap) / (util_floor + gap))))
	var util_rows := int(ceil(float(UTILITY.size()) / float(per)))
	var utility_h := margin + float(util_rows) * height + float(util_rows - 1) * gap + margin
	return {
		"button_h": height,
		"button_w": button_w,
		"left_span": left_span,
		"right_span": right_span,
		"one_row": one_row,
		"per": per,
		"inner": inner,
		"utility_h": utility_h,
		"band_h": band_h,
		"chrome": utility_h + band_h,
	}


func _span(count: int, button_w: float, gap: float) -> float:
	return float(count) * button_w + float(count - 1) * gap


func _rebuild_rects() -> void:
	_rects.clear()
	if not _controls_visible() or _font == null:
		return
	_place(_metrics())


func _place(m: Dictionary) -> void:
	var vp := get_viewport_rect().size
	var gap := GAP
	var margin := SIDE_MARGIN
	var button_h := float(m.button_h)
	var button_w := float(m.button_w)
	var per := int(m.per)
	var index := 0
	var y := margin
	while index < UTILITY.size():
		var n := mini(per, UTILITY.size() - index)
		var w := (float(m.inner) - gap * float(n - 1)) / float(n)
		var x := margin
		for _i in n:
			var id: String = UTILITY[index]
			_rects[id] = Rect2(x, y, w, button_h)
			x += w + gap
			index += 1
		y += button_h + gap
	var band_top := vp.y - float(m.band_h) + margin
	var left := ["left", "down", "right"]
	var right := ["ccw", "rot", "drop", "hold"]
	if bool(m.one_row):
		_place_row(left, margin, band_top, button_w, button_h, gap)
		_place_row(right, vp.x - margin - float(m.right_span), band_top, button_w, button_h, gap)
	else:
		_place_row(right, vp.x - margin - float(m.right_span), band_top, button_w, button_h, gap)
		_place_row(left, margin, band_top + button_h + gap, button_w, button_h, gap)


func _place_row(ids: Array, origin_x: float, origin_y: float, button_w: float, button_h: float, gap: float) -> void:
	for i in ids.size():
		var id := str(ids[i])
		_rects[id] = Rect2(origin_x + float(i) * (button_w + gap), origin_y, button_w, button_h)


func _draw() -> void:
	if not _controls_visible() or _font == null:
		return
	_rebuild_rects()
	var main := get_parent()
	for id in _rects.keys():
		var label := _button_label(str(id), main.paused)
		var held := false
		if HOLD_ACTIONS.has(id):
			held = int(_hold_counts[str(HOLD_ACTIONS[id])]) > 0
		elif id == "scale_down" and _scale == SCALE_MIN:
			held = true
		elif id == "scale_up" and _scale == SCALE_MAX:
			held = true
		_draw_button(_rects[id], label, held)


func _button_label(id: String, paused: bool) -> String:
	if id == "pause" and paused:
		return "RESUME"
	if id == "scale_down":
		return "%dx" % (maxi(SCALE_MIN, _scale - 1) if _scale > SCALE_MIN else _scale)
	if id == "scale_up":
		return "%dx" % (mini(SCALE_MAX, _scale + 1) if _scale < SCALE_MAX else _scale)
	return str(LABELS[id])


func _draw_button(rect: Rect2, label: String, pressed: bool) -> void:
	var fill := Color("123047", 0.96) if pressed else Color("0b1a28", 0.92)
	var border := Color("8ef7ff", 0.9) if pressed else Color("8ef7ff", 0.5)
	draw_rect(rect, fill, true, -1.0, true)
	draw_rect(rect, border, false, 2.0, true)
	var size := _fit_font(label, rect.size.x, clampi(int(rect.size.y * 0.32), 12, 42))
	var text_w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var baseline := rect.position.y + (rect.size.y + _font.get_ascent(size) - _font.get_descent(size)) * 0.5
	draw_string(
		_font,
		Vector2(rect.position.x + (rect.size.x - text_w) * 0.5, baseline),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		size,
		Color("e8f7ff")
	)


func _fit_font(text: String, width: float, max_size: int) -> int:
	var size := max_size
	while size > 10:
		if _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width - 8.0:
			return size
		size -= 1
	return size
