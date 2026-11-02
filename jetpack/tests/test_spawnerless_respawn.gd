extends SceneTree
## Headless proof for spawner-less respawn: a standalone soldier (no spawner
## group node) that dies below y=2000 respawns above the plane instead of
## looping on its death position, and a combat death keeps safe locality.
## Run: godot --headless --path jetpack --script res://tests/test_spawnerless_respawn.gd

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

	var packed := load("res://scenes/soldier.tscn") as PackedScene
	check(packed != null, "soldier.tscn loads as PackedScene")
	if packed == null:
		return
	check(get_first_node_in_group("spawner") == null, "no spawner node in standalone tree")

	# Case 1: standalone fall death respawns above the plane, no loop.
	var soldier := packed.instantiate() as CharacterBody2D
	check(soldier != null, "soldier.tscn instantiates CharacterBody2D")
	if soldier == null:
		return
	soldier.position = Vector2(500, 400)
	root.add_child(soldier)
	await process_frame
	await process_frame
	check(bool(soldier.get("is_alive")), "standalone soldier starts alive")

	var died_count := [0]
	var respawned_count := [0]
	soldier.connect("died", func() -> void: died_count[0] += 1)
	soldier.connect("respawned", func() -> void: respawned_count[0] += 1)

	# Let the soldier record safe ground above the plane, then fall below it.
	soldier.global_position = Vector2(500, 400)
	soldier.set("velocity", Vector2.ZERO)
	await physics_frame
	await physics_frame
	soldier.global_position = Vector2(500, 2100)
	soldier.set("velocity", Vector2.ZERO)
	var death_tick := -1
	for i in 5:
		await physics_frame
		if not bool(soldier.get("is_alive")):
			death_tick = i + 1
			break
	check(death_tick >= 1 and death_tick <= 5, "spawner-less fall kills within 5 ticks (got %d)" % death_tick)
	check(not bool(soldier.get("is_alive")), "spawner-less fall soldier is_alive is false")
	check(died_count[0] == 1, "died emitted exactly once (got %d)" % died_count[0])

	var respawn_tick := -1
	for i in 220:
		await physics_frame
		if bool(soldier.get("is_alive")):
			respawn_tick = i + 1
			break
	check(respawn_tick >= 170 and respawn_tick <= 190, "spawner-less respawn flips is_alive in 170-190 ticks (got %d)" % respawn_tick)
	check(respawned_count[0] == 1, "respawned emitted exactly once (got %d)" % respawned_count[0])
	check(died_count[0] == 1, "no second died during respawn wait (got %d)" % died_count[0])
	check_close(float(soldier.get("hp")), float(soldier.get("max_hp")), 0.0001, "spawner-less respawn restores full HP")
	check(int(soldier.collision_layer) != 0 and int(soldier.collision_mask) != 0, "spawner-less respawn restores collision")
	check(float(soldier.global_position.y) < 2000.0, "spawner-less respawn point is above the kill-plane (y=%f)" % float(soldier.global_position.y))

	# The loop regression: stays alive above the plane, never re-dies below it.
	for i in 10:
		await physics_frame
	check(bool(soldier.get("is_alive")), "spawner-less soldier stays alive after respawn")
	check(died_count[0] == 1, "no loop death after spawner-less respawn (got %d)" % died_count[0])
	check(float(soldier.global_position.y) < 2000.0, "spawner-less soldier stays above the kill-plane (y=%f)" % float(soldier.global_position.y))
	soldier.queue_free()

	# Case 2: combat death above the plane keeps safe locality.
	var duelist := packed.instantiate() as CharacterBody2D
	check(duelist != null, "second soldier instantiates CharacterBody2D")
	if duelist == null:
		return
	duelist.position = Vector2(700, 500)
	root.add_child(duelist)
	await process_frame
	await process_frame
	var died2 := [0]
	var respawned2 := [0]
	duelist.connect("died", func() -> void: died2[0] += 1)
	duelist.connect("respawned", func() -> void: respawned2[0] += 1)
	duelist.global_position = Vector2(700, 500)
	duelist.set("velocity", Vector2.ZERO)
	await physics_frame
	await physics_frame
	var safe: Vector2 = duelist.global_position
	check(safe.y < 2000.0, "combat safe position is above the plane (y=%f)" % safe.y)
	duelist.set("hp", 100.0)
	duelist.call("take_damage", 200.0)
	check(not bool(duelist.get("is_alive")), "lethal damage kills duelist")
	check(died2[0] == 1, "duelist died emitted exactly once (got %d)" % died2[0])
	var respawn2 := -1
	for i in 220:
		await physics_frame
		if bool(duelist.get("is_alive")):
			respawn2 = i + 1
			break
	check(respawn2 >= 170 and respawn2 <= 190, "combat respawn flips is_alive in 170-190 ticks (got %d)" % respawn2)
	check(respawned2[0] == 1, "duelist respawned emitted exactly once (got %d)" % respawned2[0])
	check(float(duelist.global_position.y) < 2000.0, "combat respawn point is above the kill-plane (y=%f)" % float(duelist.global_position.y))
	check((duelist.global_position as Vector2).distance_to(safe) <= 80.0, "combat respawn keeps safe locality (dist=%f)" % (duelist.global_position as Vector2).distance_to(safe))
	duelist.queue_free()
