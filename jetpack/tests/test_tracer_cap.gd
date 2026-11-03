extends SceneTree
## Headless proof for the per-weapon tracer cap: sustained _spawn_tracer
## overflow never exceeds max_tracers with oldest-first eviction, while a
## default-cap 1 s ranger hold still leaves >=10 live tracers (volume
## contract intact). Tracer counts use weapon children only so the soldier
## ArcPreview Line2D never pollutes them.
## Run: godot --headless --path jetpack --script res://tests/test_tracer_cap.gd

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


func wait_physics(n: int) -> void:
	for i in n:
		await physics_frame


func live_tracers_of(weapon: Node) -> Array:
	var out := []
	for c in weapon.get_children():
		if c is Line2D and is_instance_valid(c) and not (c as Node).is_queued_for_deletion():
			out.append(c)
	return out


func run_tests() -> void:
	await process_frame

	var scr := load("res://scripts/weapons/weapon.gd") as Script
	check(scr != null, "weapon.gd loads as Script")
	if scr == null:
		return
	check(int(scr.get_property_default_value("max_tracers")) == 32, "max_tracers defaults to 32")

	# Cap proof: small cap, 3x overflow via direct spawns.
	var lone = scr.new()
	check(lone != null, "weapon.gd instantiates standalone")
	if lone == null:
		return
	root.add_child(lone)
	await process_frame
	lone.set("max_tracers", 8)
	var a := Vector2.ZERO
	var b := Vector2(100, 0)
	var peak := 0
	for i in 24:
		lone.call("_spawn_tracer", a + Vector2(i, 0), b + Vector2(i, 0))
		peak = maxi(peak, live_tracers_of(lone).size())
	check(peak <= 8, "sustained spawn never exceeds cap (peak=%d)" % peak)
	# Oldest evicted first: first-spawned tracer freed/queued, newest live.
	var ledger: Array = lone.get("_tracers")
	check(ledger.size() == 8, "ledger holds exactly cap entries (got %d)" % ledger.size())
	var newest: Line2D = ledger.back()
	check(is_instance_valid(newest) and not newest.is_queued_for_deletion(), "newest tracer stays live")
	check(newest.get_parent() == lone, "newest tracer is a weapon child")
	# The very first tracer was evicted: no live tracer keeps its start point.
	var first_kept := false
	for t in live_tracers_of(lone):
		if (t as Line2D).get_point_count() >= 1 and (t as Line2D).get_point_position(0).is_equal_approx(a):
			first_kept = true
	check(not first_kept, "first-spawned tracer evicted oldest-first")
	lone.queue_free()
	await process_frame

	# Floor proof: 0/negative cap degrades to 1 instead of breaking fire.
	var lone2 = scr.new()
	root.add_child(lone2)
	await process_frame
	lone2.set("max_tracers", 0)
	for i in 3:
		lone2.call("_spawn_tracer", a, b)
	check(live_tracers_of(lone2).size() <= 1, "zero cap floors to 1 (got %d)" % live_tracers_of(lone2).size())
	lone2.queue_free()
	await process_frame

	# Regression proof: default cap, ranger 1 s hold keeps >=10 live tracers.
	var packed := load("res://scenes/soldier.tscn") as PackedScene
	check(packed != null, "soldier.tscn loads as PackedScene")
	if packed == null:
		return
	var soldier := packed.instantiate() as CharacterBody2D
	check(soldier != null, "soldier.tscn instantiates CharacterBody2D")
	if soldier == null:
		return
	soldier.position = Vector2(0, -200)
	root.add_child(soldier)
	await process_frame
	await process_frame
	var weapon := soldier.get_node_or_null("Weapon")
	check(weapon != null, "soldier has Weapon child")
	if weapon == null:
		return
	var ranger := load("res://resources/weapons/ranger_ar.tres") as WeaponResource
	check(ranger != null, "ranger_ar.tres loads as WeaponResource")
	if ranger != null:
		weapon.call("equip", ranger)
	check(int(weapon.get("max_tracers")) == 32, "weapon keeps default cap 32")
	check(int(weapon.get("ammo")) >= 10, "ranger equip fills mag for volume probe")
	weapon.call("set_aim_point", (weapon as Node2D).global_position + Vector2(300, 0))
	Input.action_press("fire")
	# 66 ticks (~1.1 s at 10 rps): the dummy volume probe holds 60 ticks and
	# counts weapon children, so its >=10 is genuine tracers with the soldier
	# ArcPreview Line2D excluded (the old root-wide idiom padded it by one).
	# Weapon-children-only counting excludes that padding, so hold slightly
	# longer to leave >=10 genuine tracers; none expire (1.5 s lifetime).
	await wait_physics(66)
	Input.action_release("fire")
	var held := live_tracers_of(weapon).size()
	check(held >= 10, "1 s hold leaves >=10 live tracers (got %d)" % held)
	check(held <= 32, "1 s hold stays within cap (got %d)" % held)
	# Weapon-children filter excludes the soldier ArcPreview Line2D.
	var arc := soldier.get_node_or_null("ArcPreview") as Line2D
	check(arc != null, "ArcPreview Line2D exists")
	var root_wide := root.find_children("*", "Line2D", true, false).size()
	check(root_wide >= held + 1, "root-wide count includes ArcPreview (root=%d weapon=%d)" % [root_wide, held])
	soldier.queue_free()
	await process_frame
	Input.action_release("fire")

	# Tree-less proof: _fire_ray with no world degrades to a full-range
	# miss with a visible tracer instead of erroring on get_world_2d().
	var off = scr.new()
	check(off != null, "tree-less weapon instantiates")
	if off != null:
		off.call("equip", ranger)
		check(not off.is_inside_tree(), "tree-less weapon stays off-tree")
		off.call("_fire_ray", Vector2.ZERO, Vector2.RIGHT)
		var off_live := live_tracers_of(off)
		check(off_live.size() == 1, "tree-less _fire_ray leaves one tracer (got %d)" % off_live.size())
		var off_ledger: Array = off.get("_tracers")
		check(off_ledger.size() == 1, "tree-less _fire_ray tracks one ledger entry (got %d)" % off_ledger.size())
		if off_live.size() == 1:
			var span: float = ((off_live[0] as Line2D).get_point_position(1) - (off_live[0] as Line2D).get_point_position(0)).length()
			check(absf(span - float(ranger.get("range"))) <= 1.0, "tree-less _fire_ray spans full range (got %f)" % span)
		# Off-tree cap ledger still evicts oldest-first.
		off.set("max_tracers", 4)
		for i in 10:
			off.call("_fire_ray", Vector2.ZERO, Vector2.RIGHT)
		await process_frame
		check(live_tracers_of(off).size() <= 4, "off-tree overflow never exceeds cap (got %d)" % live_tracers_of(off).size())
		check((off.get("_tracers") as Array).size() == 4, "off-tree ledger holds exactly cap entries (got %d)" % (off.get("_tracers") as Array).size())
		off.free()

	# Off-tree proof: _fire without an override never touches
	# get_global_mouse_position(); _aim_point falls back to global_position
	# so _fire's zero-length branch takes a deterministic east shot.
	var off2 = scr.new()
	check(off2 != null, "off-tree _fire weapon instantiates")
	if off2 != null:
		off2.position = Vector2(173, 89)
		off2.call("equip", ranger)
		check(not off2.is_inside_tree(), "off-tree _fire weapon stays off-tree")
		check(not bool(off2.get("has_aim_override")), "off-tree _fire override off by default")
		check((off2.call("_aim_point") as Vector2).is_equal_approx(off2.global_position), "off-tree _aim_point falls back to global_position")
		off2.call("_fire")
		var off2_live := live_tracers_of(off2)
		check(off2_live.size() == 1, "off-tree _fire leaves one tracer (got %d)" % off2_live.size())
		if off2_live.size() == 1:
			var p0: Vector2 = (off2_live[0] as Line2D).get_point_position(0)
			var p1: Vector2 = (off2_live[0] as Line2D).get_point_position(1)
			check(absf((p1 - p0).length() - float(ranger.get("range"))) <= 1.0, "off-tree _fire spans full range (got %f)" % (p1 - p0).length())
			check(p1.x > p0.x, "off-tree _fire heads east")
		off2.free()

	# Off-tree auto-expiry proof: a short-lived tracer fades on the main
	# loop without cap eviction or weapon free; a default-lifetime
	# control stays live to prove no premature free.
	var off_exp = scr.new()
	check(off_exp != null, "off-tree expiry weapon instantiates")
	if off_exp != null:
		check(not off_exp.is_inside_tree(), "off-tree expiry weapon stays off-tree")
		off_exp.set("tracer_lifetime", 0.2)
		off_exp.call("_spawn_tracer", Vector2.ZERO, Vector2(100, 0))
		check(live_tracers_of(off_exp).size() == 1, "off-tree short-lived tracer starts live (got %d)" % live_tracers_of(off_exp).size())
		check((off_exp.get("_tracers") as Array).size() == 1, "off-tree short-lived tracer tracked (got %d)" % (off_exp.get("_tracers") as Array).size())
		var off_ctl = scr.new()
		off_ctl.call("_spawn_tracer", Vector2.ZERO, Vector2(100, 0))
		check(live_tracers_of(off_ctl).size() == 1, "default-lifetime control starts live")
		await wait_physics(30)
		await process_frame
		check(live_tracers_of(off_exp).size() == 0, "off-tree tracer auto-expires (got %d)" % live_tracers_of(off_exp).size())
		check((off_exp.get("_tracers") as Array).size() == 0, "off-tree ledger pruned after expiry (got %d)" % (off_exp.get("_tracers") as Array).size())
		check(live_tracers_of(off_ctl).size() == 1, "default-lifetime control still live before expiry (got %d)" % live_tracers_of(off_ctl).size())
		off_exp.free()
		off_ctl.free()

	# Null-stats guard: a bare weapon's _fire_ray is a silent no-op.
	var bare = scr.new()
	check(bare != null, "bare weapon instantiates")
	if bare != null:
		bare.call("_fire_ray", Vector2.ZERO, Vector2.RIGHT)
		check(live_tracers_of(bare).size() == 0, "null-stats _fire_ray spawns no tracer")
		check((bare.get("_tracers") as Array).size() == 0, "null-stats _fire_ray tracks no ledger entry")
		bare.free()
