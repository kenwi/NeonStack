extends Node2D

## On-screen buttons for touch-primary sessions (phone and tablet browsers).
## Held move and soft-drop buttons drive the same input actions as the arrow keys.
## Taps call the existing rotate, hard-drop, and hold paths.

const PlayDevice = preload("res://game/platform/play_device.gd")

const GAP := 8.0
const MIN_BUTTON := 44.0
const MAX_BUTTON := 68.0
const SIDE_MARGIN := 10.0
const UTILITY_H := 52.0

const HOLD_ACTIONS := {
	"left": "ui_left",
	"right": "ui_right",
	"down": "ui_down",
}
const TAP_ACTIONS := ["rot", "ccw", "drop", "hold"]
const UTILITY := ["pause", "help", "scores", "restart", "mute"]
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


func _ready() -> void:
	_font = ThemeDB.fallback_font


func reserves_layout() -> bool:
	return PlayDevice.is_touch_primary()


func utility_height() -> float:
	return UTILITY_H if reserves_layout() else 0.0


func band_height(width: float) -> float:
	if not reserves_layout():
		return 0.0
	var button := _button_size(width)
	var rows := 2 if _two_rows(width) else 1
	return SIDE_MARGIN + float(rows) * button + float(rows - 1) * GAP + SIDE_MARGIN


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


func _button_size(width: float) -> float:
	var height := get_viewport_rect().size.y
	var cap := MAX_BUTTON
	# A short landscape viewport needs a shorter band so the board can still fit.
	if height > 0.0 and height < 520.0:
		cap = MIN_BUTTON
	if _two_rows(width):
		# The right cluster is the wider row (four buttons).
		var narrow := (width - SIDE_MARGIN * 2.0 - GAP * 3.0) / 4.0
		return clampf(narrow, 36.0, minf(MIN_BUTTON, cap))
	var fit := (width - SIDE_MARGIN * 2.0 - GAP * 6.0) / 7.0
	return clampf(fit, MIN_BUTTON, cap)


func _two_rows(width: float) -> bool:
	var fit := (width - SIDE_MARGIN * 2.0 - GAP * 6.0) / 7.0
	return fit < MIN_BUTTON


func _hit(pos: Vector2) -> String:
	for id in _rects.keys():
		var rect: Rect2 = _rects[id]
		if rect.has_point(pos):
			return str(id)
	return ""


func _rebuild_rects() -> void:
	_rects.clear()
	if not _controls_visible() or _font == null:
		return
	var vp := get_viewport_rect().size
	var utility_w := (vp.x - SIDE_MARGIN * 2.0 - GAP * float(UTILITY.size() - 1)) / float(UTILITY.size())
	var utility_y := 4.0
	var utility_h := 44.0
	for i in UTILITY.size():
		var id: String = UTILITY[i]
		_rects[id] = Rect2(SIDE_MARGIN + float(i) * (utility_w + GAP), utility_y, utility_w, utility_h)
	var button := _button_size(vp.x)
	var band_top := vp.y - band_height(vp.x) + SIDE_MARGIN
	if _two_rows(vp.x):
		var right_w := button * 4.0 + GAP * 3.0
		var right_x := maxf(SIDE_MARGIN, vp.x - SIDE_MARGIN - right_w)
		_place_row(["ccw", "rot", "drop", "hold"], right_x, band_top, button)
		_place_row(["left", "down", "right"], SIDE_MARGIN, band_top + button + GAP, button)
	else:
		_place_row(["left", "down", "right"], SIDE_MARGIN, band_top, button)
		var right_w := button * 4.0 + GAP * 3.0
		_place_row(["ccw", "rot", "drop", "hold"], vp.x - SIDE_MARGIN - right_w, band_top, button)


func _place_row(ids: Array, origin_x: float, origin_y: float, button: float) -> void:
	for i in ids.size():
		var id: String = ids[i]
		_rects[id] = Rect2(origin_x + float(i) * (button + GAP), origin_y, button, button)


func _draw() -> void:
	if not _controls_visible() or _font == null:
		return
	_rebuild_rects()
	var main := get_parent()
	for id in _rects.keys():
		var label: String = str(LABELS[id])
		if id == "pause" and main.paused:
			label = "RESUME"
		var held := false
		if HOLD_ACTIONS.has(id):
			held = int(_hold_counts[str(HOLD_ACTIONS[id])]) > 0
		_draw_button(_rects[id], label, held)


func _draw_button(rect: Rect2, label: String, pressed: bool) -> void:
	var fill := Color("123047", 0.96) if pressed else Color("0b1a28", 0.92)
	var border := Color("8ef7ff", 0.9) if pressed else Color("8ef7ff", 0.5)
	draw_rect(rect, fill, true, -1.0, true)
	draw_rect(rect, border, false, 2.0, true)
	var size := _fit_font(label, rect.size.x, clampi(int(rect.size.y * 0.34), 12, 22))
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
