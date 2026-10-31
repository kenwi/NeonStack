extends RefCounted

## Classic / daily / weekly board ids and shared UTC period seeds.

const CLASSIC := "classic"
const DAILY := "daily"
const WEEKLY := "weekly"

const FAMILIES: Array[String] = [CLASSIC, DAILY, WEEKLY]
const FAMILY_LABELS := {
	CLASSIC: "Classic",
	DAILY: "Daily",
	WEEKLY: "Weekly",
}


static func is_valid_family(game_mode: String) -> bool:
	return game_mode == CLASSIC or game_mode == DAILY or game_mode == WEEKLY


static func utc_now_unix() -> int:
	return int(Time.get_unix_time_from_system())


static func period_key(game_mode: String, unix_utc: int = -1) -> String:
	if unix_utc < 0:
		unix_utc = utc_now_unix()
	if game_mode == DAILY:
		return "daily-%s" % _format_date_utc(unix_utc)
	if game_mode == WEEKLY:
		var parts := iso_week_parts(unix_utc)
		return "weekly-%d-W%02d" % [parts.x, parts.y]
	return CLASSIC


static func board_id(game_mode: String, touch_primary: bool, unix_utc: int = -1) -> String:
	var key := period_key(game_mode, unix_utc)
	if touch_primary:
		return "%s-mobile" % key
	return key


static func period_seed(game_mode: String, unix_utc: int = -1) -> int:
	## Shared across desktop and mobile for the same UTC period.
	if game_mode != DAILY and game_mode != WEEKLY:
		return 0
	var key := period_key(game_mode, unix_utc)
	var h := hash("neonstack|%s" % key) & 0x7FFFFFFF
	return h if h != 0 else 1


static func period_label(game_mode: String, unix_utc: int = -1) -> String:
	if unix_utc < 0:
		unix_utc = utc_now_unix()
	if game_mode == DAILY:
		return _format_date_utc(unix_utc)
	if game_mode == WEEKLY:
		var parts := iso_week_parts(unix_utc)
		return "%d-W%02d" % [parts.x, parts.y]
	return ""


static func shift_period_unix(game_mode: String, unix_utc: int, delta_periods: int) -> int:
	if unix_utc < 0:
		unix_utc = utc_now_unix()
	if delta_periods == 0:
		return unix_utc
	if game_mode == DAILY:
		return unix_utc + delta_periods * 86400
	if game_mode == WEEKLY:
		return unix_utc + delta_periods * 7 * 86400
	return unix_utc


static func family_from_board_id(board_id: String) -> String:
	if board_id.begins_with("daily"):
		return DAILY
	if board_id.begins_with("weekly"):
		return WEEKLY
	return CLASSIC


static func is_mobile_board(board_id: String) -> bool:
	return board_id.ends_with("-mobile")


static func period_unix_from_board_id(board_id: String) -> int:
	var core := board_id.trim_suffix("-mobile")
	var family := family_from_board_id(core)
	if family == DAILY and core.length() > 6:
		var date := core.substr(6) # after "daily-"
		var parts := date.split("-")
		if parts.size() == 3:
			return int(Time.get_unix_time_from_datetime_dict({
				"year": int(parts[0]),
				"month": int(parts[1]),
				"day": int(parts[2]),
				"hour": 12,
				"minute": 0,
				"second": 0,
			}))
	if family == WEEKLY and core.length() > 7:
		# weekly-YYYY-Www
		var rest := core.substr(7)
		var bits := rest.split("-W")
		if bits.size() == 2:
			return unix_from_iso_week(int(bits[0]), int(bits[1]))
	return utc_now_unix()


static func unix_from_iso_week(year: int, week: int) -> int:
	# Jan 4 is always in ISO week 1; back up to that week's Monday.
	var jan4 := int(Time.get_unix_time_from_datetime_dict({
		"year": year,
		"month": 1,
		"day": 4,
		"hour": 12,
		"minute": 0,
		"second": 0,
	}))
	var d := Time.get_datetime_dict_from_unix_time(jan4)
	var godot_wd: int = int(d.weekday)
	var iso_wd := 7 if godot_wd == 0 else godot_wd
	var monday_week1 := jan4 - (iso_wd - 1) * 86400
	return monday_week1 + (maxi(1, week) - 1) * 7 * 86400


static func board_title(board_id: String) -> String:
	var family := family_from_board_id(board_id)
	var mobile := is_mobile_board(board_id)
	if family == CLASSIC:
		return "MOBILE HIGHSCORES" if mobile else "HIGHSCORES"
	var label := str(FAMILY_LABELS.get(family, family)).to_upper()
	if mobile:
		return "%s MOBILE HIGHSCORES" % label
	return "%s HIGHSCORES" % label


static func hint_for_family(game_mode: String) -> String:
	if game_mode == DAILY:
		return "Same piece sequence for everyone today (UTC). New seed tomorrow."
	if game_mode == WEEKLY:
		return "Same piece sequence all week (UTC). New seed every Monday."
	return "Random seed each run. Compete on the classic board."


## ISO-8601 week year and week number (Monday start). Returns Vector2i(year, week).
static func iso_week_parts(unix_utc: int) -> Vector2i:
	var d := Time.get_datetime_dict_from_unix_time(unix_utc)
	var year: int = int(d.year)
	var month: int = int(d.month)
	var day: int = int(d.day)
	var godot_wd: int = int(d.weekday) # 0 = Sunday .. 6 = Saturday
	var iso_wd := 7 if godot_wd == 0 else godot_wd
	var ordinal := _day_of_year(year, month, day)
	var week := int(floor(float(ordinal - iso_wd + 10) / 7.0))
	if week < 1:
		var prev := year - 1
		return Vector2i(prev, _iso_weeks_in_year(prev))
	var weeks_this := _iso_weeks_in_year(year)
	if week > weeks_this:
		return Vector2i(year + 1, 1)
	return Vector2i(year, week)


static func _format_date_utc(unix_utc: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(unix_utc)
	return "%04d-%02d-%02d" % [int(d.year), int(d.month), int(d.day)]


static func _is_leap(year: int) -> bool:
	return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)


static func _day_of_year(year: int, month: int, day: int) -> int:
	var days := [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if _is_leap(year):
		days[2] = 29
	var n := day
	for m in range(1, month):
		n += days[m]
	return n


static func _iso_weeks_in_year(year: int) -> int:
	# Dec 28 is always in the last ISO week of the year.
	var unix := int(Time.get_unix_time_from_datetime_dict({
		"year": year,
		"month": 12,
		"day": 28,
		"hour": 12,
		"minute": 0,
		"second": 0,
	}))
	var d := Time.get_datetime_dict_from_unix_time(unix)
	var godot_wd: int = int(d.weekday)
	var iso_wd := 7 if godot_wd == 0 else godot_wd
	var ordinal := _day_of_year(year, 12, 28)
	return int(floor(float(ordinal - iso_wd + 10) / 7.0))
