extends SceneTree
## Headless proof for the full 1-human-plus-7-bots match: seating plus the
## human yields exactly 8 standings rows, a short-clock fast-forward reaches
## results with the five-key match_results shape, rematch resets to countdown
## with zeroed scores and a full clock, the default config still audits to
## 25 / 300s / 30s, and the sim ticks at a fixed 60 Hz.
## Run: godot --headless --path jetpack --script res://tests/test_full_match.gd

var passed := 0
var failed := 0


func _initialize() -> void:
	await run_tests()
	print("Results: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		push_error("FAIL " + label)


func check_close(actual: float, expected: float, tol: float, label: String) -> void:
	check(absf(actual - expected) <= tol, "%s (expected ~%f, got %f)" % [label, expected, actual])


func wait_physics(n: int) -> void:
	for i in n:
		await physics_frame


func file_text(path: String) -> String:
	var out := ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		out += f.get_line() + "\n"
	return out


func run_tests() -> void:
	await process_frame

	# (i) Fixed-timestep audit: 60 Hz tick rate, no sim drift.
	check(Engine.physics_ticks_per_second == 60, "physics ticks at 60Hz (got %d)" % Engine.physics_ticks_per_second)
	var proj := file_text("res://project.godot")
	check(proj.contains("[physics]") and proj.contains("physics_ticks_per_second=60"), "project.godot pins physics_ticks_per_second=60")

	# (ii) Default config audit: 25 kills, 5:00 clock, 30s sudden death.
	var cfg := ConfigFile.new()
	check(cfg.load("res://resources/config/match.cfg") == OK, "default match.cfg loads")
	check(int(cfg.get_value("match", "target_score", 0)) == 25, "default target_score is 25")
	check_close(float(cfg.get_value("match", "time_limit_s", 0.0)), 300.0, 0.001, "default time_limit_s is 300s")
	check_close(float(cfg.get_value("match", "sudden_death_s", 0.0)), 30.0, 0.001, "default sudden_death_s is 30s")

	# (iii) Full match: arena plus a short-clock manager, 1 human + 7 bots.
	var arena := (load("res://scenes/arena/main.tscn") as PackedScene).instantiate()
	check(arena != null, "arena main.tscn instantiates")
	root.add_child(arena)
	await process_frame
	await process_frame
	var m := MatchManager.new()
	m.auto_seat = false
	arena.add_child(m)
	await process_frame
	await process_frame
	check(m.match_state == "countdown", "manager starts in countdown")
	m.time_limit_s = 5.0
	m.time_left = 5.0
	m.sudden_death_s = 2.0
	m.countdown_s = 0.2
	m.countdown_left = 0.2
	m.target_score = 99
	check(m.ensure_participant("You"), "human participant You seated")
	var seated := m.seat_bots()
	check(seated == 7, "seat_bots seats 7 bots (got %d)" % seated)
	var table := m.get_standings()
	check(table.size() == 8, "standings hold 8 rows for 1 human + 7 bots (got %d)" % table.size())
	check(table.has("You"), "standings include the human")

	# Fast-forward: countdown, the 5s clock, sudden death, then results.
	var ticks := 0
	while m.match_state != "live" and ticks < 300:
		await physics_frame
		ticks += 1
	check(m.match_state == "live", "short countdown reaches live")
	while m.match_state != "results" and ticks < 2000:
		await physics_frame
		ticks += 1
	check(m.match_state == "results", "short-clock full match reaches results (state %s)" % m.match_state)
	check(m.winner_id != "", "results name a winner (got '%s')" % m.winner_id)

	# (iv) Results shape: exactly the five-key contract, 8 standings rows.
	var r: Dictionary = m.match_results
	for key in ["kills", "deaths", "score", "duration", "difficulty"]:
		check(r.has(key), "match_results has key %s" % key)
	check(r.size() == 5, "match_results has exactly five keys (got %d)" % r.size())
	check(m.get_standings().size() == 8, "results keep 8 standings rows")

	# (v) Rematch resets to countdown with zeroed scores and a full clock.
	m.rematch()
	check(m.match_state == "countdown", "rematch returns to countdown")
	check(m.winner_id == "", "rematch clears winner_id")
	check(not m.sudden_death, "rematch clears sudden_death")
	check(m.score_for("You") == 0 and m.score_for("bot_0") == 0, "rematch zeroes scores")
	check_close(float(m.time_left), float(m.time_limit_s), 0.001, "rematch restores full clock")

	arena.queue_free()
	await process_frame
