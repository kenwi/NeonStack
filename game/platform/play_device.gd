extends RefCounted

## Session input class. Touch-primary play uses the mobile highscore board.
## Detected once so resizing a desktop window cannot change the board.

const HighscoreConfig = preload("res://game/highscore/highscore_config.gd")
const GameModes = preload("res://game/mode/game_modes.gd")

static var _checked := false
static var _touch_primary := false


static func is_touch_primary() -> bool:
	if not _checked:
		_checked = true
		_touch_primary = _detect()
	return _touch_primary


## Pin input class for headless / offline tools before any gameplay reads it.
static func force_touch_primary(touch_primary: bool) -> void:
	_checked = true
	_touch_primary = touch_primary


static func force_from_board_id(board_id: String) -> void:
	force_touch_primary(GameModes.is_mobile_board(board_id))


## Classic-difficulty board for this device. Prefer GameModes.board_id for daily/weekly/hardcore.
static func score_mode_id() -> String:
	if is_touch_primary():
		return HighscoreConfig.MODE_ID_MOBILE
	return HighscoreConfig.MODE_ID


static func score_mode_id_for(
	game_mode: String,
	unix_utc: int = -1,
	difficulty: String = GameModes.DIFFICULTY_CLASSIC
) -> String:
	if not GameModes.is_valid_family(game_mode):
		return score_mode_id()
	var diff := difficulty if GameModes.is_valid_difficulty(difficulty) else GameModes.DIFFICULTY_CLASSIC
	return GameModes.board_id(game_mode, is_touch_primary(), unix_utc, diff)


static func pointer_down_position(event: InputEvent) -> Vector2:
	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed:
			return touch_event.position
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and not mouse_event.double_click and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			return mouse_event.position
	return Vector2(INF, INF)


static func has_pointer_down(event: InputEvent) -> bool:
	return is_finite(pointer_down_position(event).x)


static func _detect() -> bool:
	# Android and iOS exports. The web build does not set this on a phone.
	if OS.has_feature("mobile"):
		return true
	if not OS.has_feature("web"):
		return false
	# Primary input is a finger. A desktop touchscreen still reports hover and a fine pointer.
	var result = JavaScriptBridge.eval(
		"window.matchMedia('(hover: none) and (pointer: coarse)').matches",
		true
	)
	return bool(result)
