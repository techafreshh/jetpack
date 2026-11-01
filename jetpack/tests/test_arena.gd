extends SceneTree
## Headless verification for the grey-box arena and match host: both scenes
## load, the collider count satisfies the >=10 gate, and a 600-tick sim keeps
## the Spawn0 soldier above the kill-plane (y=2000).
## Run: godot --headless --path jetpack --script res://tests/test_arena.gd

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


func run_tests() -> void:
	await process_frame

	var grey_packed := load("res://scenes/arena/greybox.tscn") as PackedScene
	check(grey_packed != null, "greybox.tscn loads as PackedScene")
	var match_packed := load("res://scenes/match.tscn") as PackedScene
	check(match_packed != null, "match.tscn loads as PackedScene")
	if grey_packed == null or match_packed == null:
		return

	var grey := grey_packed.instantiate() as Node2D
	check(grey != null, "greybox instantiates Node2D")
	if grey == null:
		return
	root.add_child(grey)
	await process_frame

	var bodies := grey.find_children("*", "StaticBody2D", true, false)
	check(bodies.size() >= 10, "greybox has >=10 StaticBody2D (got %d)" % bodies.size())
	check(grey.get_node_or_null("Spawn0") != null, "Spawn0 marker exists")

	var fa := FileAccess.open("res://scenes/arena/greybox.tscn", FileAccess.READ)
	if fa != null:
		var text := fa.get_as_text()
		fa.close()
		var n := text.count("StaticBody2D")
		check(n >= 10, "greybox.tscn mentions StaticBody2D >=10 times (got %d)" % n)
	else:
		check(false, "greybox.tscn readable via FileAccess")

	var match_inst := match_packed.instantiate() as Node2D
	check(match_inst != null, "match instantiates Node2D")
	if match_inst == null:
		return
	root.add_child(match_inst)
	await process_frame
	await process_frame

	var soldier := match_inst.get_node_or_null("Soldier") as CharacterBody2D
	check(soldier != null, "match contains Soldier")
	if soldier == null:
		return

	var max_y: float = soldier.position.y
	var ticks := 600
	for i in ticks:
		await physics_frame
		max_y = maxf(max_y, soldier.position.y)
	check(max_y < 2000.0, "soldier stays above kill-plane (max y=%f)" % max_y)
	check(soldier.is_on_floor(), "soldier rests on floor after 600 ticks")
