extends Node2D

## Private challenge create / join overlay + active board state.

const ChallengeConfig = preload("res://game/challenge/challenge_config.gd")
const HighscoreConfig = preload("res://game/highscore/highscore_config.gd")
const GameModes = preload("res://game/mode/game_modes.gd")
const PlayDevice = preload("res://game/platform/play_device.gd")
const ColorTheme = preload("res://game/theme/color_theme.gd")
enum Phase { IDLE, CREATE, CREATING, SHARE, JOINING }

signal activated(data: Dictionary)
signal cleared
signal closed
signal start_requested

var phase: Phase = Phase.IDLE
var active_board: Dictionary = {}
var status_text := ""
var draft_name := ""
var draft_family := GameModes.CLASSIC
var draft_difficulty := GameModes.DIFFICULTY_CLASSIC
var share_link := ""
var name_cursor_on := true
var cursor_timer := 0.0
var _ui_scale := 1.0
var _req_gen := 0
var _title_font: Font
var _body_font: Font
var _name_edit: LineEdit
var _name_field_style: StyleBoxFlat

var _create_rect := Rect2()
var _copy_rect := Rect2()
var _start_rect := Rect2()
var _leave_rect := Rect2()
var _close_rect := Rect2()
var _name_field_rect := Rect2()
var _family_rects: Array = []
var _diff_rects: Array = []


func _ready() -> void:
	_title_font = ThemeDB.fallback_font
	_body_font = ThemeDB.fallback_font
	_setup_line_edits()
	apply_color_theme()
	var saved := ChallengeConfig.load_active()
	if not saved.is_empty():
		_apply_active(saved, false)
	call_deferred("_try_deep_link")


func _setup_line_edits() -> void:
	_name_field_style = StyleBoxFlat.new()
	_name_field_style.set_border_width_all(2)
	_name_field_style.set_corner_radius_all(4)
	_name_field_style.content_margin_left = 10.0
	_name_field_style.content_margin_right = 10.0
	_name_field_style.content_margin_top = 6.0
	_name_field_style.content_margin_bottom = 6.0

	_name_edit = LineEdit.new()
	_name_edit.visible = false
	_name_edit.max_length = ChallengeConfig.MAX_NAME_LENGTH
	_name_edit.caret_blink = true
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.context_menu_enabled = false
	_name_edit.virtual_keyboard_enabled = true
	_name_edit.virtual_keyboard_show_on_focus = true
	_name_edit.placeholder_text = "Challenge name"
	_name_edit.mouse_filter = Control.MOUSE_FILTER_STOP
	_name_edit.add_theme_stylebox_override("normal", _name_field_style)
	_name_edit.add_theme_stylebox_override("focus", _name_field_style)
	_name_edit.add_theme_constant_override("caret_width", 3)
	_name_edit.text_changed.connect(_on_name_text_changed)
	add_child(_name_edit)


func apply_color_theme() -> void:
	if _name_field_style != null:
		_name_field_style.bg_color = ColorTheme.bg_deep()
		_name_field_style.border_color = ColorTheme.accent(0.85)
	if _name_edit != null:
		_name_edit.add_theme_color_override("font_color", ColorTheme.gold())
		_name_edit.add_theme_color_override("font_placeholder_color", ColorTheme.muted())
		_name_edit.add_theme_color_override("caret_color", ColorTheme.accent())
	queue_redraw()


func set_ui_scale(ui_scale: float) -> void:
	_ui_scale = maxf(0.5, ui_scale)


func is_active() -> bool:
	return not active_board.is_empty() and not str(active_board.get("id", "")).is_empty()


func active_data() -> Dictionary:
	return active_board.duplicate()


func is_showing_overlay() -> bool:
	return phase != Phase.IDLE


func is_capturing_input() -> bool:
	return phase == Phase.CREATE or phase == Phase.CREATING or phase == Phase.SHARE or phase == Phase.JOINING


func open_create() -> void:
	if is_capturing_input() and phase != Phase.SHARE:
		return
	phase = Phase.CREATE
	status_text = ""
	draft_name = ""
	draft_family = GameModes.CLASSIC
	draft_difficulty = GameModes.DIFFICULTY_CLASSIC
	if is_active():
		share_link = ChallengeConfig.share_url(str(active_board.get("id", "")))
	else:
		share_link = ""
	_show_name_edit()
	queue_redraw()


