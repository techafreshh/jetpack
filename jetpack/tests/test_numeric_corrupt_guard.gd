extends SceneTree
## Headless proof that corrupt non-numeric movement.cfg/grenade.cfg values
## degrade on the soldier loader: the guarded _load_config keeps export
## defaults instead of coercing junk (float("CORRUPT") -> 0.0) or faulting,
## the soldier stays alive, and both shared fixtures are restored on every
## path before quit.
## Run: godot --headless --path jetpack --script res://tests/test_numeric_corrupt_guard.gd

var passed := 0
var failed := 0

const MOVEMENT_CFG := "res://resources/config/movement.cfg"
const GRENADE_CFG := "res://resources/config/grenade.cfg"


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


func _backup_cfg(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _restore_cfg(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true


func _write_corrupt_movement() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(MOVEMENT_CFG) != OK:
		return false
	cfg.set_value("movement", "run_speed", "CORRUPT")
	cfg.set_value("movement", "gravity", "CORRUPT")
	cfg.set_value("movement", "thrust_force", [1, 2])
	cfg.set_value("movement", "fuel_max", Vector2(1, 2))
	cfg.set_value("movement", "air_control", true)
	return cfg.save(MOVEMENT_CFG) == OK


func _write_corrupt_grenade() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(GRENADE_CFG) != OK:
		return false
	cfg.set_value("grenade", "throw_speed", "CORRUPT")
	cfg.set_value("grenade", "max_grenades", "CORRUPT")
	return cfg.save(GRENADE_CFG) == OK


func run_tests() -> void:
	await process_frame

	var movement_backup := _backup_cfg(MOVEMENT_CFG)
	var grenade_backup := _backup_cfg(GRENADE_CFG)
	check(movement_backup != "", "movement.cfg backup read")
	check(grenade_backup != "", "grenade.cfg backup read")
	var packed := load("res://scenes/soldier.tscn") as PackedScene
	check(packed != null, "soldier.tscn loads as PackedScene")

	var ready := movement_backup != "" and grenade_backup != "" and packed != null

	# Pass 1: corrupt movement numerics keep export defaults, soldier alive.
	if ready:
		check(_write_corrupt_movement(), "corrupt movement.cfg saves")
		var soldier := packed.instantiate() as CharacterBody2D
		check(soldier != null, "corrupt-movement soldier instantiates")
		if soldier != null:
			soldier.position = Vector2(500, 400)
			root.add_child(soldier)
			await process_frame
			await process_frame
			check(bool(soldier.get("is_alive")), "corrupt-movement soldier _ready completes alive (no fault)")
			check_close(float(soldier.get("run_speed")), 260.0, 0.0001, "corrupt run_speed keeps default 260.0")
			check_close(float(soldier.get("gravity")), 1200.0, 0.0001, "corrupt gravity keeps default 1200.0")
			check_close(float(soldier.get("thrust_force")), 2600.0, 0.0001, "corrupt thrust_force keeps default 2600.0")
			check_close(float(soldier.get("fuel_max")), 100.0, 0.0001, "corrupt fuel_max keeps default 100.0")
			check_close(float(soldier.get("air_control")), 0.55, 0.0001, "corrupt air_control keeps default 0.55")
			soldier.queue_free()
			await process_frame
		check(_restore_cfg(MOVEMENT_CFG, movement_backup), "movement.cfg fixture restored after pass 1")

	# Pass 2: corrupt grenade numerics keep export defaults, soldier alive.
	if ready:
		check(_write_corrupt_grenade(), "corrupt grenade.cfg saves")
		var thrower := packed.instantiate() as CharacterBody2D
		check(thrower != null, "corrupt-grenade soldier instantiates")
		if thrower != null:
			thrower.position = Vector2(500, 400)
			root.add_child(thrower)
			await process_frame
			await process_frame
			check(bool(thrower.get("is_alive")), "corrupt-grenade soldier _ready completes alive (no fault)")
			check_close(float(thrower.get("throw_speed")), 700.0, 0.0001, "corrupt throw_speed keeps default 700.0")
			check(int(thrower.get("grenade_max")) == 2, "corrupt max_grenades keeps default 2 (got %d)" % int(thrower.get("grenade_max")))
			thrower.queue_free()
			await process_frame
		check(_restore_cfg(GRENADE_CFG, grenade_backup), "grenade.cfg fixture restored after pass 2")

	# Fixture restore on every path, then prove restored files load live.
	if movement_backup != "":
		check(_restore_cfg(MOVEMENT_CFG, movement_backup), "movement.cfg fixture restored")
		var fresh_movement := ConfigFile.new()
		check(fresh_movement.load(MOVEMENT_CFG) == OK, "restored movement.cfg loads OK")
		check_close(float(fresh_movement.get_value("movement", "run_speed", 0.0)), 260.0, 0.0001, "restored run_speed is 260.0")
	if grenade_backup != "":
		check(_restore_cfg(GRENADE_CFG, grenade_backup), "grenade.cfg fixture restored")
		var fresh_grenade := ConfigFile.new()
		check(fresh_grenade.load(GRENADE_CFG) == OK, "restored grenade.cfg loads OK")
		check_close(float(fresh_grenade.get_value("grenade", "throw_speed", 0.0)), 700.0, 0.0001, "restored throw_speed is 700.0")
		check(int(fresh_grenade.get_value("grenade", "max_grenades", 0)) == 2, "restored max_grenades is 2")
	if ready and packed != null:
		var control := packed.instantiate() as CharacterBody2D
		if control != null:
			control.position = Vector2(500, 400)
			root.add_child(control)
			await process_frame
			await process_frame
			check(bool(control.get("is_alive")), "restored-cfg soldier _ready completes alive")
			check_close(float(control.get("run_speed")), 260.0, 0.0001, "control soldier reads live run_speed")
			check_close(float(control.get("throw_speed")), 700.0, 0.0001, "control soldier reads live throw_speed")
			check(int(control.get("grenade_max")) == 2, "control soldier reads live max_grenades")
			control.queue_free()
			await process_frame
