extends Node2D

## Playlist, mute, and volume for the in-game soundtrack.
## Track order is shuffled from the current time, then shuffled again after each full pass.
## Streams load in the background. On web (Sample playback), each track is also registered
## as an AudioServer sample before play so decode hitch is not on the gameplay skip path.

const TRACK_PATHS: Array[Dictionary] = [
	{"title": "Happy on the Way We Fell", "path": "res://game/music/happy_on_the_way_we_fell.mp3"},
	{"title": "Neon Stack", "path": "res://game/music/neon_stack.mp3"},
	{"title": "Neon Tetris", "path": "res://game/music/neon_tetris.mp3"},
]
const VOLUME_STEPS := 10
const DEFAULT_STEP := 7
const STATUS_TIME := 1.8
const STATUS_FADE := 0.35

var _tracks: Array[Dictionary] = []
var _player := AudioStreamPlayer.new()
var _rng := RandomNumberGenerator.new()
var _index := 0
var _volume_step := DEFAULT_STEP
var _muted := false
var _switching := false
var _play_started_msec := 0
var _status := ""
var _status_timer := 0.0
var _font: Font
## path -> AudioStreamMP3
var _stream_cache: Dictionary = {}
## path currently requested via ResourceLoader
var _loading: Dictionary = {}
## Web: paths already passed through AudioServer.register_stream_as_sample
var _samples_registered: Dictionary = {}
## Web: paths waiting for staggered sample registration (one per frame)
var _register_queue: Array[String] = []
var _registering := false
## When set, play this playlist index as soon as its stream is ready to play.
var _pending_index := -1
var _pending_announce := false
var _load_generation := 0
var _web_samples := false


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_web_samples = OS.has_feature("web")
	_player.finished.connect(_on_finished)
	add_child(_player)
	_tracks = TRACK_PATHS.duplicate(true)
	_shuffle_tracks()
	_prefetch_all()
	_request_play(0, true)


