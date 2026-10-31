extends Node2D

## HTTP highscore client + game-over name entry / leaderboard overlay.

const HighscoreConfig = preload("res://game/highscore/highscore_config.gd")
const HighscoreChecksum = preload("res://game/highscore/highscore_checksum.gd")
const PlayDevice = preload("res://game/platform/play_device.gd")
const ReplayFormat = preload("res://game/replay/replay_format.gd")
const ColorTheme = preload("res://game/theme/color_theme.gd")

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
var pending_checksum := ""
var include_replay := true
var submitted_this_run := false
var leaderboard_open := false
var leaderboard_page := 0
var submit_mode_id := ""
var view_mode_id := ""

var _submit_gen := 0
var _leaderboard_gen := 0
var _replay_gen := 0
var _live_ranks_gen := 0
## Descending finalScore values for live in-run top-10 greetings (submit mode).
var live_top_scores: Array[int] = []
var _submit_lock := false
var _name_edit: LineEdit
var _name_field_style: StyleBoxFlat
var _editing_name := false
var _tab_classic_rect := Rect2()
var _tab_mobile_rect := Rect2()
var _lb_close_rect := Rect2()
var _lb_restart_rect := Rect2()
var _submit_rect := Rect2()
var _skip_rect := Rect2()
var _replay_toggle_rect := Rect2()
var _name_field_rect := Rect2()
var _play_hit_targets: Array = []
var _page_hit_targets: Array = []
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
	_name_field_style = StyleBoxFlat.new()
	_name_field_style.set_border_width_all(2)
	_name_field_style.set_corner_radius_all(4)
	_name_field_style.content_margin_left = 10.0
	_name_field_style.content_margin_right = 10.0
	_name_field_style.content_margin_top = 6.0
	_name_field_style.content_margin_bottom = 6.0
	_name_edit.add_theme_stylebox_override("normal", _name_field_style)
	_name_edit.add_theme_stylebox_override("focus", _name_field_style)
	_name_edit.add_theme_constant_override("caret_width", 3)
	_name_edit.text_changed.connect(_on_name_text_changed)
	_name_edit.text_submitted.connect(_on_name_submitted)
	add_child(_name_edit)
	apply_color_theme()
	player_name = _load_player_name()
	refresh_live_ranks()


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


func reset_run() -> void:
	phase = Phase.IDLE
	status_text = ""
	submitted_rank = -1
	entries.clear()
	submitted_this_run = false
	leaderboard_open = false
	leaderboard_page = 0
	pending_score = 0
	pending_lines = 0
	pending_level = 1
	pending_elapsed = 0.0
	pending_checksum = ""
	include_replay = true
	view_mode_id = submit_mode_id
	_submit_gen += 1
	_leaderboard_gen += 1
	_replay_gen += 1
	_submit_lock = false
	_play_hit_targets.clear()
	_page_hit_targets.clear()
	_hide_touch_keyboard()
	queue_redraw()


func begin_game_over(score: int, lines: int, level: int, elapsed_seconds: float) -> void:
	pending_score = score
	pending_lines = lines
	pending_level = level
	pending_elapsed = maxf(0.001, elapsed_seconds)
	pending_checksum = ""
	include_replay = true
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
	leaderboard_page = 0
	phase = Phase.LEADERBOARD
	_fetch_leaderboard()
	queue_redraw()


func _leaderboard_page_count() -> int:
	if entries.is_empty():
		return 1
	return int(ceili(float(entries.size()) / float(HighscoreConfig.LEADERBOARD_PAGE_SIZE)))


func _clamp_leaderboard_page() -> void:
	leaderboard_page = clampi(leaderboard_page, 0, maxi(0, _leaderboard_page_count() - 1))


func _set_leaderboard_page(page: int) -> void:
	var next := clampi(page, 0, maxi(0, _leaderboard_page_count() - 1))
	if next == leaderboard_page:
		return
	leaderboard_page = next
	queue_redraw()


func _page_entries() -> Array:
	_clamp_leaderboard_page()
	var page_size := HighscoreConfig.LEADERBOARD_PAGE_SIZE
	var start := leaderboard_page * page_size
	if start >= entries.size():
		return []
	return entries.slice(start, mini(start + page_size, entries.size()))


