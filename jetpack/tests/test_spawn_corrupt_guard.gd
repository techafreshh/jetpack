extends SceneTree
## Headless proof that a corrupt non-Vector2 spawns.cfg value degrades on the
## spawner-less soldier loader: the guarded _load_spawn_config skips corrupt
## entries instead of faulting the typed assignment, respawn falls back to the
## next valid point (or SAFE_FALLBACK when every entry is corrupt). Corrupt
## fixtures live only in user:// temp copies reloaded via the injectable
## loader path, so the shared res:// fixture is never written.
## Run: godot --headless --path jetpack --script res://tests/test_spawn_corrupt_guard.gd

var passed := 0
var failed := 0

const SPAWN_CFG := "res://resources/config/spawns.cfg"
const TMP_SINGLE := "user://test_spawn_corrupt_single.cfg"
const TMP_ALL := "user://test_spawn_corrupt_all.cfg"
const SAFE_FALLBACK := Vector2(200, 300)
const KILL_Y := 2000.0


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


func _seed_tmp_cfg(tmp_path: String) -> ConfigFile:
	var live := ConfigFile.new()
	if live.load(SPAWN_CFG) != OK:
		return null
	var cfg := ConfigFile.new()
	cfg.set_value("respawn", "delay_ticks", live.get_value("respawn", "delay_ticks", 180))
	for i in 8:
		cfg.set_value("spawn%d" % i, "pos", live.get_value("spawn%d" % i, "pos", Vector2.INF))
	if cfg.save(tmp_path) != OK:
		return null
	return cfg


func _write_corrupt_tmp_single() -> String:
	var cfg := _seed_tmp_cfg(TMP_SINGLE)
	if cfg == null:
		return ""
	cfg.set_value("spawn0", "pos", "CORRUPT")
	if cfg.save(TMP_SINGLE) != OK:
		return ""
	return TMP_SINGLE


func _write_corrupt_tmp_all() -> String:
	var cfg := _seed_tmp_cfg(TMP_ALL)
	if cfg == null:
		return ""
	cfg.set_value("spawn0", "pos", "CORRUPT")
	cfg.set_value("spawn1", "pos", 12345)
	cfg.set_value("spawn2", "pos", 3.14)
	cfg.set_value("spawn3", "pos", [1, 2])
	cfg.set_value("spawn4", "pos", "CORRUPT")
	cfg.set_value("spawn5", "pos", 0)
	cfg.set_value("spawn6", "pos", 2.71)
	cfg.set_value("spawn7", "pos", [3, 4])
	if cfg.save(TMP_ALL) != OK:
		return ""
	return TMP_ALL


