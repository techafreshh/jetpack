extends SceneTree
## Headless behavior tests for pickups: scene/script contract, health heal
## with disabled respawn window, weapon crates (explicit + kind-alias),
## ammo/grenade restock, re-trigger guard, and the visible timer label.
## Run: godot --headless --path jetpack --script res://tests/test_pickup.gd

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


func make_soldier():
	var packed := load("res://scenes/soldier.tscn") as PackedScene
	if packed == null:
		return null
	var soldier := packed.instantiate() as CharacterBody2D
	soldier.position = Vector2(0, -40)
	root.add_child(soldier)
	await process_frame
	await process_frame
	return soldier


func make_pickup(p_kind: String, wid: String = "scatter", respawn: float = 15.0):
	var packed := load("res://scenes/pickup.tscn") as PackedScene
	if packed == null:
		return null
	var pad := packed.instantiate() as Area2D
	pad.position = Vector2(2000, -500)
	pad.set("kind", p_kind)
	pad.set("weapon_id", wid)
	pad.set("respawn_s", respawn)
	root.add_child(pad)
	await process_frame
	await process_frame
	return pad


func run_tests() -> void:
	await process_frame

	var cfg := ConfigFile.new()
	check(cfg.load("res://resources/config/pickups.cfg") == OK, "pickups.cfg loads")
	check(float(cfg.get_value("health", "heal_amount", 0.0)) >= 25.0, "cfg heal_amount restores >=75 from 50")
	check(float(cfg.get_value("health", "respawn_s", 0.0)) >= 10.0, "cfg health respawn_s >= 10")

	# (a) Scene loads and the script exports respawn_s/kind.
	var packed := load("res://scenes/pickup.tscn") as PackedScene
	check(packed != null, "pickup.tscn loads as PackedScene")
	if packed == null:
		return
	var probe := packed.instantiate() as Area2D
	check(probe != null, "pickup.tscn instantiates Area2D")
	if probe == null:
		return
	var names := []
	for prop in probe.get_property_list():
		names.append(String(prop["name"]))
	check(names.has("respawn_s"), "pickup.gd exports respawn_s")
	check(names.has("kind"), "pickup.gd exports kind")
	root.add_child(probe)
	await process_frame
	await process_frame
	check(probe.is_in_group("pickup"), "pickup joins pickup group")
	check(probe.get_node_or_null("Visual") != null, "pickup has Visual node")
	check(probe.get_node_or_null("TimerLabel") != null, "pickup has TimerLabel node")
	probe.queue_free()
	await process_frame

	var soldier = await make_soldier()
	check(soldier != null, "soldier instantiates for pickup tests")
	if soldier == null:
		return

	# (b) Health pack at 50 HP heals to >=75 and disables for >=10 s.
	var hp_pack = await make_pickup("health", "scatter", 15.0)
	check(hp_pack != null, "health pack instantiates")
	soldier.set("hp", 50.0)
	check(float(hp_pack.get("respawn_s")) >= 10.0, "health respawn_s >= 10 (got %f)" % float(hp_pack.get("respawn_s")))
	check(bool(hp_pack.call("apply_to", soldier)), "health apply_to returns true")
	check(float(soldier.get("hp")) >= 75.0, "health heals 50 to >=75 (got %f)" % float(soldier.get("hp")))
	check(bool(hp_pack.get("disabled")), "health pad enters disabled state")
	var label = hp_pack.get_node_or_null("TimerLabel")
	check(label != null and String(label.get("text")) != "", "disabled pad shows timer label")
	# Disabled pad ignores re-trigger.
	soldier.set("hp", 50.0)
	check(not bool(hp_pack.call("apply_to", soldier)), "disabled pad ignores re-trigger")
	check_close(float(soldier.get("hp")), 50.0, 0.01, "re-trigger leaves HP untouched")
	hp_pack.queue_free()
	await process_frame

	# (b2) Full-HP walkover is ignored and the pad stays armed.
	var full_pad = await make_pickup("health", "scatter", 15.0)
	check(full_pad != null, "full-HP pad instantiates")
	soldier.set("hp", float(soldier.get("max_hp")))
	var full_hp_before := float(soldier.get("hp"))
	check(not bool(full_pad.call("apply_to", soldier)), "full-HP apply_to returns false")
	check(not bool(full_pad.get("disabled")), "full-HP pad stays enabled")
	check_close(float(full_pad.get("time_left")), 0.0, 0.01, "full-HP pad sets no timer")
	var full_label = full_pad.get_node_or_null("TimerLabel")
	check(full_label != null and String(full_label.get("text")) == "", "full-HP pad shows no timer label")
	check_close(float(soldier.get("hp")), full_hp_before, 0.01, "full-HP walkover leaves HP unchanged")
	# Same pad still consumes normally once the soldier is hurt.
	soldier.set("hp", 50.0)
	check(bool(full_pad.call("apply_to", soldier)), "hurt apply_to on same pad returns true")
	check(float(soldier.get("hp")) >= 75.0, "same pad heals once hurt (got %f)" % float(soldier.get("hp")))
	check(bool(full_pad.get("disabled")), "same pad enters disabled state")
	var full_label2 = full_pad.get_node_or_null("TimerLabel")
	check(full_label2 != null and String(full_label2.get("text")) != "", "consumed pad shows timer label")
	full_pad.queue_free()
	await process_frame

	# (b3) Corpse walkover is ignored and the pad stays armed.
	var corpse_pad = await make_pickup("health", "scatter", 15.0)
	check(corpse_pad != null, "corpse pad instantiates")
	soldier.set("hp", float(soldier.get("max_hp")))
	soldier.set("is_alive", true)
	soldier.call("take_damage", 200.0)
	check_close(float(soldier.get("hp")), 0.0, 0.01, "corpse setup HP is 0")
	check(not bool(soldier.get("is_alive")), "corpse setup is_alive is false")
	check(not bool(corpse_pad.call("apply_to", soldier)), "corpse apply_to returns false")
	check(not bool(corpse_pad.get("disabled")), "corpse pad stays enabled")
	check_close(float(corpse_pad.get("time_left")), 0.0, 0.01, "corpse pad sets no timer")
	var corpse_label = corpse_pad.get_node_or_null("TimerLabel")
	check(corpse_label != null and String(corpse_label.get("text")) == "", "corpse pad shows no timer label")
	check_close(float(soldier.get("hp")), 0.0, 0.01, "corpse walkover leaves HP unchanged")
	# Same pad still heals the next live hurt soldier with no respawn wait.
	soldier.set("is_alive", true)
	soldier.set("hp", 50.0)
	check(bool(corpse_pad.call("apply_to", soldier)), "hurt apply_to on corpse pad returns true")
	check(float(soldier.get("hp")) >= 75.0, "corpse pad heals once hurt (got %f)" % float(soldier.get("hp")))
	check(bool(corpse_pad.get("disabled")), "corpse pad enters disabled state")
	var corpse_label2 = corpse_pad.get_node_or_null("TimerLabel")
	check(corpse_label2 != null and String(corpse_label2.get("text")) != "", "consumed corpse pad shows timer label")
	corpse_pad.queue_free()
	await process_frame

	# (b4) Corpse weapon-crate walkover is refused and the pad stays armed.
	# The soldier owns the gate: add_weapon returns false while dead, so the
	# weapon/alias branches in pickup apply_to treat it as refusal.
	var corpse_crate = await make_pickup("weapon", "scatter", 12.0)
	check(corpse_crate != null, "corpse weapon crate instantiates")
	(soldier.get("slots") as Array).clear()
	(soldier.get("slots") as Array).append("ranger_ar")
	soldier.call("take_damage", 200.0)
	check(not bool(soldier.get("is_alive")), "corpse crate setup is_alive is false")
	check(not bool(corpse_crate.call("apply_to", soldier)), "corpse weapon apply_to returns false")
	check(not (soldier.get("slots") as Array).has("scatter"), "corpse weapon walkover adds no scatter")
	check(not bool(corpse_crate.get("disabled")), "corpse weapon pad stays enabled")
	check_close(float(corpse_crate.get("time_left")), 0.0, 0.01, "corpse weapon pad sets no timer")
	var corpse_crate_label = corpse_crate.get_node_or_null("TimerLabel")
	check(corpse_crate_label != null and String(corpse_crate_label.get("text")) == "", "corpse weapon pad shows no timer label")
	# Same crate still serves a live soldier with no respawn wait.
	soldier.set("is_alive", true)
	soldier.set("hp", 50.0)
	check(bool(corpse_crate.call("apply_to", soldier)), "live apply_to on corpse weapon pad returns true")
	check((soldier.get("slots") as Array).has("scatter"), "same weapon pad grants scatter once live")
	check(bool(corpse_crate.get("disabled")), "same weapon pad enters disabled state")
	var corpse_crate_label2 = corpse_crate.get_node_or_null("TimerLabel")
	check(corpse_crate_label2 != null and String(corpse_crate_label2.get("text")) != "", "consumed weapon pad shows timer label")
	corpse_crate.queue_free()
	await process_frame

	# (c) Weapon crate grants scatter and respawns within 20 s.
	var crate = await make_pickup("weapon", "scatter", 12.0)
	check(crate != null, "weapon crate instantiates")
	check(float(crate.get("respawn_s")) <= 20.0, "crate respawns within 20s (got %f)" % float(crate.get("respawn_s")))
	var slots: Array = soldier.get("slots")
	slots.clear()
	slots.append("ranger_ar")
	check(bool(crate.call("apply_to", soldier)), "crate apply_to returns true")
	check((soldier.get("slots") as Array).has("scatter"), "soldier slots contains scatter")
	check(bool(crate.get("disabled")), "crate enters disabled state")
	crate.queue_free()
	await process_frame
	# Kind-is-weapon-id alias also grants.
	var alias_pack = await make_pickup("scatter", "scatter", 12.0)
	check(alias_pack != null, "alias crate instantiates")
	(soldier.get("slots") as Array).clear()
	(soldier.get("slots") as Array).append("ranger_ar")
	check(bool(alias_pack.call("apply_to", soldier)), "alias apply_to returns true")
	check((soldier.get("slots") as Array).has("scatter"), "alias kind scatter grants scatter")
	alias_pack.queue_free()
	await process_frame

	# (d) Ammo pad refills an emptied mag; grenade pad restores max.
	var weapon = soldier.get_node_or_null("Weapon")
	check(weapon != null, "soldier has Weapon child for restock")
	if weapon != null:
		while int(weapon.get("ammo")) > 0:
			weapon.set("_cooldown", 0.0)
			weapon.call("consume_shot")
		check(int(weapon.get("ammo")) == 0, "mag emptied for ammo test")
		var ammo_pad = await make_pickup("ammo", "scatter", 10.0)
		check(bool(ammo_pad.call("apply_to", soldier)), "ammo apply_to returns true")
		check(int(weapon.get("ammo")) == int(weapon.get("stats").get("mag_size")), "ammo pad refills mag")
		check(int(weapon.get("reserve_left")) == int(weapon.get("stats").get("reserve")), "ammo pad refills reserve")
		ammo_pad.queue_free()
		await process_frame
		# (d2) Full-ammo walkover is ignored and the pad stays armed.
		var full_ammo_pad = await make_pickup("ammo", "scatter", 10.0)
		check(full_ammo_pad != null, "full-ammo pad instantiates")
		check(not bool(full_ammo_pad.call("apply_to", soldier)), "full-ammo apply_to returns false")
		check(not bool(full_ammo_pad.get("disabled")), "full-ammo pad stays enabled")
		check_close(float(full_ammo_pad.get("time_left")), 0.0, 0.01, "full-ammo pad sets no timer")
		var full_ammo_label = full_ammo_pad.get_node_or_null("TimerLabel")
		check(full_ammo_label != null and String(full_ammo_label.get("text")) == "", "full-ammo pad shows no timer label")
		weapon.set("_cooldown", 0.0)
		weapon.call("consume_shot")
		check(bool(full_ammo_pad.call("apply_to", soldier)), "spent apply_to on same pad returns true")
		check(int(weapon.get("ammo")) == int(weapon.get("stats").get("mag_size")), "same pad refills mag once spent")
		check(int(weapon.get("reserve_left")) == int(weapon.get("stats").get("reserve")), "same pad refills reserve once spent")
		check(bool(full_ammo_pad.get("disabled")), "same pad enters disabled state")
		var full_ammo_label2 = full_ammo_pad.get_node_or_null("TimerLabel")
		check(full_ammo_label2 != null and String(full_ammo_label2.get("text")) != "", "consumed ammo pad shows timer label")
		full_ammo_pad.queue_free()
		await process_frame
	soldier.set("grenade_count", 0)
	var nade_pad = await make_pickup("grenade", "scatter", 10.0)
	check(nade_pad != null, "grenade pad instantiates")
	check(bool(nade_pad.call("apply_to", soldier)), "grenade apply_to returns true")
	check(int(soldier.get("grenade_count")) == int(soldier.get("grenade_max")), "grenade pad restores max")
	nade_pad.queue_free()
	await process_frame

	# (d3) Full-grenade walkover is ignored and the pad stays armed.
	var full_nade_pad = await make_pickup("grenade", "scatter", 10.0)
	check(full_nade_pad != null, "full-grenade pad instantiates")
	soldier.set("grenade_count", int(soldier.get("grenade_max")))
	var full_nades_before := int(soldier.get("grenade_count"))
	check(not bool(full_nade_pad.call("apply_to", soldier)), "full-grenade apply_to returns false")
	check(not bool(full_nade_pad.get("disabled")), "full-grenade pad stays enabled")
	check_close(float(full_nade_pad.get("time_left")), 0.0, 0.01, "full-grenade pad sets no timer")
	var full_nade_label = full_nade_pad.get_node_or_null("TimerLabel")
	check(full_nade_label != null and String(full_nade_label.get("text")) == "", "full-grenade pad shows no timer label")
	check(int(soldier.get("grenade_count")) == full_nades_before, "full-grenade walkover leaves count unchanged")
	# Same pad still consumes normally once the soldier is below max.
	soldier.set("grenade_count", 0)
	check(bool(full_nade_pad.call("apply_to", soldier)), "empty apply_to on same grenade pad returns true")
	check(int(soldier.get("grenade_count")) == int(soldier.get("grenade_max")), "same grenade pad restores max once empty")
	check(bool(full_nade_pad.get("disabled")), "same grenade pad enters disabled state")
	var full_nade_label2 = full_nade_pad.get_node_or_null("TimerLabel")
	check(full_nade_label2 != null and String(full_nade_label2.get("text")) != "", "consumed grenade pad shows timer label")
	full_nade_pad.queue_free()
	await process_frame

	# (d4) Corpse walkover on ammo/grenade pads stays armed.
	var corpse_ammo_pad = await make_pickup("ammo", "scatter", 10.0)
	check(corpse_ammo_pad != null, "corpse ammo pad instantiates")
	var corpse_nade_pad = await make_pickup("grenade", "scatter", 10.0)
	check(corpse_nade_pad != null, "corpse grenade pad instantiates")
	soldier.set("hp", float(soldier.get("max_hp")))
	soldier.set("is_alive", true)
	soldier.call("take_damage", 200.0)
	check(not bool(soldier.get("is_alive")), "corpse pad setup is_alive is false")
	check(not bool(corpse_ammo_pad.call("apply_to", soldier)), "corpse ammo apply_to returns false")
	check(not bool(corpse_ammo_pad.get("disabled")), "corpse ammo pad stays enabled")
	check_close(float(corpse_ammo_pad.get("time_left")), 0.0, 0.01, "corpse ammo pad sets no timer")
	var corpse_ammo_label = corpse_ammo_pad.get_node_or_null("TimerLabel")
	check(corpse_ammo_label != null and String(corpse_ammo_label.get("text")) == "", "corpse ammo pad shows no timer label")
	check(not bool(corpse_nade_pad.call("apply_to", soldier)), "corpse grenade apply_to returns false")
	check(not bool(corpse_nade_pad.get("disabled")), "corpse grenade pad stays enabled")
	check_close(float(corpse_nade_pad.get("time_left")), 0.0, 0.01, "corpse grenade pad sets no timer")
	var corpse_nade_label = corpse_nade_pad.get_node_or_null("TimerLabel")
	check(corpse_nade_label != null and String(corpse_nade_label.get("text")) == "", "corpse grenade pad shows no timer label")
	# Same pads still consume for a live soldier with partial stock.
	soldier.set("is_alive", true)
	soldier.set("hp", 50.0)
	var corpse_weapon = soldier.get_node_or_null("Weapon")
	if corpse_weapon != null:
		corpse_weapon.set("ammo", 0)
	soldier.set("grenade_count", 0)
	check(bool(corpse_ammo_pad.call("apply_to", soldier)), "live apply_to on corpse ammo pad returns true")
	check(bool(corpse_ammo_pad.get("disabled")), "corpse ammo pad enters disabled state")
	check(bool(corpse_nade_pad.call("apply_to", soldier)), "live apply_to on corpse grenade pad returns true")
	check(int(soldier.get("grenade_count")) == int(soldier.get("grenade_max")), "corpse grenade pad restores max once live")
	check(bool(corpse_nade_pad.get("disabled")), "corpse grenade pad enters disabled state")
	corpse_ammo_pad.queue_free()
	corpse_nade_pad.queue_free()
	await process_frame

	# (e) Short-timer pad re-enables after expiry and clears the label.
	var quick = await make_pickup("health", "scatter", 0.3)
	soldier.set("hp", 50.0)
	check(bool(quick.call("apply_to", soldier)), "quick pad applies")
	check(bool(quick.get("disabled")), "quick pad disabled after pickup")
	await wait_physics(30)
	check(not bool(quick.get("disabled")), "quick pad respawns after timer")
	var qlabel = quick.get_node_or_null("TimerLabel")
	check(qlabel != null and String(qlabel.get("text")) == "", "timer label clears on respawn")
	# Re-armed pad picks up again.
	soldier.set("hp", 50.0)
	check(bool(quick.call("apply_to", soldier)), "respawned pad picks up again")
	check(float(soldier.get("hp")) >= 75.0, "respawned pad still heals")
	quick.queue_free()
	await process_frame

	soldier.queue_free()
	await process_frame