func close_overlay() -> void:
	phase = Phase.IDLE
	status_text = ""
	_hide_edits()
	queue_redraw()
	closed.emit()


func leave_challenge() -> void:
	active_board = {}
	ChallengeConfig.clear_active()
	share_link = ""
	cleared.emit()
	close_overlay()


func _start_challenge_game() -> void:
	phase = Phase.IDLE
	status_text = ""
	_hide_edits()
	queue_redraw()
	start_requested.emit()


func handle_input(event: InputEvent) -> bool:
	if not is_capturing_input():
		return false
	if phase == Phase.CREATING or phase == Phase.JOINING:
		return true
	if PlayDevice.has_pointer_down(event):
		return _handle_pointer(PlayDevice.pointer_down_position(event))
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE:
			close_overlay()
			return true
		if phase == Phase.SHARE:
			if key.keycode == KEY_C:
				_copy_link()
				return true
			if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
				_start_challenge_game()
				return true
			return true
		if phase == Phase.CREATE:
			return _handle_name_typing(key)
	return true


func _try_deep_link() -> void:
	var token := ChallengeConfig.parse_deep_link_token()
	if token.is_empty():
		return
	if is_active() and str(active_board.get("id", "")) == token:
		_notify_parent_activated()
		return
	_begin_join(token)


func _apply_active(data: Dictionary, persist: bool) -> void:
	var token := ChallengeConfig.sanitize_token(str(data.get("id", "")))
	if token.is_empty():
		return
	var family := str(data.get("family", GameModes.CLASSIC)).to_lower()
	if not GameModes.is_valid_family(family):
		family = GameModes.CLASSIC
	var difficulty := str(data.get("difficulty", GameModes.DIFFICULTY_CLASSIC)).to_lower()
	if not GameModes.is_valid_difficulty(difficulty):
		difficulty = GameModes.DIFFICULTY_CLASSIC
	var period = data.get("periodUnix", data.get("period_unix", 0))
	var period_unix := 0
	if period != null and str(period) != "" and str(period) != "null":
		period_unix = int(period)
	active_board = {
		"id": token,
		"name": str(data.get("name", "Challenge")),
		"family": family,
		"difficulty": difficulty,
		"periodUnix": period_unix if period_unix > 0 else 0,
	}
	share_link = ChallengeConfig.share_url(token)
	if persist:
		ChallengeConfig.save_active(active_board)
	_notify_parent_activated()


func _notify_parent_activated() -> void:
	activated.emit(active_board.duplicate())
	var main := get_parent()
	if main != null and main.has_method("on_challenge_activated"):
		main.on_challenge_activated(active_board.duplicate())


func _begin_join(token: String) -> void:
	var id := ChallengeConfig.sanitize_token(token)
	if id.is_empty():
		status_text = "Invalid invite code"
		queue_redraw()
		return
	phase = Phase.JOINING
	status_text = "Joining..."
	_hide_edits()
	queue_redraw()
	_req_gen += 1
	var generation := _req_gen
	var url := "%s/api/challenges/%s" % [ChallengeConfig.api_base(), id.uri_encode()]
	_send("join", url, PackedStringArray(), HTTPClient.METHOD_GET, "", generation)


func _submit_create() -> void:
	var sanitized := ChallengeConfig.sanitize_name(draft_name)
	if sanitized.is_empty():
		status_text = "Enter a name"
		queue_redraw()
		return
	draft_name = sanitized
	phase = Phase.CREATING
	status_text = "Creating..."
	_hide_edits()
	queue_redraw()
	_req_gen += 1
	var generation := _req_gen
	var payload := {
		"name": sanitized,
		"family": draft_family,
		"difficulty": draft_difficulty,
		"creatorId": HighscoreConfig.ensure_player_id(),
	}
	var body := JSON.stringify(payload)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var url := "%s/api/challenges" % ChallengeConfig.api_base()
	_send("create", url, headers, HTTPClient.METHOD_POST, body, generation)


