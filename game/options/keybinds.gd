extends RefCounted

## Customizable keyboard binds. Persisted to user:// (IndexedDB on web exports).

const PlayDevice = preload("res://game/platform/play_device.gd")

const CONFIG_PATH := "user://keybinds.cfg"
const CONFIG_SECTION := "binds"

const MOVE_LEFT := "move_left"
const MOVE_RIGHT := "move_right"
const ROTATE := "rotate"
const ROTATE_CCW := "rotate_ccw"
const SOFT_DROP := "soft_drop"
const HARD_DROP := "hard_drop"
const HOLD := "hold"
const MUTE := "mute"
const NEXT_TRACK := "next_track"
const VOL_UP := "vol_up"
const VOL_DOWN := "vol_down"
const PAUSE_MENU := "pause_menu"
const RESTART := "restart"
const HIGHSCORES := "highscores"
const HELP := "help"
const SCORE_TABLE := "score_table"
const QUIT := "quit"
const FULLSCREEN := "fullscreen"
const JUICE := "juice"
const BACKDROP := "backdrop"
const THEME := "theme"
const GREETINGS := "greetings"

## Catalog order for the Settings keybindings section.
const ACTION_ORDER: Array[String] = [
	MOVE_LEFT,
	MOVE_RIGHT,
	ROTATE,
	ROTATE_CCW,
	SOFT_DROP,
	HARD_DROP,
	HOLD,
	MUTE,
	NEXT_TRACK,
	VOL_UP,
	VOL_DOWN,
	PAUSE_MENU,
	RESTART,
	HIGHSCORES,
	HELP,
	SCORE_TABLE,
	FULLSCREEN,
	JUICE,
	BACKDROP,
	THEME,
	GREETINGS,
	QUIT,
]

const META := {
	MOVE_LEFT: {"title": "Move left", "blurb": "Hold to charge DAS, then repeat."},
	MOVE_RIGHT: {"title": "Move right", "blurb": "Hold to charge DAS, then repeat."},
	ROTATE: {"title": "Rotate", "blurb": "Rotate the active piece clockwise."},
	ROTATE_CCW: {"title": "Counter-rotate", "blurb": "Rotate the active piece counter-clockwise."},
	SOFT_DROP: {"title": "Soft drop", "blurb": "Hold to drop faster and score per cell."},
	HARD_DROP: {"title": "Hard drop", "blurb": "Lock the piece instantly."},
	HOLD: {"title": "Hold", "blurb": "Swap the active piece with hold."},
	MUTE: {"title": "Mute music", "blurb": "Toggle the soundtrack on or off."},
	NEXT_TRACK: {"title": "Next track", "blurb": "Skip to the next song."},
	VOL_UP: {"title": "Volume up", "blurb": "Raise music volume."},
	VOL_DOWN: {"title": "Volume down", "blurb": "Lower music volume."},
	PAUSE_MENU: {"title": "Mode menu", "blurb": "Open or resume from the mode menu."},
	RESTART: {"title": "Restart", "blurb": "Start a new run in the current mode."},
	HIGHSCORES: {"title": "Highscores", "blurb": "Open the leaderboard."},
	HELP: {"title": "Help", "blurb": "Toggle the controls overlay."},
	SCORE_TABLE: {"title": "Score table", "blurb": "Show how points are awarded."},
	FULLSCREEN: {"title": "Fullscreen", "blurb": "Toggle fullscreen mode."},
	JUICE: {"title": "Juice FX", "blurb": "Toggle particles and screen shake."},
	BACKDROP: {"title": "Background", "blurb": "Cycle dim lines, bright lines, or horizon."},
	THEME: {"title": "Color theme", "blurb": "Cycle the UI color palette."},
	GREETINGS: {"title": "Rank greetings", "blurb": "Toggle leaderboard climb announcements."},
	QUIT: {"title": "Quit", "blurb": "Leave the game."},
}

const DEFAULTS := {
	MOVE_LEFT: [KEY_LEFT],
	MOVE_RIGHT: [KEY_RIGHT],
	ROTATE: [KEY_UP, KEY_X],
	ROTATE_CCW: [KEY_Z],
	SOFT_DROP: [KEY_DOWN],
	HARD_DROP: [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER],
	HOLD: [KEY_C, KEY_SHIFT],
	MUTE: [KEY_M],
	NEXT_TRACK: [KEY_N],
	VOL_UP: [KEY_PAGEUP],
	VOL_DOWN: [KEY_PAGEDOWN],
	PAUSE_MENU: [KEY_ESCAPE],
	RESTART: [KEY_R],
	HIGHSCORES: [KEY_L],
	HELP: [KEY_H],
	SCORE_TABLE: [KEY_S],
	FULLSCREEN: [KEY_F, KEY_F11],
	JUICE: [KEY_J],
	BACKDROP: [KEY_B],
	THEME: [KEY_T],
	GREETINGS: [KEY_G],
	QUIT: [KEY_Q],
}

