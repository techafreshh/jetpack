extends SceneTree
## Headless behavior proof for the HUD: node paths, HP/ammo polling,
## death overlay with killer plus respawn countdown, grenade pips,
## targetless safety, and match.tscn seating.
## Run: godot --headless --path jetpack --script res://tests/test_hud.gd

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


func lit_pips(hud: Node) -> int:
	var pips := hud.get_node_or_null("grenade_pips")
	if pips == null:
		return -1
	var lit := 0
	for i in pips.get_child_count():
		var rect := pips.get_child(i) as ColorRect
		if rect == null:
			continue
		if rect.color.r > 0.9 and rect.color.g > 0.6:
			lit += 1
	return lit


func run_tests() -> void:
	await process_frame

	# (a) Standalone HUD exposes the acceptance paths.
	var hud_packed := load("res://scenes/ui/hud.tscn") as PackedScene
	check(hud_packed != null, "hud.tscn loads as PackedScene")
	if hud_packed == null:
		return
	var hud := hud_packed.instantiate() as CanvasLayer
	check(hud != null, "hud.tscn instantiates CanvasLayer")
	if hud == null:
		return
	check(hud.name == "hud", "hud root is named hud (got %s)" % hud.name)
	root.add_child(hud)
	await process_frame
	await process_frame
	for path in ["hud/hp_bar", "hud/ammo_label", "hud/grenade_pips", "hud/timer_label", "hud/crosshair"]:
		check(root.get_node_or_null(path) != null, "tree root resolves %s" % path)
	for child in ["hp_bar", "ammo_label", "grenade_pips", "timer_label", "crosshair"]:
		check(hud.get_node_or_null(child) != null, "hud exposes direct child %s" % child)
	check(hud.get_node_or_null("death_overlay") != null, "hud exposes death_overlay")
	check(hud.get_node_or_null("death_overlay/death_label") != null, "hud exposes death_overlay/death_label")
	var overlay := hud.get_node_or_null("death_overlay") as Control
	check(overlay != null and not overlay.visible, "targetless HUD keeps death overlay hidden")

	# (b) HP/ammo polling: soldier hp 42, weapon 17/90.
	var soldier_packed := load("res://scenes/soldier.tscn") as PackedScene
	check(soldier_packed != null, "soldier.tscn loads as PackedScene")
	if soldier_packed == null:
		return
	var soldier := soldier_packed.instantiate() as CharacterBody2D
	check(soldier != null, "soldier.tscn instantiates CharacterBody2D")
	if soldier == null:
		return
	soldier.position = Vector2(0, -40)
	root.add_child(soldier)
	await process_frame
	await process_frame
	soldier.set("hp", 42.0)
	var weapon := soldier.get_node_or_null("Weapon")
	check(weapon != null, "soldier exposes Weapon child")
	if weapon != null:
		weapon.set("ammo", 17)
		weapon.set("reserve_left", 90)
	if hud.has_method("bind_soldier"):
		hud.call("bind_soldier", soldier)
	await wait_physics(5)
	var hp_bar := hud.get_node_or_null("hp_bar") as ProgressBar
	var ammo_label := hud.get_node_or_null("ammo_label") as Label
	check(hp_bar != null, "hud has hp_bar progress")
	check(ammo_label != null, "hud has ammo_label")
	if hp_bar != null:
		check_close(float(hp_bar.value), 42.0, 0.01, "hp_bar.value equals 42")
	if ammo_label != null:
		check(ammo_label.text == "17 / 90", "ammo_label.text is 17 / 90 (got %s)" % ammo_label.text)

	# (d) Grenade pips track grenade_count.
	soldier.set("grenade_count", 1)
	await wait_physics(5)
	var pips := hud.get_node_or_null("grenade_pips")
	check(pips != null, "hud has grenade_pips")
	if pips != null:
		check(pips.get_child_count() == int(soldier.get("grenade_max")), "pips total equals grenade_max (got %d)" % pips.get_child_count())
		check(lit_pips(hud) == 1, "one lit pip for grenade_count 1 (got %d)" % lit_pips(hud))
	soldier.set("grenade_count", 2)
	await wait_physics(5)
	check(lit_pips(hud) == 2, "two lit pips for grenade_count 2 (got %d)" % lit_pips(hud))

	# (c) Lethal damage shows the death overlay with killer and countdown.
	soldier.set("hp", 100.0)
	soldier.set("grenade_count", 2)
	await wait_physics(2)
	soldier.call("take_damage", 200.0, "bot_7")
	await wait_physics(5)
	check(not bool(soldier.get("is_alive")), "lethal damage kills soldier")
	check(str(soldier.get("last_killer")) == "bot_7", "soldier records killer bot_7 (got %s)" % str(soldier.get("last_killer")))
	overlay = hud.get_node_or_null("death_overlay") as Control
	var death_label := hud.get_node_or_null("death_overlay/death_label") as Label
	check(overlay != null and overlay.visible, "death_overlay.visible after death")
	if death_label != null:
		check(death_label.text.contains("Respawning in"), "death label holds Respawning in (got %s)" % death_label.text)
		check(death_label.text.contains("bot_7"), "death label names killer bot_7 (got %s)" % death_label.text)
	var came_back := false
	for i in 220:
		await physics_frame
		if bool(soldier.get("is_alive")):
			came_back = true
			break
	check(came_back, "soldier respawns after lethal hit")
	await wait_physics(3)
	overlay = hud.get_node_or_null("death_overlay") as Control
	check(overlay != null and not overlay.visible, "death overlay hides after respawn")
	soldier.queue_free()
	hud.queue_free()
	await process_frame

	# (e) Targetless HUD runs frames error-free with overlay hidden.
	var lone := hud_packed.instantiate() as CanvasLayer
	root.add_child(lone)
	await process_frame
	await wait_physics(5)
	check(is_instance_valid(lone), "targetless HUD stays valid")
	var lone_overlay := lone.get_node_or_null("death_overlay") as Control
	check(lone_overlay != null and not lone_overlay.visible, "targetless overlay stays hidden")
	var lone_ammo := lone.get_node_or_null("ammo_label") as Label
	check(lone_ammo != null and lone_ammo.text == "0 / 0", "targetless ammo reads 0 / 0 (got %s)" % (lone_ammo.text if lone_ammo != null else "<null>"))
	lone.queue_free()
	await process_frame

	# (f) match.tscn seats hud and reflects match-soldier damage.
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
	await wait_physics(5)
	for path in ["hud/hp_bar", "hud/ammo_label", "hud/grenade_pips", "hud/timer_label", "hud/crosshair"]:
		check(host.get_node_or_null(path) != null, "match seats %s" % path)
	var match_hud := host.get_node_or_null("hud")
	check(match_hud != null, "match has hud child")
	var match_soldier := host.get_node_or_null("Soldier") as CharacterBody2D
	check(match_soldier != null, "match has Soldier node")
	if match_soldier != null and match_hud != null:
		match_soldier.set("hp", 42.0)
		var match_weapon := match_soldier.get_node_or_null("Weapon")
		if match_weapon != null:
			match_weapon.set("ammo", 17)
			match_weapon.set("reserve_left", 90)
		await wait_physics(5)
		var match_hp := host.get_node_or_null("hud/hp_bar") as ProgressBar
		var match_ammo := host.get_node_or_null("hud/ammo_label") as Label
		if match_hp != null:
			check_close(float(match_hp.value), 42.0, 0.01, "match hud hp_bar tracks 42")
		if match_ammo != null:
			check(match_ammo.text == "17 / 90", "match hud ammo tracks 17 / 90 (got %s)" % match_ammo.text)
	host.queue_free()
	await process_frame