## Prefetch top scores used to greet mid-run leaderboard climbs.
func refresh_live_ranks() -> void:
	_live_ranks_gen += 1
	var generation := _live_ranks_gen
	var mode_id: String = HighscoreChecksum.sanitize_mode_id(submit_mode_id)
	if mode_id.is_empty():
		return
	var url := "%s/api/scores/%s?top=%d" % [
		HighscoreConfig.API_BASE_URL.trim_suffix("/"),
		mode_id.uri_encode(),
		HighscoreConfig.LIVE_RANK_TOP_COUNT,
	]
	_send("live_ranks", url, PackedStringArray(), HTTPClient.METHOD_GET, "", mode_id, generation)


## Hypothetical board rank for a live score (1 = best). 0 = outside the top 10.
func rank_for_score(score: int) -> int:
	if score <= 0:
		return 0
	for i in live_top_scores.size():
		if score > live_top_scores[i]:
			return i + 1
	if live_top_scores.size() < HighscoreConfig.LIVE_RANK_TOP_COUNT:
		return live_top_scores.size() + 1
	return 0


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
	_suppress_touch_zones()
	_sync_parent_holds()
	queue_redraw()


func handle_input(event: InputEvent) -> bool:
	if phase == Phase.NAME_ENTRY:
		return _handle_name_entry(event)

	if phase == Phase.SUBMITTING:
		return true

	if is_showing_overlay() and _handle_leaderboard_pointer(event):
		return true

	if (leaderboard_open or phase == Phase.LEADERBOARD) and not is_capturing_input():
		if _key_pressed(event, KEY_LEFT):
			_set_leaderboard_page(leaderboard_page - 1)
			return true
		if _key_pressed(event, KEY_RIGHT):
			_set_leaderboard_page(leaderboard_page + 1)
			return true

	if _key_pressed(event, KEY_L) and not is_capturing_input():
		if leaderboard_open or phase == Phase.LEADERBOARD:
			leaderboard_open = false
			if not _is_game_over_context():
				phase = Phase.IDLE
			_sync_parent_holds()
			queue_redraw()
		else:
			open_leaderboard()
		return true

	return false


func _sync_parent_holds() -> void:
	var main := get_parent()
	if main != null and main.has_method("_sync_hold_flags_from_input"):
		main._sync_hold_flags_from_input()


func _is_game_over_context() -> bool:
	var parent_main = get_parent()
	return parent_main != null and parent_main.get("game_over") == true


func _handle_name_entry(event: InputEvent) -> bool:
	if PlayDevice.has_pointer_down(event):
		_layout_name_targets(get_viewport_rect().size)
		var point := PlayDevice.pointer_down_position(event)
		if _replay_toggle_rect.size.x > 0.0 and _replay_toggle_rect.has_point(point):
			include_replay = not include_replay
			queue_redraw()
			return true
		if _submit_rect.size.x > 0.0 and _submit_rect.has_point(point):
			_submit_score()
			return true
		if _skip_rect.size.x > 0.0 and _skip_rect.has_point(point):
			_skip_name_entry()
			return true
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
		if _replay_toggle_rect.size.x > 0.0 and _replay_toggle_rect.has_point(point):
			include_replay = not include_replay
			queue_redraw()
			return true
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
	for page_target in _page_hit_targets:
		var page_rect: Rect2 = page_target.rect
		if page_rect.has_point(point):
			_set_leaderboard_page(int(page_target.page))
			return true
	if _lb_close_rect.size.x > 0.0 and _lb_close_rect.has_point(point):
		leaderboard_open = false
		if _is_game_over_context():
			phase = Phase.IDLE
		elif phase == Phase.LEADERBOARD:
			phase = Phase.IDLE
		_suppress_touch_zones()
		_sync_parent_holds()
		queue_redraw()
		return true
	if _lb_restart_rect.size.x > 0.0 and _lb_restart_rect.has_point(point):
		get_parent()._new_game()
		return true
	for target in _play_hit_targets:
		var play_rect: Rect2 = target.rect
		if play_rect.has_point(point):
			_fetch_and_play_replay(str(target.checksum))
			return true
	return false


func _suppress_touch_zones() -> void:
	var main := get_parent()
	if main == null:
		return
	var touch = main.get_node_or_null("TouchControls")
	if touch != null:
		touch.suppress_play_taps()