static var _binds: Dictionary = {}
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_binds = {}
	for id in ACTION_ORDER:
		_binds[id] = _copy_keys(DEFAULTS.get(id, []))
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	for id in ACTION_ORDER:
		if not cfg.has_section_key(CONFIG_SECTION, id):
			continue
		# Empty value means intentionally unbound - do not fall back to defaults.
		var raw := str(cfg.get_value(CONFIG_SECTION, id, ""))
		_binds[id] = _parse_keys(raw)


static func reset_to_defaults() -> void:
	ensure_loaded()
	for id in ACTION_ORDER:
		_binds[id] = _copy_keys(DEFAULTS.get(id, []))
	_save()


## Quit only makes sense on native desktop - web/mobile users close the tab or app.
static func quit_supported() -> bool:
	return not OS.has_feature("web") and not PlayDevice.is_touch_primary()


static func visible_action_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in ACTION_ORDER:
		if id == QUIT and not quit_supported():
			continue
		ids.append(id)
	return ids


static func entries() -> Array:
	ensure_loaded()
	var rows: Array = []
	for id in visible_action_ids():
		var meta: Dictionary = META.get(id, {})
		rows.append({
			"id": id,
			"title": str(meta.get("title", id)),
			"blurb": str(meta.get("blurb", "")),
		})
	return rows


static func keys_for(id: String) -> Array:
	ensure_loaded()
	if _binds.has(id):
		return (_binds[id] as Array).duplicate()
	return _copy_keys(DEFAULTS.get(id, []))


static func keys_label(id: String) -> String:
	var keys := keys_for(id)
	if keys.is_empty():
		return "Unbound"
	var parts: PackedStringArray = PackedStringArray()
	for code in keys:
		parts.append(_key_name(int(code)))
	return " / ".join(parts)


static func help_rows() -> Array:
	ensure_loaded()
	var rows: Array = []
	for id in visible_action_ids():
		var meta: Dictionary = META.get(id, {})
		rows.append([keys_label(id), str(meta.get("title", id))])
	return rows


static func matches_pressed(event: InputEvent, id: String) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return false
	return _event_in_action(event as InputEventKey, id)


static func matches_released(event: InputEvent, id: String) -> bool:
	if not (event is InputEventKey and not event.pressed):
		return false
	return _event_in_action(event as InputEventKey, id)


static func matches_key(event: InputEvent, id: String) -> bool:
	if not (event is InputEventKey):
		return false
	return _event_in_action(event as InputEventKey, id)


static func is_down(id: String) -> bool:
	ensure_loaded()
	for code in keys_for(id):
		var key := int(code) as Key
		if Input.is_physical_key_pressed(key) or Input.is_key_pressed(key):
			return true
	return false


static func bind_key(id: String, keycode: Key) -> void:
	ensure_loaded()
	if not ACTION_ORDER.has(id):
		return
	if keycode == KEY_NONE:
		clear_bind(id)
		return
	# Drop this key from every other action so binds stay unique.
	for other_id in ACTION_ORDER:
		if other_id == id:
			continue
		var other: Array = keys_for(other_id)
		var filtered: Array = []
		for code in other:
			if int(code) != int(keycode):
				filtered.append(int(code))
		_binds[other_id] = filtered
	_binds[id] = [int(keycode)]
	_save()


static func clear_bind(id: String) -> void:
	ensure_loaded()
	if not ACTION_ORDER.has(id):
		return
	_binds[id] = []
	_save()


static func event_keycode(event: InputEventKey) -> Key:
	if event.keycode != KEY_NONE:
		return event.keycode
	return event.physical_keycode


static func _event_in_action(key: InputEventKey, id: String) -> bool:
	ensure_loaded()
	for code in keys_for(id):
		var want := int(code)
		if int(key.keycode) == want or int(key.physical_keycode) == want:
			return true
	return false


static func _key_name(code: int) -> String:
	var key := code as Key
	match key:
		KEY_LEFT:
			return "Left"
		KEY_RIGHT:
			return "Right"
		KEY_UP:
			return "Up"
		KEY_DOWN:
			return "Down"
		KEY_ESCAPE:
			return "Esc"
		KEY_SPACE:
			return "Space"
		KEY_ENTER:
			return "Enter"
		KEY_KP_ENTER:
			return "Keypad Enter"
		KEY_SHIFT:
			return "Shift"
		KEY_PAGEUP:
			return "PgUp"
		KEY_PAGEDOWN:
			return "PgDn"
		KEY_QUOTELEFT:
			return "`"
		_:
			var named := OS.get_keycode_string(key)
			return named if not named.is_empty() else "Key %d" % code


static func _copy_keys(source) -> Array:
	var out: Array = []
	for code in source:
		out.append(int(code))
	return out


static func _parse_keys(raw: String) -> Array:
	var out: Array = []
	if raw.strip_edges().is_empty():
		return out
	for part in raw.split(",", false):
		var token := str(part).strip_edges()
		if token.is_valid_int():
			out.append(int(token))
	return out


static func _serialize_keys(keys: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for code in keys:
		parts.append(str(int(code)))
	return ",".join(parts)


static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	for id in ACTION_ORDER:
		cfg.set_value(CONFIG_SECTION, id, _serialize_keys(_binds.get(id, [])))
	cfg.save(CONFIG_PATH)
