extends SceneTree

## Runs the play bot as fast as the sim allows until the run loses.
## The game level still climbs from line clears. Prints score and stats on a
## wall-clock interval (default 60 seconds). Status lines go to stderr so they
## stay visible when Godot is started with --quiet (that flag hides the engine
## version banner, and also swallows print()).
## Not referenced by the game client. The Web export excludes tools/bot.
##
## Usage:
##   godot --headless --quiet --path . --script res://tools/bot/headless_bot.gd -- \
##     --every 30 --random-weights --weight-seed 7

const GameModes = preload("res://game/mode/game_modes.gd")
const PlayDevice = preload("res://game/platform/play_device.gd")
const MAIN_SCENE := "res://game/main.tscn"
const BOT_SCRIPT := "res://tools/bot/player_bot.gd"
const DEFAULT_REPORT_SEC := 60
const LOG_DIR := "res://tools/bot/logs"

var _exit_code := 0
var _started := false
var _main: Node = null
var _difficulty := GameModes.DIFFICULTY_HARDCORE
var _seed := -1
var _report_ms := DEFAULT_REPORT_SEC * 1000
var _random_weights := false
var _weight_seed := -1
var _log_path := ""
var _log: FileAccess = null
var _run_id := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var arg := str(args[i])
		if arg == "--difficulty" and i + 1 < args.size():
			i += 1
			_difficulty = str(args[i]).strip_edges().to_lower()
		elif arg == "--seed" and i + 1 < args.size():
			i += 1
			_seed = int(str(args[i]))
		elif arg == "--every" and i + 1 < args.size():
			i += 1
			var seconds := float(str(args[i]))
			if seconds <= 0.0:
				push_error("--every must be a positive number of seconds")
				quit(1)
				return
			_report_ms = int(round(seconds * 1000.0))
		elif arg == "--random-weights":
			_random_weights = true
		elif arg == "--weight-seed" and i + 1 < args.size():
			i += 1
			_weight_seed = int(str(args[i]))
		elif arg == "--log" and i + 1 < args.size():
			i += 1
			_log_path = str(args[i]).strip_edges()
		elif arg == "--help":
			printerr(
				"headless_bot [--difficulty hardcore|classic] [--seed N] [--every SECONDS] "
				+ "[--random-weights] [--weight-seed N] [--log PATH]"
			)
			quit(0)
			return
		i += 1
	if not GameModes.is_valid_difficulty(_difficulty):
		push_error("Unknown difficulty '%s' (use hardcore or classic)" % _difficulty)
		quit(1)
		return
	if _weight_seed >= 0 and not _random_weights:
		push_error("--weight-seed requires --random-weights")
		quit(1)
		return
	PlayDevice.force_touch_primary(false)
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		push_error("Failed to load %s" % MAIN_SCENE)
		quit(1)
		return
	_main = packed.instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _started:
		return false
	if _main == null or not _main.is_node_ready():
		return false
	_started = true
	_run()
	quit(_exit_code)
	return true


func _run() -> void:
	var bot_script = load(BOT_SCRIPT)
	if bot_script == null:
		push_error("Failed to load %s" % BOT_SCRIPT)
		_exit_code = 1
		return
	var bot := Node.new()
	bot.set_script(bot_script)
	bot.name = "PlayBot"
	_main.add_child(bot)
	_main._play_bot = bot
	# Same max speed as the editor bot: one move per tick, and a full placement
	# in one tick only after gravity is already a few ticks per cell.
	_main._bot_pace_level = bot.max_pace_level()
	if _random_weights:
		if _weight_seed < 0:
			_weight_seed = int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_usec() & 0x7FFFFFFF)
			if _weight_seed < 0:
				_weight_seed = -_weight_seed
			if _weight_seed == 0:
				_weight_seed = 1
		var rng := RandomNumberGenerator.new()
		rng.seed = _weight_seed
		bot.randomize_weights(rng)

	_main.difficulty = _difficulty
	_main.game_mode = GameModes.CLASSIC
	_main.mode_select_open = false
	_main._feature_announce_open = false
	_main.paused = false
	_main.help_open = false
	_main.score_open = false
	_main.options_open = false
	_main._bot_enabled = true
	if _seed >= 0:
		_main._new_game(_seed)
	else:
		_main._new_game()
	_main.mode_select_open = false
	_main._feature_announce_open = false
	if _main.replay_recorder != null:
		_main.replay_recorder.stop()
		_main.replay_recorder.clear()
	if _main.juice != null and _main.juice.has_method("begin_silent"):
		_main.juice.begin_silent()

	if not _open_log():
		_exit_code = 1
		return

	var started_ms := Time.get_ticks_msec()
	var next_report := started_ms + _report_ms
	_emit("START", 0, bot)
	while not _main.game_over:
		bot.step(_main)
		_main._sim_tick()
		_main.sim_tick += 1
		if _main.sim_tick % 2000 == 0:
			var now := Time.get_ticks_msec()
			if now >= next_report:
				_emit("STAT", now - started_ms, bot)
				next_report = now + _report_ms
	_emit("LOST", Time.get_ticks_msec() - started_ms, bot)
	if _log != null:
		_log.close()
		_log = null


