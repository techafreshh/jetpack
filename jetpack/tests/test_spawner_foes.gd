extends SceneTree
## Headless regression for spawner foe selection: live dummies never count
## as foes in Spawner.live_enemy_positions, while live soldiers still repel
## respawns via Spawner.choose_spawn. Dummies stay in the damageable group.
## Run: godot --headless --path jetpack --script res://tests/test_spawner_foes.gd

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


func run_tests() -> void:
	await process_frame

	var cfg := ConfigFile.new()
	check(cfg.load("res://resources/config/spawns.cfg") == OK, "spawns.cfg loads")
	var pts: Array[Vector2] = []
	for i in 8:
		var v: Vector2 = cfg.get_value("spawn%d" % i, "pos", Vector2.INF)
		pts.append(v)
	check(pts.size() == 8, "cfg yields 8 spawn points")

	var spawner := Spawner.new()
	check(spawner != null, "Spawner instantiates")
	root.add_child(spawner)
	await process_frame
	await process_frame

	var soldier_packed := load("res://scenes/soldier.tscn") as PackedScene
	check(soldier_packed != null, "soldier.tscn loads as PackedScene")
	var dummy_packed := load("res://scenes/dummy.tscn") as PackedScene
	check(dummy_packed != null, "dummy.tscn loads as PackedScene")
	if soldier_packed == null or dummy_packed == null:
		spawner.queue_free()
		return

	# (a) A live dummy camping spawn 0 is not a foe: no repulsion.
	var dummy := dummy_packed.instantiate() as StaticBody2D
	root.add_child(dummy)
	await process_frame
	await process_frame
	check(dummy.is_in_group("damageable"), "dummy joins damageable group")
	check(not bool(dummy.get("is_dead")), "dummy starts live")
	dummy.global_position = pts[0]
	var foes: Array[Vector2] = spawner.live_enemy_positions()
	check(foes.is_empty(), "live dummy alone yields no foes (got %d)" % foes.size())
	check(Spawner.choose_spawn(pts, foes) == 0, "live dummy on spawn 0 does not repel (picks 0)")

	# (b) A live soldier on spawn 0 is a foe: respawns avoid it.
	var soldier := soldier_packed.instantiate() as CharacterBody2D
	root.add_child(soldier)
	await process_frame
	await process_frame
	check(soldier.is_in_group("damageable"), "soldier joins damageable group")
	check(bool(soldier.get("is_alive")), "soldier starts alive")
	dummy.global_position = pts[1]
	soldier.global_position = pts[0]
	foes = spawner.live_enemy_positions()
	check(foes.size() == 1, "soldier + dummy yield exactly one foe (got %d)" % foes.size())
	if foes.size() == 1:
		check(foes[0].distance_to(pts[0]) < 5.0, "the one foe is the soldier position")
	check(Spawner.choose_spawn(pts, foes) != 0, "live soldier on spawn 0 is avoided (got %d)" % Spawner.choose_spawn(pts, foes))

	# (c) Excluding the soldier (self) empties the foe list; dummy still ignored.
	foes = spawner.live_enemy_positions(soldier)
	check(foes.is_empty(), "exclude=self empties foes with live dummy present (got %d)" % foes.size())
	check(Spawner.choose_spawn(pts, foes) == 0, "excluded soldier picks index 0")

	# Killing the soldier empties the foe list while the dummy stays live.
	soldier.call("take_damage", 200.0)
	check(not bool(soldier.get("is_alive")), "lethal damage kills soldier")
	check(not bool(dummy.get("is_dead")), "dummy still live after soldier death")
	foes = spawner.live_enemy_positions()
	check(foes.is_empty(), "dead soldier + live dummy yield no foes (got %d)" % foes.size())
	check(Spawner.choose_spawn(pts, foes) == 0, "no live foes picks index 0")

	# (d) Killing the dummy changes nothing: it never counted, alive or dead.
	dummy.call("take_damage", 200.0)
	check(bool(dummy.get("is_dead")), "lethal damage kills dummy")
	check(dummy.is_in_group("damageable"), "dead dummy stays in damageable group")
	foes = spawner.live_enemy_positions()
	check(foes.is_empty(), "dead dummy yields no foes (got %d)" % foes.size())
	check(Spawner.choose_spawn(pts, foes) == 0, "dead dummy picks index 0")

	soldier.queue_free()
	dummy.queue_free()
	spawner.queue_free()
