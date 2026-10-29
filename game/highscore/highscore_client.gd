extends Node2D

## HTTP highscore client + game-over name entry / leaderboard overlay.

const HighscoreConfig = preload("res://game/highscore/highscore_config.gd")
const HighscoreChecksum = preload("res://game/highscore/highscore_checksum.gd")
const PlayDevice = preload("res://game/platform/play_device.gd")

enum Phase { IDLE, NAME_ENTRY, SUBMITTING, LEADERBOARD }

var phase: Phase = Phase.IDLE
var player_name := "Anonymous"
var name_cursor_on := true
var cursor_timer := 0.0
var status_text := ""
var submitted_rank := -1
var entries: Array = []
var pending_score := 0
var pending_lines := 0
var pending_level := 1
var pending_elapsed := 0.0
var submitted_this_run := false
var leaderboard_open := false
var submit_mode_id := ""
var view_mode_id := ""

var _submit_gen := 0
var _leaderboard_gen := 0
var _submit_lock := false
var _name_edit: LineEdit
var _editing_name := false
var _tab_classic_rect := Rect2()
var _tab_mobile_rect := Rect2()
var _lb_close_rect := Rect2()
var _lb_restart_rect := Rect2()
var _submit_rect := Rect2()
var _skip_rect := Rect2()
var _name_field_rect := Rect2()
var _title_font: Font
var _body_font: Font
var _ui_scale := 1.0


func _ready() -> void:
	_title_font = ThemeDB.fallback_font
	_body_font = ThemeDB.fallback_font
	submit_mode_id = PlayDevice.score_mode_id()
	view_mode_id = submit_mode_id
	_name_edit = LineEdit.new()
	_name_edit.visible = false
	_name_edit.max_length = HighscoreConfig.MAX_PLAYER_NAME_LENGTH
	_name_edit.caret_blink = true
	_name_edit.caret_blink_interval = 0.45
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.context_menu_enabled = false
	_name_edit.virtual_keyboard_enabled = true
	_name_edit.virtual_keyboard_show_on_focus = true
	_name_edit.mouse_filter = Control.MOUSE_FILTER_STOP
	_name_edit.placeholder_text = "Your name"
	var field := StyleBoxFlat.new()
	field.bg_color = Color("071018")
	field.border_color = Color("8ef7ff", 0.85)
	field.set_border_width_all(2)
	field.set_corner_radius_all(4)
	field.content_margin_left = 10.0
	field.content_margin_right = 10.0
	field.content_margin_top = 6.0
	field.content_margin_bottom = 6.0
	_name_edit.add_theme_stylebox_override("normal", field)
	_name_edit.add_theme_stylebox_override("focus", field)
	_name_edit.add_theme_color_override("font_color", Color("ffd166"))
	_name_edit.add_theme_color_override("font_placeholder_color", Color("6a8799"))
	_name_edit.add_theme_color_override("caret_color", Color("8ef7ff"))
	_name_edit.add_theme_constant_override("caret_width", 3)
	_name_edit.text_changed.connect(_on_name_text_changed)
	_name_edit.text_submitted.connect(_on_name_submitted)
	add_child(_name_edit)
	player_name = _load_player_name()


func set_ui_scale(scale: float) -> void:
	_ui_scale = maxf(0.5, scale)


func reset_run() -> void:
	phase = Phase.IDLE
	status_text = ""
	submitted_rank = -1
	entries.clear()
	submitted_this_run = false
	leaderboard_open = false
	pending_score = 0
	pending_lines = 0
	pending_level = 1
	pending_elapsed = 0.0
	view_mode_id = submit_mode_id
	_submit_gen += 1
	_leaderboard_gen += 1
	_submit_lock = false
	_hide_touch_keyboard()
	queue_redraw()


func begin_game_over(score: int, lines: int, level: int, elapsed_seconds: float) -> void:
	pending_score = score
	pending_lines = lines
	pending_level = level
	pending_elapsed = maxf(0.001, elapsed_seconds)
	submitted_rank = -1
	status_text = ""
	leaderboard_open = false
	view_mode_id = submit_mode_id
	if submitted_this_run:
		phase = Phase.LEADERBOARD
		_hide_touch_keyboard()
		_fetch_leaderboard()
	else:
		phase = Phase.NAME_ENTRY
		cursor_timer = 0.0
		name_cursor_on = true
		_show_touch_keyboard.call_deferred()
	queue_redraw()


