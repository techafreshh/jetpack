extends SceneTree
## Headless proof that corrupt non-numeric grenade.cfg values degrade on the
## grenade loader: the guarded _load_config keeps export defaults instead of
## coercing junk (float("CORRUPT") -> 0.0) or faulting, the grenade readies
## alive in the tree, and the shared fixture is restored on every path.
## Run: godot --headless --path jetpack --script res://tests/test_grenade_corrupt_guard.gd

var passed := 0
var failed := 0

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


func _write_corrupt_grenade() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(GRENADE_CFG) != OK:
		return false
	cfg.set_value("grenade", "fuse_time", "CORRUPT")
	cfg.set_value("grenade", "blast_radius", [1, 2])
	cfg.set_value("grenade", "max_damage", Vector2(1, 2))
	cfg.set_value("grenade", "knockback_max", true)
	return cfg.save(GRENADE_CFG) == OK


func run_tests() -> void:
	await process_frame

	var grenade_backup := _backup_cfg(GRENADE_CFG)
	check(grenade_backup != "", "grenade.cfg backup read")
	var packed := load("res://scenes/grenade.tscn") as PackedScene
	check(packed != null, "grenade.tscn loads as PackedScene")

	var ready := grenade_backup != "" and packed != null

	# Pass 1: corrupt grenade numerics keep export defaults, node alive.
	if ready:
		check(_write_corrupt_grenade(), "corrupt grenade.cfg saves")
		var shell := packed.instantiate() as RigidBody2D
		check(shell != null, "corrupt-cfg grenade instantiates")
		if shell != null:
			root.add_child(shell)
			await process_frame
			await process_frame
			check(is_instance_valid(shell), "corrupt-cfg grenade _ready completes valid (no fault)")
			check(shell.is_inside_tree(), "corrupt-cfg grenade stays in tree")
			check_close(float(shell.get("fuse_time")), 2.5, 0.0001, "corrupt fuse_time keeps default 2.5")
			check_close(float(shell.get("blast_radius")), 180.0, 0.0001, "corrupt blast_radius keeps default 180.0")
			check_close(float(shell.get("max_damage")), 60.0, 0.0001, "corrupt max_damage keeps default 60.0")
			check_close(float(shell.get("knockback_max")), 900.0, 0.0001, "corrupt knockback_max keeps default 900.0")
			shell.queue_free()
			await process_frame
		check(_restore_cfg(GRENADE_CFG, grenade_backup), "grenade.cfg fixture restored after pass 1")

	# Fixture restore on every path, then prove restored file loads live.
	if grenade_backup != "":
		check(_restore_cfg(GRENADE_CFG, grenade_backup), "grenade.cfg fixture restored")
		var fresh := ConfigFile.new()
		check(fresh.load(GRENADE_CFG) == OK, "restored grenade.cfg loads OK")
		check_close(float(fresh.get_value("grenade", "fuse_time", 0.0)), 2.5, 0.0001, "restored fuse_time is 2.5")
		check_close(float(fresh.get_value("grenade", "blast_radius", 0.0)), 180.0, 0.0001, "restored blast_radius is 180.0")
		check_close(float(fresh.get_value("grenade", "max_damage", 0.0)), 60.0, 0.0001, "restored max_damage is 60.0")
		check_close(float(fresh.get_value("grenade", "knockback_max", 0.0)), 900.0, 0.0001, "restored knockback_max is 900.0")
	if ready and packed != null:
		var control := packed.instantiate() as RigidBody2D
		if control != null:
			root.add_child(control)
			await process_frame
			await process_frame
			check(is_instance_valid(control), "restored-cfg grenade _ready completes valid")
			check_close(float(control.get("fuse_time")), 2.5, 0.0001, "control grenade reads live fuse_time")
			check_close(float(control.get("blast_radius")), 180.0, 0.0001, "control grenade reads live blast_radius")
			check_close(float(control.get("max_damage")), 60.0, 0.0001, "control grenade reads live max_damage")
			check_close(float(control.get("knockback_max")), 900.0, 0.0001, "control grenade reads live knockback_max")
			control.queue_free()
			await process_frame
