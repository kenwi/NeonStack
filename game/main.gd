extends Node2D

## Stylized neon-arcade Tetris clone.

const PlayDevice = preload("res://game/platform/play_device.gd")

const COLS := 10
const ROWS := 20
const REF_CELL := 36.0
const MIN_CELL := 18.0
const MIN_CELL_TOUCH := 6.0
const MAX_CELL := 72.0
const GAP := 2.0
const FRAME_PAD := 14.0
## Side panel sizes as multiples of the live cell size.
const HOLD_W_CELLS := 3.75
const HOLD_H_CELLS := 3.75
const SIDE_W_CELLS := 3.75
const NEXT_H_CELLS := 7.0
const STATS_H_CELLS := 3.45
const SIDE_GAP_CELLS := 0.65
const PANEL_GAP_CELLS := 0.45
const PANEL_PAD_X := 12.0
const UI_MARGIN := 12.0
const TITLE_SIZE_BASE := 28
const HINT_SIZE_BASE := 15
const HELP_TITLE_SIZE_BASE := 28
const HELP_ROW_SIZE_BASE := 18
const HELP_HINT := "Press H for controls"
const HELP_HINT_TOUCH := "Tap Help for controls"
const HELP_KEYS := [
	["Left / Right", "Move"],
	["Up / X", "Rotate"],
	["Z", "Counter-rotate"],
	["Down", "Soft drop"],
	["Space / Enter", "Hard drop"],
	["C / Shift", "Hold"],
	["M", "Mute music"],
	["N", "Next track"],
	["PgUp / PgDn", "Music volume"],
	["Esc", "Pause"],
	["R", "Restart"],
	["L", "Highscores"],
	["F / F11", "Fullscreen"],
	["J", "Toggle juice FX"],
	["Q", "Quit"],
	["H", "Toggle this help"],
	["S", "Score table"],
]
const HELP_TOUCH := [
	["Upper left", "Move left"],
	["Upper right", "Move right"],
	["Lower left", "Rotate"],
	["Lower right", "Hard drop"],
	["Left / Right", "Move"],
	["Down", "Soft drop"],
	["Rotate", "Rotate"],
	["Counter", "Counter-rotate"],
	["Drop", "Hard drop"],
	["Hold", "Hold piece"],
	["1x / 3x", "Button size"],
	["Zones", "Show tap zones"],
	["Full", "Fullscreen"],
	["Juice", "Toggle juice FX"],
	["Pause", "Pause"],
	["Restart", "Restart"],
	["Scores", "Highscores"],
	["Mute", "Mute music"],
	["Next", "Next track"],
	["Help", "Toggle this help"],
]
const SCORE_HELP_ROWS := [
	["Soft drop", "+1 per cell"],
	["Hard drop", "+2 per cell"],
	["1 line", "100 × level"],
	["2 lines", "300 × level"],
	["3 lines", "500 × level"],
	["4 lines", "800 × level"],
	["Level up", "Every 10 lines (max 15)"],
	["Holding a piece", "No points"],
]

const PIECES := {
	"I": [
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)],
		[Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3)],
	],
	"O": [[Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1)]],
	"T": [
		[Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)],
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)],
		[Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2)],
	],
	"S": [
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)],
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2)],
	],
	"Z": [
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(2, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)],
	],
	"J": [
		[Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(1, 2)],
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(2, 2)],
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2)],
	],
	"L": [
		[Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(2, 2)],
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(0, 2)],
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2)],
	],
}

const COLORS := {
	"I": Color("36d6ff"),
	"O": Color("ffd166"),
	"T": Color("c084fc"),
	"S": Color("4ade80"),
	"Z": Color("fb7185"),
	"J": Color("60a5fa"),
	"L": Color("fb923c"),
}

const SCORE_TABLE := [0, 100, 300, 500, 800]
const BAG_ORDER := ["I", "O", "T", "S", "Z", "J", "L"]

var board: Array = []
var bag: Array = []
var queue: Array = []

var piece_id: String = ""
var piece_rot: int = 0
var piece_pos := Vector2i(3, 0)
var hold_id: String = ""
var hold_locked := false

var score := 0
var lines_cleared := 0
var level := 1
var elapsed_seconds := 0.0
var game_over := false
var paused := false
var help_open := false
var score_open := false

var drop_timer := 0.0
var lock_timer := 0.0
var lock_resets := 0
var das_timer := 0.0
var arr_timer := 0.0
var soft_timer := 0.0
var move_held := 0
var clear_flash: Array = []
var clear_timer := 0.0
var pulse := 0.0

var board_origin := Vector2.ZERO
var cell_size := REF_CELL
var ui_scale := 1.0
var hold_w := HOLD_W_CELLS * REF_CELL
var hold_h := HOLD_H_CELLS * REF_CELL
var side_w := SIDE_W_CELLS * REF_CELL
var next_h := NEXT_H_CELLS * REF_CELL
var stats_h := STATS_H_CELLS * REF_CELL
var side_gap := SIDE_GAP_CELLS * REF_CELL
var panel_gap := PANEL_GAP_CELLS * REF_CELL
var title_size := TITLE_SIZE_BASE
var hint_size := HINT_SIZE_BASE
var help_title_size := HELP_TITLE_SIZE_BASE
var help_row_size := HELP_ROW_SIZE_BASE
var title_pos := Vector2.ZERO
var hint_pos := Vector2.ZERO
var title_font: Font
var body_font: Font