func _copy_link() -> void:
	if share_link.is_empty() and is_active():
		share_link = ChallengeConfig.share_url(str(active_board.get("id", "")))
	if share_link.is_empty():
		status_text = "No link yet"
		queue_redraw()
		return
	if ChallengeConfig.copy_text_to_clipboard(share_link):
		status_text = "Link copied"
	else:
		status_text = "Copy failed"
	queue_redraw()


func _show_name_edit() -> void:
	## Touch uses LineEdit for the virtual keyboard. Desktop draws fields itself
	## so the caret stays after the centered text.
	if PlayDevice.is_touch_primary():
		_name_edit.visible = true
		_name_edit.text = draft_name
		_name_edit.caret_column = draft_name.length()
		_name_edit.grab_focus.call_deferred()
	else:
		_hide_edits()
		_wake_cursor()


func _hide_edits() -> void:
	if _name_edit != null:
		_name_edit.visible = false
		_name_edit.release_focus()


func _on_name_text_changed(text: String) -> void:
	draft_name = text
	queue_redraw()


func _handle_name_typing(key: InputEventKey) -> bool:
	if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		_submit_create()
		return true
	if PlayDevice.is_touch_primary():
		return true
	if key.keycode == KEY_BACKSPACE:
		if draft_name.length() > 0:
			draft_name = draft_name.substr(0, draft_name.length() - 1)
			_wake_cursor()
		return true
	var ch := char(key.unicode)
	if key.unicode >= 32 and ChallengeConfig.is_allowed_name_char(ch):
		if draft_name.length() < ChallengeConfig.MAX_NAME_LENGTH:
			draft_name += ch
			_wake_cursor()
		return true
	return true


func _wake_cursor() -> void:
	name_cursor_on = true
	cursor_timer = 0.0
	queue_redraw()


func _handle_pointer(point: Vector2) -> bool:
	_layout_panel(get_viewport_rect().size)
	if phase == Phase.SHARE:
		if _copy_rect.has_point(point):
			_copy_link()
			return true
		if _start_rect.has_point(point):
			_start_challenge_game()
			return true
		return true
	if phase == Phase.CREATE:
		for i in _diff_rects.size():
			var r: Rect2 = _diff_rects[i]
			if r.has_point(point):
				draft_difficulty = GameModes.DIFFICULTIES[i]
				queue_redraw()
				return true
		for i in _family_rects.size():
			var r2: Rect2 = _family_rects[i]
			if r2.has_point(point):
				draft_family = GameModes.FAMILIES[i]
				queue_redraw()
				return true
		if _name_field_rect.has_point(point):
			if PlayDevice.is_touch_primary():
				_name_edit.grab_focus()
			_wake_cursor()
			queue_redraw()
			return true
		if _create_rect.has_point(point):
			_submit_create()
			return true
		if _leave_rect.size.x > 0.0 and _leave_rect.has_point(point):
			leave_challenge()
			return true
		if _close_rect.has_point(point):
			close_overlay()
			return true
	return true


func _send(
	kind: String,
	url: String,
	headers: PackedStringArray,
	method: int,
	body: String,
	generation: int
) -> void:
	var http := HTTPRequest.new()
	http.timeout = 12.0
	add_child(http)
	http.request_completed.connect(
		func(
			_result: int,
			response_code: int,
			_headers: PackedStringArray,
			response_body: PackedByteArray
		) -> void:
			_on_request_completed(http, kind, generation, response_code, response_body)
	)
	var err := http.request(url, headers, method, body)
	if err != OK:
		http.queue_free()
		status_text = "Request failed (offline)"
		phase = Phase.CREATE
		_show_name_edit()
		queue_redraw()


