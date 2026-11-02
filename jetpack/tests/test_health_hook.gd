extends SceneTree
## Headless proof that the health_changed hook is consumed: dummy and soldier
## emit exact payloads, and the match host caches the latest HP for HUD use.
## Run: godot --headless --path jetpack --script res://tests/test_health_hook.gd

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


func run_tests() -> void:
	await process_frame

	# (a) Dummy signal contract: one 12-dmg hit emits hp 88 / max 100 once.
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
	var dummy_hits: Array = []
	dummy.connect("health_changed", func(hp: float, max_hp: float) -> void: dummy_hits.append([hp, max_hp]))
	dummy.call("take_damage", 12.0)
	check(dummy_hits.size() == 1, "dummy emits health_changed once per hit (got %d)" % dummy_hits.size())
	if dummy_hits.size() >= 1:
		check(is_equal_approx(float(dummy_hits[0][0]), 88.0), "dummy health_changed hp is 88 (got %f)" % float(dummy_hits[0][0]))
		check(is_equal_approx(float(dummy_hits[0][1]), 100.0), "dummy health_changed max_hp is 100 (got %f)" % float(dummy_hits[0][1]))
	dummy.queue_free()

	# (b) Soldier signal contract: one 12-dmg hit emits hp 88 / max 100 once.
	var soldier_packed := load("res://scenes/soldier.tscn") as PackedScene
	check(soldier_packed != null, "soldier.tscn loads as PackedScene")
	if soldier_packed == null:
		return
	var soldier := soldier_packed.instantiate() as CharacterBody2D
	check(soldier != null, "soldier.tscn instantiates CharacterBody2D")
	if soldier == null:
		return
	root.add_child(soldier)
	await process_frame
	await process_frame
	var soldier_hits: Array = []
	soldier.connect("health_changed", func(hp: float, max_hp: float) -> void: soldier_hits.append([hp, max_hp]))
	soldier.call("take_damage", 12.0)
	check(soldier_hits.size() == 1, "soldier emits health_changed once per hit (got %d)" % soldier_hits.size())
	if soldier_hits.size() >= 1:
		check(is_equal_approx(float(soldier_hits[0][0]), 88.0), "soldier health_changed hp is 88 (got %f)" % float(soldier_hits[0][0]))
		check(is_equal_approx(float(soldier_hits[0][1]), 100.0), "soldier health_changed max_hp is 100 (got %f)" % float(soldier_hits[0][1]))
	soldier.queue_free()

	# (c) Match host consumes the hook: cache starts at sentinel, tracks hits.
	var match_packed := load("res://scenes/match.tscn") as PackedScene
	check(match_packed != null, "match.tscn loads as PackedScene")
	if match_packed == null:
		return
	var host := match_packed.instantiate() as Node2D
	check(host != null, "match.tscn instantiates Node2D")
	if host == null:
		return
	root.add_child(host)
	await process_frame
	await process_frame
	check(is_equal_approx(float(host.get("last_hp")), -1.0), "match cache starts at sentinel (got %f)" % float(host.get("last_hp")))
	var match_soldier := host.get_node("Soldier") as CharacterBody2D
	check(match_soldier != null, "match has Soldier node")
	if match_soldier == null:
		return
	match_soldier.call("take_damage", 12.0)
	await process_frame
	check(is_equal_approx(float(host.get("last_hp")), 88.0), "match cache updates to 88 after one hit (got %f)" % float(host.get("last_hp")))
	check(is_equal_approx(float(host.get("last_max_hp")), 100.0), "match cache max_hp is 100 (got %f)" % float(host.get("last_max_hp")))
	match_soldier.call("take_damage", 12.0)
	await process_frame
	check(is_equal_approx(float(host.get("last_hp")), 76.0), "match cache tracks second hit to 76 (got %f)" % float(host.get("last_hp")))
	# (d) Match forwards death/respawn: kill-feed hook with cause and HP refresh.
	var died_fwd := [0]
	var respawned_fwd := [0]
	host.connect("soldier_died", func() -> void: died_fwd[0] += 1)
	host.connect("soldier_respawned", func() -> void: respawned_fwd[0] += 1)
	check(int(host.get("death_count")) == 0, "match death_count starts at 0 (got %d)" % int(host.get("death_count")))
	check(int(host.get("respawn_count")) == 0, "match respawn_count starts at 0 (got %d)" % int(host.get("respawn_count")))
	match_soldier.call("take_damage", 200.0)
	await process_frame
	check(int(host.get("death_count")) == 1, "match death_count is 1 after lethal hit (got %d)" % int(host.get("death_count")))
	check(str(host.get("last_death_cause")) == "damage", "match caches death cause damage (got %s)" % str(host.get("last_death_cause")))
	check(died_fwd[0] == 1, "match soldier_died forwarded exactly once (got %d)" % died_fwd[0])
	match_soldier.call("take_damage", 50.0)
	await process_frame
	check(int(host.get("death_count")) == 1, "post-death take_damage emits no second match death (got %d)" % int(host.get("death_count")))
	check(died_fwd[0] == 1, "post-death soldier_died still exactly once (got %d)" % died_fwd[0])
	var match_alive := false
	for i in 220:
		await physics_frame
		if bool(match_soldier.get("is_alive")):
			match_alive = true
			break
	check(match_alive, "match soldier respawns after lethal hit")
	check(int(host.get("respawn_count")) == 1, "match respawn_count is 1 after respawn (got %d)" % int(host.get("respawn_count")))
	check(respawned_fwd[0] == 1, "match soldier_respawned forwarded exactly once (got %d)" % respawned_fwd[0])
	check(is_equal_approx(float(host.get("last_hp")), float(host.get("last_max_hp"))), "match HP cache refreshed to full on respawn (got %f / %f)" % [float(host.get("last_hp")), float(host.get("last_max_hp"))])
	check(is_equal_approx(float(host.get("last_hp")), float(match_soldier.get("max_hp"))), "match HP cache equals soldier max_hp after respawn (got %f)" % float(host.get("last_hp")))
	host.queue_free()
