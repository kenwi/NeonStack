extends RefCounted

## Challenge board config, persistence, and share-link helpers.

const HighscoreConfig = preload("res://game/highscore/highscore_config.gd")

const MODE_ID_PREFIX := "c_"
const TOKEN_LENGTH := 12
const MAX_NAME_LENGTH := 32
## Fallback share host when not running on web (matches production CORS origin).
const FALLBACK_GAME_BASE_URL := "https://neonstack.m0b.tech/"
const CFG_PATH := "user://challenge.cfg"
const CFG_SECTION := "active"
const CFG_TOKEN := "token"
const CFG_NAME := "name"
const CFG_FAMILY := "family"
const CFG_DIFFICULTY := "difficulty"
const CFG_PERIOD_UNIX := "period_unix"


static func score_mode_id(token: String, touch_primary: bool) -> String:
	var core := "%s%s" % [MODE_ID_PREFIX, sanitize_token(token)]
	if touch_primary:
		return "%s-mobile" % core
	return core


static func is_challenge_mode_id(mode_id: String) -> bool:
	var core := mode_id.trim_suffix("-mobile")
	return core.begins_with(MODE_ID_PREFIX)


static func token_from_mode_id(mode_id: String) -> String:
	var core := mode_id.trim_suffix("-mobile")
	if not core.begins_with(MODE_ID_PREFIX):
		return ""
	return sanitize_token(core.substr(MODE_ID_PREFIX.length()))


static func sanitize_token(raw: String) -> String:
	var t := raw.strip_edges()
	if t.begins_with(MODE_ID_PREFIX):
		t = t.substr(MODE_ID_PREFIX.length())
	t = t.trim_suffix("-mobile")
	var out := ""
	for i in t.length():
		var ch := t.substr(i, 1)
		var code := ch.unicode_at(0)
		var ok := (
			(code >= 65 and code <= 90)
			or (code >= 97 and code <= 122)
			or (code >= 48 and code <= 57)
			or ch == "_"
			or ch == "-"
		)
		if ok:
			out += ch
		if out.length() >= TOKEN_LENGTH:
			break
	return out


static func sanitize_name(raw: String) -> String:
	var t := raw.strip_edges()
	if t.length() > MAX_NAME_LENGTH:
		t = t.substr(0, MAX_NAME_LENGTH)
	var out := ""
	for i in t.length():
		var ch := t.substr(i, 1)
		if is_allowed_name_char(ch):
			out += ch
	return out.strip_edges()


static func is_allowed_name_char(ch: String) -> bool:
	var code := ch.unicode_at(0)
	if code >= 65 and code <= 90:
		return true
	if code >= 97 and code <= 122:
		return true
	if code >= 48 and code <= 57:
		return true
	# Latin-1 letters (æøå etc.) roughly À-Ö Ø-ö ø-ÿ
	if code >= 192 and code <= 214:
		return true
	if code >= 216 and code <= 246:
		return true
	if code >= 248 and code <= 255:
		return true
	return ch in [" ", "_", "-", ".", "!", "?", "'"]


static func game_base_url() -> String:
	if OS.has_feature("web"):
		var result = JavaScriptBridge.eval(
			"(function(){var p=location.pathname||'/';if(p.slice(-1)!=='/'){var i=p.lastIndexOf('/');p=i>=0?p.slice(0,i+1):'/';}return location.origin+p;})()",
			true
		)
		var url := str(result).strip_edges()
		if not url.is_empty() and url != "null":
			if not url.ends_with("/"):
				url += "/"
			return url
	return FALLBACK_GAME_BASE_URL


static func share_url(token: String) -> String:
	var id := sanitize_token(token)
	return "%s?c=%s" % [game_base_url(), id.uri_encode()]


static func api_base() -> String:
	return HighscoreConfig.API_BASE_URL.trim_suffix("/")


static func load_active() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		return {}
	var token := sanitize_token(str(cfg.get_value(CFG_SECTION, CFG_TOKEN, "")))
	if token.is_empty():
		return {}
	var family := str(cfg.get_value(CFG_SECTION, CFG_FAMILY, "classic"))
	var difficulty := str(cfg.get_value(CFG_SECTION, CFG_DIFFICULTY, "classic"))
	var period := int(cfg.get_value(CFG_SECTION, CFG_PERIOD_UNIX, 0))
	return {
		"id": token,
		"name": str(cfg.get_value(CFG_SECTION, CFG_NAME, "Challenge")),
		"family": family,
		"difficulty": difficulty,
		"periodUnix": period if period > 0 else 0,
	}


static func save_active(data: Dictionary) -> void:
	var token := sanitize_token(str(data.get("id", "")))
	if token.is_empty():
		clear_active()
		return
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	cfg.set_value(CFG_SECTION, CFG_TOKEN, token)
	cfg.set_value(CFG_SECTION, CFG_NAME, str(data.get("name", "Challenge")))
	cfg.set_value(CFG_SECTION, CFG_FAMILY, str(data.get("family", "classic")))
	cfg.set_value(CFG_SECTION, CFG_DIFFICULTY, str(data.get("difficulty", "classic")))
	var period_unix := int(data.get("periodUnix", 0))
	cfg.set_value(CFG_SECTION, CFG_PERIOD_UNIX, period_unix if period_unix > 0 else 0)
	cfg.save(CFG_PATH)


static func clear_active() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	if cfg.has_section(CFG_SECTION):
		cfg.erase_section(CFG_SECTION)
	cfg.save(CFG_PATH)
	clear_deep_link()


static func parse_deep_link_token() -> String:
	if not OS.has_feature("web"):
		return ""
	var result = JavaScriptBridge.eval(
		"(function(){try{var q=new URLSearchParams(location.search);return q.get('c')||'';}catch(e){return '';}})()",
		true
	)
	return sanitize_token(str(result))


## Drop ?c= so a refresh after Leave does not join again. Other query params stay.
static func clear_deep_link() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(
		"(function(){try{var u=new URL(location.href);if(!u.searchParams.has('c'))return;u.searchParams.delete('c');history.replaceState(null,'',u.pathname+u.search+u.hash);}catch(e){}})()",
		true
	)


static func copy_text_to_clipboard(text: String) -> bool:
	if text.is_empty():
		return false
	if OS.has_feature("web"):
		var escaped := text.replace("\\", "\\\\").replace("'", "\\'")
		var js := (
			"(function(t){if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(t);return true;}try{var a=document.createElement('textarea');a.value=t;document.body.appendChild(a);a.select();document.execCommand('copy');document.body.removeChild(a);return true;}catch(e){return false;}})('%s')"
			% escaped
		)
		var ok = JavaScriptBridge.eval(js, true)
		return bool(ok)
	DisplayServer.clipboard_set(text)
	return true
