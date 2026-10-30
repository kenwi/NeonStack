extends Node2D

## On-screen buttons for touch-primary sessions (phone and tablet browsers).
## Held move and soft-drop buttons feed the same action bus as the keyboard.
## Taps emit rotate, hard-drop, and hold actions.
## A tap that misses the buttons is one of four screen quadrants.

const PlayDevice = preload("res://game/platform/play_device.gd")
const ReplayActions = preload("res://game/replay/actions.gd")

const GAP := 8.0
const MIN_BUTTON := 44.0
const MAX_BUTTON := 68.0
const SIDE_MARGIN := 10.0
const SCALE_MIN := 1
const SCALE_MAX := 4
const SCALE_DEFAULT := 2
const CONFIG_PATH := "user://touch.cfg"

const HOLD_ACTIONS := {
	"left": "left",
	"right": "right",
	"down": "soft",
}
const TAP_ACTIONS := ["rot", "ccw", "drop", "hold"]
const UTILITY := ["pause", "help", "scores", "restart", "mute", "full", "zones", "scale_down", "scale_up"]
## Kept on its own row under the crowded utility strip.
const UTILITY_BELOW := ["next", "juice", "bg"]
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
	"full": "FULL",
	"zones": "ZONES",
	"next": "NEXT TRACK",
	"juice": "JUICE",
	"bg": "BG",
}

var _font: Font
var _fingers: Dictionary = {}
var _hold_counts := {"left": 0, "right": 0, "soft": 0}
var _rects: Dictionary = {}
var _scale := SCALE_DEFAULT
var _show_zones := false
var _suppress_play_until_msec := 0
## After any menu closes, ignore quadrant taps until that gesture fully ends.
var _zones_locked := false
var _overlay_blocked := true
var _metric_key := ""
var _metric: Dictionary = {}


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_load_prefs()


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


func suppress_play_taps(duration_msec: int = 450) -> void:
	# After closing an overlay, the same finger (or a ghost mouse click) must not
	# land in a quadrant and hard-drop the piece.
	_suppress_play_until_msec = maxi(
		_suppress_play_until_msec,
		Time.get_ticks_msec() + maxi(0, duration_msec)
	)
	_zones_locked = true


func handle_input(event: InputEvent) -> bool:
	_sync_overlay_block()
	if not _controls_visible():
		_release_all()
		return false
	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			return _begin_finger(touch_event.index, touch_event.position)
		# Lift after dismissing a menu may never have called begin_finger.
		if not _fingers.has(touch_event.index):
			if _zones_locked:
				# That closing gesture ended; time suppress still covers ghost clicks.
				_zones_locked = false
				return true
			return false
		return _end_finger(touch_event.index)
	if event is InputEventScreenDrag:
		var drag_event := event as InputEventScreenDrag
		if not _fingers.has(drag_event.index):
			return false
		_retarget(drag_event.index, drag_event.position)
		return true
	return false


func _process(_delta: float) -> void:
	_sync_overlay_block()
	if not _controls_visible():
		_release_all()
	queue_redraw()


func _controls_visible() -> bool:
	if not PlayDevice.is_touch_primary():
		return false
	return not _is_overlay_blocking()


func _is_overlay_blocking() -> bool:
	var main := get_parent()
	if main == null:
		return true
	if main.help_open or main.score_open or main.game_over:
		return true
	if main.replay_mode:
		return true
	if main.highscores != null and main.highscores.is_showing_overlay():
		return true
	return false


func _sync_overlay_block() -> void:
	var blocked := _is_overlay_blocking()
	if _overlay_blocked and not blocked:
		# Menu just closed - lock zones until this gesture ends.
		suppress_play_taps(450)
	_overlay_blocked = blocked


func _begin_finger(index: int, pos: Vector2) -> bool:
	_rebuild_rects()
	var id := _hit(pos)
	if id == "":
		if _zones_blocked():
			_fingers[index] = ""
			return true
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
	if _zones_blocked() and _is_gameplay(id):
		_fingers[index] = ""
		return true
	_fingers[index] = id
	_on_press(id)
	queue_redraw()
	return true


func _zones_blocked() -> bool:
	return _zones_locked or Time.get_ticks_msec() < _suppress_play_until_msec


func _clear_zone_lock_if_idle() -> void:
	if not _fingers.is_empty():
		return
	if Time.get_ticks_msec() < _suppress_play_until_msec:
		return
	_zones_locked = false


