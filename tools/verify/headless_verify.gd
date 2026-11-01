extends SceneTree

## Server-side / ops headless highscore verifier.
## Not referenced by the game client; excluded from the web export.
##
## Usage:
##   godot --headless --path . --script res://tools/verify/headless_verify.gd -- \
##     --checksum <hex> [--highscores PATH] [--replays PATH]
##   godot --headless --path . --script res://tools/verify/headless_verify.gd -- \
##     --mode <modeId> --rank <n> [--highscores PATH] [--replays PATH]
##   godot --headless --path . --script res://tools/verify/headless_verify.gd -- \
##     --all [--mode <modeId>] [--replays-only] [--highscores PATH] [--replays PATH]
##
## Missing replay files: skipped (and counted) by default. --replays-only quietly
## filters to entries that have a replay and never reports skip.
## --all without --mode verifies every board in highscores.json.

const PlayDevice = preload("res://game/platform/play_device.gd")
const HighscoreChecksum = preload("res://game/highscore/highscore_checksum.gd")
const ReplayFormat = preload("res://game/replay/replay_format.gd")

const ELAPSED_TOLERANCE := 0.02
const MAIN_SCENE := "res://game/main.tscn"

var _exit_code := 1
var _main: Node = null
var _replays_dir := ""
var _replays_only := false
var _jobs: Array = []
var _job_index := 0
var _pass_count := 0
var _fail_count := 0
var _skip_count := 0
var _phase := 0
var _quit_after_frames := -1


func _initialize() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	if args.has("error"):
		_fail_fatal(str(args["error"]))
		return

	var highscores_path := str(args["highscores"])
	_replays_dir = str(args["replays"])
	_replays_only = bool(args.get("replays_only", false))
	var checksum_arg := str(args.get("checksum", "")).strip_edges()
	var mode_arg := str(args.get("mode", "")).strip_edges()
	var rank_arg := int(args.get("rank", 0))
	var verify_all: bool = bool(args.get("all", false))

	if verify_all:
		if mode_arg.is_empty():
			_jobs = _jobs_for_all_modes(highscores_path)
			if _jobs.is_empty():
				_fail_fatal("No highscore entries in %s" % highscores_path)
				return
		else:
			_jobs = _jobs_for_mode(highscores_path, mode_arg)
			if _jobs.is_empty():
				_fail_fatal("No highscore entries for mode=%s in %s" % [mode_arg, highscores_path])
				return
	elif not checksum_arg.is_empty():
		var found := _find_entry_by_checksum(highscores_path, checksum_arg, mode_arg)
		if found.is_empty():
			if mode_arg.is_empty():
				_fail_fatal("No highscore entry for checksum %s in %s" % [checksum_arg.to_lower(), highscores_path])
			else:
				_fail_fatal(
					"No highscore entry for checksum %s on mode %s in %s"
					% [checksum_arg.to_lower(), mode_arg, highscores_path]
				)
			return
		_jobs = [found]
	else:
		var found_rank := _find_entry_by_rank(highscores_path, mode_arg, rank_arg)
		if found_rank.is_empty():
			_fail_fatal(
				"No highscore at mode=%s rank=%s in %s"
				% [mode_arg, rank_arg, highscores_path]
			)
			return
		_jobs = [found_rank]

	if _replays_only:
		# Quietly drop entries with no replay file; do not count or print skips.
		_jobs = _filter_jobs_with_replays(_jobs, false)
		if _jobs.is_empty():
			_fail_fatal("No entries with replay files to verify")
			return

	var first_mode := str((_jobs[0] as Dictionary).get("modeId", mode_arg))
	PlayDevice.force_from_board_id(first_mode)

	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail_fatal("Failed to load %s" % MAIN_SCENE)
		return
	_main = packed.instantiate()
	root.add_child(_main)
	_phase = 1