func _on_request_completed(
	http: HTTPRequest,
	kind: String,
	generation: int,
	response_code: int,
	body: PackedByteArray
) -> void:
	if is_instance_valid(http):
		http.queue_free()
	if generation != _req_gen:
		return
	var text := body.get_string_from_utf8()
	if kind == "create":
		if response_code == 200:
			var parsed = JSON.parse_string(text)
			if typeof(parsed) == TYPE_DICTIONARY:
				_apply_active(parsed, true)
				share_link = ChallengeConfig.share_url(str(active_board.get("id", "")))
				phase = Phase.SHARE
				status_text = "Share this link with friends"
				_hide_edits()
				queue_redraw()
				return
		status_text = _error_from_body(text, "Create failed")
		phase = Phase.CREATE
		_show_name_edit()
		queue_redraw()
		return
	if kind == "join":
		if response_code == 200:
			var parsed = JSON.parse_string(text)
			if typeof(parsed) == TYPE_DICTIONARY:
				_apply_active(parsed, true)
				share_link = ChallengeConfig.share_url(str(active_board.get("id", "")))
				phase = Phase.SHARE
				status_text = "Challenge joined"
				_hide_edits()
				queue_redraw()
				var main := get_parent()
				if main != null and main.has_method("on_challenge_joined"):
					main.on_challenge_joined(active_board.duplicate())
				return
		status_text = _error_from_body(text, "Challenge not found")
		phase = Phase.CREATE
		_show_name_edit()
		queue_redraw()


func _error_from_body(text: String, fallback: String) -> String:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		var err := str(parsed.get("error", "")).strip_edges()
		if not err.is_empty():
			return err
	return fallback


func _process(delta: float) -> void:
	if phase != Phase.CREATE:
		return
	_layout_panel(get_viewport_rect().size)
	if _name_edit != null and _name_edit.visible:
		_name_edit.position = _name_field_rect.position
		_name_edit.size = _name_field_rect.size
		_name_edit.add_theme_font_size_override("font_size", maxi(14, int(round(18.0 * _ui_scale))))
	cursor_timer += delta
	if cursor_timer >= 0.45:
		cursor_timer = 0.0
		name_cursor_on = not name_cursor_on
		queue_redraw()


func _draw() -> void:
	if phase == Phase.IDLE:
		return
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.62))
	var panel := _layout_panel(vp)
	draw_rect(panel, ColorTheme.bg_panel(0.96), true, -1.0, true)
	draw_rect(panel, ColorTheme.accent(0.45), false, 1.5, true)
	if phase == Phase.SHARE or phase == Phase.JOINING:
		_draw_share(panel)
	else:
		_draw_create(panel)


func _draw_create(panel: Rect2) -> void:
	var ui := _ui_scale
	var title_size := maxi(18, int(round(24 * ui)))
	var body_size := maxi(12, int(round(15 * ui)))
	var section_size := maxi(11, int(round(12 * ui)))
	var hint_size := maxi(10, body_size - 2)
	var y := panel.position.y + 28.0 * ui
	_draw_centered(_title_font, Vector2(panel.get_center().x, y), "CHALLENGE", title_size, ColorTheme.accent())
	if not PlayDevice.is_touch_primary() or not _name_edit.visible:
		_draw_text_field(
			_name_field_rect,
			draft_name,
			"Challenge name",
			true,
			body_size
		)
	y = _name_field_rect.end.y + 18.0 * ui
	_draw_centered(_body_font, Vector2(panel.get_center().x, y), "DIFFICULTY", section_size, ColorTheme.muted())
	for i in _diff_rects.size():
		var diff: String = GameModes.DIFFICULTIES[i]
		_draw_choice(
			_diff_rects[i],
			str(GameModes.DIFFICULTY_LABELS.get(diff, diff)),
			draft_difficulty == diff,
			body_size
		)
	y = _diff_rects[0].end.y + 16.0 * ui if not _diff_rects.is_empty() else y + 40.0
	_draw_centered(_body_font, Vector2(panel.get_center().x, y), "MODE", section_size, ColorTheme.muted())
	for i in _family_rects.size():
		var family: String = GameModes.FAMILIES[i]
		_draw_choice(
			_family_rects[i],
			str(GameModes.FAMILY_LABELS.get(family, family)),
			draft_family == family,
			body_size
		)
	var hint_max_w := panel.size.x - 32.0 * ui
	var hint_lines := _wrap_text_lines(
		GameModes.hint_for_selection(draft_family, draft_difficulty),
		_body_font,
		hint_size,
		hint_max_w
	)
	var hint_line_h := (
		_body_font.get_ascent(hint_size) + _body_font.get_descent(hint_size) + 4.0 * ui
	)
	y = _family_rects[0].end.y + 26.0 * ui if not _family_rects.is_empty() else y + 40.0
	for i in hint_lines.size():
		_draw_centered(
			_body_font,
			Vector2(panel.get_center().x, y + float(i) * hint_line_h),
			str(hint_lines[i]),
			hint_size,
			ColorTheme.muted()
		)
	if not status_text.is_empty():
		_draw_centered(
			_body_font,
			Vector2(panel.get_center().x, _create_rect.position.y - 12.0 * ui),
			status_text,
			maxi(11, body_size - 1),
			ColorTheme.gold() if phase == Phase.CREATING else ColorTheme.danger()
		)
	_draw_choice(_create_rect, "CREATE", true, body_size)
	_draw_choice(_close_rect, "CLOSE", false, body_size)
	if is_active():
		_draw_choice(_leave_rect, "LEAVE", false, body_size)


