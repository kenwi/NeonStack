extends RefCounted

## Global UI / backdrop palettes. Piece colors stay fixed for readability.

const CONFIG_PATH := "user://theme.cfg"
const CONFIG_SECTION := "theme"
const CONFIG_KEY := "id"

enum Id { CYAN, PINK, MATRIX, GRAY, VIOLET, TOXIC, AMBER }
const COUNT := 7

const LABELS := {
	Id.CYAN: "Cyan",
	Id.PINK: "Pink neon",
	Id.MATRIX: "Matrix",
	Id.GRAY: "Gray",
	Id.VIOLET: "Violet",
	Id.TOXIC: "Toxic",
	Id.AMBER: "Amber",
}

const PALETTES := {
	Id.CYAN: {
		"bg_deep": Color("071018"),
		"bg_panel": Color("0b1a28"),
		"bg_elevated": Color("123047"),
		"accent": Color("8ef7ff"),
		"accent_hot": Color("1ec8ff"),
		"text": Color("e8f7ff"),
		"muted": Color("6a8799"),
		"gold": Color("ffd166"),
		"danger": Color("fb7185"),
		"lines_dim": Color("123047"),
		"lines_bright": Color("1e4a6e"),
		"sky_top": Color("050b12"),
		"sky_horizon": Color("071018"),
		"star_cool": Color("1ec8ff"),
		"star_hot": Color("8ef7ff"),
		"star_core": Color("e8f7ff"),
	},
	Id.PINK: {
		"bg_deep": Color("12010f"),
		"bg_panel": Color("1a0b18"),
		"bg_elevated": Color("3a1530"),
		"accent": Color("ff7ad9"),
		"accent_hot": Color("ff2ebd"),
		"text": Color("fce7f3"),
		"muted": Color("a78ba0"),
		"gold": Color("ffd166"),
		"danger": Color("fb7185"),
		"lines_dim": Color("3a1530"),
		"lines_bright": Color("6b2a55"),
		"sky_top": Color("0a0108"),
		"sky_horizon": Color("12010f"),
		"star_cool": Color("ff2ebd"),
		"star_hot": Color("ff7ad9"),
		"star_core": Color("fce7f3"),
	},
	Id.MATRIX: {
		"bg_deep": Color("020a02"),
		"bg_panel": Color("051405"),
		"bg_elevated": Color("0a2a0a"),
		"accent": Color("39ff14"),
		"accent_hot": Color("00ff66"),
		"text": Color("d1fae5"),
		"muted": Color("4d7c5a"),
		"gold": Color("fbbf24"),
		"danger": Color("ef4444"),
		"lines_dim": Color("0a2a0a"),
		"lines_bright": Color("14532d"),
		"sky_top": Color("010501"),
		"sky_horizon": Color("020a02"),
		"star_cool": Color("00ff66"),
		"star_hot": Color("39ff14"),
		"star_core": Color("d1fae5"),
	},
	Id.GRAY: {
		"bg_deep": Color("0a0a0a"),
		"bg_panel": Color("141414"),
		"bg_elevated": Color("2a2a2a"),
		"accent": Color("e5e5e5"),
		"accent_hot": Color("a3a3a3"),
		"text": Color("f5f5f5"),
		"muted": Color("737373"),
		"gold": Color("fbbf24"),
		"danger": Color("f87171"),
		"lines_dim": Color("2a2a2a"),
		"lines_bright": Color("525252"),
		"sky_top": Color("050505"),
		"sky_horizon": Color("0a0a0a"),
		"star_cool": Color("a3a3a3"),
		"star_hot": Color("e5e5e5"),
		"star_core": Color("f5f5f5"),
	},
	Id.VIOLET: {
		"bg_deep": Color("0a0614"),
		"bg_panel": Color("140c22"),
		"bg_elevated": Color("2a1848"),
		"accent": Color("c4b5fd"),
		"accent_hot": Color("8b5cf6"),
		"text": Color("ede9fe"),
		"muted": Color("8b7aa8"),
		"gold": Color("f0abfc"),
		"danger": Color("f472b6"),
		"lines_dim": Color("2a1848"),
		"lines_bright": Color("4c1d95"),
		"sky_top": Color("05030c"),
		"sky_horizon": Color("0a0614"),
		"star_cool": Color("8b5cf6"),
		"star_hot": Color("c4b5fd"),
		"star_core": Color("ede9fe"),
	},
	Id.TOXIC: {
		"bg_deep": Color("050700"),
		"bg_panel": Color("0c1002"),
		"bg_elevated": Color("1a2408"),
		"accent": Color("ccff00"),
		"accent_hot": Color("a3e635"),
		"text": Color("f7fee7"),
		"muted": Color("6b7c3a"),
		"gold": Color("facc15"),
		"danger": Color("f97316"),
		"lines_dim": Color("1a2408"),
		"lines_bright": Color("3f5c12"),
		"sky_top": Color("020300"),
		"sky_horizon": Color("050700"),
		"star_cool": Color("a3e635"),
		"star_hot": Color("ccff00"),
		"star_core": Color("f7fee7"),
	},
	Id.AMBER: {
		"bg_deep": Color("0c0702"),
		"bg_panel": Color("16100a"),
		"bg_elevated": Color("2a1c0e"),
		"accent": Color("ffb020"),
		"accent_hot": Color("f59e0b"),
		"text": Color("fff7ed"),
		"muted": Color("9a7b52"),
		"gold": Color("fde68a"),
		"danger": Color("ef4444"),
		"lines_dim": Color("2a1c0e"),
		"lines_bright": Color("5c3d18"),
		"sky_top": Color("070401"),
		"sky_horizon": Color("0c0702"),
		"star_cool": Color("f59e0b"),
		"star_hot": Color("ffb020"),
		"star_core": Color("fff7ed"),
	},
}