func open_leaderboard() -> void:
	if is_capturing_input():
		return
	view_mode_id = submit_mode_id
	leaderboard_open = true
	phase = Phase.LEADERBOARD
	_fetch_leaderboard()
	queue_redraw()


func is_capturing_input() -> bool:
	return phase == Phase.NAME_ENTRY or phase == Phase.SUBMITTING


func is_showing_overlay() -> bool:
	return (
		phase == Phase.NAME_ENTRY
		or phase == Phase.SUBMITTING
		or phase == Phase.LEADERBOARD
		or leaderboard_open
	)


func close_overlay() -> void:
	if is_capturing_input():
		return
	leaderboard_open = false
	if not _is_game_over_context():
		phase = Phase.IDLE
	queue_redraw()


func handle_input(event: InputEvent) -> bool:
	if phase == Phase.NAME_ENTRY:
		return _handle_name_entry(event)

	if phase == Phase.SUBMITTING:
		return true

	if is_showing_overlay() and _handle_leaderboard_pointer(event):
		return true

	if _key_pressed(event, KEY_L) and not is_capturing_input():
		if leaderboard_open or phase == Phase.LEADERBOARD:
			leaderboard_open = false
			if not _is_game_over_context():
				phase = Phase.IDLE
			queue_redraw()
		else:
			open_leaderboard()
		return true

	return false


func _is_game_over_context() -> bool:
	var parent_main = get_parent()
	return parent_main != null and parent_main.get("game_over") == true


func _handle_name_entry(event: InputEvent) -> bool:
	if PlayDevice.is_touch_primary():
		return _handle_touch_name_entry(event)
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
			_submit_score()
			return true
		if key.keycode == KEY_ESCAPE:
			_skip_name_entry()
			return true
		if key.keycode == KEY_BACKSPACE:
			if player_name.length() > 0:
				player_name = player_name.substr(0, player_name.length() - 1)
				_wake_name_cursor()
			return true
		var ch := char(key.unicode)
		if key.unicode >= 32 and _is_allowed_name_char(ch):
			if player_name.length() < HighscoreConfig.MAX_PLAYER_NAME_LENGTH:
				player_name += ch
				_wake_name_cursor()
			return true
	return true


func _wake_name_cursor() -> void:
	name_cursor_on = true
	cursor_timer = 0.0
	queue_redraw()


func _is_allowed_name_char(ch: String) -> bool:
	if ch.length() != 1:
		return false
	var code := ch.unicode_at(0)
	return (
		(code >= 65 and code <= 90)
		or (code >= 97 and code <= 122)
		or (code >= 48 and code <= 57)
		or ch == " "
		or ch == "_"
		or ch == "-"
	)


func _skip_name_entry() -> void:
	_hide_touch_keyboard()
	phase = Phase.LEADERBOARD
	status_text = "Skipped submit"
	view_mode_id = submit_mode_id
	_fetch_leaderboard()
	queue_redraw()


func _handle_touch_name_entry(event: InputEvent) -> bool:
	if PlayDevice.has_pointer_down(event):
		_layout_name_targets(get_viewport_rect().size)
		var point := PlayDevice.pointer_down_position(event)
		if _submit_rect.has_point(point):
			_submit_score()
			return true
		if _skip_rect.has_point(point):
			_skip_name_entry()
			return true
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
			_submit_score()
			return true
		if key.keycode == KEY_ESCAPE:
			_skip_name_entry()
			return true
	return false


func _handle_leaderboard_pointer(event: InputEvent) -> bool:
	if not PlayDevice.has_pointer_down(event):
		return false
	if not (leaderboard_open or phase == Phase.LEADERBOARD):
		return false
	_layout_leaderboard(get_viewport_rect().size)
	var point := PlayDevice.pointer_down_position(event)
	if _tab_classic_rect.has_point(point):
		_set_view_mode(HighscoreConfig.MODE_ID)
		return true
	if _tab_mobile_rect.has_point(point):
		_set_view_mode(HighscoreConfig.MODE_ID_MOBILE)
		return true
	if _lb_close_rect.size.x > 0.0 and _lb_close_rect.has_point(point):
		leaderboard_open = false
		if _is_game_over_context():
			phase = Phase.IDLE
		elif phase == Phase.LEADERBOARD:
			phase = Phase.IDLE
		queue_redraw()
		return true
	if _lb_restart_rect.size.x > 0.0 and _lb_restart_rect.has_point(point):
		get_parent()._new_game()
		return true
	return false