func _share_title_lines(panel_w: float, title_size: int) -> PackedStringArray:
	var title := str(active_board.get("name", "CHALLENGE")).to_upper()
	var max_w := maxf(40.0, panel_w - 32.0 * _ui_scale)
	var font: Font = _title_font if _title_font != null else ThemeDB.fallback_font
	return _wrap_text_lines(title, font, title_size, max_w)


func _share_title_line_h(title_size: int) -> float:
	if _title_font != null:
		return (
			_title_font.get_ascent(title_size) + _title_font.get_descent(title_size) + 4.0 * _ui_scale
		)
	return 26.0 * _ui_scale


func _share_meta_h(panel_w: float) -> float:
	var ui := _ui_scale
	var title_size := maxi(18, int(round(24 * ui)))
	var title_lines := _share_title_lines(panel_w, title_size)
	var title_line_h := _share_title_line_h(title_size)
	# Title block + invite/settings (+ optional status) above the buttons.
	return (
		28.0 * ui
		+ title_line_h * float(maxi(1, title_lines.size()))
		+ 12.0 * ui
		+ 18.0 * ui
		+ 22.0 * ui
		+ 18.0 * ui
		+ (18.0 * ui if not status_text.is_empty() else 0.0)
	)


func _draw_share(panel: Rect2) -> void:
	var ui := _ui_scale
	var body_size := maxi(12, int(round(15 * ui)))
	var section_size := maxi(11, int(round(12 * ui)))
	var title_size := maxi(18, int(round(24 * ui)))
	var title_lines := _share_title_lines(panel.size.x, title_size)
	var title_line_h := _share_title_line_h(title_size)
	var y := panel.position.y + 28.0 * ui
	for i in title_lines.size():
		_draw_centered(
			_title_font,
			Vector2(panel.get_center().x, y + float(i) * title_line_h),
			str(title_lines[i]),
			title_size,
			ColorTheme.accent()
		)
	y += title_line_h * float(maxi(1, title_lines.size())) + 12.0 * ui
	_draw_centered(
		_body_font,
		Vector2(panel.get_center().x, y),
		"Invite link",
		section_size,
		ColorTheme.muted()
	)
	y += 18.0 * ui
	var link := share_link
	if link.length() > 42:
		link = "…%s" % link.substr(link.length() - 40)
	_draw_centered(
		_body_font,
		Vector2(panel.get_center().x, y),
		link,
		maxi(11, body_size - 2),
		ColorTheme.text()
	)
	y += 22.0 * ui
	var mode_label := str(GameModes.FAMILY_LABELS.get(str(active_board.get("family", "")), ""))
	var diff_label := str(GameModes.DIFFICULTY_LABELS.get(str(active_board.get("difficulty", "")), ""))
	var settings := "Mode: %s  Difficulty: %s" % [mode_label, diff_label]
	var period_unix := int(active_board.get("periodUnix", 0))
	if period_unix > 0:
		var period_label := GameModes.period_label(str(active_board.get("family", "")), period_unix)
		if not period_label.is_empty():
			settings = "%s  ·  %s" % [settings, period_label]
	_draw_centered(
		_body_font,
		Vector2(panel.get_center().x, y),
		settings,
		section_size,
		ColorTheme.muted()
	)
	if not status_text.is_empty():
		y += 18.0 * ui
		_draw_centered(
			_body_font,
			Vector2(panel.get_center().x, y),
			status_text,
			maxi(11, body_size - 1),
			ColorTheme.gold()
		)
	_draw_choice(_copy_rect, "COPY LINK", true, body_size)
	_draw_choice(_start_rect, "START GAME", true, body_size)


