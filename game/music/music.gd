extends Node2D

## Playlist, mute, and volume for the in-game soundtrack.

const TRACK_STACK: AudioStreamMP3 = preload("res://game/music/neon_stack.mp3")
const TRACK_TETRIS: AudioStreamMP3 = preload("res://game/music/neon_tetris.mp3")
const VOLUME_STEPS := 10
const DEFAULT_STEP := 7
const STATUS_TIME := 1.8
const STATUS_FADE := 0.35

var _tracks: Array[Dictionary] = [
	{"title": "Neon Stack", "stream": TRACK_STACK},
	{"title": "Neon Tetris", "stream": TRACK_TETRIS},
]
var _player := AudioStreamPlayer.new()
var _index := 0
var _volume_step := DEFAULT_STEP
var _muted := false
var _switching := false
var _play_started_msec := 0
var _status := ""
var _status_timer := 0.0
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_player.finished.connect(_on_finished)
	add_child(_player)
	_play(0, true)


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
	_play((_index + 1) % _tracks.size(), true)


func _play(index: int, announce: bool) -> void:
	_index = index
	var stream := _tracks[_index]["stream"] as AudioStreamMP3
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
		_show("Now playing: %s" % str(_tracks[_index]["title"]))


func _on_finished() -> void:
	if _switching:
		return
	# A failed stream can end on the same frame it starts. Don't spin the playlist.
	if Time.get_ticks_msec() - _play_started_msec < 400:
		push_warning("Soundtrack ended immediately: %s" % str(_tracks[_index]["title"]))
		return
	_play((_index + 1) % _tracks.size(), true)


func _apply_volume() -> void:
	if _muted or _volume_step <= 0:
		_player.volume_db = -80.0
	else:
		_player.volume_db = linear_to_db(float(_volume_step) / float(VOLUME_STEPS))


func _show(text: String) -> void:
	_status = text
	_status_timer = STATUS_TIME
	queue_redraw()


func _process(delta: float) -> void:
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
	var box := Rect2(Vector2((vp.x - box_size.x) * 0.5, vp.y - box_size.y - 18.0), box_size)
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
