extends SceneTree
## Headless behavior tests for the kill-plane: a soldier below y=2000 dies
## via _die() within ticks and respawns through the standard spawner path
## with full HP inside the 170-190 tick window, above the plane.
## Run: godot --headless --path jetpack --script res://tests/test_killplane.gd

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
	await process_frame

	var soldier := match_inst.get_node_or_null("Soldier") as CharacterBody2D
	check(soldier != null, "match contains Soldier")
	if soldier == null:
		return
	check(bool(soldier.get("is_alive")), "match soldier starts alive")

	var died_count := [0]
	var respawned_count := [0]
	soldier.connect("died", func() -> void: died_count[0] += 1)
	soldier.connect("respawned", func() -> void: respawned_count[0] += 1)

	# Boundary: exactly y=2000.0 is not past the plane, so one tick lives.
	soldier.global_position = Vector2(1200, 2000.0)
	soldier.set("velocity", Vector2.ZERO)
	await physics_frame
	check(bool(soldier.get("is_alive")), "soldier at exactly y=2000 lives")
	check(died_count[0] == 0, "no died at exactly y=2000 (got %d)" % died_count[0])

	# Below the plane: environmental death within ticks, exactly one died.
	soldier.global_position = Vector2(1200, 2100)
	soldier.set("velocity", Vector2.ZERO)
	var death_tick := -1
	for i in 5:
		await physics_frame
		if not bool(soldier.get("is_alive")):
			death_tick = i + 1
			break
	check(death_tick >= 1 and death_tick <= 5, "below-plane teleport kills within 5 ticks (got %d)" % death_tick)
	check(not bool(soldier.get("is_alive")), "below-plane soldier is_alive is false")
	check(died_count[0] == 1, "died emitted exactly once (got %d)" % died_count[0])
	check(int(soldier.collision_layer) == 0 and int(soldier.collision_mask) == 0, "fall death zeroes collision")

	# Standard spawner respawn: 170-190 ticks, full HP, above the plane.
	var respawn_tick := -1
	for i in 220:
		await physics_frame
		if bool(soldier.get("is_alive")):
			respawn_tick = i + 1
			break
	check(respawn_tick >= 170 and respawn_tick <= 190, "respawn flips is_alive in 170-190 ticks (got %d)" % respawn_tick)
	check(respawned_count[0] == 1, "respawned emitted exactly once (got %d)" % respawned_count[0])
	check(died_count[0] == 1, "no second died during respawn wait (got %d)" % died_count[0])
	check_close(float(soldier.get("hp")), float(soldier.get("max_hp")), 0.0001, "respawn restores full HP")
	check_close(float(soldier.call("respawn_seconds_left")), 0.0, 0.01, "respawn_seconds_left is 0 after respawn")
	check(int(soldier.collision_layer) != 0 and int(soldier.collision_mask) != 0, "respawn restores collision")
	check(float(soldier.global_position.y) < 2000.0, "respawn point is above the kill-plane (y=%f)" % float(soldier.global_position.y))
