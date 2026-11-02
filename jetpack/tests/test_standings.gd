extends SceneTree
## Headless behavior proof for Standings: 10/8/8/3 sort order with the local
## highlight, the `You N / 25` HUD regex, tscn structure, feed delegation
## capped at 4, and match.tscn seating.
## Run: godot --headless --path jetpack --script res://tests/test_standings.gd

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


func run_tests() -> void:
	await process_frame

	# (a) Standings sort 10/8/8/3 with the local row highlighted.
	var table := Standings.new()
	check(table != null, "Standings.new constructs")
	table.set_scores({"You": 10, "bot_1": 8, "bot_2": 8, "bot_3": 3})
	var rows := table.get_rows() as Array
	var scores: Array = []
	for r in rows:
		scores.append(int((r as Dictionary)["score"]))
	check(scores == [10, 8, 8, 3], "rows sort 10,8,8,3 (got %s)" % str(scores))
	check(str((rows[0] as Dictionary)["name"]) == "You", "leader row is You")
	var you := table.row_for("You") as Dictionary
	check(bool(you["highlight"]), "local row highlight is true")
	for r in rows:
		if str((r as Dictionary)["name"]) != "You":
			check(not bool((r as Dictionary)["highlight"]), "non-local row has no highlight (%s)" % str((r as Dictionary)["name"]))

	# (b) HUD standings line matches `You \d+ / 25`.
	var hud_line := table.hud_standings_string()
	check(hud_line == "You 10 / 25", "hud line is You 10 / 25 (got %s)" % hud_line)
	var re := RegEx.new()
	check(re.compile("You \\d+ / 25") == OK, "HUD regex compiles")
	check(re.search(hud_line) != null, "hud line matches You \\d+ / 25 (got %s)" % hud_line)

	# (c) standings.tscn structure: root name plus Rows/HudLine/Feed.
	var packed := load("res://scenes/ui/standings.tscn") as PackedScene
	check(packed != null, "standings.tscn loads as PackedScene")
	if packed == null:
		return
	var widget := packed.instantiate() as Control
	check(widget != null, "standings.tscn instantiates Control")
	if widget == null:
		return
	check(widget.name == "Standings", "standings root is named Standings (got %s)" % widget.name)
	root.add_child(widget)
	await process_frame
	await process_frame
	check(widget.get_node_or_null("Rows") != null, "standings exposes Rows")
	check(widget.get_node_or_null("HudLine") != null, "standings exposes HudLine")
	check(widget.get_node_or_null("Feed") != null, "standings exposes Feed")
	var seeded := widget.get_node_or_null("HudLine") as Label
	check(seeded != null and seeded.text == "You 0 / 25", "seeded HudLine reads You 0 / 25 (got %s)" % (seeded.text if seeded != null else "<null>"))

	# (d) Widget push_kill delegates to the feed and caps at 4.
	for i in 5:
		widget.push_kill("A%d" % i, "B%d" % i, "Scatter")
	check(int(widget.get("feed_count")) == 4, "widget feed_count caps at 4 (got %d)" % int(widget.get("feed_count")))
	var wrows := widget.get_rows() as Array
	check(wrows.size() >= 5, "push_kill seeds fresh ids (got %d rows)" % wrows.size())
	widget.queue_free()
	await process_frame

	# (e) match.tscn seats the Standings child beside hud.
	var match_packed := load("res://scenes/match.tscn") as PackedScene
	check(match_packed != null, "match.tscn loads as PackedScene")
	if match_packed == null:
		return
	var host := match_packed.instantiate() as Node2D
	check(host != null, "match.tscn instantiates Node2D")
	if host == null:
		return
	root.add_child(host)
	await process_frame
	await process_frame
	await wait_physics(5)
	check(host.get_node_or_null("Standings") != null, "match seats Standings child")
	check(host.get_node_or_null("hud") != null, "match still seats hud")
	table.queue_free()
	host.queue_free()
	await process_frame
