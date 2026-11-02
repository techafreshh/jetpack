extends SceneTree
## Headless proof for the match manager: countdown -> live, 25-kill fast
## finish with winner inside 60 ticks, tied-clock sudden death with exactly
## +30s, five-key match_results, rematch zero/countdown reset, and a
## missing-config fallback holding compiled defaults.
## Run: godot --headless --path jetpack --script res://tests/test_match.gd

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


func fresh_manager() -> MatchManager:
	var m := MatchManager.new()
	root.add_child(m)
	await process_frame
	await process_frame
	return m


func run_tests() -> void:
	await process_frame

	# (a) Countdown reaches live; 25 kills finish within 60 ticks w/ leader.
	var m := await fresh_manager()
	check(m.match_state == "countdown", "manager starts in countdown")
	m.countdown_left = 0.05
	await wait_physics(10)
	check(m.match_state == "live", "countdown ticks into live")
	m.target_score = 25
	for i in 25:
		m.register_kill("bot_0", "bot_1")
	var ticks := 0
	while m.match_state != "results" and ticks < 60:
		await physics_frame
		ticks += 1
	check(m.match_state == "results", "25 kills reach results within 60 ticks")
	check(m.winner_id == "bot_0", "winner_id equals leader id (got %s)" % m.winner_id)

	# (b) Tied clock expiry latches sudden death with exactly +30s.
	var m2 := await fresh_manager()
	m2.countdown_left = 0.01
	await wait_physics(5)
	check(m2.match_state == "live", "second manager reaches live")
	for i in 3:
		m2.register_kill("bot_a", "bot_x")
	for i in 3:
		m2.register_kill("bot_b", "bot_y")
	check(m2.score_for("bot_a") == 3 and m2.score_for("bot_b") == 3, "tie staged at 3-3")
	m2.time_left = 5.0
	var saw := false
	for t in 400:
		await physics_frame
		if m2.sudden_death:
			saw = true
			break
	check(saw, "tied expiry latches sudden_death")
	check(m2.sudden_death, "sudden_death stays true")
	check(m2.match_state == "live", "sudden death extends live, not results")
	check_close(float(m2.sudden_death_s), 30.0, 0.001, "sudden_death_s is 30s")
	check_close(float(m2.time_left), 30.0, 0.6, "clock extended by exactly 30s")
	# A sudden-death kill wins at once.
	m2.register_kill("bot_a", "bot_b")
	check(m2.match_state == "results", "sudden-death kill ends match")
	check(m2.winner_id == "bot_a", "sudden-death winner is the scorer (got %s)" % m2.winner_id)

	# (c) Results shape and instant rematch.
	var r: Dictionary = m2.match_results
	for key in ["kills", "deaths", "score", "duration", "difficulty"]:
		check(r.has(key), "match_results has key %s" % key)
	check(r.size() == 5, "match_results has exactly five keys (got %d)" % r.size())
	m2.rematch()
	check(m2.match_state == "countdown", "rematch returns to countdown")
	check(m2.winner_id == "", "rematch clears winner_id")
	check(not m2.sudden_death, "rematch clears sudden_death")
	check(m2.score_for("bot_a") == 0 and m2.score_for("bot_b") == 0, "rematch zeroes scores")
	check_close(float(m2.time_left), float(m2.time_limit_s), 0.001, "rematch restores full clock")

	# (d) Missing config keeps compiled defaults instead of crashing.
	var m3 := MatchManager.new()
	m3.config_path = "res://resources/config/does_not_exist_match.cfg"
	root.add_child(m3)
	await process_frame
	await process_frame
	check(m3.target_score == 25, "missing cfg keeps target_score 25")
	check_close(float(m3.time_limit_s), 300.0, 0.001, "missing cfg keeps time_limit_s 300")
	check_close(float(m3.sudden_death_s), 30.0, 0.001, "missing cfg keeps sudden_death_s 30")
	check(m3.difficulty == "standard", "missing cfg keeps difficulty standard")
	check(m3.match_state == "countdown", "missing cfg still boots to countdown")

	m.queue_free()
	m2.queue_free()
	m3.queue_free()
	await process_frame
