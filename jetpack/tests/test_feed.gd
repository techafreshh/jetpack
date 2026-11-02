extends SceneTree
## Headless behavior proof for the KillFeed last-4 ring: 5-kill cap at 4,
## newest-evicts-oldest, latest killer/victim/weapon substrings, empty-push
## ignore, add_kill alias parity, and clear.
## Run: godot --headless --path jetpack --script res://tests/test_feed.gd

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

	# (a) Five pushes cap the feed at four.
	var feed := KillFeed.new()
	check(feed != null, "KillFeed.new constructs")
	check(int(feed.get("feed_count")) == 0, "fresh feed_count is 0")
	check(str(feed.latest_text()) == "", "fresh latest_text is empty")
	check((feed.latest() as Dictionary).is_empty(), "fresh latest is empty dict")
	check((feed.get_entries() as Array).is_empty(), "fresh get_entries is empty")
	for i in 5:
		feed.push_kill("A%d" % i, "B%d" % i, "Scatter")
	check(int(feed.get("feed_count")) == 4, "feed_count caps at 4 after 5 pushes (got %d)" % int(feed.get("feed_count")))
	check(feed.feed_count == 4, "feed_count property reads 4")

	# (b) Latest entry carries killer, victim, and weapon substrings.
	var top := feed.latest() as Dictionary
	check(str(top["killer"]).contains("A4"), "latest killer holds A4 (got %s)" % str(top["killer"]))
	check(str(top["victim"]).contains("B4"), "latest victim holds B4 (got %s)" % str(top["victim"]))
	check(str(top["weapon"]).contains("Scatter"), "latest weapon holds Scatter (got %s)" % str(top["weapon"]))
	var text := feed.latest_text()
	check(text.contains("A4"), "latest_text holds A4 (got %s)" % text)
	check(text.contains("B4"), "latest_text holds B4 (got %s)" % text)
	check(text.contains("Scatter"), "latest_text holds Scatter (got %s)" % text)

	# (c) Oldest evicted; newest-first order holds.
	var entries := feed.get_entries() as Array
	check(entries.size() == 4, "get_entries holds 4 (got %d)" % entries.size())
	var killers := ""
	for e in entries:
		killers += str((e as Dictionary)["killer"]) + ","
	check(not killers.contains("A0"), "oldest A0 evicted (got %s)" % killers)
	check(str((entries[0] as Dictionary)["killer"]) == "A4", "entries[0] is newest A4")
	check(str((entries[3] as Dictionary)["killer"]) == "A1", "entries[3] is oldest retained A1")

	# (d) Guards: all-empty push ignored, arena fallback, alias parity, clear.
	var before := feed.feed_count
	feed.push_kill("", "", "")
	check(feed.feed_count == before, "all-empty push ignored")
	feed.push_kill("", "B9", "Scatter")
	check(feed.latest_text().contains("The arena"), "empty killer renders as The arena (got %s)" % feed.latest_text())
	var alias := KillFeed.new()
	alias.add_kill("X", "Y", "Ranger")
	check(alias.feed_count == 1, "add_kill pushes one event")
	check(alias.latest_text().contains("X") and alias.latest_text().contains("Y"), "add_kill matches push_kill text")
	feed.clear()
	check(feed.feed_count == 0, "clear zeroes feed_count")
	check(str(feed.latest_text()) == "", "clear empties latest_text")
	check((feed.get_entries() as Array).is_empty(), "clear empties get_entries")
