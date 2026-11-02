extends SceneTree
## Headless proof that the spawner caches spawns.cfg once at ready: the cache
## matches spawns.cfg after _ready, the per-death readers honor the cache
## (sentinel overrides despite live markers and disk contents), a failed load
## keeps the marker fallback, and spawner-present deaths keep foe-aware
## placement with 170-190-tick timing, full-HP restore, above-plane position,
## and restored collision across 2 cycles. No ConfigFile access happens on
## the per-death path.
## Run: godot --headless --path jetpack --script res://tests/test_spawner_cache.gd

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


func run_tests() -> void:
	await process_frame
	check(get_first_node_in_group("spawner") == null, "no spawner node in standalone tree")

	var cfg := ConfigFile.new()
	check(cfg.load("res://resources/config/spawns.cfg") == OK, "spawns.cfg loads")
	var expected: Array[Vector2] = []
	for i in 8:
		expected.append(cfg.get_value("spawn%d" % i, "pos", Vector2.INF))
	check(expected.size() == 8, "cfg yields 8 spawn points")

	# Cache matches spawns.cfg after _ready.
	var spawner := Spawner.new()
	check(spawner != null, "Spawner instantiates")
	root.add_child(spawner)
	await process_frame
	await process_frame
	check(spawner.is_in_group("spawner"), "spawner joins spawner group")
	check(bool(spawner.get("_has_cfg")), "spawner cache flag set after _ready")
	var cached: Array = spawner.get("_cfg_points")
	check(cached.size() == 8, "spawner cache has 8 entries (got %d)" % cached.size())
	if cached.size() == 8:
		var order_ok := true
		for i in 8:
			if cached[i] != expected[i]:
				order_ok = false
		check(order_ok, "spawner cache matches spawns.cfg after _ready")
		check_close((cached[0] as Vector2).x, 200.0, 0.5, "spawner cached spawn0 x is 200")
		check_close((cached[0] as Vector2).y, 300.0, 0.5, "spawner cached spawn0 y is 300")

	# Live greybox markers: the fallback the cache merges over.
	var m0 := Marker2D.new()
	m0.name = "SpawnA"
	m0.position = Vector2(11, 22)
	root.add_child(m0)
	var m1 := Marker2D.new()
	m1.name = "SpawnB"
	m1.position = Vector2(33, 44)
	root.add_child(m1)
	var markers: Array[Vector2] = spawner.collect_markers()
	check(markers.size() == 2, "collect_markers finds 2 Spawn* markers (got %d)" % markers.size())

	# Readers honor the cache: sentinel override despite disk and markers.
	var sentinel: Array[Vector2] = []
	for i in 8:
		sentinel.append(Vector2(900 + i, 100 + i))
	spawner.set("_cfg_points", sentinel)
	var via_load: Array = spawner.call("load_points", markers)
	var load_ok := via_load.size() == 8
	if load_ok:
		for i in 8:
			if via_load[i] != sentinel[i]:
				load_ok = false
	check(load_ok, "load_points returns sentinel cache values, not disk/markers")
	var via_spawn: Array = spawner.call("spawn_points")
	var spawn_ok := via_spawn.size() == 8
	if spawn_ok:
		for i in 8:
			if via_spawn[i] != sentinel[i]:
				spawn_ok = false
	check(spawn_ok, "spawn_points returns sentinel cache values despite disk contents")

	# Partial cache: INF entries fall back to the per-index marker.
	var partial: Array[Vector2] = []
	for i in 8:
		partial.append(sentinel[i] if i % 2 == 0 else Vector2.INF)
	spawner.set("_cfg_points", partial)
	var merged: Array = spawner.call("load_points", markers)
	var merge_ok := merged.size() == 8
	if merge_ok:
		for i in 8:
			var want: Vector2 = sentinel[i] if i % 2 == 0 else (markers[i] if i < markers.size() else Vector2.ZERO)
			if merged[i] != want:
				merge_ok = false
	check(merge_ok, "INF cache entries fall back to per-index markers")

	# Failed load keeps the marker fallback.
	spawner.set("_has_cfg", false)
	var fb_explicit: Array[Vector2] = [Vector2(7, 8), Vector2(9, 10)]
	var fb_back: Array = spawner.call("load_points", fb_explicit)
	var fb_ok := fb_back.size() == fb_explicit.size()
	if fb_ok:
		for i in fb_explicit.size():
			if fb_back[i] != fb_explicit[i]:
				fb_ok = false
	check(fb_ok, "missing-file flag yields marker fallback")
	var spawn_fb: Array = spawner.call("spawn_points")
	check(spawn_fb.size() == 2 and spawn_fb[0] == Vector2(11, 22) and spawn_fb[1] == Vector2(33, 44), "spawn_points with failed load returns scene markers")

	# Restore the ready cache and drop the markers before the death cycles.
	spawner.call("_load_config")
	check(bool(spawner.get("_has_cfg")), "cache reload restores loaded flag")
	m0.queue_free()
	m1.queue_free()
	await process_frame
	var pts: Array = spawner.call("spawn_points")
	check(pts.size() == 8, "restored spawn_points yields 8 cfg points")

	# Spawner-present deaths: victim respawns foe-aware across 2 cycles.
	var packed := load("res://scenes/soldier.tscn") as PackedScene
	check(packed != null, "soldier.tscn loads as PackedScene")
	if packed == null:
		spawner.queue_free()
		return
	var foe := packed.instantiate() as CharacterBody2D
	root.add_child(foe)
	var victim := packed.instantiate() as CharacterBody2D
	root.add_child(victim)
	await process_frame
	await process_frame
	foe.set_physics_process(false)
	foe.global_position = pts[0]
	check(bool(foe.get("is_alive")), "foe starts alive")
	check(bool(victim.get("is_alive")), "victim starts alive")
	var foes0: Array = spawner.call("live_enemy_positions", victim)
	check(foes0.size() == 1, "foe alone counts with victim excluded (got %d)" % foes0.size())
	for cycle in 2:
		victim.global_position = pts[1]
		victim.set("velocity", Vector2.ZERO)
		victim.set("hp", 100.0)
		foe.global_position = pts[0]
		victim.call("take_damage", 200.0)
		check(not bool(victim.get("is_alive")), "cycle %d: lethal damage kills" % cycle)
		var delay: int = victim.get("respawn_ticks_left")
		check(delay >= 170 and delay <= 190, "cycle %d: countdown starts in 170-190 (got %d)" % [cycle, delay])
		var flip := -1
		for i in 220:
			await physics_frame
			if bool(victim.get("is_alive")):
				flip = i + 1
				break
		check(flip >= 170 and flip <= 190, "cycle %d: respawn flips is_alive in 170-190 ticks (got %d)" % [cycle, flip])
		var cur_pts: Array = spawner.call("spawn_points")
		var cur_foes: Array = spawner.call("live_enemy_positions", victim)
		var typed_pts: Array[Vector2] = []
		for p in cur_pts:
			typed_pts.append(p)
		var typed_foes: Array[Vector2] = []
		for e in cur_foes:
			typed_foes.append(e)
		var idx := Spawner.choose_spawn(typed_pts, typed_foes)
		check(idx != 0, "cycle %d: camper on spawn 0 avoided (got %d)" % [cycle, idx])
		var best_d := -1.0
		for i in typed_pts.size():
			best_d = maxf(best_d, Spawner.nearest_enemy_dist(typed_pts[i], typed_foes))
		check_close(Spawner.nearest_enemy_dist(typed_pts[idx], typed_foes), best_d, 0.01, "cycle %d: chosen spawn maximizes nearest-enemy distance" % cycle)
		check((victim.global_position as Vector2).distance_to(typed_pts[idx]) < 5.0, "cycle %d: victim respawns at foe-aware spawn" % cycle)
		check_close(float(victim.get("hp")), float(victim.get("max_hp")), 0.0001, "cycle %d: respawn restores full HP" % cycle)
		check(float(victim.global_position.y) < 2000.0, "cycle %d: respawn point above kill-plane (y=%f)" % [cycle, float(victim.global_position.y)])
		check(int(victim.collision_layer) != 0 and int(victim.collision_mask) != 0, "cycle %d: respawn restores collision" % cycle)

	foe.queue_free()
	victim.queue_free()
	spawner.queue_free()
