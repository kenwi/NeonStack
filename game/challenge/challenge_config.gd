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
## Synchronous browser store. user:// on web is IndexedDB and can keep the pre-leave file.
const WEB_STORAGE_KEY := "neonstack.challenge"


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
	if OS.has_feature("web"):
		var raw := _web_storage_read()
		if raw == "empty":
			return {}
		if raw.begins_with("json:"):
			var parsed = JSON.parse_string(raw.substr(5))
			if typeof(parsed) == TYPE_DICTIONARY:
				return _board_from_dict(parsed)
			return {}
	var from_cfg := _load_cfg()
	if OS.has_feature("web"):
		# First visit after this store existed: keep a joined challenge, remember a leave.
		_web_storage_write("" if from_cfg.is_empty() else JSON.stringify(from_cfg))
	return from_cfg


static func save_active(data: Dictionary) -> void:
	var board := _board_from_dict(data)
	if board.is_empty():
		clear_active()
		return
	if OS.has_feature("web"):
		_web_storage_write(JSON.stringify(board))
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	cfg.set_value(CFG_SECTION, CFG_TOKEN, str(board.get("id", "")))
	cfg.set_value(CFG_SECTION, CFG_NAME, str(board.get("name", "Challenge")))
	cfg.set_value(CFG_SECTION, CFG_FAMILY, str(board.get("family", "classic")))
	cfg.set_value(CFG_SECTION, CFG_DIFFICULTY, str(board.get("difficulty", "classic")))
	cfg.set_value(CFG_SECTION, CFG_PERIOD_UNIX, int(board.get("periodUnix", 0)))
	cfg.save(CFG_PATH)


static func clear_active() -> void:
	if OS.has_feature("web"):
		_web_storage_write("")
	_clear_cfg_file()
	clear_deep_link()


static func _board_from_dict(data: Dictionary) -> Dictionary:
	var token := sanitize_token(str(data.get("id", "")))
	if token.is_empty():
		return {}
	var period := int(data.get("periodUnix", data.get("period_unix", 0)))
	return {
		"id": token,
		"name": str(data.get("name", "Challenge")),
		"family": str(data.get("family", "classic")),
		"difficulty": str(data.get("difficulty", "classic")),
		"periodUnix": period if period > 0 else 0,
	}


static func _load_cfg() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		return {}
	return _board_from_dict({
		"id": str(cfg.get_value(CFG_SECTION, CFG_TOKEN, "")),
		"name": str(cfg.get_value(CFG_SECTION, CFG_NAME, "Challenge")),
		"family": str(cfg.get_value(CFG_SECTION, CFG_FAMILY, "classic")),
		"difficulty": str(cfg.get_value(CFG_SECTION, CFG_DIFFICULTY, "classic")),
		"periodUnix": int(cfg.get_value(CFG_SECTION, CFG_PERIOD_UNIX, 0)),
	})


static func _clear_cfg_file() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK and cfg.has_section(CFG_SECTION):
		cfg.erase_section(CFG_SECTION)
		cfg.save(CFG_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG_PATH))


static func _web_storage_read() -> String:
	var result = JavaScriptBridge.eval(
		"(function(){try{var v=localStorage.getItem('%s');if(v===null)return 'missing';if(v==='')return 'empty';return 'json:'+v;}catch(e){return 'missing';}})()" % WEB_STORAGE_KEY,
		true
	)
	return str(result)


static func _web_storage_write(payload: String) -> void:
	JavaScriptBridge.eval(
		"(function(){try{localStorage.setItem('%s', decodeURIComponent('%s'));}catch(e){}})()" % [
			WEB_STORAGE_KEY,
			payload.uri_encode(),
		],
		true
	)


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
