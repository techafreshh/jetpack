extends SceneTree
## Headless behavior tests for damage, death, and enemy-aware respawn: exact
## HP math, one-shot death, 170-190 tick respawn, spawner argmax with a
## camper on spawn 0, knockback, death idempotence, and spawns.cfg contents.
## Run: godot --headless --path jetpack --script res://tests/test_health_respawn.gd

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

	# (a) Pure HP math is exact.
	check_close(Health.apply_damage(100.0, 12.0), 88.0, 0.0001, "Health.apply_damage 100-12 is 88")
	check_close(Health.apply_damage(88.0, 12.0), 76.0, 0.0001, "Health.apply_damage 88-12 is 76")
	check_close(Health.apply_damage(5.0, 12.0), 0.0, 0.0001, "Health.apply_damage clamps at 0")
	check_close(Health.heal_to(50.0, 100.0, 30.0), 80.0, 0.0001, "Health.heal_to 50+30 is 80")
	check_close(Health.heal_to(90.0, 100.0, 30.0), 100.0, 0.0001, "Health.heal_to clamps at max")
	check(int(Health.RESPAWN_TICKS) == 180, "Health.RESPAWN_TICKS is 180")

	# (b) spawns.cfg loads 8 Vector2 points with delay 180.
	var cfg := ConfigFile.new()
	check(cfg.load("res://resources/config/spawns.cfg") == OK, "spawns.cfg loads")
	check(int(cfg.get_value("respawn", "delay_ticks", 0)) == 180, "cfg delay_ticks is 180")
	var pts: Array[Vector2] = []
	for i in 8:
		var v: Vector2 = cfg.get_value("spawn%d" % i, "pos", Vector2.INF)
		pts.append(v)
	check(pts.size() == 8, "cfg yields 8 spawn points")
	var all_finite := true
	for p in pts:
		if p == Vector2.INF:
			all_finite = false
	check(all_finite, "all 8 cfg points are Vector2")
	check_close(pts[0].x, 200.0, 0.5, "spawn0 x is 200")
	check_close(pts[0].y, 300.0, 0.5, "spawn0 y is 300")

	# (c) Spawner pure function: camper on spawn 0 is avoided, max distance wins.
	var foes: Array[Vector2] = [pts[0]]
	var idx := Spawner.choose_spawn(pts, foes)
	check(idx != 0, "camper on spawn 0 is avoided (got %d)" % idx)
	var best_d := -1.0
	for i in pts.size():
		best_d = maxf(best_d, Spawner.nearest_enemy_dist(pts[i], foes))
	check_close(Spawner.nearest_enemy_dist(pts[idx], foes), best_d, 0.01, "chosen spawn maximizes nearest-enemy distance")
	check(Spawner.choose_spawn(pts, []) == 0, "no enemies picks index 0")
	check(Spawner.choose_spawn([], foes) == -1, "no spawns returns -1")
	# Tie breaks to the lowest index.
	var pair: Array[Vector2] = [Vector2(0, 0), Vector2(0, 0)]
	check(Spawner.choose_spawn(pair, foes) == 0, "distance tie breaks to index 0")

	# (d) Soldier damage/death/respawn lifecycle headless.
	var packed := load("res://scenes/soldier.tscn") as PackedScene
	check(packed != null, "soldier.tscn loads as PackedScene")
	if packed == null:
		return
	var soldier := packed.instantiate() as CharacterBody2D
	check(soldier != null, "soldier.tscn instantiates CharacterBody2D")
	if soldier == null:
		return
	soldier.position = Vector2(0, -40)
	root.add_child(soldier)
	await process_frame
	await process_frame
	check(bool(soldier.get("is_alive")), "fresh soldier is_alive")
	check(int(soldier.get("respawn_ticks_left")) == 0, "fresh soldier respawn_ticks_left is 0")

	# Exact 76 after two 12-dmg hits.
	soldier.set("hp", 100.0)
	soldier.call("take_damage", 12.0)
	soldier.call("take_damage", 12.0)
	check_close(float(soldier.get("hp")), 76.0, 0.0001, "two 12-dmg hits leave exactly 76")

	# Knockback adds the impulse to velocity.
	soldier.set("velocity", Vector2.ZERO)
	soldier.call("apply_knockback", Vector2(300.0, -200.0))
	check_close((soldier.get("velocity") as Vector2).x, 300.0, 0.01, "knockback sets vx")
	check_close((soldier.get("velocity") as Vector2).y, -200.0, 0.01, "knockback sets vy")

	# Lethal damage: one died, is_alive flips, then respawn in 170-190 ticks.
	var died_count := [0]
	var respawned_count := [0]
	soldier.connect("died", func() -> void: died_count[0] += 1)
	soldier.connect("respawned", func() -> void: respawned_count[0] += 1)
	soldier.set("hp", 100.0)
	soldier.set("velocity", Vector2.ZERO)
	soldier.call("take_damage", 200.0)
	check(not bool(soldier.get("is_alive")), "lethal damage clears is_alive")
	check(died_count[0] == 1, "died emitted exactly once (got %d)" % died_count[0])
	check(not soldier.is_in_group("damageable"), "dead soldier leaves damageable group")
	var dummy_packed := load("res://scenes/dummy.tscn") as PackedScene
	check(dummy_packed != null, "dummy.tscn loads for group-count probe")
	var probe_dummy := dummy_packed.instantiate() as StaticBody2D
	root.add_child(probe_dummy)
	await process_frame
	await process_frame
	var live_set := get_nodes_in_group("damageable")
	check(probe_dummy in live_set, "group enumeration sees live dummy beside corpse")
	check(not (soldier in live_set), "group enumeration hides dead soldier corpse")
	probe_dummy.queue_free()
	await process_frame
	check(str(soldier.get("last_death_cause")) == "damage", "lethal damage records cause damage")
	check_close(float(soldier.get("hp")), 0.0, 0.0001, "lethal damage leaves hp at 0")
	var delay: int = soldier.get("respawn_ticks_left")
	check(delay >= 170 and delay <= 190, "respawn countdown starts in 170-190 (got %d)" % delay)
	# Post-death hits are ignored.
	soldier.call("take_damage", 50.0)
	check(died_count[0] == 1, "post-death take_damage emits no second died")
	check_close(float(soldier.get("hp")), 0.0, 0.0001, "post-death hp stays 0")
	check(not bool(soldier.call("throw_grenade")), "dead soldier cannot throw grenades")
	# Corpse knockback is a silent no-op: velocity stays frozen.
	soldier.set("velocity", Vector2.ZERO)
	soldier.call("apply_knockback", Vector2(300.0, -200.0))
	var corpse_vel := soldier.get("velocity") as Vector2
	check(corpse_vel.length() < 0.01, "post-death knockback leaves velocity frozen (drift %f)" % corpse_vel.length())
	check(died_count[0] == 1, "post-death knockback emits no second died")
	check(not bool(soldier.get("is_alive")), "post-death knockback keeps is_alive false")
	var respawn_tick := -1
	for i in 220:
		await physics_frame
		if bool(soldier.get("is_alive")):
			respawn_tick = i + 1
			break
	check(respawn_tick >= 170 and respawn_tick <= 190, "respawn flips is_alive in 170-190 ticks (got %d)" % respawn_tick)
	check(respawned_count[0] == 1, "respawned emitted exactly once (got %d)" % respawned_count[0])
	check(soldier.is_in_group("damageable"), "respawned soldier rejoins damageable group")
	check_close(float(soldier.get("hp")), float(soldier.get("max_hp")), 0.0001, "respawn restores full HP")
	check_close(float(soldier.call("respawn_seconds_left")), 0.0, 0.01, "respawn_seconds_left is 0 after respawn")
	check(int(soldier.collision_layer) != 0 and int(soldier.collision_mask) != 0, "respawn restores collision")
	# Soldier fights again after respawn.
	soldier.call("take_damage", 12.0)
	check_close(float(soldier.get("hp")), 88.0, 0.0001, "post-respawn damage works (88)")
	soldier.queue_free()
