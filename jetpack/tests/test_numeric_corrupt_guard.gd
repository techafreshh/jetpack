extends SceneTree
## Headless proof that corrupt non-numeric movement.cfg/grenade.cfg values
## degrade on the soldier loader: the guarded _load_config keeps export
## defaults instead of coercing junk (float("CORRUPT") -> 0.0) or faulting,
## the soldier stays alive, and the shared fixtures stay untouched. Corrupt
## fixtures live only in user:// temp copies reloaded via the injectable
## loader paths, so the shared res:// fixtures are never written.
## Run: godot --headless --path jetpack --script res://tests/test_numeric_corrupt_guard.gd

var passed := 0
var failed := 0

const MOVEMENT_CFG := "res://resources/config/movement.cfg"
const GRENADE_CFG := "res://resources/config/grenade.cfg"
const TMP_MOVEMENT := "user://test_numeric_corrupt_movement.cfg"
const TMP_GRENADE := "user://test_numeric_corrupt_grenade.cfg"


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


func _seed_tmp_movement(tmp_path: String) -> ConfigFile:
	var live := ConfigFile.new()
	if live.load(MOVEMENT_CFG) != OK:
		return null
	var cfg := ConfigFile.new()
	for section in live.get_sections():
		for key in live.get_section_keys(section):
			cfg.set_value(section, key, live.get_value(section, key))
	if cfg.save(tmp_path) != OK:
		return null
	return cfg


func _seed_tmp_grenade(tmp_path: String) -> ConfigFile:
	var live := ConfigFile.new()
	if live.load(GRENADE_CFG) != OK:
		return null
	var cfg := ConfigFile.new()
	for section in live.get_sections():
		for key in live.get_section_keys(section):
			cfg.set_value(section, key, live.get_value(section, key))
	if cfg.save(tmp_path) != OK:
		return null
	return cfg


func _write_corrupt_tmp_movement() -> String:
	var cfg := _seed_tmp_movement(TMP_MOVEMENT)
	if cfg == null:
		return ""
	cfg.set_value("movement", "run_speed", "CORRUPT")
	cfg.set_value("movement", "gravity", "CORRUPT")
	cfg.set_value("movement", "thrust_force", [1, 2])
	cfg.set_value("movement", "fuel_max", Vector2(1, 2))
	cfg.set_value("movement", "air_control", true)
	if cfg.save(TMP_MOVEMENT) != OK:
		return ""
	return TMP_MOVEMENT


func _write_corrupt_tmp_grenade() -> String:
	var cfg := _seed_tmp_grenade(TMP_GRENADE)
	if cfg == null:
		return ""
	cfg.set_value("grenade", "throw_speed", "CORRUPT")
	cfg.set_value("grenade", "max_grenades", "CORRUPT")
	if cfg.save(TMP_GRENADE) != OK:
		return ""
	return TMP_GRENADE


func run_tests() -> void:
	await process_frame

	var packed := load("res://scenes/soldier.tscn") as PackedScene
	check(packed != null, "soldier.tscn loads as PackedScene")

	var ready := packed != null

	# Pass 1: corrupt movement numerics keep export defaults, soldier alive.
	if ready:
		var tmp_movement := _write_corrupt_tmp_movement()
		check(tmp_movement != "", "corrupt movement temp cfg saves")
		var soldier := packed.instantiate() as CharacterBody2D
		check(soldier != null, "corrupt-movement soldier instantiates")
		if soldier != null and tmp_movement != "":
			soldier.position = Vector2(500, 400)
			root.add_child(soldier)
			await process_frame
			await process_frame
			soldier.call("_load_config", tmp_movement, GRENADE_CFG)
			check(bool(soldier.get("is_alive")), "corrupt-movement soldier _ready completes alive (no fault)")
			check_close(float(soldier.get("run_speed")), 260.0, 0.0001, "corrupt run_speed keeps default 260.0")
			check_close(float(soldier.get("gravity")), 1200.0, 0.0001, "corrupt gravity keeps default 1200.0")
			check_close(float(soldier.get("thrust_force")), 2600.0, 0.0001, "corrupt thrust_force keeps default 2600.0")
			check_close(float(soldier.get("fuel_max")), 100.0, 0.0001, "corrupt fuel_max keeps default 100.0")
			check_close(float(soldier.get("air_control")), 0.55, 0.0001, "corrupt air_control keeps default 0.55")
			soldier.queue_free()
			await process_frame

	# Pass 2: corrupt grenade numerics keep export defaults, soldier alive.
	if ready:
		var tmp_grenade := _write_corrupt_tmp_grenade()
		check(tmp_grenade != "", "corrupt grenade temp cfg saves")
		var thrower := packed.instantiate() as CharacterBody2D
		check(thrower != null, "corrupt-grenade soldier instantiates")
		if thrower != null and tmp_grenade != "":
			thrower.position = Vector2(500, 400)
			root.add_child(thrower)
			await process_frame
			await process_frame
			thrower.call("_load_config", MOVEMENT_CFG, tmp_grenade)
			check(bool(thrower.get("is_alive")), "corrupt-grenade soldier _ready completes alive (no fault)")
			check_close(float(thrower.get("throw_speed")), 700.0, 0.0001, "corrupt throw_speed keeps default 700.0")
			check(int(thrower.get("grenade_max")) == 2, "corrupt max_grenades keeps default 2 (got %d)" % int(thrower.get("grenade_max")))
			thrower.queue_free()
			await process_frame

	# Shared fixtures untouched: no res:// write ran on any path, the live
	# files still load with their committed values and a control soldier
	# instantiated with no reload reads them live.
	var fresh_movement := ConfigFile.new()
	check(fresh_movement.load(MOVEMENT_CFG) == OK, "shared movement.cfg loads OK")
	check_close(float(fresh_movement.get_value("movement", "run_speed", 0.0)), 260.0, 0.0001, "shared run_speed is 260.0")
	var fresh_grenade := ConfigFile.new()
	check(fresh_grenade.load(GRENADE_CFG) == OK, "shared grenade.cfg loads OK")
	check_close(float(fresh_grenade.get_value("grenade", "throw_speed", 0.0)), 700.0, 0.0001, "shared throw_speed is 700.0")
	check(int(fresh_grenade.get_value("grenade", "max_grenades", 0)) == 2, "shared max_grenades is 2")
	if ready and packed != null:
		var control := packed.instantiate() as CharacterBody2D
		if control != null:
			control.position = Vector2(500, 400)
			root.add_child(control)
			await process_frame
			await process_frame
			check(bool(control.get("is_alive")), "control soldier _ready completes alive")
			check_close(float(control.get("run_speed")), 260.0, 0.0001, "control soldier reads live run_speed")
			check_close(float(control.get("throw_speed")), 700.0, 0.0001, "control soldier reads live throw_speed")
			check(int(control.get("grenade_max")) == 2, "control soldier reads live max_grenades")
			control.queue_free()
			await process_frame

	DirAccess.remove_absolute(TMP_MOVEMENT)
	DirAccess.remove_absolute(TMP_GRENADE)