func _process(_delta: float) -> bool:
	if _quit_after_frames >= 0:
		_quit_after_frames -= 1
		if _quit_after_frames < 0:
			quit(_exit_code)
		return false
	if _phase != 1:
		return false
	if _main == null or not _main.is_node_ready():
		return false
	_phase = 2
	_run_all_jobs()
	return false


func _run_all_jobs() -> void:
	print("VERIFY jobs=%s" % _jobs.size())
	for i in _jobs.size():
		_job_index = i
		var job: Dictionary = _jobs[i]
		_verify_job(job)
	var total := _pass_count + _fail_count
	if not _replays_only and _skip_count > 0:
		print(
			"SUMMARY pass=%s fail=%s skip=%s verified=%s"
			% [_pass_count, _fail_count, _skip_count, total]
		)
	else:
		print(
			"SUMMARY pass=%s fail=%s total=%s"
			% [_pass_count, _fail_count, total]
		)
	if _fail_count == 0 and _pass_count > 0:
		_finish(0)
	else:
		_finish(1)


func _verify_job(job: Dictionary) -> void:
	var mode_id := str(job.get("modeId", ""))
	var rank := int(job.get("rank", 0))
	var entry: Dictionary = job.get("entry", {})
	var checksum := str(entry.get("Checksum", entry.get("checksum", ""))).strip_edges().to_lower()
	var player_name := str(entry.get("PlayerName", entry.get("playerName", "")))
	var name_san := HighscoreChecksum.sanitize_player_name(player_name)
	var rank_bit := (" rank=#%s" % rank) if rank > 0 else ""
	var label := "checksum=%s mode=%s%s player=%s" % [checksum, mode_id, rank_bit, name_san]

	if checksum.is_empty():
		_record_fail("%s | empty checksum" % label)
		return

	var replay_path := _replay_path(_replays_dir, checksum)
	var replay_text := _read_text(replay_path)
	if replay_text.is_empty():
		# Without --replays-only, missing files are skips (not fails).
		_record_skip("%s | no replay" % label)
		return

	var parsed: Variant = JSON.parse_string(replay_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_record_fail("%s | replay JSON is not an object" % label)
		return
	var replay_data: Dictionary = parsed
	if not ReplayFormat.is_valid(replay_data):
		_record_fail("%s | replay schema invalid" % label)
		return

	PlayDevice.force_from_board_id(mode_id)
	_main.configure_run_from_board_id(mode_id)
	if not _main.start_replay_from_data(replay_data):
		_record_fail("%s | failed to start replay" % label)
		return
	if not _main.fast_forward_replay_until_done():
		_record_fail(
			"%s | replay did not reach game over (sim_tick=%s score=%s)"
			% [label, _main.sim_tick, _main.score]
		)
		return

	var expected_score := int(entry.get("FinalScore", entry.get("finalScore", -1)))
	var expected_lines := int(entry.get("LinesCleared", entry.get("linesCleared", -1)))
	var expected_level := int(entry.get("Level", entry.get("level", -1)))
	var expected_elapsed := float(entry.get("ElapsedSeconds", entry.get("elapsedSeconds", -1.0)))
	var stored_checksum := str(entry.get("Checksum", entry.get("checksum", ""))).strip_edges()

	var sim_score := int(_main.score)
	var sim_lines := int(_main.lines_cleared)
	var sim_level := int(_main.level)
	var sim_elapsed := float(_main.elapsed_seconds)

	var mode_san := HighscoreChecksum.sanitize_mode_id(mode_id)
	var recomputed := HighscoreChecksum.compute(
		mode_san,
		name_san,
		expected_score,
		expected_lines,
		expected_level,
		expected_elapsed
	)

	var score_ok := sim_score == expected_score
	var lines_ok := sim_lines == expected_lines
	var level_ok := sim_level == expected_level
	var elapsed_ok := absf(sim_elapsed - expected_elapsed) <= ELAPSED_TOLERANCE
	var checksum_ok := (
		recomputed.to_lower() == stored_checksum.to_lower()
		and recomputed.to_lower() == checksum
	)
	if score_ok and lines_ok and level_ok and elapsed_ok and checksum_ok:
		_pass_count += 1
		print(
			"%s %s score=%s lines=%s level=%s elapsed=%.3f"
			% [_ansi_pass(), label, sim_score, sim_lines, sim_level, sim_elapsed]
		)
		return

	var rows: Array = [
		["score", str(sim_score), str(expected_score), not score_ok],
		["lines", str(sim_lines), str(expected_lines), not lines_ok],
		["level", str(sim_level), str(expected_level), not level_ok],
		["elapsed", "%.3f" % sim_elapsed, "%.3f" % expected_elapsed, not elapsed_ok],
	]
	if not checksum_ok:
		rows.append(["checksum", recomputed, stored_checksum, true])
	_record_fail_table(label, rows)


func _ansi_enabled() -> bool:
	return OS.get_environment("NO_COLOR").is_empty()


func _ansi_pass() -> String:
	if not _ansi_enabled():
		return "PASS"
	return "\u001b[32mPASS\u001b[0m"


func _ansi_fail() -> String:
	if not _ansi_enabled():
		return "FAIL"
	return "\u001b[31mFAIL\u001b[0m"


func _record_fail(message: String) -> void:
	_fail_count += 1
	printerr("%s %s" % [_ansi_fail(), message])


func _record_fail_table(label: String, rows: Array) -> void:
	_fail_count += 1
	printerr("%s %s" % [_ansi_fail(), label])
	printerr("  %-10s %14s %14s" % ["field", "simulated", "expected"])
	for row in rows:
		var field := str(row[0])
		var simulated := str(row[1])
		var expected := str(row[2])
		var mismatched: bool = bool(row[3])
		var marker := " *" if mismatched else "  "
		# Keep long checksums readable on their own line pair.
		if field == "checksum":
			printerr("  %-10s%s" % [field, marker])
			printerr("    simulated %s" % simulated)
			printerr("    expected  %s" % expected)
		else:
			printerr("  %-10s%s %14s %14s" % [field, marker, simulated, expected])


func _parse_args(argv: PackedStringArray) -> Dictionary:
	var checksum := ""
	var mode := ""
	var rank := 0
	var verify_all := false
	var replays_only := false
	var project_root := ProjectSettings.globalize_path("res://").rstrip("/")
	var highscores := project_root.path_join("server/data/highscores.json")
	var replays := project_root.path_join("server/data/replays")
	var i := 0
	while i < argv.size():
		var a := str(argv[i])
		match a:
			"--checksum", "-c":
				i += 1
				if i >= argv.size():
					return {"error": "Missing value for --checksum"}
				checksum = str(argv[i])
			"--mode", "-m":
				i += 1
				if i >= argv.size():
					return {"error": "Missing value for --mode"}
				mode = str(argv[i])
			"--rank", "-r":
				i += 1
				if i >= argv.size():
					return {"error": "Missing value for --rank"}
				rank = int(str(argv[i]))
			"--all", "-a":
				verify_all = true
			"--replays-only":
				replays_only = true
			"--highscores":
				i += 1
				if i >= argv.size():
					return {"error": "Missing value for --highscores"}
				highscores = str(argv[i])
			"--replays":
				i += 1
				if i >= argv.size():
					return {"error": "Missing value for --replays"}
				replays = str(argv[i])
			"--help", "-h":
				return {
					"error":
					"Usage: --checksum <hex> | --mode <modeId> --rank <n> | --all [--mode <modeId>] [--replays-only] [--highscores PATH] [--replays PATH]"
				}
			_:
				if a.begins_with("--checksum="):
					checksum = a.get_slice("=", 1)
				elif a.begins_with("--mode="):
					mode = a.get_slice("=", 1)
				elif a.begins_with("--rank="):
					rank = int(a.get_slice("=", 1))
				elif a.begins_with("--highscores="):
					highscores = a.get_slice("=", 1)
				elif a.begins_with("--replays="):
					replays = a.get_slice("=", 1)
				else:
					return {"error": "Unknown argument: %s" % a}
		i += 1

	var has_checksum := not checksum.strip_edges().is_empty()
	var has_mode := not mode.strip_edges().is_empty()
	var has_rank := rank > 0
	var base := {
		"replays_only": replays_only,
		"highscores": highscores,
		"replays": replays,
	}
	if verify_all:
		if has_checksum or has_rank:
			return {"error": "--all cannot be combined with --checksum or --rank"}
		base["checksum"] = ""
		base["mode"] = mode
		base["rank"] = 0
		base["all"] = true
		return base
	if has_checksum:
		if has_rank and not has_mode:
			return {"error": "--rank requires --mode (or use --checksum alone)"}
		base["checksum"] = checksum
		base["mode"] = mode
		base["rank"] = rank
		base["all"] = false
		return base
	if has_mode and has_rank:
		base["checksum"] = ""
		base["mode"] = mode
		base["rank"] = rank
		base["all"] = false
		return base
	if has_mode and not has_rank:
		return {"error": "--mode requires --rank or --all (or pass --checksum)"}
	if has_rank and not has_mode:
		return {"error": "--rank requires --mode"}
	return {"error": "Required: --checksum <hex>  OR  --mode <modeId> --rank <n>  OR  --all [--mode <modeId>]"}


func _job_label(job: Dictionary) -> String:
	var mode_id := str(job.get("modeId", ""))
	var rank := int(job.get("rank", 0))
	var entry: Dictionary = job.get("entry", {})
	var checksum := str(entry.get("Checksum", entry.get("checksum", ""))).strip_edges().to_lower()
	var player_name := HighscoreChecksum.sanitize_player_name(
		str(entry.get("PlayerName", entry.get("playerName", "")))
	)
	var rank_bit := (" rank=#%s" % rank) if rank > 0 else ""
	return "checksum=%s mode=%s%s player=%s" % [checksum, mode_id, rank_bit, player_name]


func _job_has_replay(job: Dictionary) -> bool:
	var entry: Dictionary = job.get("entry", {})
	var checksum := str(entry.get("Checksum", entry.get("checksum", ""))).strip_edges().to_lower()
	if checksum.is_empty():
		return false
	var path := _replay_path(_replays_dir, checksum)
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	return not f.get_as_text().strip_edges().is_empty()


func _filter_jobs_with_replays(jobs: Array, report_skips: bool) -> Array:
	var kept: Array = []
	for job in jobs:
		if typeof(job) != TYPE_DICTIONARY:
			continue
		var typed: Dictionary = job
		if _job_has_replay(typed):
			kept.append(typed)
		elif report_skips:
			_record_skip("%s | no replay" % _job_label(typed))
	return kept


func _record_skip(message: String) -> void:
	_skip_count += 1
	print("%s %s" % [_ansi_skip(), message])


func _ansi_skip() -> String:
	if not _ansi_enabled():
		return "SKIP"
	return "\u001b[33mSKIP\u001b[0m"


func _jobs_for_all_modes(highscores_path: String) -> Array:
	var modes := _load_modes(highscores_path)
	if modes.is_empty():
		return []
	var jobs: Array = []
	var keys: Array = modes.keys()
	keys.sort()
	for key in keys:
		var mode_id := str(key)
		var raw: Variant = modes[key]
		if typeof(raw) != TYPE_ARRAY:
			continue
		var ranked := _rank_entries(raw as Array)
		for i in ranked.size():
			jobs.append({"modeId": mode_id, "entry": ranked[i], "rank": i + 1})
	return jobs


func _jobs_for_mode(highscores_path: String, mode_id: String) -> Array:
	var modes := _load_modes(highscores_path)
	if modes.is_empty():
		return []
	var needle := mode_id.strip_edges().to_lower()
	var matched_mode := ""
	var board: Array = []
	for key in modes.keys():
		if str(key).to_lower() == needle:
			matched_mode = str(key)
			var raw: Variant = modes[key]
			if typeof(raw) == TYPE_ARRAY:
				board = raw as Array
			break
	if matched_mode.is_empty():
		return []
	var ranked := _rank_entries(board)
	var jobs: Array = []
	for i in ranked.size():
		jobs.append({"modeId": matched_mode, "entry": ranked[i], "rank": i + 1})
	return jobs


func _load_modes(highscores_path: String) -> Dictionary:
	var text := _read_text(highscores_path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var root: Dictionary = parsed
	var modes: Variant = root.get("Modes", root.get("modes", {}))
	if typeof(modes) != TYPE_DICTIONARY:
		return {}
	return modes as Dictionary


func _find_entry_by_checksum(highscores_path: String, checksum: String, mode_filter: String) -> Dictionary:
	var modes := _load_modes(highscores_path)
	if modes.is_empty():
		return {}
	var needle := checksum.to_lower()
	var mode_needle := mode_filter.strip_edges().to_lower()
	for mode_id in modes.keys():
		if not mode_needle.is_empty() and str(mode_id).to_lower() != mode_needle:
			continue
		var board: Variant = modes[mode_id]
		if typeof(board) != TYPE_ARRAY:
			continue
		var ranked := _rank_entries(board as Array)
		for i in ranked.size():
			var entry: Dictionary = ranked[i]
			var cs := str(entry.get("Checksum", entry.get("checksum", ""))).strip_edges().to_lower()
			if cs == needle:
				return {"modeId": str(mode_id), "entry": entry, "rank": i + 1}
	return {}


func _find_entry_by_rank(highscores_path: String, mode_id: String, rank: int) -> Dictionary:
	if rank < 1:
		return {}
	var jobs := _jobs_for_mode(highscores_path, mode_id)
	if rank > jobs.size():
		return {}
	return jobs[rank - 1]


func _rank_entries(board: Array) -> Array:
	var entries: Array = []
	for item in board:
		if typeof(item) == TYPE_DICTIONARY:
			entries.append(item)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := int(a.get("FinalScore", a.get("finalScore", 0)))
		var sb := int(b.get("FinalScore", b.get("finalScore", 0)))
		if sa != sb:
			return sa > sb
		var ea := float(a.get("ElapsedSeconds", a.get("elapsedSeconds", 0.0)))
		var eb := float(b.get("ElapsedSeconds", b.get("elapsedSeconds", 0.0)))
		if not is_equal_approx(ea, eb):
			return ea < eb
		var ta := str(a.get("SubmittedAt", a.get("submittedAt", "")))
		var tb := str(b.get("SubmittedAt", b.get("submittedAt", "")))
		return ta < tb
	)
	return entries


func _replay_path(replays_dir: String, checksum: String) -> String:
	var safe := ""
	for i in checksum.length():
		var ch := checksum.substr(i, 1)
		var code := ch.unicode_at(0)
		var ok := (
			(code >= 48 and code <= 57)
			or (code >= 65 and code <= 90)
			or (code >= 97 and code <= 122)
			or ch == "-"
			or ch == "_"
		)
		if ok:
			safe += ch
	if safe.is_empty():
		safe = "invalid"
	return replays_dir.rstrip("/").path_join("%s.json" % safe)


func _read_text(path: String) -> String:
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


func _cleanup_main() -> void:
	if _main != null and is_instance_valid(_main):
		var node := _main
		_main = null
		if node.get("music") != null and node.music != null and node.music.has_method("stop"):
			node.music.stop()
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()


func _finish(code: int) -> void:
	_phase = 3
	_cleanup_main()
	_exit_code = code
	_quit_after_frames = 2


func _fail_fatal(message: String) -> void:
	push_error(message)
	printerr("%s %s" % [_ansi_fail(), message])
	_finish(1)