func _set_view_mode(mode_id: String) -> void:
	if view_mode_id == mode_id:
		return
	view_mode_id = mode_id
	entries.clear()
	leaderboard_page = 0
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
	draw_rect(panel, ColorTheme.bg_panel(0.94), true, -1.0, true)
	draw_rect(panel, ColorTheme.accent(0.55), false, maxf(1.0, 2.0 * ui_scale), true)

	var title_size := maxi(18, int(round(26 * ui_scale)))
	var body_size := maxi(14, int(round(18 * ui_scale)))
	var hint_size := maxi(12, int(round(14 * ui_scale)))
	var cx := panel.get_center().x
	var y := panel.position.y + 36.0 * ui_scale
	_draw_centered(_title_font, Vector2(cx, y), "ENTER NAME", title_size, ColorTheme.accent())
	y += 42.0 * ui_scale
	_draw_centered(
		_body_font,
		Vector2(cx, y),
		"Score %s" % HighscoreConfig.format_score(pending_score),
		body_size,
		ColorTheme.text()
	)
	_draw_replay_toggle_row(body_size)
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
	var text_color := ColorTheme.gold()
	if display.is_empty() and phase == Phase.NAME_ENTRY:
		display = "Your name"
		text_color = ColorTheme.muted()
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
			maxf(3.0, 3.0 * ui_scale),
			caret_h
		)
		draw_rect(caret, ColorTheme.accent(), true, -1.0, true)
	if phase == Phase.NAME_ENTRY or phase == Phase.SUBMITTING:
		_draw_choice(_skip_rect, "SKIP", false)
		_draw_choice(_submit_rect, "SUBMIT", true)
	if phase == Phase.SUBMITTING:
		var status := status_text if not status_text.is_empty() else "Submitting..."
		_draw_centered(
			_body_font,
			Vector2(cx, _submit_rect.position.y - 14.0 * ui_scale),
			status,
			hint_size,
			ColorTheme.muted()
		)


func _draw_replay_toggle_row(label_size: int) -> void:
	if _replay_toggle_rect.size.x <= 0.0:
		return
	var label := "Send replay"
	var label_w := _body_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x
	var label_x := _replay_toggle_rect.position.x - 10.0 * _ui_scale - label_w
	var baseline := (
		_replay_toggle_rect.position.y
		+ (_replay_toggle_rect.size.y + _body_font.get_ascent(label_size) - _body_font.get_descent(label_size)) * 0.5
	)
	draw_string(
		_body_font,
		Vector2(label_x, baseline),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		label_size,
		ColorTheme.text()
	)
	_draw_choice(
		_replay_toggle_rect,
		"YES" if include_replay else "NO",
		include_replay
	)


func _leaderboard_columns(panel: Rect2, ui_scale: float) -> Dictionary:
	var pad := 16.0 * ui_scale
	var gap := 8.0 * ui_scale
	var inner_left := panel.position.x + pad
	var inner_right := panel.end.x - pad
	var body_size := maxi(12, int(round(15 * ui_scale)))
	var rank_w := 40.0 * ui_scale
	# Name max is 16 chars; size the column to that, not leftover flex space.
	var name_sample := "W".repeat(HighscoreConfig.MAX_PLAYER_NAME_LENGTH)
	var name_w := 64.0 * ui_scale
	if _body_font != null:
		name_w = _body_font.get_string_size(
			name_sample, HORIZONTAL_ALIGNMENT_LEFT, -1, body_size
		).x
	# Mobile boards are tight; skip the datetime column there.
	var show_date := not PlayDevice.is_touch_primary()
	var date_w := 0.0
	if show_date:
		var date_sample := "00.00.0000 00:00"
		date_w = 120.0 * ui_scale
		if _body_font != null:
			date_w = _body_font.get_string_size(
				date_sample, HORIZONTAL_ALIGNMENT_LEFT, -1, body_size
			).x + 4.0 * ui_scale
	var score_w := 92.0 * ui_scale
	var lv_w := 52.0 * ui_scale
	var lines_w := 108.0 * ui_scale
	var replay_col_w := 68.0 * ui_scale
	var replay_btn_w := 60.0 * ui_scale
	var time_w := 48.0 * ui_scale
	var name_x := inner_left + rank_w + gap
	var date_x := name_x + name_w + (gap if show_date else 0.0)
	var time_x := inner_right - time_w
	var replay_x := time_x - gap - replay_col_w
	var lines_x := replay_x - gap - lines_w
	var lv_x := lines_x - gap - lv_w
	var score_x := lv_x - gap - score_w
	return {
		"rank_x": inner_left,
		"rank_w": rank_w,
		"name_x": name_x,
		"name_w": name_w,
		"date_x": date_x,
		"date_w": date_w,
		"show_date": show_date,
		"score_x": score_x,
		"score_w": score_w,
		"lv_x": lv_x,
		"lv_w": lv_w,
		"lines_x": lines_x,
		"lines_w": lines_w,
		"replay_x": replay_x,
		"replay_col_w": replay_col_w,
		"replay_btn_w": replay_btn_w,
		"time_x": time_x,
		"time_w": time_w,
	}


