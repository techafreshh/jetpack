extends SceneTree
## Headless behavior tests for target dummies and tracer volume: 10x12
## damage kills a 100 HP dummy.tscn/dummy.gd, death signals once, hits
## flash, and a 1 s hold through weapon.gd Weapon on soldier.tscn leaves
## >=10 live Line2D tracers at tick 60.
## Run: godot --headless --path jetpack --script res://tests/test_dummy.gd

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


func run_tests() -> void:
	await process_frame

	var dummy_packed := load("res://scenes/dummy.tscn") as PackedScene
	check(dummy_packed != null, "dummy.tscn loads as PackedScene")
	if dummy_packed == null:
		return
	var dummy := dummy_packed.instantiate() as StaticBody2D
	check(dummy != null, "dummy.tscn instantiates StaticBody2D")
	if dummy == null:
		return
	root.add_child(dummy)
	await process_frame
	await process_frame

	# Kill contract: 10 shots at 12 dmg drop a 100 HP dummy, one died signal.
	var died_count := [0]
	dummy.connect("died", func() -> void: died_count[0] += 1)
	check(float(dummy.get("hp")) > 0.0, "dummy starts alive (hp=%f)" % float(dummy.get("hp")))
	for i in 10:
		dummy.call("take_damage", 12.0)
	check(float(dummy.get("hp")) <= 0.0, "10x12 dmg kills 100 HP dummy (hp=%f)" % float(dummy.get("hp")))
	check(bool(dummy.get("is_dead")), "dummy is_dead after lethal damage")
	check(died_count[0] == 1, "died emitted exactly once (got %d)" % died_count[0])
	dummy.call("take_damage", 12.0)
	check(bool(dummy.get("is_dead")), "post-death take_damage keeps is_dead")
	check(died_count[0] == 1, "post-death take_damage emits no second died")
	check(float(dummy.get("hp")) <= 0.0, "post-death hp stays <= 0")

	# Flash contract: a fresh hit whitens the visual and arms flash_t.
	var flash_dummy := dummy_packed.instantiate() as StaticBody2D
	root.add_child(flash_dummy)
	await process_frame
	await process_frame
	flash_dummy.call("take_damage", 10.0)
	var visual := flash_dummy.get_node("Visual") as Polygon2D
	check(float(flash_dummy.get("flash_t")) > 0.0, "hit arms flash_t (got %f)" % float(flash_dummy.get("flash_t")))
	check(visual != null and (visual.modulate == Color.WHITE or visual.color == Color.WHITE), "hit whitens dummy visual")

	# Tracer volume: hold fire 60 physics ticks, >=10 live Line2D at tick 60.
	var soldier_packed := load("res://scenes/soldier.tscn") as PackedScene
	check(soldier_packed != null, "soldier.tscn loads as PackedScene")
	if soldier_packed == null:
		return
	var soldier := soldier_packed.instantiate() as CharacterBody2D
	check(soldier != null, "soldier.tscn instantiates CharacterBody2D")
	if soldier == null:
		return
	soldier.position = Vector2(0, -200)
	root.add_child(soldier)
	await process_frame
	await process_frame
	check(soldier.get_node_or_null("Weapon") != null, "soldier has Weapon child")
	var ranger := load("res://resources/weapons/ranger_ar.tres") as WeaponResource
	check(ranger != null, "ranger_ar.tres loads as WeaponResource")
	var weapon := soldier.get_node_or_null("Weapon")
	if weapon != null and ranger != null:
		weapon.call("equip", ranger)
	check(weapon != null and ranger != null and int(weapon.get("ammo")) >= 10, "ranger equip fills mag for volume probe")
	Input.action_press("fire")
	await wait_physics(60)
	var tracers := root.find_children("*", "Line2D", true, false)
	check(tracers.size() >= 10, "1 s hold leaves >=10 live tracers (got %d)" % tracers.size())
	Input.action_release("fire")