func _end_finger(index: int) -> bool:
	if not _fingers.has(index):
		return false
	var id: String = _fingers[index]
	_fingers.erase(index)
	if HOLD_ACTIONS.has(id):
		_set_hold(str(HOLD_ACTIONS[id]), false)
	_clear_zone_lock_if_idle()
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
		main.apply_action(ReplayActions.ROT)
	elif id == "ccw" and _can_play():
		main.apply_action(ReplayActions.CCW)
	elif id == "drop" and _can_play():
		main.apply_action(ReplayActions.DROP)
	elif id == "hold" and _can_play():
		main.apply_action(ReplayActions.HOLD)
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
		if main.replay_mode:
			main.stop_replay()
		else:
			main._new_game()
	elif id == "mute":
		var music := main.get_node_or_null("Music")
		if music != null:
			music.toggle_mute()
	elif id == "next":
		var music_next := main.get_node_or_null("Music")
		if music_next != null:
			music_next.skip_track()
	elif id == "juice":
		if main.has_method("toggle_juice"):
			main.toggle_juice()
		queue_redraw()
	elif id == "bg":
		if main.has_method("cycle_backdrop"):
			main.cycle_backdrop()
		queue_redraw()
	elif id == "full":
		main._toggle_fullscreen()
		queue_redraw()
	elif id == "zones":
		_show_zones = not _show_zones
		_save_prefs()
		queue_redraw()
	elif id == "scale_down":
		_set_scale(_scale - 1)
	elif id == "scale_up":
		_set_scale(_scale + 1)


func _tap_quadrant(pos: Vector2) -> bool:
	# Upper half nudges one column. Lower half rotates or hard-drops.
	# Zones live only in the open play band between the top and bottom buttons.
	if not _can_play():
		return false
	var zone := _play_zone_rect()
	if zone.size.y <= 1.0 or not zone.has_point(pos):
		return false
	var main := get_parent()
	var mid := zone.get_center()
	var left := pos.x < mid.x
	var upper := pos.y < mid.y
	if upper:
		main.apply_action(ReplayActions.NUDGE_LEFT if left else ReplayActions.NUDGE_RIGHT)
	elif left:
		main.apply_action(ReplayActions.ROT)
	else:
		main.apply_action(ReplayActions.DROP)
	return true


func _play_zone_rect() -> Rect2:
	var vp := get_viewport_rect().size
	var top := utility_height()
	var bottom := vp.y - band_height(vp.x)
	if bottom <= top:
		return Rect2()
	return Rect2(0.0, top, vp.x, bottom - top)


func _can_play() -> bool:
	var main := get_parent()
	return (
		not main.game_over
		and not main.paused
		and not main.help_open
		and not main.score_open
		and not main.replay_mode
		and main.clear_timer <= 0.0
		and not main._highscores_open()
	)


func _is_gameplay(id: String) -> bool:
	return HOLD_ACTIONS.has(id) or id in TAP_ACTIONS


func _set_hold(action: String, down: bool) -> void:
	var count: int = int(_hold_counts[action])
	var main := get_parent()
	if down:
		if count == 0 and main != null and main.has_method("apply_action"):
			match action:
				"left":
					main.apply_action(ReplayActions.LEFT_ON)
				"right":
					main.apply_action(ReplayActions.RIGHT_ON)
				"soft":
					main.apply_action(ReplayActions.SOFT_ON)
		_hold_counts[action] = count + 1
	else:
		count = maxi(0, count - 1)
		_hold_counts[action] = count
		if count == 0 and main != null and main.has_method("apply_action"):
			match action:
				"left":
					main.apply_action(ReplayActions.LEFT_OFF)
				"right":
					main.apply_action(ReplayActions.RIGHT_OFF)
				"soft":
					main.apply_action(ReplayActions.SOFT_OFF)


func _release_all() -> void:
	if _fingers.is_empty() and int(_hold_counts["left"]) == 0 and int(_hold_counts["right"]) == 0 and int(_hold_counts["soft"]) == 0:
		return
	_fingers.clear()
	for action in _hold_counts.keys():
		if int(_hold_counts[action]) > 0:
			var main := get_parent()
			if main != null and main.has_method("apply_action"):
				match str(action):
					"left":
						main.apply_action(ReplayActions.LEFT_OFF)
					"right":
						main.apply_action(ReplayActions.RIGHT_OFF)
					"soft":
						main.apply_action(ReplayActions.SOFT_OFF)
		_hold_counts[action] = 0
	queue_redraw()


func _set_scale(next: int) -> void:
	next = clampi(next, SCALE_MIN, SCALE_MAX)
	if next == _scale:
		return
	_scale = next
	_metric_key = ""
	_save_prefs()
	var main := get_parent()
	if main != null and main.has_method("_layout"):
		main._layout()
	queue_redraw()


