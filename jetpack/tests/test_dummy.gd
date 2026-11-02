extends SceneTree
## Headless behavior tests for target dummies and tracer volume: 10x12
## damage kills a 100 HP dummy.tscn/dummy.gd, death signals once, hits
## flash, and a 2 s hold through weapon.gd Weapon on soldier.tscn leaves
## >=10 genuine Line2D tracers (weapon children, ArcPreview excluded) at tick 120.
## Run: godot --headless --path jetpack --script res://tests/test_dummy.gd

const EXPLOSION_SCRIPT := preload("res://scripts/fx/explosion.gd")

# Recording double for the race backup: take_damage fires even when flagged
# dead, unlike a real dummy whose own guard early-returns on is_dead and
# whose body takes no knockback. A zero call count therefore proves detonate
# itself skipped the node via the Health.is_dead guard.
class RaceProbe extends Node2D:
	var is_dead := false
	var hp := 100.0
	var velocity := Vector2.ZERO
	var take_damage_calls := 0
	func take_damage(amount: float) -> void:
		take_damage_calls += 1
		hp -= amount

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


func live_tracers_of(weapon: Node) -> Array:
	var out := []
	for c in weapon.get_children():
		if c is Line2D and is_instance_valid(c) and not (c as Node).is_queued_for_deletion():
			out.append(c)
	return out


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
	check(dummy.is_in_group("damageable"), "dummy joins damageable group")

	# Kill contract: 10 shots at 12 dmg drop a 100 HP dummy, one died signal.
	var died_count := [0]
	dummy.connect("died", func() -> void: died_count[0] += 1)
	check(float(dummy.get("hp")) > 0.0, "dummy starts alive (hp=%f)" % float(dummy.get("hp")))
	var kill_visual := dummy.get_node("Visual") as Polygon2D
	var kill_modulate_before := Color.WHITE
	if kill_visual != null:
		kill_modulate_before = kill_visual.modulate
	for i in 10:
		dummy.call("take_damage", 12.0)
	check(float(dummy.get("flash_t")) == 0.0, "lethal hit leaves no pending flash (flash_t==0)")
	check(kill_visual != null and kill_visual.color == Color(0.45, 0.45, 0.48, 1.0), "corpse born grey without hit-flash tint")
	check(kill_visual != null and kill_visual.modulate == kill_modulate_before, "corpse modulate untinted by lethal hit")
	check(float(dummy.get("hp")) <= 0.0, "10x12 dmg kills 100 HP dummy (hp=%f)" % float(dummy.get("hp")))
	check(bool(dummy.get("is_dead")), "dummy is_dead after lethal damage")
	check(died_count[0] == 1, "died emitted exactly once (got %d)" % died_count[0])
	check(not dummy.is_in_group("damageable"), "dead dummy leaves damageable group")
	dummy.call("take_damage", 12.0)
	check(bool(dummy.get("is_dead")), "post-death take_damage keeps is_dead")
	check(died_count[0] == 1, "post-death take_damage emits no second died")
	check(float(dummy.get("hp")) <= 0.0, "post-death hp stays <= 0")
	check(int(dummy.get("collision_layer")) == 0, "corpse collision_layer zeroed on death")
	check(int(dummy.get("collision_mask")) == 0, "corpse collision_mask zeroed on death")
	check_close(float(dummy.get("corpse_lifetime")), 3.0, 0.001, "corpse_lifetime defaults to 3.0")
	check(float(dummy.get("corpse_age")) == 0.0, "corpse timer armed at 0 on death")
	await process_frame
	check(is_instance_valid(dummy) and not dummy.is_queued_for_deletion(), "corpse still valid the frame after death")
	for i in 15:
		await process_frame
	check(float(dummy.get("flash_t")) == 0.0, "corpse stays flash-free across flash window")
	check(kill_visual != null and kill_visual.color == Color(0.45, 0.45, 0.48, 1.0), "corpse stays grey across flash window")
	check(is_instance_valid(dummy) and not dummy.is_queued_for_deletion(), "corpse still valid after flash window")

	# Flash contract: a fresh hit whitens the visual and arms flash_t.
	var flash_dummy := dummy_packed.instantiate() as StaticBody2D
	root.add_child(flash_dummy)
	await process_frame
	await process_frame
	var visual := flash_dummy.get_node("Visual") as Polygon2D
	check(visual != null, "flash dummy exposes Visual")
	var modulate_before := Color.WHITE
	var flash_base: Color = flash_dummy.get("_base_color")
	if visual != null:
		modulate_before = visual.modulate
	flash_dummy.call("take_damage", 10.0)
	check(float(flash_dummy.get("flash_t")) > 0.0, "hit arms flash_t (got %f)" % float(flash_dummy.get("flash_t")))
	check(visual != null and visual.color == Color.WHITE, "hit whitens dummy visual via color")
	check(visual != null and visual.modulate == modulate_before, "hit leaves modulate untouched")
	var flash_ticks := 0
	while float(flash_dummy.get("flash_t")) > 0.0 and flash_ticks < 60:
		await process_frame
		flash_ticks += 1
	await process_frame
	check(visual != null and visual.color == flash_base, "flash restores base color via color")

	# Blast contract: radial blasts hit dummies in the damageable group.
	var blast_dummy := dummy_packed.instantiate() as StaticBody2D
	root.add_child(blast_dummy)
	await process_frame
	await process_frame
	var blast_centre := Vector2(2000, -500)
	blast_dummy.global_position = blast_centre
	var boom := EXPLOSION_SCRIPT.new() as Node2D
	root.add_child(boom)
	boom.global_position = blast_centre
	var radius: float = boom.get("blast_radius")
	var max_dmg: float = boom.get("max_damage")
	var hp0 := float(blast_dummy.get("hp"))
	boom.call("detonate")
	var hp1 := float(blast_dummy.get("hp"))
	check(hp1 < hp0, "centre blast damages dummy (hp %f -> %f)" % [hp0, hp1])
	check_close(hp1, hp0 - max_dmg, 1.0, "centre blast deals full max_damage")
	boom.queue_free()
	var far_dummy := dummy_packed.instantiate() as StaticBody2D
	root.add_child(far_dummy)
	await process_frame
	await process_frame
	far_dummy.global_position = blast_centre + Vector2(radius + 50.0, 0.0)
	var boom2 := EXPLOSION_SCRIPT.new() as Node2D
	root.add_child(boom2)
	boom2.global_position = blast_centre
	var far_hp0 := float(far_dummy.get("hp"))
	boom2.call("detonate")
	check(float(far_dummy.get("hp")) == far_hp0, "out-of-radius blast spares dummy (hp=%f)" % float(far_dummy.get("hp")))
	boom2.queue_free()

	# Race backup: detonate itself must skip an externally-flagged-but-grouped
	# node even though group-leave never ran. The recording double stands in
	# for the race; the live control in the same blast proves the blast reached
	# the centre.
	var race_probe := RaceProbe.new()
	race_probe.set("is_dead", true)
	root.add_child(race_probe)
	var race_live := RaceProbe.new()
	race_live.set("is_dead", false)
	root.add_child(race_live)
	await process_frame
	await process_frame
	race_probe.global_position = blast_centre
	race_live.global_position = blast_centre
	race_probe.add_to_group("damageable")
	race_live.add_to_group("damageable")
	var race_hp0 := float(race_probe.get("hp"))
	check_close(race_hp0, 100.0, 0.001, "race probe keeps full HP when flagged")
	check(race_probe.is_in_group("damageable"), "flagged probe still grouped before race blast")
	check(race_live.is_in_group("damageable"), "live control grouped before race blast")
	check(Health.is_dead(race_probe), "externally-flagged probe reads dead")
	check(not Health.is_dead(race_live), "live control reads not dead")
	var boom3 := EXPLOSION_SCRIPT.new() as Node2D
	root.add_child(boom3)
	boom3.global_position = blast_centre
	var race_max: float = boom3.get("max_damage")
	boom3.call("detonate")
	check(int(race_probe.get("take_damage_calls")) == 0, "flagged-but-grouped blast never calls take_damage")
	check_close(float(race_probe.get("hp")), race_hp0, 0.001, "flagged-but-grouped blast deals no damage")
	check((race_probe.get("velocity") as Vector2).is_equal_approx(Vector2.ZERO), "flagged-but-grouped blast applies no knockback")
	check(race_probe.is_in_group("damageable"), "flagged probe still grouped after race blast")
	check(int(race_live.get("take_damage_calls")) == 1, "same blast hits the live control once")
	check_close(float(race_live.get("hp")), 100.0 - race_max, 0.001, "live control takes full centre damage")
	check((race_live.get("velocity") as Vector2).length() > 1.0, "live control takes knockback")
	boom3.queue_free()
	race_probe.queue_free()
	race_live.queue_free()

	# Tracer volume: hold fire 120 physics ticks for >=10 genuine
	# weapon-child Line2D tracers (soldier ArcPreview excluded). A 0.1 s
	# cooldown clears every 7th physics tick, so 60 ticks yield only 9
	# genuine tracers; the old root-wide >=10 passed on ArcPreview padding.
	# Hit-stop stretches cooldown recovery (60 ms at 0.2 scale per landed
	# hit), so the hold runs 120 ticks to land the same >=10 volume.
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
	await wait_physics(120)
	var held := live_tracers_of(weapon).size()
	check(held >= 10, "2 s hold leaves >=10 live tracers (got %d)" % held)
	# Weapon-children filter excludes the soldier ArcPreview Line2D.
	var arc := soldier.get_node_or_null("ArcPreview") as Line2D
	check(arc != null, "ArcPreview Line2D exists")
	var root_wide := root.find_children("*", "Line2D", true, false).size()
	check(root_wide >= held + 1, "root-wide count includes ArcPreview (root=%d weapon=%d)" % [root_wide, held])
	Input.action_release("fire")

	# Corpse expiry: a short-lifetime corpse frees itself, died still once.
	var corpse_dummy := dummy_packed.instantiate() as StaticBody2D
	root.add_child(corpse_dummy)
	await process_frame
	await process_frame
	corpse_dummy.set("corpse_lifetime", 0.4)
	var corpse_died := [0]
	corpse_dummy.connect("died", func() -> void: corpse_died[0] += 1)
	for i in 10:
		corpse_dummy.call("take_damage", 12.0)
	check(bool(corpse_dummy.get("is_dead")), "short-lifetime dummy is_dead after lethal damage")
	check(corpse_died[0] == 1, "short-lifetime died emitted once (got %d)" % corpse_died[0])
	check(not corpse_dummy.is_in_group("damageable"), "short-lifetime corpse leaves damageable group")
	check(int(corpse_dummy.get("collision_layer")) == 0, "short-lifetime corpse collision_layer zeroed")
	check(int(corpse_dummy.get("collision_mask")) == 0, "short-lifetime corpse collision_mask zeroed")
	check(is_instance_valid(corpse_dummy), "short-lifetime corpse valid right after death")
	corpse_dummy.call("take_damage", 12.0)
	check(corpse_died[0] == 1, "corpse-window take_damage emits no second died")
	var corpse_tick := -1
	for i in 90:
		await physics_frame
		if not is_instance_valid(corpse_dummy):
			corpse_tick = i + 1
			break
	check(corpse_tick >= 1, "short-lifetime corpse freed after its window (tick=%d)" % corpse_tick)
	check(not is_instance_valid(corpse_dummy), "corpse gone after lifetime")
	check(corpse_died[0] == 1, "freed corpse emitted died exactly once (got %d)" % corpse_died[0])
