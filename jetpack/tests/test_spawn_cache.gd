extends SceneTree
## Headless proof that the soldier caches spawn config once at ready: the
## cache matches spawns.cfg after _ready, both readers honor the cache
## (sentinel overrides), and rapid successive deaths keep 170-190-tick
## timing with full-HP respawns above the kill-plane. No ConfigFile access
## happens on the per-death path.
## Run: godot --headless --path jetpack --script res://tests/test_spawn_cache.gd

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

	# Cache matches spawns.cfg after _ready.
	var cfg := ConfigFile.new()
	check(cfg.load("res://resources/config/spawns.cfg") == OK, "spawns.cfg loads")
	var expected_delay := int(cfg.get_value("respawn", "delay_ticks", 0))
	var expected: Array[Vector2] = []
	for i in 8:
		expected.append(cfg.get_value("spawn%d" % i, "pos", Vector2.INF))

	var soldier := packed.instantiate() as CharacterBody2D
	check(soldier != null, "soldier.tscn instantiates CharacterBody2D")
	if soldier == null:
		return
	soldier.position = Vector2(0, -40)
	root.add_child(soldier)
	await process_frame
	await process_frame
	check(int(soldier.get("_spawn_delay_ticks")) == expected_delay, "cached delay matches spawns.cfg (got %d)" % int(soldier.get("_spawn_delay_ticks")))
	check(int(soldier.get("_spawn_delay_ticks")) == int(Health.RESPAWN_TICKS), "cached delay is Health.RESPAWN_TICKS")
	var cached: Array = soldier.get("_spawn_points")
	check(cached.size() == 8, "cached spawn points has 8 entries (got %d)" % cached.size())
	if cached.size() == 8 and expected.size() == 8:
		var order_ok := true
		for i in 8:
			if cached[i] != expected[i]:
				order_ok = false
		check(order_ok, "cached spawn points preserve spawns.cfg order")
		check_close((cached[0] as Vector2).x, 200.0, 0.5, "cached spawn0 x is 200")
		check_close((cached[0] as Vector2).y, 300.0, 0.5, "cached spawn0 y is 300")

	# Readers honor the cache: sentinel delay override.
	soldier.set("_spawn_delay_ticks", 42)
	check(int(soldier.call("_respawn_delay_ticks")) == 42, "delay reader returns sentinel 42 from cache")

	# Readers honor the cache: single known above-plane point.
	var sentinel := Vector2(111, 222)
	var single: Array[Vector2] = [sentinel]
	soldier.set("_spawn_points", single)
	check((soldier.call("_config_respawn_point") as Vector2) == sentinel, "point reader returns sentinel cache point")
	soldier.set("_spawn_points", [] as Array[Vector2])
	check((soldier.call("_config_respawn_point") as Vector2) == Vector2(200, 300), "empty cache falls back to SAFE_FALLBACK")

	# Full respawn path lands on the cached point with no spawner and no safe memory.
	soldier.set("_spawn_points", single)
	soldier.set("_last_safe_position", Vector2.INF)
	soldier.set("hp", 100.0)
	soldier.call("take_damage", 200.0)
	check(not bool(soldier.get("is_alive")), "sentinel soldier dies from lethal damage")
	soldier.set("_last_safe_position", Vector2.INF)
	var sentinel_tick := -1
	for i in 220:
		await physics_frame
		if bool(soldier.get("is_alive")):
			sentinel_tick = i + 1
			break
	check(sentinel_tick >= 1 and sentinel_tick <= 220, "sentinel soldier respawns (got %d)" % sentinel_tick)
	check((soldier.global_position as Vector2) == sentinel, "respawn lands exactly on cached point")
	check_close(float(soldier.get("hp")), float(soldier.get("max_hp")), 0.0001, "sentinel respawn restores full HP")
	soldier.queue_free()

	# Rapid successive deaths keep 170-190-tick timing on one cached soldier.
	var duelist := packed.instantiate() as CharacterBody2D
	check(duelist != null, "second soldier instantiates CharacterBody2D")
	if duelist == null:
		return
	duelist.position = Vector2(0, -40)
	root.add_child(duelist)
	await process_frame
	await process_frame
	var died_count := [0]
	var respawned_count := [0]
	duelist.connect("died", func() -> void: died_count[0] += 1)
	duelist.connect("respawned", func() -> void: respawned_count[0] += 1)
	for cycle in 3:
		duelist.set("hp", 100.0)
		duelist.set("velocity", Vector2.ZERO)
		duelist.call("take_damage", 200.0)
		check(not bool(duelist.get("is_alive")), "cycle %d: lethal damage kills" % cycle)
		var delay: int = duelist.get("respawn_ticks_left")
		check(delay >= 170 and delay <= 190, "cycle %d: countdown starts in 170-190 (got %d)" % [cycle, delay])
		var flip := -1
		for i in 220:
			await physics_frame
			if bool(duelist.get("is_alive")):
				flip = i + 1
				break
		check(flip >= 170 and flip <= 190, "cycle %d: respawn flips is_alive in 170-190 ticks (got %d)" % [cycle, flip])
		check(died_count[0] == cycle + 1, "cycle %d: died exactly once (got %d)" % [cycle, died_count[0]])
		check(respawned_count[0] == cycle + 1, "cycle %d: respawned exactly once (got %d)" % [cycle, respawned_count[0]])
		check_close(float(duelist.get("hp")), float(duelist.get("max_hp")), 0.0001, "cycle %d: respawn restores full HP" % cycle)
		check(float(duelist.global_position.y) < 2000.0, "cycle %d: respawn point above kill-plane (y=%f)" % [cycle, float(duelist.global_position.y)])
		check(int(duelist.collision_layer) != 0 and int(duelist.collision_mask) != 0, "cycle %d: respawn restores collision" % cycle)
	duelist.queue_free()