static var _id: Id = Id.CYAN
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	var raw: int = int(cfg.get_value(CONFIG_SECTION, CONFIG_KEY, int(Id.CYAN)))
	_id = clampi(raw, 0, COUNT - 1) as Id


static func current_id() -> Id:
	ensure_loaded()
	return _id


static func label() -> String:
	ensure_loaded()
	return str(LABELS.get(_id, "Cyan"))


static func short_label() -> String:
	ensure_loaded()
	match _id:
		Id.PINK:
			return "PINK"
		Id.MATRIX:
			return "MTX"
		Id.GRAY:
			return "GRAY"
		Id.VIOLET:
			return "VIO"
		Id.TOXIC:
			return "TOX"
		Id.AMBER:
			return "AMBR"
		_:
			return "CYAN"


static func cycle() -> String:
	ensure_loaded()
	_id = ((int(_id) + 1) % COUNT) as Id
	_save()
	return label()


static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value(CONFIG_SECTION, CONFIG_KEY, int(_id))
	cfg.save(CONFIG_PATH)


static func _pal() -> Dictionary:
	ensure_loaded()
	return PALETTES[_id]


static func _alpha(base: Color, a: float) -> Color:
	var out := base
	out.a = a
	return out


static func bg_deep(a: float = 1.0) -> Color:
	return _alpha((_pal()["bg_deep"] as Color), a)


static func bg_panel(a: float = 1.0) -> Color:
	return _alpha((_pal()["bg_panel"] as Color), a)


static func bg_elevated(a: float = 1.0) -> Color:
	return _alpha((_pal()["bg_elevated"] as Color), a)


static func accent(a: float = 1.0) -> Color:
	return _alpha((_pal()["accent"] as Color), a)


static func accent_hot(a: float = 1.0) -> Color:
	return _alpha((_pal()["accent_hot"] as Color), a)


static func text(a: float = 1.0) -> Color:
	return _alpha((_pal()["text"] as Color), a)


static func muted(a: float = 1.0) -> Color:
	return _alpha((_pal()["muted"] as Color), a)


static func gold(a: float = 1.0) -> Color:
	return _alpha((_pal()["gold"] as Color), a)


static func danger(a: float = 1.0) -> Color:
	return _alpha((_pal()["danger"] as Color), a)


static func lines_dim() -> Color:
	return (_pal()["lines_dim"] as Color)


static func lines_bright() -> Color:
	return (_pal()["lines_bright"] as Color)


static func sky_top() -> Color:
	return (_pal()["sky_top"] as Color)


static func sky_horizon() -> Color:
	return (_pal()["sky_horizon"] as Color)


static func star_cool() -> Color:
	return (_pal()["star_cool"] as Color)


static func star_hot() -> Color:
	return (_pal()["star_hot"] as Color)


static func star_core() -> Color:
	return (_pal()["star_core"] as Color)
