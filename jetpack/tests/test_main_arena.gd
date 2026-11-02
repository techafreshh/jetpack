extends SceneTree
## Headless verification for the final MVP map: main.tscn loads with exactly
## 8 Spawn* markers and >=6 pickup pads, spans >=2560 px with >=300 px spawn
## spacing, and match.tscn defaults arena_path to the new map.
## Run: godot --headless --path jetpack --script res://tests/test_main_arena.gd

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


func run_tests() -> void:
	await process_frame

	var main_packed := load("res://scenes/arena/main.tscn") as PackedScene
	check(main_packed != null, "main.tscn loads as PackedScene")
	if main_packed == null:
		return
	var main := main_packed.instantiate() as Node2D
	check(main != null, "main instantiates Node2D")
	if main == null:
		return
	root.add_child(main)
	await process_frame
	await process_frame

	var spawns := main.find_children("Spawn*", "Marker2D", true, false)
	check(spawns.size() == 8, "main has exactly 8 Spawn* markers (got %d)" % spawns.size())

	var pads := 0
	for n in main.find_children("*", "Area2D", true, false):
		var nm := String((n as Node).name)
		if (n as Node).is_in_group("pickup") or nm.contains("Pad") or nm.contains("Pickup"):
			pads += 1
	check(pads >= 6, "main has >=6 pickup pads (got %d)" % pads)

	var bodies := main.find_children("*", "StaticBody2D", true, false)
	check(bodies.size() >= 10, "main has >=10 StaticBody2D (got %d)" % bodies.size())
	var min_x := INF
	var max_x := -INF
	for b in bodies:
		var pos := (b as Node2D).position
		var lo := pos.x
		var hi := pos.x
		var col := (b as Node).get_node_or_null("Collision") as CollisionShape2D
		if col != null and col.shape is RectangleShape2D:
			var half := (col.shape as RectangleShape2D).size.x * 0.5
			lo = pos.x - half
			hi = pos.x + half
		min_x = minf(min_x, lo)
		max_x = maxf(max_x, hi)
	check(max_x - min_x >= 2560.0, "main playable width >=2560 (got %f)" % (max_x - min_x))

	var pts: Array = []
	for s in spawns:
		pts.append((s as Node2D).position)
	var ok := true
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			if (pts[i] as Vector2).distance_to(pts[j] as Vector2) < 300.0:
				ok = false
	check(ok, "no two spawns within 300 px")

	var match_packed := load("res://scenes/match.tscn") as PackedScene
	check(match_packed != null, "match.tscn loads as PackedScene")
	if match_packed == null:
		return
	var match_inst := match_packed.instantiate() as Node2D
	check(match_inst != null, "match instantiates Node2D")
	if match_inst == null:
		return
	root.add_child(match_inst)
	await process_frame
	var arena_path := ""
	if match_inst.get("arena_path") != null:
		arena_path = String(match_inst.get("arena_path"))
	else:
		var mgr := match_inst.get_node_or_null("MatchManager")
		if mgr != null and mgr.get("arena_path") != null:
			arena_path = String(mgr.get("arena_path"))
	check(arena_path.ends_with("scenes/arena/main.tscn"), "match arena_path defaults to main.tscn (got %s)" % arena_path)
	var grey := match_inst.get_node_or_null("Greybox")
	check(grey != null, "match keeps Greybox arena node name")

	main.queue_free()
	match_inst.queue_free()
	await process_frame
