extends SceneTree
## Headless proof for gamepad parity: every movement/fire action carries a
## pad binding, 60-tick pad-held fly/fire drains fuel and ammo within 5% of
## the keyboard baseline through the same Pilot.Command consumption path,
## right-stick deflection steers HumanPilot aim with undiminished fire drain,
## and sim sources never touch Input directly.
## Run: godot --headless --path jetpack --script res://tests/test_gamepad.gd

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


func check_within_frac(actual: float, baseline: float, frac: float, label: String) -> void:
	var denom := maxf(absf(baseline), 0.0001)
	check(absf(actual - baseline) / denom <= frac, "%s (pad %f vs keyboard %f)" % [label, actual, baseline])


func wait_physics(n: int) -> void:
	for i in n:
		await physics_frame


func release_all() -> void:
	for action in ["move_left", "move_right", "crouch", "fly", "fire", "throw_grenade", "reload"]:
		if InputMap.has_action(action):
			Input.action_release(action)
	for i in 8:
		if InputMap.has_action("slot_%d" % (i + 1)):
			Input.action_release("slot_%d" % (i + 1))


func pad_set_button(btn: JoyButton, pressed: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = btn
	ev.pressed = pressed
	ev.pressure = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


func pad_set_axis(axis: JoyAxis, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = 0
	ev.axis = axis
	ev.axis_value = value
	Input.parse_input_event(ev)


func pad_release_all() -> void:
	pad_set_button(JOY_BUTTON_A, false)
	pad_set_button(JOY_BUTTON_B, false)
	pad_set_button(JOY_BUTTON_LEFT_SHOULDER, false)
	pad_set_button(JOY_BUTTON_RIGHT_SHOULDER, false)
	pad_set_axis(JOY_AXIS_LEFT_X, 0.0)
	pad_set_axis(JOY_AXIS_RIGHT_Y, 0.0)
	pad_set_axis(JOY_AXIS_RIGHT_X, 0.0)
	pad_set_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	release_all()


func file_lines(path: String) -> Array[String]:
	var out: Array[String] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		out.append(f.get_line())
	return out


func make_ranger_soldier(aim: bool) -> CharacterBody2D:
	var packed := load("res://scenes/soldier.tscn") as PackedScene
	var soldier := packed.instantiate() as CharacterBody2D
	soldier.position = Vector2(0, -200)
	root.add_child(soldier)
	await process_frame
	await process_frame
	var weapon := soldier.get_node_or_null("Weapon")
	var ranger := load("res://resources/weapons/ranger_ar.tres") as WeaponResource
	weapon.call("equip", ranger)
	if aim:
		soldier.call("set_aim_point", soldier.global_position + Vector2(300, 0))
	return soldier


## One 60-tick held fly+fire drain run; pad=True feeds virtual pad events,
## pad=False uses the keyboard/mouse baseline. Returns [fuel_spent, ammo_spent].
func drain_run(use_pad: bool) -> Array:
	var soldier := await make_ranger_soldier(true)
	var weapon := soldier.get_node_or_null("Weapon")
	var fuel0 := float(soldier.get("fuel"))
	var ammo0 := int(weapon.get("ammo"))
	if use_pad:
		pad_set_button(JOY_BUTTON_A, true)
		pad_set_button(JOY_BUTTON_RIGHT_SHOULDER, true)
	else:
		Input.action_press("fly")
		Input.action_press("fire")
	await wait_physics(60)
	var out := [fuel0 - float(soldier.get("fuel")), ammo0 - int(weapon.get("ammo"))]
	pad_release_all()
	soldier.queue_free()
	await process_frame
	return out


func run_tests() -> void:
	await process_frame
	pad_release_all()

	# HumanPilot backfill runs at _ready: pad events exist even where the
	# Settings remap rebuilt the map from keys alone.
	var backfill := HumanPilot.new()
	root.add_child(backfill)
	await process_frame

	# (a) Every movement/fire action carries at least one pad binding.
	for action in ["move_left", "move_right", "crouch", "fly", "fire", "throw_grenade"]:
		var pad_events := 0
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				pad_events += 1
		check(pad_events > 0, "%s carries a pad binding (got %d)" % [action, pad_events])
	var proj_lines := file_lines("res://project.godot")
	var proj_blob := "\n".join(proj_lines)
	check(proj_blob.contains("InputEventJoypadButton"), "project.godot maps pad buttons")
	check(proj_blob.contains("InputEventJoypadMotion"), "project.godot maps pad motion")
	backfill.queue_free()
	await process_frame

	# (b) 60-tick pad-held fly+fire matches the keyboard drain within 5%.
	var kb := await drain_run(false)
	check(float(kb[0]) > 10.0, "keyboard baseline burns fuel (spent %f)" % float(kb[0]))
	check(int(kb[1]) >= 4, "keyboard baseline spends ammo (spent %d)" % int(kb[1]))
	var pad := await drain_run(true)
	check(float(pad[0]) > 10.0, "pad run burns fuel (spent %f)" % float(pad[0]))
	check(int(pad[1]) >= 4, "pad run spends ammo (spent %d)" % int(pad[1]))
	check_within_frac(float(pad[0]), float(kb[0]), 0.05, "pad fuel drain within 5% of keyboard")
	check_within_frac(float(pad[1]), float(kb[1]), 0.05, "pad ammo drain within 5% of keyboard")

	# (c) Right-stick deflection steers aim; deadzone keeps the fallback.
	var host := Node2D.new()
	host.position = Vector2(1000, 500)
	root.add_child(host)
	var pilot := HumanPilot.new()
	host.add_child(pilot)
	await process_frame
	var fallback: Vector2 = (pilot.get_command(0.016) as Pilot.Command).aim_point
	pad_set_axis(JOY_AXIS_RIGHT_X, 1.0)
	pad_set_axis(JOY_AXIS_RIGHT_Y, 0.0)
	await process_frame
	var steered: Vector2 = (pilot.get_command(0.016) as Pilot.Command).aim_point
	check(steered.distance_to(host.global_position + Vector2(600, 0)) < 60.0, "full-right stick aims 600 right of the soldier (got %s)" % str(steered))
	check(steered.distance_to(fallback) > 100.0, "stick aim leaves the mouse fallback")
	pad_set_axis(JOY_AXIS_RIGHT_X, 0.1)
	await process_frame
	var small: Vector2 = (pilot.get_command(0.016) as Pilot.Command).aim_point
	check(small.is_equal_approx(fallback), "0.1 deflection stays inside the 0.2 deadzone")
	pad_set_axis(JOY_AXIS_RIGHT_X, 0.0)
	host.queue_free()
	await process_frame

	# (c2) Held pad fire still drains ammo while the stick steers aim.
	var gunner := await make_ranger_soldier(false)
	var gun := gunner.get_node_or_null("Weapon")
	var ammo_before := int(gun.get("ammo"))
	pad_set_axis(JOY_AXIS_RIGHT_X, 1.0)
	pad_set_button(JOY_BUTTON_RIGHT_SHOULDER, true)
	await wait_physics(12)
	var gpilot := gunner.get("pilot") as HumanPilot
	var aimed: Vector2 = (gpilot.get_command(0.016) as Pilot.Command).aim_point
	check(aimed.distance_to(gunner.global_position + Vector2(600, 0)) < 120.0, "stick still steers while firing (got %s)" % str(aimed))
	check(ammo_before - int(gun.get("ammo")) >= 1, "pad fire drains ammo while stick-aiming")
	pad_release_all()
	gunner.queue_free()
	await process_frame

	# (d) Source gate: sim files never touch Input; the pad path ends in HumanPilot.
	for path in ["res://scripts/soldier.gd", "res://scripts/weapons/weapon.gd", "res://scripts/match.gd", "res://scripts/pilots/bot_pilot.gd"]:
		var lines := file_lines(path)
		check(not lines.is_empty(), "%s reads from disk" % path)
		var hits := 0
		for ln in lines:
			if (ln as String).contains("Input."):
				hits += 1
		check(hits == 0, "%s has zero Input. lines (got %d)" % [path, hits])

	pad_release_all()
