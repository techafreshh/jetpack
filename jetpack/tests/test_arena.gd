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

	var ceiling := grey.get_node_or_null("Ceiling")
	check(ceiling != null, "Ceiling node exists")
	check(ceiling is StaticBody2D, "Ceiling is StaticBody2D")
	var wall_l := grey.get_node_or_null("WallL") as StaticBody2D
	var wall_r := grey.get_node_or_null("WallR") as StaticBody2D
	check(wall_l != null, "WallL exists for ceiling span check")
	check(wall_r != null, "WallR exists for ceiling span check")
	if ceiling is StaticBody2D and wall_l != null and wall_r != null:
		var ceil_col := ceiling.get_node_or_null("Collision") as CollisionShape2D
		var wall_l_col := wall_l.get_node_or_null("Collision") as CollisionShape2D
		var wall_r_col := wall_r.get_node_or_null("Collision") as CollisionShape2D
		check(ceil_col != null and ceil_col.shape is RectangleShape2D, "Ceiling has RectangleShape2D collision")
		if ceil_col != null and ceil_col.shape is RectangleShape2D and wall_l_col != null and wall_l_col.shape is RectangleShape2D and wall_r_col != null and wall_r_col.shape is RectangleShape2D:
			var ceil_size := (ceil_col.shape as RectangleShape2D).size
			var ceil_pos := (ceiling as Node2D).position
			var wl_size := (wall_l_col.shape as RectangleShape2D).size
			var wr_size := (wall_r_col.shape as RectangleShape2D).size
			var wl_pos := (wall_l as Node2D).position
			var wr_pos := (wall_r as Node2D).position
			var ceil_left := ceil_pos.x - ceil_size.x * 0.5
			var ceil_right := ceil_pos.x + ceil_size.x * 0.5
			var ceil_bottom := ceil_pos.y + ceil_size.y * 0.5
			var wall_l_outer := wl_pos.x - wl_size.x * 0.5
			var wall_r_outer := wr_pos.x + wr_size.x * 0.5
			var wall_top := wl_pos.y - wl_size.y * 0.5
			check(ceil_left <= wall_l_outer + 1.0, "Ceiling spans to WallL outer face (left=%f outer=%f)" % [ceil_left, wall_l_outer])
			check(ceil_right >= wall_r_outer - 1.0, "Ceiling spans to WallR outer face (right=%f outer=%f)" % [ceil_right, wall_r_outer])
			check(absf(ceil_bottom - wall_top) <= 40.0, "Ceiling bottom flush with wall tops (bottom=%f top=%f)" % [ceil_bottom, wall_top])
			check(ceil_size.x >= wall_r_outer - wall_l_outer, "Ceiling covers wall-to-wall width")

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

	# Ceiling-bounded climb: sustained thrust must stop at the ceiling.
	var ceil_node := grey.get_node_or_null("Ceiling") as StaticBody2D
	var ceil_collision: CollisionShape2D = null
	if ceil_node != null:
		ceil_collision = ceil_node.get_node_or_null("Collision") as CollisionShape2D
	var ceil_bottom := -1600.0
	if ceil_collision != null and ceil_collision.shape is RectangleShape2D:
		ceil_bottom = ceil_node.position.y + (ceil_collision.shape as RectangleShape2D).size.y * 0.5
	var soldier_body := soldier.get_node_or_null("Body") as CollisionShape2D
	check(soldier_body != null and soldier_body.shape is RectangleShape2D, "Soldier body shape readable for ceiling check")
	var soldier_h := 64.0
	if soldier_body != null and soldier_body.shape is RectangleShape2D:
		soldier_h = (soldier_body.shape as RectangleShape2D).size.y
	soldier.position = Vector2(1200, -1000)
	soldier.velocity = Vector2.ZERO
	await process_frame
	await physics_frame
	var min_y: float = soldier.position.y
	var touched_ceiling := soldier.is_on_ceiling()
	Input.action_press("fly")
	for i in 600:
		soldier.set("fuel", float(soldier.get("fuel_max")))
		await physics_frame
		min_y = minf(min_y, soldier.position.y)
		if soldier.is_on_ceiling():
			touched_ceiling = true
	Input.action_release("fly")
	check(touched_ceiling, "sustained thrust contacts ceiling (is_on_ceiling)")
	check(min_y >= ceil_bottom + soldier_h - 100.0, "climb stopped by ceiling (min y=%f floor=%f)" % [min_y, ceil_bottom + soldier_h - 100.0])
