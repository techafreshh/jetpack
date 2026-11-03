extends SceneTree
## Headless proof that corrupt non-numeric pickups.cfg values degrade on the
## pickup loader: the guarded _load_config keeps export defaults instead of
## coercing junk (float("CORRUPT") -> 0.0) or faulting, the pad stays valid
## in the tree, and the shared fixture is restored on every path.
## Run: godot --headless --path jetpack --script res://tests/test_pickup_corrupt_guard.gd

var passed := 0
var failed := 0

const PICKUPS_CFG := "res://resources/config/pickups.cfg"


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


func _write_corrupt_pickups() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(PICKUPS_CFG) != OK:
		return false
	cfg.set_value("health", "heal_amount", "CORRUPT")
	cfg.set_value("health", "respawn_s", [1, 2])
	cfg.set_value("weapon", "respawn_s", Vector2(1, 2))
	cfg.set_value("ammo", "respawn_s", true)
	cfg.set_value("weapon", "weapon_id", [1, 2])
	return cfg.save(PICKUPS_CFG) == OK


func _write_weapon_id(bad_id: Variant) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(PICKUPS_CFG) != OK:
		return false
	cfg.set_value("weapon", "weapon_id", bad_id)
	return cfg.save(PICKUPS_CFG) == OK


func make_pickup(p_kind: String):
	var packed := load("res://scenes/pickup.tscn") as PackedScene
	if packed == null:
		return null
	var pad := packed.instantiate() as Area2D
	pad.position = Vector2(2000, -500)
	pad.set("kind", p_kind)
	root.add_child(pad)
	await process_frame
	await process_frame
	return pad


func run_tests() -> void:
	await process_frame

	var backup := _backup_cfg(PICKUPS_CFG)
	check(backup != "", "pickups.cfg backup read")
	var packed := load("res://scenes/pickup.tscn") as PackedScene
	check(packed != null, "pickup.tscn loads as PackedScene")

	var ready := backup != "" and packed != null

	# Pass 1: corrupt health numerics keep export defaults, pad valid in tree.
	if ready:
		check(_write_corrupt_pickups(), "corrupt pickups.cfg saves")
		var pad = await make_pickup("health")
		check(pad != null, "corrupt-cfg health pad instantiates")
		if pad != null:
			check(is_instance_valid(pad), "corrupt-cfg health pad _ready completes valid (no fault)")
			check(pad.is_inside_tree(), "corrupt-cfg health pad stays in tree")
			check_close(float(pad.get("respawn_s")), 15.0, 0.0001, "corrupt health respawn_s keeps default 15.0")
			check_close(float(pad.get("heal_amount")), 30.0, 0.0001, "corrupt heal_amount keeps default 30.0")
			pad.queue_free()
			await process_frame
		check(_restore_cfg(PICKUPS_CFG, backup), "pickups.cfg fixture restored after pass 1")

	# Pass 2: corrupt weapon respawn keeps the export default.
	if ready:
		check(_write_corrupt_pickups(), "corrupt pickups.cfg saves (pass 2)")
		var crate = await make_pickup("weapon")
		check(crate != null, "corrupt-cfg weapon pad instantiates")
		if crate != null:
			check(is_instance_valid(crate), "corrupt-cfg weapon pad _ready completes valid (no fault)")
			check(crate.is_inside_tree(), "corrupt-cfg weapon pad stays in tree")
			check_close(float(crate.get("respawn_s")), 15.0, 0.0001, "corrupt weapon respawn_s keeps default 15.0")
			check(String(crate.get("weapon_id")) == "scatter", "corrupt non-string weapon_id keeps default scatter")
			check(String(crate.call("effective_weapon_id")) == "scatter", "corrupt non-string effective_weapon_id is scatter")
			crate.queue_free()
			await process_frame
		check(_restore_cfg(PICKUPS_CFG, backup), "pickups.cfg fixture restored after pass 2")

	# Pass 3: corrupt unknown-string weapon_id keeps the export default.
	if ready:
		check(_write_weapon_id("CORRUPT"), "corrupt unknown-string weapon_id saves (pass 3)")
		var bad_str = await make_pickup("weapon")
		check(bad_str != null, "bad-string weapon pad instantiates")
		if bad_str != null:
			check(is_instance_valid(bad_str), "bad-string weapon pad _ready completes valid (no fault)")
			check(bad_str.is_inside_tree(), "bad-string weapon pad stays in tree")
			check(String(bad_str.get("weapon_id")) == "scatter", "unknown-string weapon_id keeps default scatter")
			check(String(bad_str.call("effective_weapon_id")) == "scatter", "unknown-string effective_weapon_id is scatter")
			bad_str.queue_free()
			await process_frame
		check(_restore_cfg(PICKUPS_CFG, backup), "pickups.cfg fixture restored after pass 3")

	# Pass 4: every other corrupt weapon_id shape keeps the default.
	if ready:
		for bad in [42, true, Vector2(1, 2), "", "SCATTER", " longbow "]:
			check(_write_weapon_id(bad), "corrupt weapon_id saves (%s)" % str(bad))
			var pad_bad = await make_pickup("weapon")
			check(pad_bad != null, "corrupt-weapon_id pad instantiates (%s)" % str(bad))
			if pad_bad != null:
				check(String(pad_bad.get("weapon_id")) == "scatter", "corrupt weapon_id keeps default (%s)" % str(bad))
				check(String(pad_bad.call("effective_weapon_id")) == "scatter", "corrupt effective_weapon_id is scatter (%s)" % str(bad))
				pad_bad.queue_free()
				await process_frame
		check(_restore_cfg(PICKUPS_CFG, backup), "pickups.cfg fixture restored after pass 4")

	# Pass 5: valid weapon ids still load through the guard.
	if ready:
		for good in ["scatter", "longbow", "ranger_ar"]:
			check(_write_weapon_id(good), "valid weapon_id saves (%s)" % good)
			var pad_good = await make_pickup("weapon")
			check(pad_good != null, "valid-weapon_id pad instantiates (%s)" % good)
			if pad_good != null:
				check(String(pad_good.get("weapon_id")) == good, "valid weapon_id loads (%s)" % good)
				check(String(pad_good.call("effective_weapon_id")) == good, "valid effective_weapon_id loads (%s)" % good)
				pad_good.queue_free()
				await process_frame
		check(_restore_cfg(PICKUPS_CFG, backup), "pickups.cfg fixture restored after pass 5")

	# Fixture restore on every path, then prove restored file loads live.
	if backup != "":
		check(_restore_cfg(PICKUPS_CFG, backup), "pickups.cfg fixture restored")
		var fresh := ConfigFile.new()
		check(fresh.load(PICKUPS_CFG) == OK, "restored pickups.cfg loads OK")
		check_close(float(fresh.get_value("health", "heal_amount", 0.0)), 30.0, 0.0001, "restored heal_amount is 30.0")
		check_close(float(fresh.get_value("health", "respawn_s", 0.0)), 15.0, 0.0001, "restored health respawn_s is 15.0")
		check_close(float(fresh.get_value("weapon", "respawn_s", 0.0)), 12.0, 0.0001, "restored weapon respawn_s is 12.0")
	if ready and packed != null:
		var control = await make_pickup("health")
		if control != null:
			check(is_instance_valid(control), "restored-cfg health pad _ready completes valid")
			check_close(float(control.get("respawn_s")), 15.0, 0.0001, "control pad reads live health respawn_s")
			check_close(float(control.get("heal_amount")), 30.0, 0.0001, "control pad reads live heal_amount")
			control.queue_free()
			await process_frame
