extends SceneTree
## Headless regression for the shared foe-alive idiom: Health holds the one
## `"is_alive" in` duck-type check (has_alive_flag) with strict (is_live_foe)
## and permissive (is_host_alive) wrappers; weapon.gd and spawner.gd delegate.
## Run: godot --headless --path jetpack --script res://tests/test_foe_alive.gd

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


func read_source(path: String) -> String:
	var fa := FileAccess.open(path, FileAccess.READ)
	check(fa != null, "%s readable" % path)
	if fa == null:
		return ""
	var text := fa.get_as_text()
	fa.close()
	return text


func run_tests() -> void:
	await process_frame

	var soldier_packed := load("res://scenes/soldier.tscn") as PackedScene
	check(soldier_packed != null, "soldier.tscn loads as PackedScene")
	var dummy_packed := load("res://scenes/dummy.tscn") as PackedScene
	check(dummy_packed != null, "dummy.tscn loads as PackedScene")
	if soldier_packed == null or dummy_packed == null:
		return

	# (a) Helper unit matrix: strict vs permissive defaults.
	var soldier := soldier_packed.instantiate() as CharacterBody2D
	root.add_child(soldier)
	await process_frame
	await process_frame
	check(bool(soldier.get("is_alive")), "soldier starts alive")
	check(Health.has_alive_flag(soldier), "live soldier has alive flag")
	check(Health.is_live_foe(soldier), "live soldier is live foe")
	check(Health.is_host_alive(soldier), "live soldier is host alive")

	soldier.call("take_damage", 200.0)
	check(not bool(soldier.get("is_alive")), "lethal damage kills soldier")
	check(Health.has_alive_flag(soldier), "dead soldier keeps alive flag")
	check(not Health.is_live_foe(soldier), "dead soldier is not live foe")
	check(not Health.is_host_alive(soldier), "dead soldier is not host alive")

	var dummy := dummy_packed.instantiate() as StaticBody2D
	root.add_child(dummy)
	await process_frame
	await process_frame
	check(not bool(dummy.get("is_dead")), "dummy starts live")
	check(not Health.has_alive_flag(dummy), "live dummy has no alive flag")
	check(not Health.is_live_foe(dummy), "live dummy is not live foe")
	check(Health.is_host_alive(dummy), "live dummy is host alive")

	var plain := Node.new()
	check(not Health.has_alive_flag(plain), "plain Node has no alive flag")
	check(not Health.is_live_foe(plain), "plain Node is not live foe")
	check(Health.is_host_alive(plain), "plain Node is host alive")
	plain.free()

	check(not Health.has_alive_flag(null), "null has no alive flag")
	check(not Health.is_live_foe(null), "null is not live foe")
	check(Health.is_host_alive(null), "null is host alive")

	# Dead dummy never counts either way.
	dummy.call("take_damage", 200.0)
	check(bool(dummy.get("is_dead")), "lethal damage kills dummy")
	check(not Health.has_alive_flag(dummy), "dead dummy still has no alive flag")
	check(not Health.is_live_foe(dummy), "dead dummy is not live foe")
	check(Health.is_host_alive(dummy), "dead dummy is host alive")

	# Bare gun (null parent) stays fireable through the shared helper.
	var weapon_scr := load("res://scripts/weapons/weapon.gd") as Script
	check(weapon_scr != null, "weapon.gd loads as Script")
	if weapon_scr != null:
		var bare_gun = weapon_scr.new()
		root.add_child(bare_gun)
		await process_frame
		check(bool(bare_gun.call("_host_alive")), "bare gun (null parent) is host alive")
		root.remove_child(bare_gun)
		bare_gun.free()

	# Weapon delegates: dead host denies fire via the helper.
	var gun_soldier := soldier_packed.instantiate() as CharacterBody2D
	root.add_child(gun_soldier)
	await process_frame
	await process_frame
	var gun = gun_soldier.get_node_or_null("Weapon")
	check(gun != null, "soldier has Weapon child")
	if gun != null:
		check(bool(gun.call("_host_alive")), "live host gun is host alive")
		gun_soldier.call("take_damage", 200.0)
		check(not bool(gun.call("_host_alive")), "dead host gun is not host alive")
		check(not bool(gun.call("can_fire")), "dead host can_fire is false")
	gun_soldier.queue_free()
	await process_frame

	# Spawner delegates: live dummy ignored, live soldier repels, dead ignored.
	var spawner := Spawner.new()
	root.add_child(spawner)
	await process_frame
	await process_frame
	var foe_soldier := soldier_packed.instantiate() as CharacterBody2D
	root.add_child(foe_soldier)
	await process_frame
	await process_frame
	var foe_dummy := dummy_packed.instantiate() as StaticBody2D
	root.add_child(foe_dummy)
	await process_frame
	await process_frame
	foe_dummy.global_position = Vector2(400, 300)
	foe_soldier.global_position = Vector2(100, 300)
	var foes: Array[Vector2] = spawner.live_enemy_positions()
	check(foes.size() == 1, "soldier + dummy yield exactly one foe (got %d)" % foes.size())
	foe_soldier.call("take_damage", 200.0)
	foes = spawner.live_enemy_positions()
	check(foes.is_empty(), "dead soldier + live dummy yield no foes (got %d)" % foes.size())
	foe_soldier.queue_free()
	foe_dummy.queue_free()
	spawner.queue_free()
	await process_frame

	soldier.queue_free()
	dummy.queue_free()
	await process_frame

	# (b) Single-source delegation: weapon/spawner hold no literal, health holds one.
	var weapon_text := read_source("res://scripts/weapons/weapon.gd")
	var spawner_text := read_source("res://scripts/match/spawner.gd")
	var health_text := read_source("res://scripts/health.gd")
	check(not weapon_text.contains("\"is_alive\" in"), "weapon.gd holds no is_alive idiom literal")
	check(not spawner_text.contains("\"is_alive\" in"), "spawner.gd holds no is_alive idiom literal")
	check(weapon_text.contains("Health.is_host_alive"), "weapon.gd delegates to Health.is_host_alive")
	check(spawner_text.contains("Health.is_live_foe"), "spawner.gd delegates to Health.is_live_foe")
	check(health_text.count("\"is_alive\" in") == 1, "health.gd holds the idiom exactly once")