func _open_log() -> bool:
	var dir := ProjectSettings.globalize_path(LOG_DIR)
	if _log_path.is_empty():
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK and err != ERR_ALREADY_EXISTS:
			push_error("Could not create log dir %s" % dir)
			return false
		var stamp := _stamp()
		var weight_bit := "default" if not _random_weights else "w%s" % _weight_seed
		_run_id = "%s_seed%s_%s" % [stamp, int(_main.run_seed), weight_bit]
		_log_path = dir.path_join("%s.jsonl" % _run_id)
	else:
		if not _log_path.is_absolute_path():
			_log_path = ProjectSettings.globalize_path(_log_path)
		_run_id = _log_path.get_file().get_basename()
		var parent := _log_path.get_base_dir()
		var err := DirAccess.make_dir_recursive_absolute(parent)
		if err != OK and err != ERR_ALREADY_EXISTS:
			push_error("Could not create log dir %s" % parent)
			return false
	_log = FileAccess.open(_log_path, FileAccess.WRITE)
	if _log == null:
		push_error("Could not open log %s" % _log_path)
		return false
	return true


func _emit(tag: String, wall_ms: int, bot: Node) -> void:
	var weights: Dictionary = bot.weights()
	printerr(_console_line(tag, wall_ms, weights, tag == "START"))
	if tag == "START":
		printerr("")
	if _log == null:
		return
	var record := {
		"run_id": _run_id,
		"event": tag.to_lower(),
		"wall_s": snapped(float(wall_ms) / 1000.0, 0.001),
		"score": int(_main.score),
		"lines": int(_main.lines_cleared),
		"level": int(_main.level),
		"pieces": int(_main.bot_piece_serial),
		"sim_s": snapped(float(_main.elapsed_seconds), 0.001),
		"difficulty": str(_main.difficulty),
		"seed": int(_main.run_seed),
		"random_weights": _random_weights,
		"weight_seed": _weight_seed if _random_weights else -1,
		"weights": weights,
	}
	_log.store_line(JSON.stringify(record))
	_log.flush()


func _console_line(tag: String, wall_ms: int, weights: Dictionary, with_setup: bool) -> String:
	if with_setup:
		var seed_bit := "default" if not _random_weights else str(_weight_seed)
		return "START  %s  seed %s  weight_seed %s\nweights  lines=%s  holes=%s  bumpiness=%s  height=%s\nlog  %s" % [
			str(_main.difficulty),
			int(_main.run_seed),
			seed_bit,
			_weight_text(float(weights.lines)),
			_weight_text(float(weights.holes)),
			_weight_text(float(weights.bumpiness)),
			_weight_text(float(weights.height)),
			_project_relative(_log_path),
		]
	return "%s  wall %s  score %s  lines %s  level %s  pieces %s  sim %s" % [
		tag,
		_clock(wall_ms),
		_grouped(int(_main.score)),
		_grouped(int(_main.lines_cleared)),
		int(_main.level),
		int(_main.bot_piece_serial),
		_clock(int(round(float(_main.elapsed_seconds) * 1000.0))),
	]


func _project_relative(abs_path: String) -> String:
	var root := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var prefix := root + "/"
	if abs_path.begins_with(prefix):
		return abs_path.substr(prefix.length())
	return abs_path


func _weight_text(value: float) -> String:
	return "%+.4f" % value


func _stamp() -> String:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	return "%04d%02d%02dT%02d%02d%02d" % [
		int(dt.year), int(dt.month), int(dt.day),
		int(dt.hour), int(dt.minute), int(dt.second),
	]


func _clock(ms: int) -> String:
	var total := int(ms / 1000.0)
	var h := int(total / 3600.0)
	var m := int(total % 3600 / 60.0)
	var s := total % 60
	return "%02d:%02d:%02d" % [h, m, s]


func _grouped(value: int) -> String:
	var text := str(value)
	var out := ""
	var count := 0
	for i in range(text.length() - 1, -1, -1):
		if count == 3:
			out = " " + out
			count = 0
		out = text[i] + out
		count += 1
	return out