# The scene already owns these nodes. Preloading scripts from here cycles the load.
@onready var music = $Music
@onready var highscores = $Highscores
@onready var juice = $Juice
@onready var touch = $TouchControls

var _touch_close_rect := Rect2()
var _touch_restart_rect := Rect2()


func _board_size() -> Vector2:
	return Vector2(COLS * cell_size, ROWS * cell_size)


func _board_center() -> Vector2:
	return board_origin + _board_size() * 0.5


func _set_game_over() -> void:
	if game_over:
		return
	game_over = true
	if highscores != null:
		highscores.begin_game_over(score, lines_cleared, level, elapsed_seconds)


func _ready() -> void:
	title_font = ThemeDB.fallback_font
	body_font = ThemeDB.fallback_font
	_layout()
	_new_game()
	# Desktop: show keyboard controls before the first piece drops.
	# Touch: skip that overlay so the close tap cannot also hard-drop the piece.
	help_open = not PlayDevice.is_touch_primary()
	if PlayDevice.is_touch_primary() and touch != null:
		touch.suppress_play_taps(400)
	queue_redraw()
	get_viewport().size_changed.connect(_layout)


func _apply_cell_metrics() -> void:
	ui_scale = cell_size / REF_CELL
	hold_w = HOLD_W_CELLS * cell_size
	hold_h = HOLD_H_CELLS * cell_size
	side_w = SIDE_W_CELLS * cell_size
	next_h = NEXT_H_CELLS * cell_size
	stats_h = STATS_H_CELLS * cell_size
	side_gap = SIDE_GAP_CELLS * cell_size
	panel_gap = PANEL_GAP_CELLS * cell_size
	title_size = maxi(18, int(round(TITLE_SIZE_BASE * ui_scale)))
	hint_size = maxi(12, int(round(HINT_SIZE_BASE * ui_scale)))
	help_title_size = maxi(18, int(round(HELP_TITLE_SIZE_BASE * ui_scale)))
	help_row_size = maxi(14, int(round(HELP_ROW_SIZE_BASE * ui_scale)))
	if highscores != null:
		highscores.set_ui_scale(ui_scale)


func _layout() -> void:
	if title_font == null or body_font == null:
		return
	var vp := get_viewport_rect().size
	var margin := UI_MARGIN
	# Include the outer glow so the frame is never clipped by the window edge.
	var frame_outer := float(FRAME_PAD) + 3.0
	var title_gap := 8.0
	var width_cells := float(COLS) + HOLD_W_CELLS + SIDE_W_CELLS + SIDE_GAP_CELLS * 2.0
	var min_cell := MIN_CELL
	var top_inset := 0.0
	var bottom_inset := 0.0
	if touch != null and touch.reserves_layout():
		min_cell = MIN_CELL_TOUCH
		top_inset = touch.utility_height()
		bottom_inset = touch.band_height(vp.x)
	var usable_h := vp.y - top_inset - bottom_inset
	var cell_from_w := floorf((vp.x - margin * 2.0) / width_cells)
	var title_cells := float(TITLE_SIZE_BASE) / REF_CELL
	var cell_from_h := floorf((usable_h - margin * 2.0 - title_gap - frame_outer * 2.0) / (float(ROWS) + title_cells))
	cell_size = clampf(minf(cell_from_w, cell_from_h), min_cell, MAX_CELL)
	# Shrink until the measured title + board stack actually fits the viewport.
	var title_ascent := 0.0
	var title_descent := 0.0
	var stack_h := 0.0
	while cell_size > min_cell:
		_apply_cell_metrics()
		title_ascent = title_font.get_ascent(title_size)
		title_descent = title_font.get_descent(title_size)
		stack_h = title_ascent + title_descent + title_gap + frame_outer * 2.0 + ROWS * cell_size
		var stack_w := COLS * cell_size + hold_w + side_w + side_gap * 2.0
		if stack_h <= usable_h - margin * 2.0 and stack_w <= vp.x - margin * 2.0:
			break
		cell_size -= 1.0
	_apply_cell_metrics()
	title_ascent = title_font.get_ascent(title_size)
	title_descent = title_font.get_descent(title_size)
	var board_w := COLS * cell_size
	var board_h := ROWS * cell_size
	stack_h = title_ascent + title_descent + title_gap + frame_outer * 2.0 + board_h
	var stack_top := top_inset + maxf(margin, (usable_h - stack_h) * 0.5)
	board_origin = Vector2((vp.x - board_w) * 0.5, stack_top + title_ascent + title_descent + title_gap + frame_outer)
	var title := "NEON STACK"
	var title_w := title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
	title_pos = Vector2(
		board_origin.x + (board_w - title_w) * 0.5,
		board_origin.y - frame_outer - title_gap - title_descent
	)
	hint_pos = Vector2(
		board_origin.x - side_gap - hold_w,
		maxf(margin, board_origin.y - frame_outer) - (body_font.get_descent(hint_size) + 6.0)
	)
	hint_pos.y = clampf(
		hint_pos.y,
		top_inset + margin + body_font.get_ascent(hint_size),
		board_origin.y - frame_outer - 8.0
	)
	queue_redraw()


