extends SceneTree
## Headless proof for first-match tips: 5s idle shows tips_label, the
## user://seen_tips flag is written, and a later run stays hidden.
## Run: godot --headless --path jetpack --script res://tests/test_tips.gd

const TipsScript := "res://scripts/ui/tips.gd"

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


func wait_physics(n: int) -> void:
	for i in n:
		await physics_frame


func clear_flag() -> void:
	if FileAccess.file_exists("user://seen_tips"):
		DirAccess.remove_absolute("user://seen_tips")


func fresh_tips() -> CanvasLayer:
	var tips := (load(TipsScript) as Script).new() as CanvasLayer
	root.add_child(tips)
	await process_frame
	await process_frame
	return tips


func run_tests() -> void:
	await process_frame
	clear_flag()

	# (a) Tips builds a hidden label on a first run.
	var tips := await fresh_tips()
	check(tips != null, "tips node instantiates")
	if tips == null:
		return
	var label := tips.find_child("tips_label", true, false) as Label
	check(label != null, "tips exposes tips_label")
	if label != null:
		check(not label.visible, "tips_label starts hidden")

	# (b) 5s idle shows the label and writes the flag.
	if label != null:
		tips.set("idle_s", 4.9)
		await wait_physics(15)
		check(label.visible, "idle past 5s shows tips_label")
		check(FileAccess.file_exists("user://seen_tips"), "seen_tips flag exists after one match")
	tips.queue_free()
	await process_frame

	# (c) A second run with the flag present stays hidden.
	var tips2 := await fresh_tips()
	var label2 := tips2.find_child("tips_label", true, false) as Label
	check(label2 != null, "second run still builds tips_label")
	if label2 != null:
		check(not label2.visible, "second run stays hidden")
		tips2.set("idle_s", 30.0)
		await wait_physics(10)
		check(not label2.visible, "flagged run never shows tips")
	tips2.queue_free()
	await process_frame

	# (d) A live 5s idle wait shows tips from zero without preset clocks.
	clear_flag()
	var tips3 := await fresh_tips()
	var label3 := tips3.find_child("tips_label", true, false) as Label
	check(label3 != null, "third run builds tips_label")
	if label3 != null:
		await wait_physics(320)
		check(label3.visible, "live 5s idle shows tips_label")
		check(FileAccess.file_exists("user://seen_tips"), "live run writes seen_tips")
	tips3.queue_free()
	await process_frame

	# (e) match.tscn seats the Tips child beside hud and MatchManager.
	var match_packed := load("res://scenes/match.tscn") as PackedScene
	check(match_packed != null, "match.tscn loads as PackedScene")
	if match_packed != null:
		var host := match_packed.instantiate() as Node2D
		root.add_child(host)
		await process_frame
		await process_frame
		check(host.get_node_or_null("Tips") != null, "match seats Tips child")
		check(host.get_node_or_null("Tips/tips_label") != null, "seated Tips builds tips_label")
		check(host.get_node_or_null("MatchManager") != null, "match still seats MatchManager")
		check(host.get_node_or_null("hud") != null, "match still seats hud")
		host.queue_free()
		await process_frame

	clear_flag()
	paused = false