func _fit_leaderboard_text(text: String, max_w: float, font_size: int) -> String:
	if _body_font == null or max_w <= 0.0:
		return text
	if _body_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
		return text
	var trimmed := text
	while trimmed.length() > 1:
		trimmed = trimmed.substr(0, trimmed.length() - 1)
		var candidate := trimmed + "…"
		if _body_font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_w:
			return candidate
	return "…"


func _draw_leaderboard_col(
	text: String,
	x: float,
	y: float,
	col_w: float,
	font_size: int,
	color: Color,
	align_right: bool = false
) -> void:
	var draw_text := text
	var text_w := _body_font.get_string_size(draw_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if text_w > col_w:
		draw_text = _fit_leaderboard_text(text, col_w, font_size)
		text_w = _body_font.get_string_size(draw_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var draw_x := x + col_w - text_w if align_right else x
	draw_string(
		_body_font,
		Vector2(draw_x, y),
		draw_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		color
	)


func _draw_leaderboard_panel(vp: Vector2) -> void:
	var panel := _layout_leaderboard(vp)
	var ui_scale := _ui_scale
	var touch_ui := PlayDevice.is_touch_primary()
	draw_rect(panel, ColorTheme.bg_panel(0.94), true, -1.0, true)
	draw_rect(panel, ColorTheme.accent(0.55), false, maxf(1.0, 2.0 * ui_scale), true)

	var title_size := maxi(18, int(round(26 * ui_scale)))
	var body_size := maxi(12, int(round(15 * ui_scale)))
	var header_size := maxi(10, int(round(12 * ui_scale)))
	var hint_size := maxi(11, int(round(13 * ui_scale)))
	var y := panel.position.y + 28.0 * ui_scale
	_draw_centered(_title_font, Vector2(panel.get_center().x, y), _board_title(), title_size, ColorTheme.accent())
	_draw_choice(_tab_classic_rect, "CLASSIC", view_mode_id != HighscoreConfig.MODE_ID_MOBILE)
	_draw_choice(_tab_mobile_rect, "MOBILE", view_mode_id == HighscoreConfig.MODE_ID_MOBILE)
	y = _tab_classic_rect.end.y + 22.0 * ui_scale
	if submitted_rank > 0 and view_mode_id == submit_mode_id:
		_draw_centered(
			_body_font,
			Vector2(panel.get_center().x, y),
			"Your rank #%d" % submitted_rank,
			body_size,
			ColorTheme.gold()
		)
		y += 24.0 * ui_scale
	elif not status_text.is_empty():
		_draw_centered(_body_font, Vector2(panel.get_center().x, y), status_text, body_size, ColorTheme.danger())
		y += 24.0 * ui_scale

	var pager_h := 0.0
	if _leaderboard_page_count() > 1:
		pager_h = 34.0 * ui_scale
	var row_limit := panel.end.y - 28.0 * ui_scale - pager_h
	if _lb_close_rect.size.x > 0.0:
		row_limit = _lb_close_rect.position.y - 8.0 - pager_h
	_page_hit_targets.clear()
	if entries.is_empty() and status_text.is_empty():
		_draw_centered(
			_body_font,
			Vector2(panel.get_center().x, y + 20.0 * ui_scale),
			"No scores yet",
			body_size,
			ColorTheme.muted()
		)
	else:
		var cols := _leaderboard_columns(panel, ui_scale)
		var row_h := 28.0 * ui_scale
		var header_color := ColorTheme.muted()
		_draw_leaderboard_col("#", cols.rank_x, y, cols.rank_w, header_size, header_color)
		_draw_leaderboard_col("NAME", cols.name_x, y, cols.name_w, header_size, header_color)
		if cols.show_date:
			_draw_leaderboard_col("DATE", cols.date_x, y, cols.date_w, header_size, header_color)
		_draw_leaderboard_col("SCORE", cols.score_x, y, cols.score_w, header_size, header_color, true)
		_draw_leaderboard_col("LEVEL", cols.lv_x, y, cols.lv_w, header_size, header_color, true)
		_draw_leaderboard_col("LINES CLEARED", cols.lines_x, y, cols.lines_w, header_size, header_color, true)
		_draw_leaderboard_col("TIME", cols.time_x, y, cols.time_w, header_size, header_color, true)
		y += 22.0 * ui_scale
		_play_hit_targets.clear()
		for entry in _page_entries():
			if y > row_limit:
				break
			var rank: int = int(entry.get("rank", 0))
			var pname: String = str(entry.get("playerName", "?"))
			var score: int = int(entry.get("finalScore", 0))
			var level: int = int(entry.get("level", 1))
			var lines: int = int(entry.get("linesCleared", 0))
			var elapsed: float = float(entry.get("elapsedSeconds", 0.0))
			var has_replay: bool = bool(entry.get("hasReplay", false))
			var checksum: String = str(entry.get("checksum", ""))
			var submitted_at: String = _format_submitted_at(entry.get("submittedAt", ""))
			var is_you := (
				submitted_rank > 0
				and rank == submitted_rank
				and view_mode_id == submit_mode_id
			)
			var primary := ColorTheme.gold() if is_you else ColorTheme.text()
			var accent := ColorTheme.gold() if is_you else ColorTheme.accent()
			var muted := ColorTheme.gold(0.78) if is_you else ColorTheme.muted()
			_draw_leaderboard_col("#%d" % rank, cols.rank_x, y, cols.rank_w, body_size, primary)
			_draw_leaderboard_col(pname, cols.name_x, y, cols.name_w, body_size, primary)
			if cols.show_date:
				_draw_leaderboard_col(submitted_at, cols.date_x, y, cols.date_w, body_size, muted)
			_draw_leaderboard_col(
				HighscoreConfig.format_score(score),
				cols.score_x,
				y,
				cols.score_w,
				body_size,
				accent,
				true
			)
			_draw_leaderboard_col(str(level), cols.lv_x, y, cols.lv_w, body_size, muted, true)
			_draw_leaderboard_col(str(lines), cols.lines_x, y, cols.lines_w, body_size, muted, true)
			_draw_leaderboard_col(
				_format_time(elapsed),
				cols.time_x,
				y,
				cols.time_w,
				body_size,
				muted,
				true
			)
			if has_replay and not checksum.is_empty():
				var play_h := maxf(20.0, row_h - 6.0)
				# Center in the open span between LINES CLEARED and TIME content.
				var span_left: float = float(cols.lines_x) + float(cols.lines_w)
				var span_right: float = float(cols.time_x)
				var play_x: float = (
					(span_left + span_right) * 0.5
					- float(cols.replay_btn_w) * 0.5
					+ 14.0 * ui_scale
				)
				var play_rect := Rect2(play_x, y - play_h * 0.72, float(cols.replay_btn_w), play_h)
				_draw_choice(play_rect, "REPLAY", true, 11)
				_play_hit_targets.append({"rect": play_rect, "checksum": checksum})
			y += row_h

	_draw_leaderboard_pager(panel, ui_scale, hint_size)

	if touch_ui:
		if _lb_close_rect.size.x > 0.0:
			_draw_choice(_lb_close_rect, "CLOSE", false)
		if _lb_restart_rect.size.x > 0.0:
			_draw_choice(_lb_restart_rect, "RESTART", true)
	else:
		var footer := "R / Space / Enter restart"
		if not _is_game_over_context():
			footer = "L close · Left/Right page"
		else:
			footer = "R / Space / Enter restart · Left/Right page"
		_draw_centered(
			_body_font,
			Vector2(panel.get_center().x, panel.end.y - 16.0 * ui_scale),
			footer,
			hint_size,
			ColorTheme.muted()
		)


func _draw_leaderboard_pager(panel: Rect2, ui_scale: float, hint_size: int) -> void:
	_page_hit_targets.clear()
	var page_count := _leaderboard_page_count()
	if page_count <= 1:
		return
	var btn_h := maxf(26.0, 28.0 * ui_scale)
	var btn_w := maxf(28.0, 30.0 * ui_scale)
	var gap := 6.0 * ui_scale
	var total_w := float(page_count) * btn_w + float(page_count - 1) * gap
	var x := panel.get_center().x - total_w * 0.5
	var y := panel.end.y - 16.0 * ui_scale - btn_h
	if _lb_close_rect.size.x > 0.0:
		y = _lb_close_rect.position.y - 8.0 - btn_h
	elif not PlayDevice.is_touch_primary():
		y = panel.end.y - 36.0 * ui_scale - btn_h
	for page_i in page_count:
		var rect := Rect2(x, y, btn_w, btn_h)
		_draw_choice(rect, str(page_i + 1), page_i == leaderboard_page, hint_size)
		_page_hit_targets.append({"rect": rect, "page": page_i})
		x += btn_w + gap


func _draw_centered(font: Font, center: Vector2, text: String, size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(center.x - w * 0.5, center.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _format_time(seconds: float) -> String:
	var total := int(floor(seconds))
	var m := int(total / 60.0)
	var s := total % 60
	return "%d:%02d" % [m, s]


## Norwegian date/time: DD.MM.YYYY HH:MM (local clock).
func _format_submitted_at(raw: Variant) -> String:
	var s := str(raw).strip_edges()
	if s.is_empty() or s == "null":
		return "-"
	var cleaned := s
	var t_pos := cleaned.find("T")
	if t_pos >= 0:
		var frac := cleaned.find(".", t_pos)
		if frac >= 0:
			var end := frac + 1
			while end < cleaned.length():
				var ch := cleaned.substr(end, 1)
				if ch < "0" or ch > "9":
					break
				end += 1
			cleaned = cleaned.substr(0, frac) + cleaned.substr(end)
	var unix := Time.get_unix_time_from_datetime_string(cleaned)
	if unix > 0.0:
		var dt: Dictionary = Time.get_datetime_dict_from_unix_time(int(unix))
		return "%02d.%02d.%04d %02d:%02d" % [
			int(dt.get("day", 1)),
			int(dt.get("month", 1)),
			int(dt.get("year", 1970)),
			int(dt.get("hour", 0)),
			int(dt.get("minute", 0)),
		]
	# Fallback: parse ISO fragments without timezone conversion.
	if t_pos < 0:
		return "-"
	var parts := cleaned.split("T")
	if parts.size() < 2:
		return "-"
	var d := str(parts[0]).split("-")
	var t := str(parts[1]).split(":")
	if d.size() < 3 or t.size() < 2:
		return "-"
	return "%s.%s.%s %s:%s" % [d[2], d[1], d[0], t[0], t[1]]


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
	pending_checksum = checksum
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


func _maybe_upload_replay_after_score() -> void:
	if not include_replay:
		phase = Phase.LEADERBOARD
		_fetch_leaderboard()
		return
	var main := get_parent()
	if main == null or not main.has_method("get_replay_json"):
		status_text = "Score saved, replay upload failed"
		phase = Phase.LEADERBOARD
		_fetch_leaderboard()
		return
	var replay_json: String = main.get_replay_json()
	if replay_json.is_empty() or not ReplayFormat.fits_size_limit(replay_json):
		status_text = "Score saved, replay upload failed"
		phase = Phase.LEADERBOARD
		_fetch_leaderboard()
		return
	var replay_data := ReplayFormat.parse(replay_json)
	if replay_data.is_empty() or not ReplayFormat.is_valid(replay_data):
		status_text = "Score saved, replay upload failed"
		phase = Phase.LEADERBOARD
		_fetch_leaderboard()
		return
	# Embed the recorder JSON as-is. Re-stringifying a parsed Dictionary turns
	# ints into floats (v/tickHz as 1.0/60.0), which older servers rejected.
	var mode_id: String = HighscoreChecksum.sanitize_mode_id(submit_mode_id)
	var body := '{"checksum":"%s","modeId":"%s","replay":%s}' % [
		pending_checksum,
		mode_id,
		replay_json,
	]
	status_text = "Uploading replay..."
	queue_redraw()
	_replay_gen += 1
	var headers := PackedStringArray(["Content-Type: application/json"])
	var url := "%s/api/replays" % HighscoreConfig.API_BASE_URL.trim_suffix("/")
	var err := _send("replay_upload", url, headers, HTTPClient.METHOD_POST, body, mode_id, _replay_gen)
	if err != OK:
		status_text = "Score saved, replay upload failed"
		phase = Phase.LEADERBOARD
		_fetch_leaderboard()
		queue_redraw()


func _fetch_and_play_replay(checksum: String) -> void:
	if checksum.is_empty():
		return
	status_text = "Loading replay..."
	queue_redraw()
	_replay_gen += 1
	var generation := _replay_gen
	var mode_id: String = HighscoreChecksum.sanitize_mode_id(view_mode_id if not view_mode_id.is_empty() else submit_mode_id)
	var url := "%s/api/replays/%s" % [
		HighscoreConfig.API_BASE_URL.trim_suffix("/"),
		checksum.uri_encode(),
	]
	var err := _send("replay_fetch", url, PackedStringArray(), HTTPClient.METHOD_GET, "", mode_id, generation)
	if err != OK:
		status_text = "Replay unavailable"
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
	http.timeout = 12.0
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
	if kind == "live_ranks" and generation != _live_ranks_gen:
		return
	if kind in ["replay_upload", "replay_fetch"] and generation != _replay_gen:
		return
	var text := body.get_string_from_utf8()

	if kind == "submit":
		if response_code == 200:
			var parsed = JSON.parse_string(text)
			if typeof(parsed) == TYPE_DICTIONARY:
				submitted_rank = int(parsed.get("rank", -1))
			_maybe_upload_replay_after_score()
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

	if kind == "replay_upload":
		if response_code == 200:
			status_text = ""
		else:
			status_text = "Score saved, replay upload failed"
		phase = Phase.LEADERBOARD
		_fetch_leaderboard()
		queue_redraw()
		return

	if kind == "replay_fetch":
		if response_code == 200:
			var parsed = JSON.parse_string(text)
			if typeof(parsed) == TYPE_DICTIONARY:
				var main := get_parent()
				if main != null and main.has_method("start_replay_from_data"):
					if main.start_replay_from_data(parsed):
						status_text = ""
						close_overlay()
						queue_redraw()
						return
			status_text = "Replay invalid"
		else:
			status_text = "Replay unavailable"
		queue_redraw()
		return

	if kind == "leaderboard":
		if response_code == 200:
			var parsed = JSON.parse_string(text)
			if typeof(parsed) == TYPE_ARRAY:
				entries = parsed
			else:
				entries = []
			if status_text == "Submitting..." or status_text == "Uploading replay..." or status_text == "Loading replay...":
				status_text = ""
			if submitted_rank > 0 and view_mode_id == submit_mode_id:
				leaderboard_page = int(float(submitted_rank - 1) / float(HighscoreConfig.LEADERBOARD_PAGE_SIZE))
			_clamp_leaderboard_page()
		else:
			entries = []
			if status_text.is_empty():
				status_text = "Scores unavailable"
			_clamp_leaderboard_page()
		queue_redraw()
		return

	if kind == "live_ranks":
		live_top_scores.clear()
		if response_code == 200:
			var parsed = JSON.parse_string(text)
			if typeof(parsed) == TYPE_ARRAY:
				for entry in parsed:
					if typeof(entry) != TYPE_DICTIONARY:
						continue
					live_top_scores.append(int(entry.get("finalScore", 0)))
					if live_top_scores.size() >= HighscoreConfig.LIVE_RANK_TOP_COUNT:
						break
		return


func _board_title() -> String:
	if view_mode_id == HighscoreConfig.MODE_ID_MOBILE:
		return "MOBILE HIGHSCORES"
	return "HIGHSCORES"


func _layout_name_targets(vp: Vector2) -> Rect2:
	var ui_scale := _ui_scale
	var touch_ui := PlayDevice.is_touch_primary()
	_submit_rect = Rect2()
	_skip_rect = Rect2()
	_replay_toggle_rect = Rect2()
	_name_field_rect = Rect2()
	var panel := Rect2()
	var gap := 0.0
	var button_h := 0.0
	var button_w := 0.0
	var button_y := 0.0
	var toggle_w := 0.0
	var toggle_h := 0.0
	var label_w := 0.0
	var row_w := 0.0
	var row_x := 0.0
	var label_size := maxi(14, int(round(18.0 * ui_scale)))
	if _body_font != null:
		label_w = _body_font.get_string_size(
			"Send replay", HORIZONTAL_ALIGNMENT_LEFT, -1, label_size
		).x
	else:
		label_w = 110.0
	if not touch_ui:
		var desktop_w := minf(420.0 * ui_scale, vp.x - 40.0)
		var desktop_h := 340.0 * ui_scale
		panel = Rect2(
			(vp.x - desktop_w) * 0.5,
			(vp.y - desktop_h) * 0.5 + 36.0 * ui_scale,
			desktop_w,
			desktop_h
		)
		var field_h := 44.0 * ui_scale
		_name_field_rect = Rect2(
			panel.position.x + 20.0 * ui_scale,
			panel.position.y + 110.0 * ui_scale,
			panel.size.x - 40.0 * ui_scale,
			field_h
		)
		toggle_w = maxf(72.0, 70.0 * ui_scale)
		toggle_h = 36.0 * ui_scale
		row_w = label_w + 10.0 * ui_scale + toggle_w
		row_x = panel.get_center().x - row_w * 0.5
		_replay_toggle_rect = Rect2(
			row_x + label_w + 10.0 * ui_scale,
			_name_field_rect.end.y + 14.0 * ui_scale,
			toggle_w,
			toggle_h
		)
		gap = 8.0 * ui_scale
		button_h = 40.0 * ui_scale
		button_w = (panel.size.x - 40.0 * ui_scale - gap) * 0.5
		button_y = panel.end.y - button_h - 16.0 * ui_scale
		_skip_rect = Rect2(panel.position.x + 20.0 * ui_scale, button_y, button_w, button_h)
		_submit_rect = Rect2(_skip_rect.end.x + gap, button_y, button_w, button_h)
		return panel
	var panel_w := minf(maxf(420.0 * ui_scale, 300.0), vp.x - 16.0)
	var panel_h := minf(maxf(300.0, 260.0 * ui_scale), vp.y - 16.0)
	panel = Rect2((vp.x - panel_w) * 0.5, maxf(8.0, (vp.y - panel_h) * 0.35), panel_w, panel_h)
	gap = 8.0
	button_h = 44.0
	button_w = (panel.size.x - 24.0 - gap) * 0.5
	button_y = panel.end.y - button_h - 12.0
	_skip_rect = Rect2(panel.position.x + 12.0, button_y, button_w, button_h)
	_submit_rect = Rect2(_skip_rect.end.x + gap, button_y, button_w, button_h)
	_name_field_rect = Rect2(panel.position.x + 20.0, button_y - 112.0, panel.size.x - 40.0, 44.0)
	toggle_w = 72.0
	row_w = label_w + 10.0 + toggle_w
	row_x = panel.get_center().x - row_w * 0.5
	_replay_toggle_rect = Rect2(
		row_x + label_w + 10.0,
		_name_field_rect.end.y + 10.0,
		toggle_w,
		40.0
	)
	return panel


func _draw_name_field_chrome(field: Rect2, active: bool) -> void:
	if field.size.x <= 0.0:
		return
	var fill := ColorTheme.bg_deep(0.98)
	var border := ColorTheme.accent(0.95) if active else ColorTheme.accent(0.45)
	draw_rect(field, fill, true, -1.0, true)
	draw_rect(field, border, false, maxf(2.0, 2.0 * _ui_scale), true)
	if active and name_cursor_on:
		# Outer pulse so the active field is easy to spot behind the keyboard.
		draw_rect(
			field.grow(3.0 * _ui_scale),
			ColorTheme.accent(0.22),
			false,
			maxf(1.0, 1.5 * _ui_scale),
			true
		)


func _layout_leaderboard(vp: Vector2) -> Rect2:
	var ui_scale := _ui_scale
	var touch_ui := PlayDevice.is_touch_primary()
	var panel_w := minf(900.0 * ui_scale, vp.x - 24.0)
	if touch_ui:
		panel_w = minf(maxf(720.0 * ui_scale, 320.0), vp.x - 12.0)
	var row_h := 28.0 * ui_scale
	var header_h := 22.0 * ui_scale
	var rows := clampi(entries.size(), 1, HighscoreConfig.LEADERBOARD_PAGE_SIZE)
	var page_count := _leaderboard_page_count()
	var pager_h := 40.0 * ui_scale if page_count > 1 else 0.0
	var tab_h := maxf(36.0, 32.0 * ui_scale)
	var action_h := 56.0 if touch_ui else 0.0
	var panel_h := minf(
		100.0 * ui_scale
		+ tab_h
		+ action_h
		+ header_h
		+ float(rows) * row_h
		+ pager_h
		+ 48.0 * ui_scale,
		vp.y - 16.0
	)
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


func _draw_choice(rect: Rect2, label: String, selected: bool, font_size: int = 14) -> void:
	if rect.size.x <= 0.0:
		return
	var fill := ColorTheme.bg_elevated(0.96) if selected else ColorTheme.bg_deep(0.94)
	var border := ColorTheme.accent(0.9) if selected else ColorTheme.accent(0.4)
	draw_rect(rect, fill, true, -1.0, true)
	draw_rect(rect, border, false, 2.0, true)
	var size := font_size
	var baseline := rect.position.y + (rect.size.y + _body_font.get_ascent(size) - _body_font.get_descent(size)) * 0.5
	_draw_centered(_body_font, Vector2(rect.get_center().x, baseline), label, size, ColorTheme.text())


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


func _save_player_name(saved_name: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(HighscoreConfig.PLAYER_NAME_PATH)
	cfg.set_value(HighscoreConfig.PLAYER_NAME_SECTION, HighscoreConfig.PLAYER_NAME_KEY, saved_name)
	cfg.save(HighscoreConfig.PLAYER_NAME_PATH)


func _key_pressed(event: InputEvent, code: Key) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return false
	var key := event as InputEventKey
	return key.keycode == code or key.physical_keycode == code