func _set_view_mode(mode_id: String) -> void:
	if view_mode_id == mode_id:
		return
	view_mode_id = mode_id
	entries.clear()
	status_text = ""
	_fetch_leaderboard()
	queue_redraw()


func _process(delta: float) -> void:
	if _name_edit != null and _name_edit.visible:
		_layout_name_targets(get_viewport_rect().size)
		_name_edit.position = _name_field_rect.position
		_name_edit.size = _name_field_rect.size
		_name_edit.add_theme_font_size_override("font_size", maxi(14, int(round(18.0 * _ui_scale))))
		if phase == Phase.NAME_ENTRY and not _name_edit.has_focus():
			_name_edit.grab_focus()
	if phase != Phase.NAME_ENTRY:
		return
	cursor_timer += delta
	if cursor_timer >= 0.45:
		cursor_timer = 0.0
		name_cursor_on = not name_cursor_on
		queue_redraw()


func _draw() -> void:
	if not is_showing_overlay():
		return
	var vp := get_viewport_rect().size
	if phase == Phase.NAME_ENTRY or phase == Phase.SUBMITTING:
		_draw_name_panel(vp)
	elif leaderboard_open or phase == Phase.LEADERBOARD:
		_draw_leaderboard_panel(vp)


func _draw_name_panel(vp: Vector2) -> void:
	var panel := _layout_name_targets(vp)
	var ui_scale := _ui_scale
	var touch_ui := PlayDevice.is_touch_primary()
	draw_rect(panel, Color("0b1a28", 0.94), true, -1.0, true)
	draw_rect(panel, Color("8ef7ff", 0.55), false, maxf(1.0, 2.0 * ui_scale), true)

	var title_size := maxi(18, int(round(26 * ui_scale)))
	var body_size := maxi(14, int(round(18 * ui_scale)))
	var hint_size := maxi(12, int(round(14 * ui_scale)))
	var cx := panel.get_center().x
	var y := panel.position.y + 36.0 * ui_scale
	_draw_centered(_title_font, Vector2(cx, y), "ENTER NAME", title_size, Color("8ef7ff"))
	y += 42.0 * ui_scale
	_draw_centered(_body_font, Vector2(cx, y), "Score %d" % pending_score, body_size, Color("e8f7ff"))
	if touch_ui and phase == Phase.NAME_ENTRY:
		_draw_name_field_chrome(_name_field_rect, true)
		_draw_choice(_submit_rect, "SUBMIT", true)
		_draw_choice(_skip_rect, "SKIP", false)
		return
	y += 28.0 * ui_scale
	var field := _name_field_rect
	if field.size.x <= 0.0:
		var field_w := panel.size.x - 40.0 * ui_scale
		var field_h := 44.0 * ui_scale
		field = Rect2(panel.position.x + 20.0 * ui_scale, y, field_w, field_h)
	_draw_name_field_chrome(field, phase == Phase.NAME_ENTRY)
	var display := player_name
	if phase == Phase.SUBMITTING:
		display = HighscoreChecksum.sanitize_player_name(player_name)
	var text_size := maxi(14, int(round(18.0 * ui_scale)))
	var text_color := Color("ffd166")
	if display.is_empty() and phase == Phase.NAME_ENTRY:
		display = "Your name"
		text_color = Color("6a8799")
	var text_w := _body_font.get_string_size(display, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
	var text_baseline := field.position.y + (field.size.y + _body_font.get_ascent(text_size) - _body_font.get_descent(text_size)) * 0.5
	var text_x := field.get_center().x - text_w * 0.5
	draw_string(_body_font, Vector2(text_x, text_baseline), display, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, text_color)
	if phase == Phase.NAME_ENTRY and name_cursor_on:
		var caret_x := text_x + text_w
		if player_name.is_empty():
			caret_x = field.get_center().x
		var caret_h := minf(field.size.y - 12.0 * ui_scale, float(text_size) + 8.0 * ui_scale)
		var caret := Rect2(
			caret_x + 2.0 * ui_scale,
			field.get_center().y - caret_h * 0.5,
			maxi(3.0, 3.0 * ui_scale),
			caret_h
		)
		draw_rect(caret, Color("8ef7ff"), true, -1.0, true)
	y = field.end.y + 28.0 * ui_scale
	var hint := "Enter submit    Esc skip"
	if phase == Phase.SUBMITTING:
		hint = status_text if not status_text.is_empty() else "Submitting..."
	_draw_centered(_body_font, Vector2(cx, y), hint, hint_size, Color("6a8799"))


func _draw_leaderboard_panel(vp: Vector2) -> void:
	var panel := _layout_leaderboard(vp)
	var ui_scale := _ui_scale
	var touch_ui := PlayDevice.is_touch_primary()
	draw_rect(panel, Color("0b1a28", 0.94), true, -1.0, true)
	draw_rect(panel, Color("8ef7ff", 0.55), false, maxf(1.0, 2.0 * ui_scale), true)

	var title_size := maxi(18, int(round(26 * ui_scale)))
	var body_size := maxi(12, int(round(16 * ui_scale)))
	var hint_size := maxi(11, int(round(13 * ui_scale)))
	var y := panel.position.y + 28.0 * ui_scale
	_draw_centered(_title_font, Vector2(panel.get_center().x, y), _board_title(), title_size, Color("8ef7ff"))
	_draw_choice(_tab_classic_rect, "CLASSIC", view_mode_id != HighscoreConfig.MODE_ID_MOBILE)
	_draw_choice(_tab_mobile_rect, "MOBILE", view_mode_id == HighscoreConfig.MODE_ID_MOBILE)
	y = _tab_classic_rect.end.y + 22.0 * ui_scale
	if submitted_rank > 0 and view_mode_id == submit_mode_id:
		_draw_centered(
			_body_font,
			Vector2(panel.get_center().x, y),
			"Your rank #%d" % submitted_rank,
			body_size,
			Color("ffd166")
		)
		y += 24.0 * ui_scale
	elif not status_text.is_empty():
		_draw_centered(_body_font, Vector2(panel.get_center().x, y), status_text, body_size, Color("fb7185"))
		y += 24.0 * ui_scale

	var row_limit := panel.end.y - 28.0 * ui_scale
	if _lb_close_rect.size.x > 0.0:
		row_limit = _lb_close_rect.position.y - 8.0
	if entries.is_empty() and status_text.is_empty():
		_draw_centered(
			_body_font,
			Vector2(panel.get_center().x, y + 20.0 * ui_scale),
			"No scores yet",
			body_size,
			Color("6a8799")
		)
	else:
		var row_h := 26.0 * ui_scale
		var left_x := panel.position.x + 18.0 * ui_scale
		var score_x := panel.position.x + panel.size.x * 0.55
		var time_x := panel.end.x - 18.0 * ui_scale
		for entry in entries:
			if y > row_limit:
				break
			var rank: int = int(entry.get("rank", 0))
			var pname: String = str(entry.get("playerName", "?"))
			var score: int = int(entry.get("finalScore", 0))
			var elapsed: float = float(entry.get("elapsedSeconds", 0.0))
			var line := "#%d  %s" % [rank, pname]
			draw_string(_body_font, Vector2(left_x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, body_size, Color("e8f7ff"))
			draw_string(
				_body_font,
				Vector2(score_x, y),
				str(score),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				body_size,
				Color("8ef7ff")
			)
			var time_str := _format_time(elapsed)
			var time_w := _body_font.get_string_size(time_str, HORIZONTAL_ALIGNMENT_LEFT, -1, body_size).x
			draw_string(
				_body_font,
				Vector2(time_x - time_w, y),
				time_str,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				body_size,
				Color("6a8799")
			)
			y += row_h

	if touch_ui:
		if _lb_close_rect.size.x > 0.0:
			_draw_choice(_lb_close_rect, "CLOSE", false)
		if _lb_restart_rect.size.x > 0.0:
			_draw_choice(_lb_restart_rect, "RESTART", true)
	else:
		var footer := "R / Space / Enter restart"
		if not _is_game_over_context():
			footer = "L close"
		_draw_centered(
			_body_font,
			Vector2(panel.get_center().x, panel.end.y - 16.0 * ui_scale),
			footer,
			hint_size,
			Color("6a8799")
		)


func _draw_centered(font: Font, center: Vector2, text: String, size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(center.x - w * 0.5, center.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _format_time(seconds: float) -> String:
	var total := int(floor(seconds))
	var m := total / 60
	var s := total % 60
	return "%d:%02d" % [m, s]


func _submit_score() -> void:
	if _submit_lock or phase == Phase.SUBMITTING:
		return
	_submit_lock = true
	if _name_edit != null and _name_edit.visible:
		player_name = _filter_name_live(_name_edit.text)
	_hide_touch_keyboard()
	if submitted_this_run:
		phase = Phase.LEADERBOARD
		view_mode_id = submit_mode_id
		_fetch_leaderboard()
		queue_redraw()
		return

	var sanitized_name: String = HighscoreChecksum.sanitize_player_name(player_name)
	player_name = sanitized_name
	_save_player_name(sanitized_name)

	view_mode_id = submit_mode_id
	var mode_id: String = HighscoreChecksum.sanitize_mode_id(submit_mode_id)
	var checksum: String = HighscoreChecksum.compute(
		mode_id,
		sanitized_name,
		pending_score,
		pending_lines,
		pending_level,
		pending_elapsed
	)
	var payload := {
		"modeId": mode_id,
		"playerName": sanitized_name,
		"finalScore": pending_score,
		"linesCleared": pending_lines,
		"level": pending_level,
		"elapsedSeconds": pending_elapsed,
		"checksum": checksum,
	}
	phase = Phase.SUBMITTING
	status_text = "Submitting..."
	submitted_this_run = true
	queue_redraw()

	var body := JSON.stringify(payload)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var url := "%s/api/scores" % HighscoreConfig.API_BASE_URL.trim_suffix("/")
	var err := _send("submit", url, headers, HTTPClient.METHOD_POST, body, mode_id, _submit_gen)
	if err != OK:
		status_text = "Submit failed (offline)"
		phase = Phase.LEADERBOARD
		_fetch_leaderboard()
		queue_redraw()


func _fetch_leaderboard() -> void:
	_leaderboard_gen += 1
	var generation := _leaderboard_gen
	var mode_id: String = HighscoreChecksum.sanitize_mode_id(view_mode_id if not view_mode_id.is_empty() else submit_mode_id)
	var url := "%s/api/scores/%s?top=%d" % [
		HighscoreConfig.API_BASE_URL.trim_suffix("/"),
		mode_id.uri_encode(),
		HighscoreConfig.DEFAULT_TOP_COUNT,
	]
	var err := _send("leaderboard", url, PackedStringArray(), HTTPClient.METHOD_GET, "", mode_id, generation)
	if err != OK:
		if status_text.is_empty():
			status_text = "Scores unavailable"
		queue_redraw()


func _send(
	kind: String,
	url: String,
	headers: PackedStringArray,
	method: int,
	body: String,
	mode_id: String,
	generation: int
) -> int:
	var http := HTTPRequest.new()
	http.timeout = 8.0
	add_child(http)
	http.request_completed.connect(func(result: int, response_code: int, response_headers: PackedStringArray, response_body: PackedByteArray) -> void:
		_on_request_completed(http, kind, mode_id, generation, result, response_code, response_headers, response_body)
	)
	var err := http.request(url, headers, method, body)
	if err != OK:
		http.queue_free()
	return err


func _on_request_completed(
	http: HTTPRequest,
	kind: String,
	mode_id: String,
	generation: int,
	_result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if is_instance_valid(http):
		http.queue_free()
	if kind == "submit" and generation != _submit_gen:
		return
	if kind == "leaderboard" and (
		generation != _leaderboard_gen
		or mode_id != HighscoreChecksum.sanitize_mode_id(view_mode_id)
	):
		return
	var text := body.get_string_from_utf8()

	if kind == "submit":
		if response_code == 200:
			var parsed = JSON.parse_string(text)
			if typeof(parsed) == TYPE_DICTIONARY:
				submitted_rank = int(parsed.get("rank", -1))
			status_text = ""
			phase = Phase.LEADERBOARD
			_fetch_leaderboard()
		elif response_code == 409:
			status_text = "Duplicate score"
			phase = Phase.LEADERBOARD
			_fetch_leaderboard()
		else:
			status_text = "Submit failed"
			phase = Phase.LEADERBOARD
			_fetch_leaderboard()
		queue_redraw()
		return

	if kind == "leaderboard":
		if response_code == 200:
			var parsed = JSON.parse_string(text)
			if typeof(parsed) == TYPE_ARRAY:
				entries = parsed
			else:
				entries = []
			if status_text == "Submitting...":
				status_text = ""
		else:
			entries = []
			if status_text.is_empty():
				status_text = "Scores unavailable"
		queue_redraw()


func _board_title() -> String:
	if view_mode_id == HighscoreConfig.MODE_ID_MOBILE:
		return "MOBILE HIGHSCORES"
	return "HIGHSCORES"


func _layout_name_targets(vp: Vector2) -> Rect2:
	var ui_scale := _ui_scale
	var touch_ui := PlayDevice.is_touch_primary()
	_submit_rect = Rect2()
	_skip_rect = Rect2()
	_name_field_rect = Rect2()
	if not touch_ui:
		var desktop_w := mini(420.0 * ui_scale, vp.x - 40.0)
		var desktop_h := 230.0 * ui_scale
		var panel := Rect2((vp.x - desktop_w) * 0.5, (vp.y - desktop_h) * 0.5 + 36.0 * ui_scale, desktop_w, desktop_h)
		var field_h := 44.0 * ui_scale
		_name_field_rect = Rect2(
			panel.position.x + 20.0 * ui_scale,
			panel.position.y + 110.0 * ui_scale,
			panel.size.x - 40.0 * ui_scale,
			field_h
		)
		return panel
	var panel_w := mini(maxf(420.0 * ui_scale, 300.0), vp.x - 16.0)
	var panel_h := minf(maxf(250.0, 210.0 * ui_scale), vp.y - 16.0)
	var panel := Rect2((vp.x - panel_w) * 0.5, maxf(8.0, (vp.y - panel_h) * 0.35), panel_w, panel_h)
	var gap := 8.0
	var button_h := 44.0
	var button_w := (panel.size.x - 24.0 - gap) * 0.5
	var button_y := panel.end.y - button_h - 12.0
	_skip_rect = Rect2(panel.position.x + 12.0, button_y, button_w, button_h)
	_submit_rect = Rect2(_skip_rect.end.x + gap, button_y, button_w, button_h)
	_name_field_rect = Rect2(panel.position.x + 20.0, button_y - 56.0, panel.size.x - 40.0, 44.0)
	return panel


func _draw_name_field_chrome(field: Rect2, active: bool) -> void:
	if field.size.x <= 0.0:
		return
	var fill := Color("071018", 0.98)
	var border := Color("8ef7ff", 0.95) if active else Color("8ef7ff", 0.45)
	draw_rect(field, fill, true, -1.0, true)
	draw_rect(field, border, false, maxf(2.0, 2.0 * _ui_scale), true)
	if active and name_cursor_on:
		# Outer pulse so the active field is easy to spot behind the keyboard.
		draw_rect(
			field.grow(3.0 * _ui_scale),
			Color("8ef7ff", 0.22),
			false,
			maxf(1.0, 1.5 * _ui_scale),
			true
		)


func _layout_leaderboard(vp: Vector2) -> Rect2:
	var ui_scale := _ui_scale
	var touch_ui := PlayDevice.is_touch_primary()
	var panel_w := mini(480.0 * ui_scale, vp.x - 32.0)
	if touch_ui:
		panel_w = mini(maxf(480.0 * ui_scale, 300.0), vp.x - 16.0)
	var row_h := 26.0 * ui_scale
	var rows := maxi(1, entries.size())
	var tab_h := maxf(36.0, 32.0 * ui_scale)
	var action_h := 56.0 if touch_ui else 0.0
	var panel_h := mini(100.0 * ui_scale + tab_h + action_h + float(rows) * row_h + 48.0 * ui_scale, vp.y - 16.0)
	var panel_y := (vp.y - panel_h) * 0.5
	if touch_ui:
		panel_y = maxf(8.0, panel_y)
	var panel := Rect2((vp.x - panel_w) * 0.5, panel_y, panel_w, panel_h)
	var gap := 8.0
	var tab_w := (panel.size.x - 24.0 - gap) * 0.5
	var tab_y := panel.position.y + 40.0 * ui_scale
	_tab_classic_rect = Rect2(panel.position.x + 12.0, tab_y, tab_w, tab_h)
	_tab_mobile_rect = Rect2(_tab_classic_rect.end.x + gap, tab_y, tab_w, tab_h)
	_lb_close_rect = Rect2()
	_lb_restart_rect = Rect2()
	if touch_ui:
		var button_h := 44.0
		var button_y := panel.end.y - button_h - 10.0
		if _is_game_over_context():
			var button_w := (panel.size.x - 24.0 - gap) * 0.5
			_lb_close_rect = Rect2(panel.position.x + 12.0, button_y, button_w, button_h)
			_lb_restart_rect = Rect2(_lb_close_rect.end.x + gap, button_y, button_w, button_h)
		else:
			var button_w := minf(180.0, panel.size.x - 24.0)
			_lb_close_rect = Rect2(panel.position.x + (panel.size.x - button_w) * 0.5, button_y, button_w, button_h)
	return panel


func _draw_choice(rect: Rect2, label: String, selected: bool) -> void:
	if rect.size.x <= 0.0:
		return
	var fill := Color("123047", 0.96) if selected else Color("071018", 0.94)
	var border := Color("8ef7ff", 0.9) if selected else Color("8ef7ff", 0.4)
	draw_rect(rect, fill, true, -1.0, true)
	draw_rect(rect, border, false, 2.0, true)
	var size := 14
	var baseline := rect.position.y + (rect.size.y + _body_font.get_ascent(size) - _body_font.get_descent(size)) * 0.5
	_draw_centered(_body_font, Vector2(rect.get_center().x, baseline), label, size, Color("e8f7ff"))


func _filter_name_live(value: String) -> String:
	var out := ""
	for i in value.length():
		var ch := value.substr(i, 1)
		if _is_allowed_name_char(ch):
			out += ch
	return out


func _on_name_text_changed(value: String) -> void:
	if _editing_name:
		return
	var filtered := _filter_name_live(value)
	if filtered != value:
		_editing_name = true
		var caret := _name_edit.caret_column
		_name_edit.text = filtered
		_name_edit.caret_column = mini(caret, filtered.length())
		_editing_name = false
	player_name = filtered
	_wake_name_cursor()


func _on_name_submitted(_value: String) -> void:
	_submit_score()


func _show_touch_keyboard() -> void:
	if not PlayDevice.is_touch_primary() or _name_edit == null or phase != Phase.NAME_ENTRY:
		return
	_layout_name_targets(get_viewport_rect().size)
	_name_edit.text = player_name
	_name_edit.visible = true
	_name_edit.position = _name_field_rect.position
	_name_edit.size = _name_field_rect.size
	_name_edit.caret_column = player_name.length()
	_name_edit.grab_focus()
	_wake_name_cursor()
	DisplayServer.virtual_keyboard_show(
		player_name,
		_name_field_rect,
		DisplayServer.KEYBOARD_TYPE_DEFAULT,
		HighscoreConfig.MAX_PLAYER_NAME_LENGTH,
		player_name.length(),
		player_name.length()
	)


func _hide_touch_keyboard() -> void:
	if _name_edit == null:
		return
	_name_edit.release_focus()
	_name_edit.visible = false
	if PlayDevice.is_touch_primary():
		DisplayServer.virtual_keyboard_hide()


func _load_player_name() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(HighscoreConfig.PLAYER_NAME_PATH) != OK:
		return "Anonymous"
	var value = cfg.get_value(HighscoreConfig.PLAYER_NAME_SECTION, HighscoreConfig.PLAYER_NAME_KEY, "Anonymous")
	return HighscoreChecksum.sanitize_player_name(str(value))


func _save_player_name(name: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(HighscoreConfig.PLAYER_NAME_PATH)
	cfg.set_value(HighscoreConfig.PLAYER_NAME_SECTION, HighscoreConfig.PLAYER_NAME_KEY, name)
	cfg.save(HighscoreConfig.PLAYER_NAME_PATH)


func _key_pressed(event: InputEvent, code: Key) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return false
	var key := event as InputEventKey
	return key.keycode == code or key.physical_keycode == code