func _new_game() -> void:
	board = []
	for _y in ROWS:
		var row: Array = []
		row.resize(COLS)
		row.fill("")
		board.append(row)
	bag.clear()
	queue.clear()
	hold_id = ""
	hold_locked = false
	score = 0
	lines_cleared = 0
	level = 1
	elapsed_seconds = 0.0
	game_over = false
	paused = false
	help_open = false
	score_open = false
	clear_flash.clear()
	clear_timer = 0.0
	lock_timer = 0.0
	lock_resets = 0
	drop_timer = 0.0
	das_timer = 0.0
	arr_timer = 0.0
	soft_timer = 0.0
	move_held = 0
	if highscores != null:
		highscores.reset_run()
	if juice != null:
		juice.reset_run()
	_spawn_next()
	queue_redraw()


func _refill_bag() -> void:
	var next_bag := BAG_ORDER.duplicate()
	next_bag.shuffle()
	bag.append_array(next_bag)


func _spawn_next() -> void:
	while queue.size() < 5:
		if bag.is_empty():
			_refill_bag()
		queue.append(bag.pop_front())
	piece_id = queue.pop_front()
	piece_rot = 0
	piece_pos = Vector2i(3, 0)
	hold_locked = false
	lock_timer = 0.0
	lock_resets = 0
	if not _valid(piece_pos, piece_rot):
		_set_game_over()


func _cells(pid: String, rot: int, origin: Vector2i) -> Array[Vector2i]:
	var shapes: Array = PIECES[pid]
	var shape: Array = shapes[rot % shapes.size()]
	var out: Array[Vector2i] = []
	for c in shape:
		out.append(origin + c)
	return out


func _valid(origin: Vector2i, rot: int, pid: String = piece_id) -> bool:
	for c in _cells(pid, rot, origin):
		if c.x < 0 or c.x >= COLS or c.y >= ROWS:
			return false
		if c.y >= 0 and board[c.y][c.x] != "":
			return false
	return true


func _try_move(dx: int, dy: int) -> bool:
	var next := piece_pos + Vector2i(dx, dy)
	if _valid(next, piece_rot):
		piece_pos = next
		if dy == 0:
			_bump_lock()
		queue_redraw()
		return true
	return false


func _try_rotate(dir: int) -> void:
	var shapes: Array = PIECES[piece_id]
	var next_rot := (piece_rot + dir) % shapes.size()
	if next_rot < 0:
		next_rot += shapes.size()
	var kicks := [
		Vector2i(0, 0),
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(-2, 0),
		Vector2i(2, 0),
		Vector2i(0, -1),
		Vector2i(0, 1),
		Vector2i(-1, -1),
		Vector2i(1, -1),
		Vector2i(-2, -1),
		Vector2i(2, -1),
	]
	for k in kicks:
		if _valid(piece_pos + k, next_rot):
			piece_pos += k
			piece_rot = next_rot
			_bump_lock()
			queue_redraw()
			return


func _bump_lock() -> void:
	if _grounded():
		if lock_resets < 15:
			lock_timer = 0.0
			lock_resets += 1


func _grounded() -> bool:
	return not _valid(piece_pos + Vector2i(0, 1), piece_rot)


func _hard_drop() -> void:
	if clear_timer > 0.0 or game_over or paused:
		return
	var from_cells: Array = _cells(piece_id, piece_rot, piece_pos)
	var dist := 0
	while _try_move(0, 1):
		dist += 1
	score += dist * 2
	if juice != null and dist > 0:
		var col: Color = COLORS[piece_id]
		juice.hard_drop(from_cells, _cells(piece_id, piece_rot, piece_pos), col, board_origin, cell_size)
		juice.note_score(score, _board_center())
	_lock_piece()


func _lock_piece() -> void:
	if clear_timer > 0.0:
		return
	var locked_cells: Array = _cells(piece_id, piece_rot, piece_pos)
	var lock_color: Color = COLORS[piece_id] if COLORS.has(piece_id) else Color("8ef7ff")
	for c in locked_cells:
		if c.y < 0:
			_set_game_over()
			queue_redraw()
			return
		board[c.y][c.x] = piece_id
	if juice != null:
		juice.lock_impact(locked_cells, lock_color, board_origin, cell_size)
	_begin_line_clear()


func _begin_line_clear() -> void:
	clear_flash.clear()
	for y in ROWS:
		var full := true
		for x in COLS:
			if board[y][x] == "":
				full = false
				break
		if full:
			clear_flash.append(y)
	if clear_flash.is_empty():
		if juice != null:
			juice.note_no_clear()
		_spawn_next()
	else:
		if juice != null:
			juice.line_clear_begin(clear_flash, board, COLORS, board_origin, cell_size)
		clear_timer = 0.28
	queue_redraw()


func _finish_line_clear() -> void:
	var cleared := clear_flash.size()
	# Remove bottom-to-top first (keeps lower indices stable), then add empty
	# rows. Interleaving push_front with remove_at shifts indices and leaves
	# the upper cleared row(s) on the board for doubles/triples/tetrises.
	clear_flash.sort()
	clear_flash.reverse()
	for y in clear_flash:
		board.remove_at(y)
	for _i in cleared:
		var row: Array = []
		row.resize(COLS)
		row.fill("")
		board.push_front(row)
	clear_flash.clear()
	clear_timer = 0.0
	lines_cleared += cleared
	var points: int = int(SCORE_TABLE[cleared]) * level
	score += points
	var previous_level := level
	level = mini(15, 1 + int(lines_cleared / 10.0))
	if juice != null:
		juice.line_clear_scored(cleared, points, _board_center())
		juice.note_score(score, _board_center())
		if level > previous_level:
			juice.level_up(level, _board_center())
	_spawn_next()
	queue_redraw()


