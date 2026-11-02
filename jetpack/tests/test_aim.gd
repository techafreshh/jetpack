extends SceneTree
## Headless proof for the script-level aim override seam: with no override
## aim falls back to get_global_mouse_position(), while set_aim_point steers
## grenade aim and hitscan fire east headlessly (raw Input.warp_mouse stays
## a display-server no-op), and clear_aim_override restores the fallback.
## Run: godot --headless --path jetpack --script res://tests/test_aim.gd

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


func east_tracers_of(weapon: Node) -> Array:
	var out := []
	for c in weapon.get_children():
		if c is Line2D and (c as Line2D).get_point_count() >= 2:
			var a: Vector2 = (c as Line2D).get_point_position(1)
			var b: Vector2 = (c as Line2D).get_point_position(0)
			if a.x > b.x:
				out.append(c)
	return out


func run_tests() -> void:
	await process_frame

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

	# (a) No override: both nodes fall back to get_global_mouse_position().
	check(not bool(soldier.get("has_aim_override")), "soldier override off by default")
	check(not bool(weapon.get("has_aim_override")), "weapon override off by default")
	var s_fallback: Vector2 = soldier.get_global_mouse_position()
	var s_aim = soldier.call("_aim_point")
	check((s_aim as Vector2).distance_to(s_fallback) < 0.001, "soldier aim equals mouse fallback")
	var w_fallback: Vector2 = (weapon as Node2D).get_global_mouse_position()
	var w_aim = weapon.call("_aim_point")
	check((w_aim as Vector2).distance_to(w_fallback) < 0.001, "weapon aim equals mouse fallback")

	# (b) Soldier override steers grenade aim and shell velocity east.
	soldier.call("set_aim_point", soldier.global_position + Vector2(300, 0))
	check(bool(soldier.get("has_aim_override")), "soldier override flag set")
	var dir = soldier.call("_aim_direction") as Vector2
	check(dir.x > 0.99 and absf(dir.y) < 0.15, "override aims east (dir=%s)" % str(dir))
	var before := root.find_children("Grenade", "RigidBody2D", true, false).size()
	check(bool(soldier.call("throw_grenade")), "throw returns true with stock")
	var shells := root.find_children("Grenade", "RigidBody2D", true, false)
	check(shells.size() == before + 1, "throw spawns one shell")
	var shell_vel := Vector2.ZERO
	if shells.size() == before + 1:
		shell_vel = shells.back().get("linear_velocity")
	check(shell_vel.x > 500.0, "shell leaves east (vx=%f)" % shell_vel.x)

	# (c) Weapon override steers hitscan tracers east of the muzzle.
	var muzzle := (weapon as Node2D).global_position
	var m := weapon.get_node_or_null("Muzzle") as Marker2D
	if m != null:
		muzzle = m.global_position
	weapon.call("set_aim_point", muzzle + Vector2(300, 0))
	check(bool(weapon.get("has_aim_override")), "weapon override flag set")
	Input.action_press("fire")
	await wait_physics(12)
	Input.action_release("fire")
	var east := east_tracers_of(weapon)
	check(east.size() >= 1, "override fires tracers east (got %d)" % east.size())

	# (d) Standalone weapon honors its own override with no soldier parent.
	var scr := load("res://scripts/weapons/weapon.gd") as Script
	check(scr != null, "weapon.gd loads as Script")
	var lone = scr.new() if scr != null else null
	check(lone != null, "weapon.gd instantiates standalone")
	if lone != null:
		check(not bool(lone.get("has_aim_override")), "standalone override off by default")
		lone.call("set_aim_point", Vector2(300, 0))
		check(bool(lone.get("has_aim_override")), "standalone override flag set")
		check((lone.call("_aim_point") as Vector2).is_equal_approx(Vector2(300, 0)), "standalone aim returns override")
		var ranger := load("res://resources/weapons/ranger_ar.tres") as WeaponResource
		root.add_child(lone)
		lone.global_position = Vector2(-500, -200)
		lone.call("equip", ranger)
		lone.call("set_aim_point", (lone as Node2D).global_position + Vector2(300, 0))
		Input.action_press("fire")
		await wait_physics(12)
		Input.action_release("fire")
		check(east_tracers_of(lone).size() >= 1, "standalone fires tracers east")
		lone.queue_free()
		await process_frame

	# (e) Clearing restores fallback reads on both nodes.
	soldier.call("clear_aim_override")
	weapon.call("clear_aim_override")
	check(not bool(soldier.get("has_aim_override")), "soldier clear drops flag")
	check(not bool(weapon.get("has_aim_override")), "weapon clear drops flag")
	var s_back = soldier.call("_aim_point") as Vector2
	check(s_back.distance_to(soldier.get_global_mouse_position()) < 0.001, "soldier fallback restored")
	var w_back = weapon.call("_aim_point") as Vector2
	check(w_back.distance_to((weapon as Node2D).get_global_mouse_position()) < 0.001, "weapon fallback restored")

	var leftover := root.find_children("Grenade", "RigidBody2D", true, false)
	for n in leftover:
		(n as Node).queue_free()
	await process_frame
	await wait_physics(1)
	check(root.find_children("Grenade", "RigidBody2D", true, false).is_empty(), "aim throw leaves no shells")

	Input.action_release("fire")