func _layout_panel(vp: Vector2) -> Rect2:
	var ui := _ui_scale
	_family_rects.clear()
	_diff_rects.clear()
	_create_rect = Rect2()
	_copy_rect = Rect2()
	_start_rect = Rect2()
	_leave_rect = Rect2()
	_close_rect = Rect2()
	_name_field_rect = Rect2()
	var panel_w := minf(440.0 * ui, vp.x - 16.0)
	var pad := 16.0 * ui
	var gap := 8.0 * ui
	var btn_h := maxf(40.0, 42.0 * ui)
	var field_h := maxf(40.0, 44.0 * ui)
	var hint_block_h := 0.0
	var panel_h := 0.0
	if phase == Phase.SHARE or phase == Phase.JOINING:
		var meta_h := _share_meta_h(panel_w)
		panel_h = minf(meta_h + 14.0 * ui + btn_h + gap + btn_h + pad, vp.y - 16.0)
	if phase != Phase.SHARE and phase != Phase.JOINING:
		var hint_size := maxi(10, int(round(13 * ui)))
		var hint_max_w := panel_w - pad * 2.0
		var hint_lines := _wrap_text_lines(
			GameModes.hint_for_selection(draft_family, draft_difficulty),
			_body_font if _body_font != null else ThemeDB.fallback_font,
			hint_size,
			hint_max_w
		)
		var hint_line_h := 16.0 * ui
		if _body_font != null:
			hint_line_h = (
				_body_font.get_ascent(hint_size) + _body_font.get_descent(hint_size) + 4.0 * ui
			)
		hint_block_h = hint_line_h * float(maxi(1, hint_lines.size()))
		var content_h := (
			52.0 * ui
			+ field_h
			+ 28.0 * ui
			+ btn_h
			+ 28.0 * ui
			+ btn_h
			+ 26.0 * ui
			+ hint_block_h
			+ 28.0 * ui
			+ btn_h
			+ gap
			+ btn_h
			+ pad
		)
		panel_h = minf(content_h, vp.y - 16.0)
	var panel := Rect2(
		(vp.x - panel_w) * 0.5,
		(vp.y - panel_h) * 0.5,
		panel_w,
		panel_h
	)
	panel.position.y = clampf(panel.position.y, 8.0, maxf(8.0, vp.y - panel.size.y - 8.0))
	if phase == Phase.SHARE or phase == Phase.JOINING:
		var meta_h := _share_meta_h(panel_w)
		_copy_rect = Rect2(
			panel.position.x + pad,
			panel.position.y + meta_h + 14.0 * ui,
			panel.size.x - pad * 2.0,
			btn_h
		)
		_start_rect = Rect2(
			panel.position.x + pad,
			_copy_rect.end.y + gap,
			panel.size.x - pad * 2.0,
			btn_h
		)
		return panel

	var y := panel.position.y + 52.0 * ui
	_name_field_rect = Rect2(panel.position.x + pad, y, panel.size.x - pad * 2.0, field_h)
	y = _name_field_rect.end.y + 28.0 * ui
	var diff_w := (panel.size.x - pad * 2.0 - gap) * 0.5
	for i in GameModes.DIFFICULTIES.size():
		_diff_rects.append(Rect2(panel.position.x + pad + float(i) * (diff_w + gap), y, diff_w, btn_h))
	y += btn_h + 28.0 * ui
	var fam_w := (panel.size.x - pad * 2.0 - gap * 2.0) / 3.0
	for i in GameModes.FAMILIES.size():
		_family_rects.append(Rect2(panel.position.x + pad + float(i) * (fam_w + gap), y, fam_w, btn_h))
	y = (
		(_family_rects[0].end.y if not _family_rects.is_empty() else y + btn_h)
		+ 26.0 * ui
		+ hint_block_h
		+ 28.0 * ui
	)
	_create_rect = Rect2(panel.position.x + pad, y, panel.size.x - pad * 2.0, btn_h)
	y = _create_rect.end.y + gap
	if is_active():
		var row_w := (panel.size.x - pad * 2.0 - gap) * 0.5
		_close_rect = Rect2(panel.position.x + pad, y, row_w, btn_h)
		_leave_rect = Rect2(_close_rect.end.x + gap, y, row_w, btn_h)
	else:
		_close_rect = Rect2(panel.position.x + pad, y, panel.size.x - pad * 2.0, btn_h)
	return panel