func toggle_juice() -> void:
	if juice == null:
		return
	juice.toggle()
	queue_redraw()


func _hold() -> void:
	if hold_locked or game_over or paused or clear_timer > 0.0:
		return
	hold_locked = true
	if hold_id == "":
		hold_id = piece_id
		_spawn_next()
	else:
		var swap := hold_id
		hold_id = piece_id
		piece_id = swap
		piece_rot = 0
		piece_pos = Vector2i(3, 0)
		lock_timer = 0.0
		lock_resets = 0
		if not _valid(piece_pos, piece_rot):
			_set_game_over()
	queue_redraw()


func _ghost_y() -> int:
	var y := piece_pos.y
	while _valid(Vector2i(piece_pos.x, y + 1), piece_rot):
		y += 1
	return y


func _drop_interval() -> float:
	return maxf(0.05, 0.85 * pow(0.82, level - 1))


func _highscores_open() -> bool:
	return highscores != null and highscores.is_showing_overlay()


func _process(delta: float) -> void:
	pulse += delta
	if juice != null:
		juice.tick(delta)
	if game_over or paused or help_open or score_open or _highscores_open():
		queue_redraw()
		return
	if clear_timer > 0.0:
		clear_timer -= delta
		if clear_timer <= 0.0:
			_finish_line_clear()
		queue_redraw()
		return
	elapsed_seconds += delta
	_handle_das(delta)
	if Input.is_action_pressed("ui_down"):
		soft_timer -= delta
		if soft_timer <= 0.0:
			if _try_move(0, 1):
				score += 1
				if juice != null:
					juice.note_score(score, _board_center())
			soft_timer = 0.035
	else:
		soft_timer = 0.0
		drop_timer += delta
		if drop_timer >= _drop_interval():
			drop_timer = 0.0
			if not _try_move(0, 1):
				pass
	if _grounded():
		lock_timer += delta
		if lock_timer >= 0.5:
			_lock_piece()
	else:
		lock_timer = 0.0
		lock_resets = 0
	queue_redraw()


func _handle_das(delta: float) -> void:
	var dir := 0
	if Input.is_action_pressed("ui_left"):
		dir -= 1
	if Input.is_action_pressed("ui_right"):
		dir += 1
	if dir == 0:
		move_held = 0
		das_timer = 0.0
		arr_timer = 0.0
		return
	if dir != move_held:
		move_held = dir
		_try_move(dir, 0)
		das_timer = 0.15
		arr_timer = 0.0
		return
	das_timer -= delta
	if das_timer <= 0.0:
		arr_timer -= delta
		if arr_timer <= 0.0:
			_try_move(dir, 0)
			arr_timer = 0.03


func _key_pressed(event: InputEvent, code: Key) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return false
	var key := event as InputEventKey
	return key.keycode == code or key.physical_keycode == code


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	var fullscreen := (
		mode == DisplayServer.WINDOW_MODE_FULLSCREEN
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	)
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN
	)


func _quit_game() -> void:
	if OS.has_feature("web"):
		# Browsers only allow close for script-opened windows; try anyway, then
		# blank the tab so a blocked close still leaves the page.
		JavaScriptBridge.eval(
			"(function(){try{window.open('','_self');window.close();}catch(e){}"
			+ "document.documentElement.innerHTML='';"
			+ "window.location.replace('about:blank');})();",
			true
		)
	get_tree().quit()


func _help_rows() -> Array:
	if PlayDevice.is_touch_primary():
		return HELP_TOUCH
	return HELP_KEYS


func _handle_touch_overlay(event: InputEvent) -> bool:
	# Ghost mouse clicks after a finger tap must not close and then also play.
	if PlayDevice.is_touch_primary() and event is InputEventMouseButton:
		return false
	if not PlayDevice.has_pointer_down(event):
		return false
	_sync_touch_overlay_rects()
	var point := PlayDevice.pointer_down_position(event)
	if _touch_close_rect.size.x > 0.0 and _touch_close_rect.has_point(point):
		help_open = false
		score_open = false
		if touch != null:
			touch.suppress_play_taps()
		queue_redraw()
		return true
	if _touch_restart_rect.size.x > 0.0 and _touch_restart_rect.has_point(point):
		_new_game()
		return true
	if PlayDevice.is_touch_primary() and (help_open or score_open):
		# Eat taps on the dimmed panel so they cannot fall through to play.
		if touch != null:
			touch.suppress_play_taps()
		help_open = false
		score_open = false
		queue_redraw()
		return true
	return false


