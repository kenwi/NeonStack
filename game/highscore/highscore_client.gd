extends Node2D

## HTTP highscore client + game-over name entry / leaderboard overlay.

const HighscoreConfig = preload("res://game/highscore/highscore_config.gd")
const HighscoreChecksum = preload("res://game/highscore/highscore_checksum.gd")

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

var _http: HTTPRequest
var _title_font: Font
var _body_font: Font
var _awaiting: String = ""
var _ui_scale := 1.0


func _ready() -> void:
	_title_font = ThemeDB.fallback_font
	_body_font = ThemeDB.fallback_font
	_http = HTTPRequest.new()
	_http.timeout = 8.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
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
	_awaiting = ""
	queue_redraw()


func begin_game_over(score: int, lines: int, level: int, elapsed_seconds: float) -> void:
	pending_score = score
	pending_lines = lines
	pending_level = level
	pending_elapsed = maxf(0.001, elapsed_seconds)
	submitted_rank = -1
	status_text = ""
	leaderboard_open = false
	if submitted_this_run:
		phase = Phase.LEADERBOARD
		_fetch_leaderboard()
	else:
		phase = Phase.NAME_ENTRY
		cursor_timer = 0.0
		name_cursor_on = true
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
	if _key_pressed(event, KEY_L) and not is_capturing_input():
		if leaderboard_open or phase == Phase.LEADERBOARD:
			leaderboard_open = false
			if not _is_game_over_context():
				phase = Phase.IDLE
			queue_redraw()
		else:
			leaderboard_open = true
			phase = Phase.LEADERBOARD
			_fetch_leaderboard()
			queue_redraw()
		return true

	if phase == Phase.NAME_ENTRY:
		return _handle_name_entry(event)

	if phase == Phase.SUBMITTING:
		return true

	return false


func _is_game_over_context() -> bool:
	var parent_main = get_parent()
	return parent_main != null and parent_main.get("game_over") == true


func _handle_name_entry(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
			_submit_score()
			return true
		if key.keycode == KEY_ESCAPE:
			phase = Phase.LEADERBOARD
			status_text = "Skipped submit"
			_fetch_leaderboard()
			queue_redraw()
			return true
		if key.keycode == KEY_BACKSPACE:
			if player_name.length() > 0:
				player_name = player_name.substr(0, player_name.length() - 1)
				queue_redraw()
			return true
		var ch := char(key.unicode)
		if key.unicode >= 32 and _is_allowed_name_char(ch):
			if player_name.length() < HighscoreConfig.MAX_PLAYER_NAME_LENGTH:
				player_name += ch
				queue_redraw()
			return true
	return true


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


func _process(delta: float) -> void:
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
	var ui_scale := _ui_scale
	var panel_w := mini(420.0 * ui_scale, vp.x - 40.0)
	var panel_h := 210.0 * ui_scale
	var panel := Rect2((vp.x - panel_w) * 0.5, (vp.y - panel_h) * 0.5 + 36.0 * ui_scale, panel_w, panel_h)
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
	y += 36.0 * ui_scale
	var display := player_name
	if name_cursor_on and phase == Phase.NAME_ENTRY:
		display += "|"
	elif phase == Phase.SUBMITTING:
		display = HighscoreChecksum.sanitize_player_name(player_name)
	_draw_centered(_body_font, Vector2(cx, y), display if not display.is_empty() else "|", body_size, Color("ffd166"))
	y += 40.0 * ui_scale
	var hint := "Enter submit    Esc skip"
	if phase == Phase.SUBMITTING:
		hint = status_text if not status_text.is_empty() else "Submitting..."
	_draw_centered(_body_font, Vector2(cx, y), hint, hint_size, Color("6a8799"))


func _draw_leaderboard_panel(vp: Vector2) -> void:
	var ui_scale := _ui_scale
	var panel_w := mini(480.0 * ui_scale, vp.x - 32.0)
	var row_h := 26.0 * ui_scale
	var rows := maxi(1, entries.size())
	var panel_h := mini(120.0 * ui_scale + float(rows) * row_h + 48.0 * ui_scale, vp.y - 32.0)
	var panel := Rect2((vp.x - panel_w) * 0.5, (vp.y - panel_h) * 0.5, panel_w, panel_h)
	draw_rect(panel, Color("0b1a28", 0.94), true, -1.0, true)
	draw_rect(panel, Color("8ef7ff", 0.55), false, maxf(1.0, 2.0 * ui_scale), true)

	var title_size := maxi(18, int(round(26 * ui_scale)))
	var body_size := maxi(12, int(round(16 * ui_scale)))
	var hint_size := maxi(11, int(round(13 * ui_scale)))
	var y := panel.position.y + 34.0 * ui_scale
	_draw_centered(_title_font, Vector2(panel.get_center().x, y), "HIGHSCORES", title_size, Color("8ef7ff"))
	y += 28.0 * ui_scale
	if submitted_rank > 0:
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

	if entries.is_empty() and status_text.is_empty():
		_draw_centered(
			_body_font,
			Vector2(panel.get_center().x, y + 20.0 * ui_scale),
			"No scores yet",
			body_size,
			Color("6a8799")
		)
	else:
		var left_x := panel.position.x + 18.0 * ui_scale
		var score_x := panel.position.x + panel_w * 0.55
		var time_x := panel.position.x + panel_w - 18.0 * ui_scale
		for entry in entries:
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
			if y > panel.end.y - 36.0 * ui_scale:
				break

	var footer := "R / Space / Enter restart"
	if not _is_game_over_context():
		footer = "L close"
	_draw_centered(
		_body_font,
		Vector2(panel.get_center().x, panel.end.y - 18.0 * ui_scale),
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
	if submitted_this_run:
		phase = Phase.LEADERBOARD
		_fetch_leaderboard()
		queue_redraw()
		return

	var sanitized_name: String = HighscoreChecksum.sanitize_player_name(player_name)
	player_name = sanitized_name
	_save_player_name(sanitized_name)

	var mode_id: String = HighscoreChecksum.sanitize_mode_id(HighscoreConfig.MODE_ID)
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
	_awaiting = "submit"
	queue_redraw()

	var body := JSON.stringify(payload)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var url := "%s/api/scores" % HighscoreConfig.API_BASE_URL.trim_suffix("/")
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		status_text = "Submit failed (offline)"
		phase = Phase.LEADERBOARD
		_awaiting = ""
		_fetch_leaderboard()
		queue_redraw()


func _fetch_leaderboard() -> void:
	_awaiting = "leaderboard"
	var mode_id: String = HighscoreChecksum.sanitize_mode_id(HighscoreConfig.MODE_ID)
	var url := "%s/api/scores/%s?top=%d" % [
		HighscoreConfig.API_BASE_URL.trim_suffix("/"),
		mode_id.uri_encode(),
		HighscoreConfig.DEFAULT_TOP_COUNT,
	]
	var err := _http.request(url, PackedStringArray(), HTTPClient.METHOD_GET)
	if err != OK:
		if status_text.is_empty():
			status_text = "Scores unavailable"
		_awaiting = ""
		queue_redraw()


func _on_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var awaiting := _awaiting
	_awaiting = ""
	var text := body.get_string_from_utf8()

	if awaiting == "submit":
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

	if awaiting == "leaderboard":
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