func _draw_choice(rect: Rect2, label: String, selected: bool, size: int = 15) -> void:
	if rect.size.x <= 0.0:
		return
	var fill := ColorTheme.bg_elevated(0.96) if selected else ColorTheme.bg_deep(0.94)
	var border := ColorTheme.accent(0.95) if selected else ColorTheme.accent(0.4)
	draw_rect(rect, fill, true, -1.0, true)
	draw_rect(rect, border, false, 2.0 if selected else 1.5, true)
	var w := _body_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var baseline := (
		rect.position.y
		+ (rect.size.y + _body_font.get_ascent(size) - _body_font.get_descent(size)) * 0.5
	)
	draw_string(
		_body_font,
		Vector2(rect.position.x + (rect.size.x - w) * 0.5, baseline),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		size,
		ColorTheme.text()
	)


func _draw_text_field(
	field: Rect2,
	value: String,
	placeholder: String,
	focused: bool,
	body_size: int
) -> void:
	if field.size.x <= 0.0:
		return
	draw_rect(field, ColorTheme.bg_deep(0.98), true, -1.0, true)
	draw_rect(
		field,
		ColorTheme.accent(0.95) if focused else ColorTheme.accent(0.45),
		false,
		2.0,
		true
	)
	var baseline := (
		field.position.y
		+ (field.size.y + _body_font.get_ascent(body_size) - _body_font.get_descent(body_size)) * 0.5
	)
	if value.is_empty():
		_draw_centered(
			_body_font,
			Vector2(field.get_center().x, baseline),
			placeholder,
			body_size,
			ColorTheme.muted()
		)
		if focused and name_cursor_on:
			var caret_x := field.get_center().x
			draw_line(
				Vector2(caret_x, field.position.y + 8.0),
				Vector2(caret_x, field.end.y - 8.0),
				ColorTheme.accent(),
				2.0
			)
		return
	var shown := value
	var text_w := _body_font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, body_size).x
	var text_x := field.get_center().x - text_w * 0.5
	draw_string(
		_body_font,
		Vector2(text_x, baseline),
		shown,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		body_size,
		ColorTheme.gold()
	)
	if focused and name_cursor_on:
		var caret_x := text_x + text_w + 2.0
		draw_line(
			Vector2(caret_x, field.position.y + 8.0),
			Vector2(caret_x, field.end.y - 8.0),
			ColorTheme.accent(),
			2.0
		)


func _draw_centered(font: Font, center: Vector2, text: String, size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(center.x - w * 0.5, center.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _wrap_text_lines(text: String, font: Font, font_size: int, max_width: float) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if text.is_empty() or max_width <= 0.0 or font == null:
		lines.append(text)
		return lines
	var words := text.split(" ", false)
	var current := ""
	for word in words:
		var candidate := word if current.is_empty() else current + " " + word
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
			current = candidate
			continue
		if not current.is_empty():
			lines.append(current)
		if font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
			var chunk := ""
			for i in word.length():
				var next_chunk := chunk + word.substr(i, 1)
				if (
					chunk.length() > 0
					and font.get_string_size(next_chunk, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width
				):
					lines.append(chunk)
					chunk = word.substr(i, 1)
				else:
					chunk = next_chunk
			current = chunk
		else:
			current = word
	if not current.is_empty() or lines.is_empty():
		lines.append(current)
	return lines
