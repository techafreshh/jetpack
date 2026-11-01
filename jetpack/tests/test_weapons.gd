extends SceneTree
## Headless behavior tests for data-driven weapons: .tres values load
## parsed-correct, ammo/reload math and zoom hold per gun, and weapon
## scripts carry no per-gun name branches.
## Run: godot --headless --path jetpack --script res://tests/test_weapons.gd

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


func make_weapon():
	var scr := load("res://scripts/weapons/weapon.gd") as Script
	check(scr != null, "weapon.gd loads as Script")
	if scr == null:
		return null
	return scr.new()


func run_tests() -> void:
	await process_frame

	# (a) Resource values load parsed-correct.
	var ranger := load("res://resources/weapons/ranger_ar.tres") as WeaponResource
	var scatter := load("res://resources/weapons/scatter.tres") as WeaponResource
	var longbow := load("res://resources/weapons/longbow.tres") as WeaponResource
	check(ranger != null, "ranger_ar.tres loads as WeaponResource")
	check(scatter != null, "scatter.tres loads as WeaponResource")
	check(longbow != null, "longbow.tres loads as WeaponResource")
	if ranger == null or scatter == null or longbow == null:
		return
	check(String(ranger.get("display_name")) != "", "ranger display_name non-empty")
	check(String(scatter.get("display_name")) != "", "scatter display_name non-empty")
	check(String(longbow.get("display_name")) != "", "longbow display_name non-empty")
	check(int(ranger.get("mag_size")) == 30, "ranger mag_size == 30")
	check(int(scatter.get("pellet_count")) == 8, "scatter pellet_count == 8")
	check_close(float(longbow.get("zoom")), 2.5, 0.001, "longbow zoom == 2.5")
	check(int(scatter.get("projectile")) == 1, "scatter projectile is pellet kind")
	check(int(ranger.get("projectile")) == 0, "ranger projectile is hitscan kind")

	# (b) Ammo/reload math and zoom per gun through the generic driver.
	var cases := [ranger, scatter, longbow]
	var zooms := [1.0, 1.0, 2.5]
	for i in cases.size():
		var res: WeaponResource = cases[i]
		var w = make_weapon()
		if w == null:
			return
		w.call("equip", res)
		check_close(float(w.call("get_zoom")), float(zooms[i]), 0.001, "get_zoom matches stats")
		check(int(w.get("ammo")) == int(res.get("mag_size")), "equip fills mag")
		check(int(w.get("reserve_left")) == int(res.get("reserve")), "equip fills reserve")
		check(bool(w.call("can_fire")), "fresh mag can_fire")
		var mag: int = int(res.get("mag_size"))
		for s in mag:
			check(bool(w.call("consume_shot")), "consume_shot succeeds while ammo lasts")
		check(int(w.get("ammo")) == 0, "consume_shot drains mag to empty")
		check(not bool(w.call("consume_shot")), "consume_shot fails when empty")
		check(not bool(w.call("can_fire")), "empty mag cannot fire")
		var reserve_before: int = int(w.get("reserve_left"))
		check(bool(w.call("reload")), "reload succeeds with reserve")
		check(int(w.get("ammo")) == mag, "reload refills mag")
		check(int(w.get("reserve_left")) == reserve_before - mag, "reload transfers from reserve")
		check(bool(w.call("can_fire")), "refilled mag can_fire")
		check(not bool(w.call("reload")), "reload fails when mag full")
		w.free()

	# Null-stats driver no-ops safely.
	var bare = make_weapon()
	if bare != null:
		check(not bool(bare.call("can_fire")), "null stats cannot fire")
		check(not bool(bare.call("consume_shot")), "null stats consume fails")
		check(not bool(bare.call("reload")), "null stats reload fails")
		check_close(float(bare.call("get_zoom")), 1.0, 0.001, "null stats zoom is 1.0")
		bare.free()

	# (c) No per-gun name branches in weapon scripts.
	var names := ["Ranger", "Scatter", "Longbow"]
	for path in ["res://scripts/weapons/weapon.gd", "res://scripts/weapons/weapon_resource.gd"]:
		var fa := FileAccess.open(path, FileAccess.READ)
		check(fa != null, "%s readable" % path)
		if fa == null:
			continue
		var text := fa.get_as_text()
		fa.close()
		for n in names:
			check(not text.contains(n), "%s has no %s branch" % [path.get_file(), n])

	# (d) Default-equip path is live: soldier spawns with a Weapon on ranger data.
	var packed := load("res://scenes/soldier.tscn") as PackedScene
	check(packed != null, "soldier.tscn loads as PackedScene")
	if packed != null:
		var soldier := packed.instantiate() as CharacterBody2D
		check(soldier != null, "soldier.tscn instantiates CharacterBody2D")
		if soldier != null:
			root.add_child(soldier)
			await process_frame
			await process_frame
			var weapon = soldier.get_node_or_null("Weapon")
			check(weapon != null, "soldier has Weapon child")
			if weapon != null:
				check(weapon.get("stats") != null, "default Weapon has stats equipped")
				if weapon.get("stats") != null:
					check(int(weapon.get("stats").get("mag_size")) == 30, "default Weapon is ranger data")
			soldier.queue_free()
			await process_frame