func _input(event: InputEvent) -> void:
	# Name entry / submit owns the keyboard so game and music binds do not fire.
	# Unhandled events stay unhandled so the touch name field can take them.
	if highscores != null and highscores.is_capturing_input():
		if highscores.handle_input(event):
			get_viewport().set_input_as_handled()
		return
	if _handle_touch_overlay(event):
		get_viewport().set_input_as_handled()
		return
	if touch != null and touch.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if music != null and music.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if highscores != null and highscores.handle_input(event):
		if _highscores_open():
			help_open = false
			score_open = false
		get_viewport().set_input_as_handled()
		return
	if _key_pressed(event, KEY_H):
		help_open = not help_open
		if help_open:
			score_open = false
			if highscores != null:
				highscores.close_overlay()
		queue_redraw()
		get_viewport().set_input_as_handled()
		return
	if _key_pressed(event, KEY_S):
		score_open = not score_open
		if score_open:
			help_open = false
			if highscores != null:
				highscores.close_overlay()
		queue_redraw()
		get_viewport().set_input_as_handled()
		return
	if _key_pressed(event, KEY_F) or _key_pressed(event, KEY_F11):
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return
	if _key_pressed(event, KEY_J):
		toggle_juice()
		get_viewport().set_input_as_handled()
		return
	if _key_pressed(event, KEY_Q):
		_quit_game()
		get_viewport().set_input_as_handled()
		return
	if _key_pressed(event, KEY_R):
		_new_game()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		if help_open or score_open:
			help_open = false
			score_open = false
		elif _highscores_open() and highscores != null and not highscores.is_capturing_input():
			highscores.close_overlay()
		elif DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN \
			or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		elif game_over:
			_quit_game()
		elif paused:
			_quit_game()
		else:
			paused = true
		queue_redraw()
		get_viewport().set_input_as_handled()
		return
	if game_over:
		if (
			_key_pressed(event, KEY_SPACE)
			or _key_pressed(event, KEY_ENTER)
			or _key_pressed(event, KEY_KP_ENTER)
		):
			_new_game()
			get_viewport().set_input_as_handled()
		return
	if help_open or score_open or _highscores_open():
		get_viewport().set_input_as_handled()
		return
	if paused:
		if event.is_pressed() and not event.is_echo():
			paused = false
			queue_redraw()
			get_viewport().set_input_as_handled()
		return
	# Line-clear flash owns the board; ignore play input until rows are removed.
	if clear_timer > 0.0:
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_up") or _key_pressed(event, KEY_X):
		_try_rotate(1)
		get_viewport().set_input_as_handled()
	elif _key_pressed(event, KEY_Z):
		_try_rotate(-1)
		get_viewport().set_input_as_handled()
	elif (
		_key_pressed(event, KEY_SPACE)
		or _key_pressed(event, KEY_ENTER)
		or _key_pressed(event, KEY_KP_ENTER)
	):
		_hard_drop()
		get_viewport().set_input_as_handled()
	elif _key_pressed(event, KEY_C) or _key_pressed(event, KEY_SHIFT):
		_hold()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	var vp := get_viewport_rect().size
	_draw_backdrop(vp)
	_draw_board_frame()
	_draw_board_cells()
	if juice != null:
		juice.draw_fx(self)
	if not game_over and clear_timer <= 0.0:
		_draw_ghost()
		_draw_active()
	_draw_side_panels()
	_draw_hud()
	_draw_overlays(vp)


func _draw_backdrop(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color("071018"))
	var accent := Color("123047")
	for i in 18:
		var y := fposmod(pulse * 18.0 + i * 54.0, vp.y + 80.0) - 40.0
		draw_line(Vector2(0, y), Vector2(vp.x, y), Color(accent, 0.18), 1.0)
	var glow := Color("1ec8ff")
	glow.a = 0.05 + 0.03 * sin(pulse * 1.4)
	draw_circle(_board_center() + Vector2(0, _board_size().y * -0.05), 280.0, glow)


func _draw_board_frame() -> void:
	var pad := FRAME_PAD
	var board_w := COLS * cell_size
	var board_h := ROWS * cell_size
	var frame := Rect2(board_origin - Vector2(pad, pad), Vector2(board_w, board_h) + Vector2(pad, pad) * 2.0)
	draw_rect(frame, Color("0b1a28"), true, -1.0, true)
	draw_rect(frame.grow(3.0), Color("1ec8ff", 0.35), false, 2.0, true)
	draw_rect(frame, Color("8ef7ff", 0.55), false, 1.5, true)
	for x in COLS + 1:
		var px := board_origin.x + x * cell_size
		draw_line(Vector2(px, board_origin.y), Vector2(px, board_origin.y + board_h), Color("123047", 0.55), 1.0)
	for y in ROWS + 1:
		var py := board_origin.y + y * cell_size
		draw_line(Vector2(board_origin.x, py), Vector2(board_origin.x + board_w, py), Color("123047", 0.55), 1.0)


func _draw_board_cells() -> void:
	for y in ROWS:
		var flashing := clear_flash.has(y) and int(pulse * 24.0) % 2 == 0
		for x in COLS:
			var id: String = board[y][x]
			if id == "":
				continue
			var col: Color = COLORS[id]
			if flashing:
				col = Color.WHITE
			_draw_block(Vector2i(x, y), col, 1.0)


func _draw_active() -> void:
	var col: Color = COLORS[piece_id]
	var scale_mul := 1.0
	if juice != null:
		scale_mul = juice.active_pulse_scale(_grounded(), lock_timer, 0.5)
	for c in _cells(piece_id, piece_rot, piece_pos):
		if c.y < 0:
			continue
		_draw_block(c, col, scale_mul)


func _draw_ghost() -> void:
	var gy := _ghost_y()
	if gy == piece_pos.y:
		return
	var col: Color = COLORS[piece_id]
	col.a = 0.22
	for c in _cells(piece_id, piece_rot, Vector2i(piece_pos.x, gy)):
		if c.y < 0:
			continue
		_draw_block(c, col, 0.55)