func run_tests() -> void:
	await process_frame

	check(get_first_node_in_group("spawner") == null, "no spawner node in standalone tree")
	var packed := load("res://scenes/soldier.tscn") as PackedScene
	check(packed != null, "soldier.tscn loads as PackedScene")

	var ready := packed != null

	# Pass 1: a single corrupt entry keeps the remaining valid points.
	if ready:
		var tmp_single := _write_corrupt_tmp_single()
		check(tmp_single != "", "single-corrupt temp cfg saves")
		var soldier := packed.instantiate() as CharacterBody2D
		check(soldier != null, "corrupt-cfg soldier instantiates")
		if soldier != null and tmp_single != "":
			soldier.position = Vector2(500, 400)
			root.add_child(soldier)
			await process_frame
			await process_frame
			soldier.call("_load_spawn_config", tmp_single)
			check(bool(soldier.get("is_alive")), "corrupt-cfg soldier _ready completes alive (no fault)")
			var cached: Array = soldier.get("_spawn_points")
			check(cached.size() == 7, "single-corrupt cache keeps 7 valid points (got %d)" % cached.size())
			var first_ok := cached.size() == 7 and (cached[0] as Vector2) == Vector2(1500, 300)
			check(first_ok, "single-corrupt cache falls through to spawn1")
			check((soldier.call("_config_respawn_point") as Vector2) == Vector2(1500, 300), "single-corrupt reader returns spawn1")
			# Kill with no safe memory: respawn must come from the guarded cache.
			soldier.set("_last_safe_position", Vector2.INF)
			soldier.set("hp", 100.0)
			soldier.call("take_damage", 200.0)
			check(not bool(soldier.get("is_alive")), "single-corrupt lethal damage kills")
			soldier.set("_last_safe_position", Vector2.INF)
			var flip := -1
			for i in 220:
				await physics_frame
				if bool(soldier.get("is_alive")):
					flip = i + 1
					break
			check(flip >= 170 and flip <= 190, "single-corrupt respawn flips is_alive in 170-190 ticks (got %d)" % flip)
			check((soldier.global_position as Vector2) == Vector2(1500, 300), "single-corrupt respawn lands on spawn1")
			check(float(soldier.global_position.y) < KILL_Y, "single-corrupt respawn above kill-plane (y=%f)" % float(soldier.global_position.y))
			check_close(float(soldier.get("hp")), float(soldier.get("max_hp")), 0.0001, "single-corrupt respawn restores full HP")
			check(int(soldier.collision_layer) != 0 and int(soldier.collision_mask) != 0, "single-corrupt respawn restores collision")
			soldier.queue_free()
			await process_frame

	# Pass 2: every entry corrupt degrades to SAFE_FALLBACK.
	if ready:
		var tmp_all := _write_corrupt_tmp_all()
		check(tmp_all != "", "all-corrupt temp cfg saves")
		var flat := packed.instantiate() as CharacterBody2D
		check(flat != null, "all-corrupt soldier instantiates")
		if flat != null and tmp_all != "":
			flat.position = Vector2(500, 400)
			root.add_child(flat)
			await process_frame
			await process_frame
			flat.call("_load_spawn_config", tmp_all)
			check(bool(flat.get("is_alive")), "all-corrupt soldier _ready completes alive (no fault)")
			var empty_cache: Array = flat.get("_spawn_points")
			check(empty_cache.is_empty(), "all-corrupt cache is empty (got %d)" % empty_cache.size())
			check((flat.call("_config_respawn_point") as Vector2) == SAFE_FALLBACK, "all-corrupt reader returns SAFE_FALLBACK")
			flat.set("_last_safe_position", Vector2.INF)
			flat.set("hp", 100.0)
			flat.call("take_damage", 200.0)
			check(not bool(flat.get("is_alive")), "all-corrupt lethal damage kills")
			flat.set("_last_safe_position", Vector2.INF)
			var flip2 := -1
			for i in 220:
				await physics_frame
				if bool(flat.get("is_alive")):
					flip2 = i + 1
					break
			check(flip2 >= 170 and flip2 <= 190, "all-corrupt respawn flips is_alive in 170-190 ticks (got %d)" % flip2)
			check((flat.global_position as Vector2) == SAFE_FALLBACK, "all-corrupt respawn lands on SAFE_FALLBACK")
			check(float(flat.global_position.y) < KILL_Y, "all-corrupt respawn above kill-plane (y=%f)" % float(flat.global_position.y))
			check_close(float(flat.get("hp")), float(flat.get("max_hp")), 0.0001, "all-corrupt respawn restores full HP")
			check(int(flat.collision_layer) != 0 and int(flat.collision_mask) != 0, "all-corrupt respawn restores collision")
			flat.queue_free()
			await process_frame

	# Shared fixture untouched: no restore step ran, the live file still loads
	# with its committed values and a control soldier caches all 8 points.
	var fresh := ConfigFile.new()
	check(fresh.load(SPAWN_CFG) == OK, "shared spawns.cfg loads OK")
	check((fresh.get_value("spawn0", "pos", Vector2.INF) as Vector2) == Vector2(200, 300), "shared spawn0 is Vector2(200, 300)")
	if packed != null:
		var control := packed.instantiate() as CharacterBody2D
		if control != null:
			control.position = Vector2(500, 400)
			root.add_child(control)
			await process_frame
			await process_frame
			var control_cache: Array = control.get("_spawn_points")
			check(control_cache.size() == 8, "shared cache has 8 entries (got %d)" % control_cache.size())
			control.queue_free()
			await process_frame

	DirAccess.remove_absolute(TMP_SINGLE)
	DirAccess.remove_absolute(TMP_ALL)