func _load_prefs() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	_scale = clampi(int(cfg.get_value("ui", "scale", SCALE_DEFAULT)), SCALE_MIN, SCALE_MAX)
	_show_zones = bool(cfg.get_value("ui", "show_zones", false))


func _save_prefs() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("ui", "scale", _scale)
	cfg.set_value("ui", "show_zones", _show_zones)
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
	var below_rows := 1 if not UTILITY_BELOW.is_empty() else 0
	var total_util_rows := util_rows + below_rows
	var utility_h := margin + float(total_util_rows) * height + float(total_util_rows - 1) * gap + margin
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
	if not UTILITY_BELOW.is_empty():
		var below_n := UTILITY_BELOW.size()
		var below_w := (float(m.inner) - gap * float(below_n - 1)) / float(below_n)
		var below_x := margin
		for below_id in UTILITY_BELOW:
			_rects[str(below_id)] = Rect2(below_x, y, below_w, button_h)
			below_x += below_w + gap
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
	if _show_zones:
		_draw_zone_guides()
	var main := get_parent()
	for id in _rects.keys():
		var label := _button_label(str(id), main.paused)
		var held := false
		if HOLD_ACTIONS.has(id):
			held = int(_hold_counts[str(HOLD_ACTIONS[id])]) > 0
		elif id == "full" and _is_fullscreen():
			held = true
		elif id == "zones" and _show_zones:
			held = true
		elif id == "juice" and main.juice != null and main.juice.is_enabled():
			held = true
		elif id == "bg" and int(main.backdrop_mode) == 2:
			held = true
		elif id == "scale_down" and _scale == SCALE_MIN:
			held = true
		elif id == "scale_up" and _scale == SCALE_MAX:
			held = true
		_draw_button(_rects[id], label, held)


func _draw_zone_guides() -> void:
	var zone := _play_zone_rect()
	if zone.size.y <= 1.0:
		return
	var mid := zone.get_center()
	var line := Color("8ef7ff", 0.35)
	draw_line(Vector2(mid.x, zone.position.y), Vector2(mid.x, zone.end.y), line, 2.0, true)
	draw_line(Vector2(zone.position.x, mid.y), Vector2(zone.end.x, mid.y), line, 2.0, true)
	# Light frame so the zone stops clearly above/below the button rows.
	draw_rect(zone, Color("8ef7ff", 0.18), false, 2.0, true)
	var half := zone.size * 0.5
	var labels := [
		["<", Vector2(zone.position.x + half.x * 0.5, zone.position.y + half.y * 0.5)],
		[">", Vector2(mid.x + half.x * 0.5, zone.position.y + half.y * 0.5)],
		["ROT", Vector2(zone.position.x + half.x * 0.5, mid.y + half.y * 0.5)],
		["DROP", Vector2(mid.x + half.x * 0.5, mid.y + half.y * 0.5)],
	]
	# Fit the longest label into about half a quadrant so the guides read from arm's length.
	var max_w := half.x * 0.55
	var max_h := half.y * 0.4
	var size := clampi(int(minf(max_w * 0.55, max_h)), 48, 160)
	while size > 48:
		var drop_w := _font.get_string_size("DROP", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var drop_h := _font.get_ascent(size) + _font.get_descent(size)
		if drop_w <= max_w and drop_h <= max_h:
			break
		size -= 2
	var tint := Color("8ef7ff", 0.5)
	for entry in labels:
		var text := str(entry[0])
		var center: Vector2 = entry[1]
		var text_w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var baseline := center.y + (_font.get_ascent(size) - _font.get_descent(size)) * 0.5
		draw_string(
			_font,
			Vector2(center.x - text_w * 0.5, baseline),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			size,
			tint
		)


func _button_label(id: String, paused: bool) -> String:
	if id == "pause" and paused:
		return "RESUME"
	if id == "full" and _is_fullscreen():
		return "WINDOW"
	if id == "juice":
		var main := get_parent()
		var on: bool = main != null and main.juice != null and main.juice.is_enabled()
		return "JUICE ON" if on else "JUICE OFF"
	if id == "bg":
		var main_bg := get_parent()
		if main_bg != null and main_bg.has_method("_backdrop_mode_label"):
			match int(main_bg.backdrop_mode):
				0:
					return "BG DIM"
				1:
					return "BG LIT"
				_:
					return "BG GRID"
		return "BG"
	if id == "scale_down":
		return "%dx" % (maxi(SCALE_MIN, _scale - 1) if _scale > SCALE_MIN else _scale)
	if id == "scale_up":
		return "%dx" % (mini(SCALE_MAX, _scale + 1) if _scale < SCALE_MAX else _scale)
	return str(LABELS[id])


func _is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return (
		mode == DisplayServer.WINDOW_MODE_FULLSCREEN
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	)


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