func _draw_block(cell: Vector2i, color: Color, scale_mul: float) -> void:
	var size := (cell_size - GAP * 2.0) * scale_mul
	var inset := (cell_size - size) * 0.5
	var pos := board_origin + Vector2(cell.x * cell_size + inset, cell.y * cell_size + inset)
	_draw_block_rect(Rect2(pos, Vector2(size, size)), color)


func _draw_block_rect(rect: Rect2, color: Color) -> void:
	var s := minf(rect.size.x, rect.size.y)
	var glow_pad := maxf(1.5, s * 0.09)
	var edge := maxf(1.5, s * 0.12)
	var bar := maxf(1.5, s * 0.12)
	var glow := color.lightened(0.15)
	glow.a = color.a * 0.35
	draw_rect(rect.grow(glow_pad), glow, true, -1.0, true)
	draw_rect(rect, color, true, -1.0, true)
	var hi := color.lightened(0.45)
	hi.a = color.a * 0.85
	draw_rect(Rect2(rect.position + Vector2(edge, edge), Vector2(rect.size.x * 0.42, bar)), hi, true, -1.0, true)
	draw_rect(Rect2(rect.position + Vector2(edge, edge), Vector2(bar, rect.size.y * 0.42)), hi, true, -1.0, true)
	var shade := color.darkened(0.35)
	shade.a = color.a * 0.7
	var shade_inset := edge * 1.5
	draw_rect(
		Rect2(
			rect.position + Vector2(rect.size.x - edge - bar, shade_inset),
			Vector2(bar, maxf(1.0, rect.size.y - shade_inset * 2.0))
		),
		shade,
		true,
		-1.0,
		true
	)
	draw_rect(
		Rect2(
			rect.position + Vector2(shade_inset, rect.size.y - edge - bar),
			Vector2(maxf(1.0, rect.size.x - shade_inset * 2.0), bar)
		),
		shade,
		true,
		-1.0,
		true
	)


func _draw_mini(origin: Vector2, pid: String, cell: float) -> void:
	if pid == "":
		return
	var shapes: Array = PIECES[pid]
	var shape: Array = shapes[0]
	var min_c := Vector2i(99, 99)
	var max_c := Vector2i(-99, -99)
	for c in shape:
		min_c = Vector2i(mini(min_c.x, c.x), mini(min_c.y, c.y))
		max_c = Vector2i(maxi(max_c.x, c.x), maxi(max_c.y, c.y))
	var w := (max_c.x - min_c.x + 1) * cell
	var h := (max_c.y - min_c.y + 1) * cell
	var base := origin - Vector2(w, h) * 0.5
	var col: Color = COLORS[pid]
	var gap := maxf(1.0, cell * 0.08)
	var block := cell - gap * 2.0
	for c in shape:
		var p := base + Vector2((c.x - min_c.x) * cell + gap, (c.y - min_c.y) * cell + gap)
		_draw_block_rect(Rect2(p, Vector2(block, block)), col)


func _draw_panel(rect: Rect2, label: String, label_size: int = 18) -> void:
	draw_rect(rect, Color("0b1a28", 0.92), true, -1.0, true)
	draw_rect(rect, Color("8ef7ff", 0.35), false, 1.5, true)
	draw_string(
		body_font,
		rect.position + Vector2(PANEL_PAD_X * ui_scale, 22.0 * ui_scale),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		label_size,
		Color("8ef7ff")
	)


func _draw_side_panels() -> void:
	var board_w := COLS * cell_size
	# Align side panels with the outermost board border (frame + glow).
	var panel_top := board_origin.y - FRAME_PAD - 3.0
	var hold := Rect2(Vector2(board_origin.x - side_gap - hold_w, panel_top), Vector2(hold_w, hold_h))
	var next := Rect2(Vector2(board_origin.x + board_w + side_gap, panel_top), Vector2(side_w, next_h))
	var stats := Rect2(Vector2(next.position.x, next.end.y + panel_gap), Vector2(side_w, stats_h))
	var label_size := maxi(14, int(round(18.0 * ui_scale)))
	var mini_hold := maxf(14.0, cell_size * 0.6)
	var mini_next := maxf(12.0, cell_size * 0.55)
	var next_slot := next_h / 3.5
	_draw_panel(hold, "HOLD", label_size)
	_draw_mini(hold.get_center() + Vector2(0, 10.0 * ui_scale), hold_id, mini_hold)
	_draw_panel(next, "NEXT", label_size)
	for i in mini(3, queue.size()):
		_draw_mini(next.position + Vector2(side_w * 0.5, next_slot * (0.85 + i)), queue[i], mini_next)
	_draw_panel(stats, "STATS", label_size)
	# Label left / value right-aligned so large scores grow inward, not past the border.
	var stat_rows := [
		["SCORE", str(score)],
		["LINES", str(lines_cleared)],
		["LEVEL", str(level)],
	]
	var stats_size := maxi(14, int(round(18.0 * ui_scale)))
	var stats_step := maxf(20.0, 28.0 * ui_scale)
	var stats_top := 50.0 * ui_scale
	var pad_x := PANEL_PAD_X * ui_scale
	var text_w := stats.size.x - pad_x * 2.0
	var gap := 10.0 * ui_scale
	# One shared size for all rows so SCORE/LINES/LEVEL stay visually consistent.
	var row_size := stats_size
	while row_size > 10:
		var fits := true
		for row in stat_rows:
			var label_w := body_font.get_string_size(row[0], HORIZONTAL_ALIGNMENT_LEFT, -1, row_size).x
			var value_w := body_font.get_string_size(row[1], HORIZONTAL_ALIGNMENT_LEFT, -1, row_size).x
			if label_w + gap + value_w > text_w:
				fits = false
				break
		if fits:
			break
		row_size -= 1
	for i in stat_rows.size():
		var y := stats.position.y + stats_top + i * stats_step
		var label: String = stat_rows[i][0]
		var value: String = stat_rows[i][1]
		draw_string(
			body_font,
			Vector2(stats.position.x + pad_x, y),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			row_size,
			Color("e8f7ff")
		)
		draw_string(
			body_font,
			Vector2(stats.position.x + pad_x, y),
			value,
			HORIZONTAL_ALIGNMENT_RIGHT,
			text_w,
			row_size,
			Color("e8f7ff")
		)


