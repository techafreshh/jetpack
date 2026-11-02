extends SceneTree
## Headless proof for the Pilot/Command seam: Pilot.Command carries the eight
## fixed-60 Hz fields, HumanPilot is the sole raw-input reader mapping keys
## to Commands, a held fire Command drains a ranger mag through the soldier
## consumption path, and sim sources never touch Input directly.
## Run: godot --headless --path jetpack --script res://tests/test_pilots.gd

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


func release_action(action: StringName) -> void:
	if InputMap.has_action(action):
		Input.action_release(action)


func release_all() -> void:
	for action in ["move_left", "move_right", "crouch", "fly", "fire", "throw_grenade", "reload"]:
		release_action(action)
	for i in 8:
		release_action("slot_%d" % (i + 1))


func file_lines(path: String) -> Array[String]:
	var out: Array[String] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		out.append(f.get_line())
	return out


func run_tests() -> void:
	await process_frame
	release_all()

	# (i) Command defaults for all eight fields.
	var cmd := Pilot.Command.new()
	check(cmd != null, "Pilot.Command instantiates")
	check_close_float(float(cmd.move_x), 0.0, "Command.move_x defaults to 0.0")
	check(not bool(cmd.fly), "Command.fly defaults to false")
	check(not bool(cmd.crouch), "Command.crouch defaults to false")
	check((cmd.aim_point as Vector2).is_equal_approx(Vector2.ZERO), "Command.aim_point defaults to ZERO")
	check(not bool(cmd.fire), "Command.fire defaults to false")
	check(not bool(cmd.grenade), "Command.grenade defaults to false")
	check(int(cmd.switch_to) == -1, "Command.switch_to defaults to -1")
	check(not bool(cmd.reload), "Command.reload defaults to false")

	# (ii) HumanPilot mapping: a Pilot producing Commands from raw input.
	var human := HumanPilot.new()
	check(human is Pilot, "HumanPilot is a Pilot")
	root.add_child(human)
	await process_frame
	Input.action_press("move_right")
	var right := human.get_command(0.016)
	check(right is Pilot.Command, "get_command returns Pilot.Command")
	check(float(right.move_x) > 0.5, "held move_right maps to move_x > 0.5 (got %f)" % float(right.move_x))
	Input.action_release("move_right")
	Input.action_press("fire")
	check(bool(human.get_command(0.016).fire), "held fire maps to fire=true")
	Input.action_release("fire")
	check(not bool(human.get_command(0.016).fire), "released fire maps to fire=false")
	Input.action_press("throw_grenade")
	check(bool(human.get_command(0.016).grenade), "grenade edge true on the just-pressed tick")
	Input.action_release("throw_grenade")
	await wait_physics(2)
	check(not bool(human.get_command(0.016).grenade), "grenade edge false after release")
	human.queue_free()
	await process_frame

	# (iii) Soldier with default pilot: held fire for 30 ticks drains ammo.
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
	check(soldier.get("pilot") != null, "soldier seats a default pilot")
	check((soldier.get("pilot") as Node) is HumanPilot, "default pilot is a HumanPilot")
	var weapon := soldier.get_node_or_null("Weapon")
	check(weapon != null, "soldier has Weapon child")
	if weapon == null:
		return
	var ranger := load("res://resources/weapons/ranger_ar.tres") as WeaponResource
	check(ranger != null, "ranger_ar.tres loads as WeaponResource")
	if ranger != null:
		weapon.call("equip", ranger)
	var ammo0: int = int(weapon.get("ammo"))
	check(ammo0 == int(ranger.get("mag_size")), "ranger starts with a full mag (got %d)" % ammo0)
	soldier.call("set_aim_point", soldier.global_position + Vector2(300, 0))
	Input.action_press("fire")
	await wait_physics(30)
	Input.action_release("fire")
	var spent: int = ammo0 - int(weapon.get("ammo"))
	check(spent >= 4, "30-tick held fire spends >=4 shots (spent %d)" % spent)
	soldier.queue_free()
	await process_frame

	# (iv) Source gate: sim files never touch Input; pilot.gd owns the seam.
	for path in ["res://scripts/soldier.gd", "res://scripts/match.gd", "res://scripts/match/spawner.gd"]:
		var lines := file_lines(path)
		check(not lines.is_empty(), "%s reads from disk" % path)
		var hits := 0
		for ln in lines:
			if (ln as String).contains("Input."):
				hits += 1
		check(hits == 0, "%s has zero Input. lines (got %d)" % [path, hits])
	var pilot_lines := file_lines("res://scripts/pilots/pilot.gd")
	check(not pilot_lines.is_empty(), "pilot.gd reads from disk")
	var blob := "\n".join(pilot_lines)
	for field in ["move_x", "fly", "crouch", "aim_point", "fire", "grenade", "switch_to", "reload", "get_command"]:
		check(blob.contains(field), "pilot.gd defines %s" % field)

	release_all()


func check_close_float(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.0001, "%s (expected %f, got %f)" % [label, expected, actual])