func handle_input(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if _is_key(event, KEY_M):
		if not key.echo:
			_toggle_mute()
		return true
	if _is_key(event, KEY_N):
		if not key.echo:
			_skip()
		return true
	if _is_key(event, KEY_PAGEUP):
		_change_volume(1)
		return true
	if _is_key(event, KEY_PAGEDOWN):
		_change_volume(-1)
		return true
	return false


func _is_key(event: InputEvent, code: Key) -> bool:
	if not (event is InputEventKey and event.pressed):
		return false
	var key := event as InputEventKey
	return key.keycode == code or key.physical_keycode == code


func toggle_mute() -> void:
	_toggle_mute()


func skip_track() -> void:
	_skip()


func _toggle_mute() -> void:
	_muted = not _muted
	_apply_volume()
	if _muted:
		_show("Music muted")
	else:
		_show("Music %d%%" % (_volume_step * 10))


func _change_volume(direction: int) -> void:
	_volume_step = clampi(_volume_step + direction, 0, VOLUME_STEPS)
	_muted = false
	_apply_volume()
	_show("Music %d%%" % (_volume_step * 10))


func _skip() -> void:
	_advance()


func _advance() -> void:
	var from := _pending_index if _pending_index >= 0 else _index
	var next := from + 1
	if next < _tracks.size():
		_request_play(next, true)
		return
	var finished_path := _track_path(from)
	_shuffle_tracks()
	if _tracks.size() > 1 and _track_path(0) == finished_path:
		var swap := _rng.randi_range(1, _tracks.size() - 1)
		var first: Dictionary = _tracks[0]
		_tracks[0] = _tracks[swap]
		_tracks[swap] = first
	_request_play(0, true)


func _shuffle_tracks() -> void:
	# The web export's engine clock stays at zero, so the global shuffle repeats
	# on every refresh. Seed from the wall clock, and from the browser clock on web.
	_rng.seed = _time_seed()
	for i in range(_tracks.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		if i == j:
			continue
		var swap: Dictionary = _tracks[i]
		_tracks[i] = _tracks[j]
		_tracks[j] = swap


func _time_seed() -> int:
	var mixed := int(Time.get_unix_time_from_system() * 1_000_000.0) ^ Time.get_ticks_usec()
	if OS.has_feature("web"):
		var stamp = JavaScriptBridge.eval(
			"(Date.now() * 1000) ^ Math.floor(Math.random() * 4294967296)",
			false
		)
		if stamp != null:
			mixed ^= int(stamp)
	# Nearby seeds produce similar shuffles. Hash so each refresh diverges.
	return hash(mixed)


func _track_path(index: int) -> String:
	return str(_tracks[index]["path"])


func _track_title(index: int) -> String:
	return str(_tracks[index]["title"])


func _is_play_ready(path: String) -> bool:
	if not _stream_cache.has(path):
		return false
	if _web_samples and not _samples_registered.has(path):
		return false
	return true


func _prefetch_all() -> void:
	for track in _tracks:
		_ensure_loading(str(track["path"]))


func _request_play(index: int, announce: bool) -> void:
	if index < 0 or index >= _tracks.size():
		return
	_pending_index = index
	_pending_announce = announce
	var path := _track_path(index)
	if _is_play_ready(path):
		_commit_play(index, announce)
		return
	if announce:
		_show("Loading: %s" % _track_title(index))
	if _stream_cache.has(path):
		_enqueue_sample_register(path)
	else:
		_ensure_loading(path)


func _ensure_loading(path: String) -> void:
	if path.is_empty() or _stream_cache.has(path) or _loading.has(path):
		return
	_loading[path] = true
	var err := ResourceLoader.load_threaded_request(path, "AudioStreamMP3", false)
	if err != OK:
		# Request failed (already in progress, etc). Fall back without blocking this frame.
		_loading.erase(path)
		_load_generation += 1
		var gen := _load_generation
		_load_stream_deferred(path, gen)


func _load_stream_deferred(path: String, gen: int) -> void:
	await get_tree().process_frame
	if gen != _load_generation:
		return
	if _stream_cache.has(path):
		_on_stream_cached(path)
		return
	# Last resort on platforms where threaded load cannot start. Still yield a frame
	# so the current input / physics step finishes before the hitch.
	var stream := ResourceLoader.load(path, "AudioStreamMP3", ResourceLoader.CACHE_MODE_REUSE)
	if stream is AudioStreamMP3:
		_stream_cache[path] = stream
		_on_stream_cached(path)
	else:
		push_warning("Soundtrack failed to load: %s" % path)
		if _pending_index >= 0 and _track_path(_pending_index) == path:
			_pending_index = -1


func _poll_loads() -> void:
	if _loading.is_empty():
		return
	var finished: Array[String] = []
	for path in _loading.keys():
		var status := ResourceLoader.load_threaded_get_status(str(path))
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		finished.append(str(path))
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			push_warning("Soundtrack failed to load: %s" % path)
			if _pending_index >= 0 and _track_path(_pending_index) == str(path):
				_pending_index = -1
			continue
		var stream := ResourceLoader.load_threaded_get(str(path))
		if stream is AudioStreamMP3:
			_stream_cache[str(path)] = stream
			_on_stream_cached(str(path))
		else:
			push_warning("Soundtrack has unexpected type: %s" % path)
	for path in finished:
		_loading.erase(path)


func _on_stream_cached(path: String) -> void:
	if _web_samples and not _samples_registered.has(path):
		_enqueue_sample_register(path)
		return
	_try_commit_pending(path)


func _enqueue_sample_register(path: String) -> void:
	if not _web_samples:
		_try_commit_pending(path)
		return
	if _samples_registered.has(path):
		_try_commit_pending(path)
		return
	if path in _register_queue:
		return
	_register_queue.append(path)


func _poll_sample_register() -> void:
	if not _web_samples or _registering or _register_queue.is_empty():
		return
	var path: String = str(_register_queue.pop_front())
	if _samples_registered.has(path):
		_try_commit_pending(path)
		return
	if not _stream_cache.has(path):
		return
	_registering = true
	# Prefer pending track: keep its Loading toast alive across the decode hitch.
	if _pending_index >= 0 and _track_path(_pending_index) == path and _pending_announce:
		_show("Loading: %s" % _track_title(_pending_index))
	var stream: AudioStreamMP3 = _stream_cache[path] as AudioStreamMP3
	AudioServer.register_stream_as_sample(stream)
	_samples_registered[path] = true
	_registering = false
	_try_commit_pending(path)


func _try_commit_pending(path: String) -> void:
	if _pending_index < 0:
		return
	if _track_path(_pending_index) != path:
		return
	if not _is_play_ready(path):
		return
	var index := _pending_index
	var announce := _pending_announce
	_commit_play(index, announce)


func _commit_play(index: int, announce: bool) -> void:
	var path := _track_path(index)
	if not _is_play_ready(path):
		# Keep pending; registration / load will retry commit.
		_pending_index = index
		_pending_announce = announce
		if announce:
			_show("Loading: %s" % _track_title(index))
		if _stream_cache.has(path):
			_enqueue_sample_register(path)
		else:
			_ensure_loading(path)
		return
	_pending_index = -1
	_index = index
	var stream: AudioStreamMP3 = _stream_cache[path]
	stream.loop = false
	_switching = true
	if _player.playing:
		_player.stop()
	_switching = false
	_player.stream = stream
	_apply_volume()
	_play_started_msec = Time.get_ticks_msec()
	_player.play()
	if announce:
		_show("Now playing: %s" % _track_title(index))


func _on_finished() -> void:
	if _switching:
		return
	# A failed stream can end on the same frame it starts. Don't spin the playlist.
	if Time.get_ticks_msec() - _play_started_msec < 400:
		push_warning("Soundtrack ended immediately: %s" % _track_title(_index))
		return
	_advance()


func _apply_volume() -> void:
	if _muted or _volume_step <= 0:
		_player.volume_db = -80.0
	else:
		_player.volume_db = linear_to_db(float(_volume_step) / float(VOLUME_STEPS))


func _toast_bottom_inset() -> float:
	var parent_node := get_parent()
	if parent_node == null:
		return 18.0
	var touch := parent_node.get_node_or_null("TouchControls")
	if touch != null and touch.has_method("toast_bottom_inset"):
		return float(touch.toast_bottom_inset())
	return 18.0


func show_status(text: String) -> void:
	_show(text)


func _show(text: String) -> void:
	_status = text
	_status_timer = STATUS_TIME
	queue_redraw()


func _process(delta: float) -> void:
	_poll_loads()
	# Prefer registering the pending track ahead of background prefetch work.
	if _web_samples and _pending_index >= 0:
		var pending_path := _track_path(_pending_index)
		if (
			_stream_cache.has(pending_path)
			and not _samples_registered.has(pending_path)
			and pending_path in _register_queue
			and _register_queue.size() > 1
			and _register_queue[0] != pending_path
		):
			_register_queue.erase(pending_path)
			_register_queue.push_front(pending_path)
		if _pending_announce and not _is_play_ready(pending_path):
			# Keep Loading visible across multi-second sample decode.
			_show("Loading: %s" % _track_title(_pending_index))
	_poll_sample_register()
	if _status_timer <= 0.0:
		return
	_status_timer = maxf(0.0, _status_timer - delta)
	queue_redraw()


func _draw() -> void:
	if _font == null or _status_timer <= 0.0 or _status == "":
		return
	var alpha := 1.0
	if _status_timer < STATUS_FADE:
		alpha = clampf(_status_timer / STATUS_FADE, 0.0, 1.0)
	var vp := get_viewport_rect().size
	var font_size := clampi(int(round(vp.y / 42.0)), 16, 26)
	var text_size := _font.get_string_size(_status, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pad_x := 16.0
	var pad_y := 8.0
	var box_size := Vector2(text_size.x + pad_x * 2.0, text_size.y + pad_y * 2.0)
	var box := Rect2(Vector2((vp.x - box_size.x) * 0.5, vp.y - box_size.y - _toast_bottom_inset()), box_size)
	draw_rect(box, Color("0b1a28", 0.92 * alpha), true, -1.0, true)
	draw_rect(box, Color("8ef7ff", 0.45 * alpha), false, 1.5, true)
	var baseline := box.position.y + pad_y + _font.get_ascent(font_size)
	draw_string(
		_font,
		Vector2(box.position.x + pad_x, baseline),
		_status,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color("e8f7ff", alpha)
	)
