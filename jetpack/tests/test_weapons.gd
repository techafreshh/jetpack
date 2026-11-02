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
			w.set("_cooldown", 0.0)
			check(bool(w.call("consume_shot")), "consume_shot succeeds while ammo lasts")
		check(int(w.get("ammo")) == 0, "consume_shot drains mag to empty")
		check(not bool(w.call("consume_shot")), "consume_shot fails when empty")
		check(not bool(w.call("can_fire")), "empty mag cannot fire")
		var reserve_before: int = int(w.get("reserve_left"))
		check(bool(w.call("reload")), "reload succeeds with reserve")
		check(int(w.get("ammo")) == mag, "reload refills mag")
		check(int(w.get("reserve_left")) == reserve_before - mag, "reload transfers from reserve")
		w.set("_cooldown", 0.0)
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

	# Cooldown rest invariant: a null-stats gun never ticks its gate, and
	# an equipped idle gun clamps back to zero instead of drifting negative.
	var idle_bare = make_weapon()
	if idle_bare != null:
		root.add_child(idle_bare)
		Input.action_release("fire")
		await wait_physics(60)
		check_close(float(idle_bare.get("_cooldown")), 0.0, 0.0001, "null-stats gun holds _cooldown at 0.0")
		root.remove_child(idle_bare)
		idle_bare.free()
	var idle_armed = make_weapon()
	if idle_armed != null:
		idle_armed.call("equip", ranger)
		root.add_child(idle_armed)
		check(bool(idle_armed.call("consume_shot")), "idle-gate setup shot succeeds")
		Input.action_release("fire")
		await wait_physics(60)
		check(float(idle_armed.get("_cooldown")) >= 0.0, "equipped idle gun never goes negative")
		check(bool(idle_armed.call("can_fire")), "equipped idle gate re-opens")
		root.remove_child(idle_armed)
		idle_armed.free()

	# fire_rate is editor-guarded: out-of-range and non-finite assignments
	# clamp into range with a warning, so the gun stays fireable with a
	# real cooldown; in-range values pass through untouched.
	for bad_rate in [0.0, -5.0, INF, -INF, NAN]:
		var bad := WeaponResource.new()
		bad.fire_rate = bad_rate
		bad.mag_size = 30
		bad.reserve = 90
		check_close(float(bad.fire_rate), WeaponResource.MIN_FIRE_RATE, 0.0001, "fire_rate %f clamps to minimum" % bad_rate)
		var bw = make_weapon()
		if bw == null:
			return
		bw.call("equip", bad)
		check(bool(bw.call("can_fire")), "clamped fire_rate %f can_fire" % bad_rate)
		check(bool(bw.call("consume_shot")), "clamped fire_rate %f consume succeeds" % bad_rate)
		check(float(bw.get("_cooldown")) > 0.0, "clamped fire_rate %f arms cooldown" % bad_rate)
		bw.free()
	var hot := WeaponResource.new()
	hot.fire_rate = 100.0
	check_close(float(hot.fire_rate), WeaponResource.MAX_FIRE_RATE, 0.0001, "fire_rate 100.0 clamps to maximum")
	for ok_rate in [0.1, 0.8, 1.1, 10.0, 60.0]:
		var ok := WeaponResource.new()
		ok.fire_rate = ok_rate
		check_close(float(ok.fire_rate), ok_rate, 0.0001, "fire_rate %f passes through" % ok_rate)
	var good := WeaponResource.new()
	good.fire_rate = 1.0
	good.mag_size = 30
	good.reserve = 90
	var gw = make_weapon()
	if gw != null:
		gw.call("equip", good)
		check(bool(gw.call("can_fire")), "fire_rate 1.0 can_fire")
		check(bool(gw.call("consume_shot")), "fire_rate 1.0 consume succeeds")
		check(float(gw.get("_cooldown")) > 0.0, "fire_rate 1.0 arms cooldown")
		gw.free()

	# is_fireable_rate refusal predicate: last-resort driver refusal for
	# direct-storage/bulk-load smuggles; over-MAX rates stay fireable.
	for bad_pred in [0.0, -5.0, 0.05, INF, -INF, NAN]:
		check(not WeaponResource.is_fireable_rate(bad_pred), "is_fireable_rate %f refuses" % bad_pred)
	for ok_pred in [0.1, 0.8, 1.1, 10.0, 60.0, 100.0]:
		check(WeaponResource.is_fireable_rate(ok_pred), "is_fireable_rate %f fires" % ok_pred)

	# damage is editor-guarded: below-range and non-finite assignments
	# clamp to the minimum, over-range clamps to the maximum, and
	# shipped values pass through untouched.
	for bad_damage in [-50.0, 0.0, INF, -INF, NAN]:
		var bad_d := WeaponResource.new()
		bad_d.damage = bad_damage
		check_close(float(bad_d.damage), WeaponResource.MIN_DAMAGE, 0.0001, "damage %f clamps to minimum" % bad_damage)
	var hot_d := WeaponResource.new()
	hot_d.damage = 1000.0
	check_close(float(hot_d.damage), WeaponResource.MAX_DAMAGE, 0.0001, "damage 1000.0 clamps to maximum")
	for ok_damage in [5.0, 12.0, 50.0]:
		var ok_d := WeaponResource.new()
		ok_d.damage = ok_damage
		check_close(float(ok_d.damage), ok_damage, 0.0001, "damage %f passes through" % ok_damage)

	# spread_deg is editor-guarded: negative and non-finite cones clamp
	# to the minimum, absurd cones clamp to the maximum, and shipped
	# values pass through untouched.
	for bad_spread in [-10.0, INF, -INF, NAN]:
		var bad_s := WeaponResource.new()
		bad_s.spread_deg = bad_spread
		check_close(float(bad_s.spread_deg), WeaponResource.MIN_SPREAD_DEG, 0.0001, "spread_deg %f clamps to minimum" % bad_spread)
	var hot_s := WeaponResource.new()
	hot_s.spread_deg = 720.0
	check_close(float(hot_s.spread_deg), WeaponResource.MAX_SPREAD_DEG, 0.0001, "spread_deg 720.0 clamps to maximum")
	for ok_spread in [0.4, 2.0, 12.0]:
		var ok_s := WeaponResource.new()
		ok_s.spread_deg = ok_spread
		check_close(float(ok_s.spread_deg), ok_spread, 0.0001, "spread_deg %f passes through" % ok_spread)

	# range is editor-guarded: degenerate and non-finite rays clamp to
	# the minimum, sightline typos clamp to the maximum, and shipped
	# values pass through untouched.
	for bad_range in [-100.0, 0.0, INF, -INF, NAN]:
		var bad_r := WeaponResource.new()
		bad_r.range = bad_range
		check_close(float(bad_r.range), WeaponResource.MIN_RANGE, 0.0001, "range %f clamps to minimum" % bad_range)
	var hot_r := WeaponResource.new()
	hot_r.range = 1e9
	check_close(float(hot_r.range), WeaponResource.MAX_RANGE, 0.0001, "range 1e9 clamps to maximum")
	for ok_range in [500.0, 1200.0, 2000.0]:
		var ok_r := WeaponResource.new()
		ok_r.range = ok_range
		check_close(float(ok_r.range), ok_range, 0.0001, "range %f passes through" % ok_range)

	# mag_size is editor-guarded: zero and negative mags clamp to the
	# minimum, belt-fed typos clamp to the maximum, and shipped values
	# pass through untouched.
	for bad_mag in [0, -10]:
		var bad_m := WeaponResource.new()
		bad_m.mag_size = bad_mag
		check(int(bad_m.mag_size) == WeaponResource.MIN_MAG_SIZE, "mag_size %d clamps to minimum" % bad_mag)
	var hot_m := WeaponResource.new()
	hot_m.mag_size = 10000
	check(int(hot_m.mag_size) == WeaponResource.MAX_MAG_SIZE, "mag_size 10000 clamps to maximum")
	for ok_mag in [5, 6, 30]:
		var ok_m := WeaponResource.new()
		ok_m.mag_size = ok_mag
		check(int(ok_m.mag_size) == ok_mag, "mag_size %d passes through" % ok_mag)

	# zoom is editor-guarded: sub-identity and non-finite scopes clamp
	# to the minimum, absurd scopes clamp to the maximum, and shipped
	# values pass through untouched.
	for bad_zoom in [0.0, 0.5, -2.0, INF, -INF, NAN]:
		var bad_z := WeaponResource.new()
		bad_z.zoom = bad_zoom
		check_close(float(bad_z.zoom), WeaponResource.MIN_ZOOM, 0.0001, "zoom %f clamps to minimum" % bad_zoom)
	var hot_z := WeaponResource.new()
	hot_z.zoom = 100.0
	check_close(float(hot_z.zoom), WeaponResource.MAX_ZOOM, 0.0001, "zoom 100.0 clamps to maximum")
	for ok_zoom in [1.0, 2.5]:
		var ok_z := WeaponResource.new()
		ok_z.zoom = ok_zoom
		check_close(float(ok_z.zoom), ok_zoom, 0.0001, "zoom %f passes through" % ok_zoom)

	# Clamped-bad resources stay usable: equip arms a fireable gun and
	# get_zoom reports the clamped scope.
	var clamped := WeaponResource.new()
	clamped.damage = -25.0
	clamped.spread_deg = 720.0
	clamped.range = -500.0
	clamped.mag_size = 0
	clamped.zoom = 0.0
	clamped.fire_rate = 1.0
	clamped.reserve = 90
	check_close(float(clamped.damage), WeaponResource.MIN_DAMAGE, 0.0001, "clamped driver damage is minimum")
	check_close(float(clamped.spread_deg), WeaponResource.MAX_SPREAD_DEG, 0.0001, "clamped driver spread is maximum")
	check_close(float(clamped.range), WeaponResource.MIN_RANGE, 0.0001, "clamped driver range is minimum")
	check(int(clamped.mag_size) == WeaponResource.MIN_MAG_SIZE, "clamped driver mag is minimum")
	check_close(float(clamped.zoom), WeaponResource.MIN_ZOOM, 0.0001, "clamped driver zoom is minimum")
	var cw = make_weapon()
	if cw == null:
		return
	cw.call("equip", clamped)
	check(bool(cw.call("can_fire")), "clamped driver can_fire")
	check(bool(cw.call("consume_shot")), "clamped driver consume succeeds")
	check_close(float(cw.call("get_zoom")), WeaponResource.MIN_ZOOM, 0.0001, "clamped driver zoom matches stats")
	cw.free()

	# Direct-API cooldown: consume_shot owns the rate gate.
	var cd = make_weapon()
	if cd != null:
		cd.call("equip", ranger)
		check(bool(cd.call("can_fire")), "fresh equip can_fire")
		var mag_full: int = int(cd.get("ammo"))
		check(bool(cd.call("consume_shot")), "first consume_shot succeeds")
		check(int(cd.get("ammo")) == mag_full - 1, "first shot decrements ammo once")
		check(not bool(cd.call("consume_shot")), "second immediate consume_shot blocked by cooldown")
		check(int(cd.get("ammo")) == mag_full - 1, "blocked shot leaves ammo unchanged")
		check(not bool(cd.call("can_fire")), "can_fire false while cooldown armed")
		cd.set("_cooldown", 0.0)
		check(bool(cd.call("can_fire")), "gate re-opens after cooldown reset")
		check(bool(cd.call("consume_shot")), "consume_shot succeeds after cooldown reset")
		cd.call("equip", ranger)
		check(bool(cd.call("can_fire")), "equip clears the gate")
		# Reload clears the gate: a mid-cooldown refill re-opens fire,
		# while no-op reloads leave a preset gate untouched.
		check(bool(cd.call("consume_shot")), "reload-gate setup shot succeeds")
		check(float(cd.get("_cooldown")) > 0.0, "setup shot arms the gate")
		check(not bool(cd.call("can_fire")), "can_fire false before mid-cooldown reload")
		check(bool(cd.call("reload")), "mid-cooldown reload succeeds")
		check_close(float(cd.get("_cooldown")), 0.0, 0.0001, "reload clears the gate")
		check(bool(cd.call("can_fire")), "refilled mag can_fire after reload")
		cd.set("_cooldown", 0.5)
		check(not bool(cd.call("reload")), "reload fails when mag full")
		check_close(float(cd.get("_cooldown")), 0.5, 0.0001, "full-mag reload preserves the gate")
		cd.set("ammo", int(cd.get("ammo")) - 1)
		cd.set("reserve_left", 0)
		cd.set("_cooldown", 0.5)
		check(not bool(cd.call("reload")), "reload fails with empty reserve")
		check_close(float(cd.get("_cooldown")), 0.5, 0.0001, "empty-reserve reload preserves the gate")
		cd.free()

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

	# (e) Dead soldier cannot fire: live gun fires headless, the corpse
	# holds ammo with `fire` held, and respawn re-arms the same weapon.
	var corpse_packed := load("res://scenes/soldier.tscn") as PackedScene
	check(corpse_packed != null, "soldier.tscn loads for dead-fire test")
	if corpse_packed != null:
		var corpse := corpse_packed.instantiate() as CharacterBody2D
		check(corpse != null, "dead-fire soldier instantiates")
		if corpse != null:
			corpse.position = Vector2(0, -40)
			root.add_child(corpse)
			await process_frame
			await process_frame
			var gun = corpse.get_node_or_null("Weapon")
			check(gun != null, "dead-fire soldier has Weapon child")
			if gun != null:
				# Sanity: the live gun fires headless with `fire` held.
				gun.set("_cooldown", 0.0)
				var live_ammo: int = int(gun.get("ammo"))
				Input.action_press("fire")
				await wait_physics(20)
				Input.action_release("fire")
				check(int(gun.get("ammo")) < live_ammo, "live gun consumes ammo with fire held")
				# Corpse: trigger pulls consume nothing while dead.
				corpse.call("take_damage", 200.0)
				check(not bool(corpse.get("is_alive")), "fire-test soldier is dead")
				gun.set("_cooldown", 0.0)
				var dead_ammo: int = int(gun.get("ammo"))
				check(not bool(gun.call("can_fire")), "dead host can_fire is false")
				Input.action_press("fire")
				await wait_physics(10)
				Input.action_release("fire")
				check(int(gun.get("ammo")) == dead_ammo, "dead gun consumes no ammo with fire held")
				check(not bool(gun.call("can_fire")), "dead host can_fire stays false")
				# Dead host cannot reload: denial is a pure no-op.
				gun.set("ammo", int(gun.get("stats").get("mag_size")) - 5)
				if int(gun.get("reserve_left")) <= 0:
					gun.set("reserve_left", 5)
				gun.set("_cooldown", 0.5)
				var dead_reload_ammo: int = int(gun.get("ammo"))
				var dead_reload_reserve: int = int(gun.get("reserve_left"))
				var dead_reload_cd: float = float(gun.get("_cooldown"))
				check(not bool(gun.call("reload")), "dead host reload is false")
				check(int(gun.get("ammo")) == dead_reload_ammo, "dead reload leaves ammo unchanged")
				check(int(gun.get("reserve_left")) == dead_reload_reserve, "dead reload leaves reserve unchanged")
				check_close(float(gun.get("_cooldown")), dead_reload_cd, 0.0001, "dead reload preserves the gate")
				# Respawn re-arms the same weapon automatically.
				var back := false
				for i in 220:
					await physics_frame
					if bool(corpse.get("is_alive")):
						back = true
						break
				check(back, "fire-test soldier respawns")
				gun.set("_cooldown", 0.0)
				var rearmed: int = int(gun.get("ammo"))
				Input.action_press("fire")
				await wait_physics(20)
				Input.action_release("fire")
				check(int(gun.get("ammo")) < rearmed, "respawned gun fires again")
				# Live control: the same gun reloads again once the host is alive.
				gun.set("ammo", int(gun.get("stats").get("mag_size")) - 3)
				if int(gun.get("reserve_left")) <= 0:
					gun.set("reserve_left", 5)
				gun.set("_cooldown", 0.5)
				check(bool(gun.call("reload")), "live host reload succeeds after respawn")
				check(int(gun.get("ammo")) == int(gun.get("stats").get("mag_size")), "live reload refills mag after respawn")
				check_close(float(gun.get("_cooldown")), 0.0, 0.0001, "live reload clears the gate after respawn")
			Input.action_release("fire")
			corpse.queue_free()
			await process_frame