func _draw_hud() -> void:
	draw_string(title_font, title_pos, "NEON STACK", HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, Color("8ef7ff"))
	var hint := HELP_HINT_TOUCH if PlayDevice.is_touch_primary() else HELP_HINT
	draw_string(body_font, hint_pos, hint, HORIZONTAL_ALIGNMENT_LEFT, -1, hint_size, Color("8ef7ff", 0.72))


func _draw_centered_label(center: Vector2, text: String, font: Font, size: int, color: Color, y_offset: float = 0.0) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, Vector2(center.x - width * 0.5, center.y + y_offset), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _measure_info_table(vp: Vector2, title: String, rows: Array, footer: String) -> Dictionary:
	var touch_ui := PlayDevice.is_touch_primary()
	var row_size := help_row_size
	var title_size_local := help_title_size
	var col_gap := 40.0 * ui_scale
	var pad_x := 32.0 * ui_scale
	var pad_top := 26.0 * ui_scale
	var pad_bottom := 28.0 * ui_scale
	var footer_h := 56.0 if touch_ui else body_font.get_ascent(hint_size) + body_font.get_descent(hint_size) + 10.0 * ui_scale
	var max_panel_h := maxf(160.0, vp.y - 16.0)
	var left_w := 0.0
	var right_w := 0.0
	var title_h := 0.0
	var row_h := 0.0
	var title_w := 0.0
	var footer_w := 0.0
	var panel_w := 0.0
	var panel_h := 0.0
	# Shrink row typography until the panel fits short desktop windows.
	while true:
		left_w = 0.0
		right_w = 0.0
		for row in rows:
			left_w = maxf(left_w, body_font.get_string_size(str(row[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, row_size).x)
			right_w = maxf(right_w, body_font.get_string_size(str(row[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, row_size).x)
		title_h = title_font.get_ascent(title_size_local) + title_font.get_descent(title_size_local)
		row_h = body_font.get_ascent(row_size) + body_font.get_descent(row_size) + maxf(6.0, 14.0 * ui_scale * float(row_size) / float(help_row_size))
		title_w = title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size_local).x
		footer_w = 0.0 if touch_ui else body_font.get_string_size(footer, HORIZONTAL_ALIGNMENT_LEFT, -1, hint_size).x
		var content_w := left_w + col_gap + right_w
		panel_w = maxf(pad_x * 2.0 + content_w, maxf(title_w, footer_w) + pad_x * 2.0)
		if touch_ui:
			panel_w = minf(panel_w, vp.x - 16.0)
		panel_h = pad_top + title_h + 18.0 * ui_scale + row_h * float(rows.size()) + footer_h + pad_bottom
		if panel_h <= max_panel_h or row_size <= 12:
			break
		row_size -= 1
		if title_size_local > 18 and row_size % 2 == 0:
			title_size_local -= 1
	panel_h = minf(panel_h, max_panel_h)
	var center := _board_center()
	var panel := Rect2(center - Vector2(panel_w, panel_h) * 0.5, Vector2(panel_w, panel_h))
	panel.position.x = clampf(panel.position.x, 8.0, maxf(8.0, vp.x - panel.size.x - 8.0))
	panel.position.y = clampf(panel.position.y, 8.0, maxf(8.0, vp.y - panel.size.y - 8.0))
	var close := Rect2()
	if touch_ui:
		var button_w := minf(160.0, panel.size.x - 24.0)
		var button_h := 44.0
		var button_y := minf(panel.end.y - button_h - 12.0, vp.y - button_h - 12.0)
		close = Rect2(panel.position.x + (panel.size.x - button_w) * 0.5, button_y, button_w, button_h)
	return {
		"panel": panel,
		"left_w": left_w,
		"right_w": right_w,
		"col_gap": col_gap,
		"pad_x": pad_x,
		"pad_top": pad_top,
		"pad_bottom": pad_bottom,
		"title_h": title_h,
		"row_h": row_h,
		"footer_h": footer_h,
		"title_w": title_w,
		"footer_w": footer_w,
		"close": close,
		"row_size": row_size,
		"title_size": title_size_local,
	}


func _draw_info_table(vp: Vector2, title: String, rows: Array, footer: String) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.62))
	var layout := _measure_info_table(vp, title, rows, footer)
	var panel: Rect2 = layout["panel"]
	var panel_w := panel.size.x
	var left_w: float = layout["left_w"]
	var right_w: float = layout["right_w"]
	var col_gap: float = layout["col_gap"]
	var pad_x: float = layout["pad_x"]
	var pad_top: float = layout["pad_top"]
	var pad_bottom: float = layout["pad_bottom"]
	var title_h: float = layout["title_h"]
	var row_h: float = layout["row_h"]
	var footer_h: float = layout["footer_h"]
	var title_w: float = layout["title_w"]
	var footer_w: float = layout["footer_w"]
	var close: Rect2 = layout["close"]
	var row_size: int = int(layout.get("row_size", help_row_size))
	var title_size_local: int = int(layout.get("title_size", help_title_size))
	_touch_close_rect = close
	draw_rect(panel, Color("0b1a28", 0.96), true, -1.0, true)
	draw_rect(panel, Color("8ef7ff", 0.45), false, 1.5, true)
	draw_string(
		title_font,
		Vector2(panel.position.x + (panel_w - title_w) * 0.5, panel.position.y + pad_top + title_font.get_ascent(title_size_local)),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		title_size_local,
		Color("8ef7ff")
	)
	var divider_y := panel.position.y + pad_top + title_h + 10.0 * ui_scale
	draw_line(
		Vector2(panel.position.x + pad_x, divider_y),
		Vector2(panel.end.x - pad_x, divider_y),
		Color("8ef7ff", 0.28),
		1.0
	)
	var table_w := left_w + col_gap + right_w
	var left_x := panel.position.x + (panel_w - table_w) * 0.5
	var right_x := left_x + left_w + col_gap
	var row_y := divider_y + 8.0 * ui_scale + body_font.get_ascent(row_size)
	var row_limit_y := panel.end.y - footer_h
	if close.size.x > 0.0:
		row_limit_y = close.position.y - 8.0
	for i in rows.size():
		var row: Array = rows[i]
		var left := str(row[0])
		var right := str(row[1])
		var y := row_y + i * row_h
		if y > row_limit_y:
			break
		if i % 2 == 1:
			draw_rect(
				Rect2(Vector2(panel.position.x + 10.0, y - body_font.get_ascent(row_size) - 4.0), Vector2(panel_w - 20.0, row_h - 2.0)),
				Color("123047", 0.35),
				true,
				-1.0,
				true
			)
		draw_string(body_font, Vector2(left_x, y), left, HORIZONTAL_ALIGNMENT_LEFT, -1, row_size, Color("8ef7ff"))
		draw_string(body_font, Vector2(right_x, y), right, HORIZONTAL_ALIGNMENT_LEFT, -1, row_size, Color("e8f7ff"))
	if close.size.x > 0.0:
		_draw_overlay_button(close, "CLOSE")
	else:
		var footer_y := panel.end.y - pad_bottom + body_font.get_ascent(hint_size) - footer_h + 8.0 * ui_scale
		draw_string(
			body_font,
			Vector2(panel.position.x + (panel_w - footer_w) * 0.5, footer_y),
			footer,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			hint_size,
			Color("6a8799")
		)


func _draw_overlay_button(rect: Rect2, label: String) -> void:
	draw_rect(rect, Color("0b1a28", 0.96), true, -1.0, true)
	draw_rect(rect, Color("8ef7ff", 0.7), false, 2.0, true)
	var size := 16
	var text_w := body_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var baseline := rect.position.y + (rect.size.y + body_font.get_ascent(size) - body_font.get_descent(size)) * 0.5
	draw_string(
		body_font,
		Vector2(rect.position.x + (rect.size.x - text_w) * 0.5, baseline),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		size,
		Color("e8f7ff")
	)


func _sync_touch_overlay_rects() -> void:
	_touch_close_rect = Rect2()
	_touch_restart_rect = Rect2()
	if title_font == null or body_font == null:
		return
	var vp := get_viewport_rect().size
	if help_open or score_open:
		var title := "CONTROLS" if help_open else "SCORE"
		var rows: Array = _help_rows() if help_open else SCORE_HELP_ROWS
		var layout := _measure_info_table(vp, title, rows, "")
		_touch_close_rect = layout["close"]
	elif PlayDevice.is_touch_primary() and game_over and not _highscores_open():
		var center := _board_center()
		_touch_restart_rect = Rect2(center.x - 80.0, center.y + 24.0, 160.0, 48.0)


func _draw_overlays(vp: Vector2) -> void:
	_sync_touch_overlay_rects()
	if score_open:
		_draw_info_table(vp, "SCORE", SCORE_HELP_ROWS, "S or Esc to close")
		return
	if help_open:
		_draw_info_table(vp, "CONTROLS", _help_rows(), "H or Esc to close")
		return
	var center := _board_center()
	if paused:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.55))
		_draw_centered_label(center, "PAUSED", title_font, 42, Color("8ef7ff"), -24.0)
		var paused_hint := "Tap anywhere to resume" if PlayDevice.is_touch_primary() else "Any key resume    Esc / Q quit"
		_draw_centered_label(center, paused_hint, body_font, 20, Color("e8f7ff"), 24.0)
	if game_over:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.62))
		var highscore_ui: bool = highscores != null and highscores.is_showing_overlay()
		_draw_centered_label(
			center,
			"STACK FULL",
			title_font,
			42,
			Color("fb7185"),
			-120.0 if highscore_ui else -36.0
		)
		if not highscore_ui:
			if _touch_restart_rect.size.x > 0.0:
				_draw_overlay_button(_touch_restart_rect, "RESTART")
			else:
				_draw_centered_label(center, "R / Space / Enter restart    Esc / Q quit", body_font, 20, Color("e8f7ff"), 18.0)
