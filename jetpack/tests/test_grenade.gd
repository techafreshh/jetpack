extends SceneTree
## Headless behavior tests for grenades: 2-slot count with max clamp,
## G edge-trigger, 2.5 s fuse window with explosion FX, and edge-of-blast
## self-damage plus knockback for grenade jumps.
## Run: godot --headless --path jetpack --script res://tests/test_grenade.gd

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


func wait_until_floor(soldier: CharacterBody2D, cap: int) -> bool:
	for i in cap:
		if soldier.is_on_floor():
			return true
		await physics_frame
	return soldier.is_on_floor()


func free_shells() -> void:
	for n in root.find_children("Grenade", "RigidBody2D", true, false):
		(n as Node).queue_free()
	for n in get_nodes_in_group("explosion"):
		(n as Node).queue_free()
	await process_frame
	await physics_frame


func run_tests() -> void:
	await process_frame

	var cfg := ConfigFile.new()
	check(cfg.load("res://resources/config/grenade.cfg") == OK, "grenade.cfg loads")
	check_close(float(cfg.get_value("grenade", "fuse_time", 0.0)), 2.5, 0.05, "cfg fuse_time is 2.5")
	check_close(float(cfg.get_value("grenade", "blast_radius", 0.0)), 180.0, 0.5, "cfg blast_radius is 180")
	check(InputMap.has_action("throw_grenade"), "throw_grenade action registered")

	var packed := load("res://scenes/soldier.tscn") as PackedScene
	check(packed != null, "soldier.tscn loads as PackedScene")
	if packed == null:
		return
	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2.ZERO
	var floor_shape := CollisionShape2D.new()
	var world_edge := WorldBoundaryShape2D.new()
	floor_shape.shape = world_edge
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)
	var soldier := packed.instantiate() as CharacterBody2D
	check(soldier != null, "soldier.tscn instantiates CharacterBody2D")
	if soldier == null:
		return
	soldier.position = Vector2(0, -40)
	root.add_child(soldier)
	await process_frame
	await process_frame
	var early_died := [0]
	soldier.connect("died", func() -> void: early_died[0] += 1)
	var settled := await wait_until_floor(soldier, 120)
	check(settled, "soldier settles onto floor")

	# (a) Two-slot count with max clamp.
	check(int(soldier.get("grenade_count")) == 2, "fresh soldier carries 2 grenades")
	check(int(soldier.get("grenade_max")) == 2, "grenade max clamp is 2")
	var arc := soldier.get_node_or_null("ArcPreview") as Line2D
	check(arc != null, "ArcPreview Line2D exists")
	if arc != null:
		check(arc.points.size() == 24, "arc preview has 24 points (got %d)" % arc.points.size())
		check(arc.visible, "arc visible while stocked")
	check(bool(soldier.call("throw_grenade")), "throw returns true with stock")
	check(int(soldier.get("grenade_count")) == 1, "throw decrements to 1")
	var shell := root.find_child("Grenade", true, false)
	check(shell != null and bool(shell.get("primed")), "thrown shell leaves primed")
	await free_shells()
	check(int(soldier.call("add_grenades", 5)) == 2, "add_grenades(5) clamps to 2")
	check(int(soldier.get("grenade_count")) == 2, "count restored to max 2")
	soldier.set("grenade_count", 0)
	await wait_physics(2)
	check(not bool(soldier.call("throw_grenade")), "empty throw returns false")
	check(int(soldier.get("grenade_count")) == 0, "empty throw keeps count 0")
	if arc != null:
		check(not arc.visible, "arc hidden when empty")
	# G key is edge-triggered: a 5-tick hold throws exactly one shell.
	soldier.call("add_grenades", 2)
	Input.action_press("throw_grenade")
	await wait_physics(5)
	Input.action_release("throw_grenade")
	check(int(soldier.get("grenade_count")) == 1, "held G throws once (count=%d)" % int(soldier.get("grenade_count")))
	await free_shells()

	# (b) Primed shell explodes inside 145-160 ticks and spawns FX.
	var nade_packed := load("res://scenes/grenade.tscn") as PackedScene
	check(nade_packed != null, "grenade.tscn loads as PackedScene")
	if nade_packed == null:
		return
	var nade := nade_packed.instantiate() as RigidBody2D
	check(nade != null, "grenade.tscn instantiates RigidBody2D")
	if nade == null:
		return
	check(nade.get_node_or_null("FuseBeep") != null, "fuse beep player exists")
	root.add_child(nade)
	await process_frame
	nade.global_position = Vector2(2000, -500)
	nade.set("freeze", true)
	nade.set("linear_velocity", Vector2.ZERO)
	nade.call("prime")
	check(bool(nade.get("primed")), "shell reports primed")
	var boom_tick := -1
	for i in 220:
		await physics_frame
		if not is_instance_valid(nade):
			boom_tick = i + 1
			break
	check(boom_tick >= 145 and boom_tick <= 160, "fuse booms in 145-160 ticks (got %d)" % boom_tick)
	var fx := get_nodes_in_group("explosion")
	check(fx.size() >= 1, "explosion FX node spawned in group")
	check(root.find_child("Explosion", true, false) != null, "FX node named Explosion exists")
	await wait_physics(120)
	check(get_nodes_in_group("explosion").is_empty(), "explosion FX auto-frees")

	# (b2) Fuse-rest invariant: the stored fuse never drifts negative.
	# Overshoot clamps to exactly 0.0 at the decrement (weapon-gate idiom).
	var nade_rest := nade_packed.instantiate() as RigidBody2D
	root.add_child(nade_rest)
	await process_frame
	nade_rest.global_position = Vector2(2000, -500)
	nade_rest.set("freeze", true)
	nade_rest.set("linear_velocity", Vector2.ZERO)
	nade_rest.set("fuse_time", 0.05)
	nade_rest.call("prime")
	check_close(float(nade_rest.get("fuse_left")), 0.05, 0.0001, "tiny fuse primes at 0.05")
	var fuse_negative := false
	for i in 12:
		await physics_frame
		if is_instance_valid(nade_rest):
			if float(nade_rest.get("fuse_left")) < 0.0:
				fuse_negative = true
		else:
			break
	check(not fuse_negative, "primed fuse never goes negative past detonation")
	# Direct overshoot: a large delta on a near-zero fuse rests at exactly 0.0.
	var nade_os := nade_packed.instantiate() as RigidBody2D
	root.add_child(nade_os)
	await process_frame
	nade_os.global_position = Vector2(2000, -500)
	nade_os.set("freeze", true)
	nade_os.set("linear_velocity", Vector2.ZERO)
	nade_os.call("prime")
	nade_os.set("fuse_left", 0.01)
	nade_os.call("_physics_process", 1.0)
	check(float(nade_os.get("fuse_left")) >= 0.0, "overshoot fuse never negative")
	check_close(float(nade_os.get("fuse_left")), 0.0, 0.0001, "overshoot fuse clamps to exactly 0.0")
	await free_shells()
	check(bool(soldier.get("is_alive")), "soldier alive before blast-edge block")
	check(str(soldier.get("last_death_cause")) != "fall", "no fall death before blast-edge block")
	check(early_died[0] == 0, "no died before blast-edge block (got %d)" % early_died[0])
	check(soldier.global_position.y < 2000.0, "soldier above kill-plane before blast-edge block (y=%f)" % soldier.global_position.y)

	# (c) Soldier at the blast edge takes damage and knockback.
	soldier.set("hp", 100.0)
	soldier.set("velocity", Vector2.ZERO)
	var nade2 := nade_packed.instantiate() as RigidBody2D
	var centre := Vector2(2000, -500)
	root.add_child(nade2)
	await process_frame
	nade2.global_position = centre
	nade2.set("freeze", true)
	nade2.set("linear_velocity", Vector2.ZERO)
	var radius: float = nade2.get("blast_radius")
	var edge := centre + Vector2(radius * 0.95, 0.0)
	soldier.global_position = edge
	nade2.call("prime")
	var hp0: float = soldier.get("hp")
	for i in 220:
		if is_instance_valid(nade2):
			nade2.global_position = centre
		soldier.global_position = edge
		await physics_frame
		if not is_instance_valid(nade2):
			break
		soldier.set("velocity", Vector2.ZERO)
	await wait_physics(3)
	var hp1: float = soldier.get("hp")
	var kick: Vector2 = soldier.get("velocity")
	check(hp1 < hp0, "edge blast damages soldier (hp %f -> %f)" % [hp0, hp1])
	check_close(hp1, 82.75, 5.0, "edge damage matches falloff")
	check(kick.length() > 200.0, "edge blast knocks back >200 px/s (got %f)" % kick.length())
	check(bool(soldier.get("is_alive")), "soldier alive after edge blast")
	check(str(soldier.get("last_death_cause")) != "fall", "no fall death through edge blast")
	check(early_died[0] == 0, "no died through edge blast (got %d)" % early_died[0])
	# (d) Dead soldier inside the blast is skipped: no damage, no knockback, no second died.
	var corpse_died := [0]
	soldier.connect("died", func() -> void: corpse_died[0] += 1)
	soldier.set("hp", 100.0)
	soldier.set("velocity", Vector2.ZERO)
	soldier.call("take_damage", 200.0)
	check(not bool(soldier.get("is_alive")), "corpse setup: lethal damage kills soldier")
	check(corpse_died[0] == 1, "corpse setup: died emitted once (got %d)" % corpse_died[0])
	check(soldier.is_in_group("damageable"), "corpse stays in damageable group through respawn window")
	var corpse_hp0: float = soldier.get("hp")
	var corpse_vel0: Vector2 = soldier.get("velocity")
	var nade3 := nade_packed.instantiate() as RigidBody2D
	root.add_child(nade3)
	await process_frame
	nade3.global_position = centre
	nade3.set("freeze", true)
	nade3.set("linear_velocity", Vector2.ZERO)
	var corpse_spot := centre + Vector2(radius * 0.5, 0.0)
	soldier.global_position = corpse_spot
	nade3.call("prime")
	for i in 220:
		if is_instance_valid(nade3):
			nade3.global_position = centre
		soldier.global_position = corpse_spot
		await physics_frame
		if not is_instance_valid(nade3):
			break
	await wait_physics(3)
	check(not bool(soldier.get("is_alive")), "corpse still dead after blast inside radius")
	check(float(soldier.get("hp")) == corpse_hp0, "corpse blast deals no damage (hp=%f)" % float(soldier.get("hp")))
	var corpse_kick: Vector2 = (soldier.get("velocity") as Vector2) - corpse_vel0
	check(corpse_kick.length() < 1.0, "corpse blast applies no knockback (drift=%f)" % corpse_kick.length())
	check(corpse_died[0] == 1, "corpse blast emits no second died (got %d)" % corpse_died[0])
	await free_shells()
	Input.action_release("throw_grenade")
