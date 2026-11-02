extends SceneTree
## Headless proof for BotPilot utility AI: cfg tolerances per tier, tiers
## differing only in reaction/aim, 60-tick reload-or-retreat under fire with
## an empty mag, LOS occlusion with 3s last-seen memory (no wall-hack fire),
## and a short 2-bot arena smoke run proving displacement and live fire.
## Run: godot --headless --path jetpack --script res://tests/test_bots.gd

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


func make_floor() -> StaticBody2D:
	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2.ZERO
	var shape := CollisionShape2D.new()
	var edge := WorldBoundaryShape2D.new()
	shape.shape = edge
	floor_body.add_child(shape)
	root.add_child(floor_body)
	return floor_body


func make_soldier(pos: Vector2, diff: String) -> CharacterBody2D:
	var packed := load("res://scenes/soldier.tscn") as PackedScene
	var soldier := packed.instantiate() as CharacterBody2D
	soldier.position = pos
	root.add_child(soldier)
	await process_frame
	await process_frame
	var pilot := BotPilot.new(diff)
	soldier.call("set_pilot", pilot)
	await process_frame
	return soldier


func run_tests() -> void:
	await process_frame

	# (a) bots.cfg parses with exact tier values inside issue tolerances.
	var cfg := ConfigFile.new()
	check(cfg.load("res://resources/config/bots.cfg") == OK, "bots.cfg loads")
	check_close(float(cfg.get_value("easy", "reaction_ms", 0.0)), 250.0, 20.0, "easy reaction 250ms +/-20")
	check_close(float(cfg.get_value("standard", "reaction_ms", 0.0)), 140.0, 20.0, "standard reaction 140ms +/-20")
	check_close(float(cfg.get_value("sharp", "reaction_ms", 0.0)), 70.0, 20.0, "sharp reaction 70ms +/-20")
	check_close(float(cfg.get_value("easy", "aim_error_deg", 0.0)), 8.0, 0.5, "easy aim 8.0deg +/-0.5")
	check_close(float(cfg.get_value("standard", "aim_error_deg", 0.0)), 4.0, 0.5, "standard aim 4.0deg +/-0.5")
	check_close(float(cfg.get_value("sharp", "aim_error_deg", 0.0)), 1.5, 0.5, "sharp aim 1.5deg +/-0.5")
	# Aliases duplicate the canonical values.
	check_close(float(cfg.get_value("easy", "reaction_delay_ms", 0.0)), 250.0, 0.01, "easy alias reaction_delay_ms")
	check_close(float(cfg.get_value("sharp", "aim_error", 0.0)), 1.5, 0.01, "sharp alias aim_error")
	check_close(float(cfg.get_value("standard", "spread_deg", 0.0)), 4.0, 0.01, "standard alias spread_deg")
	check_close(float(cfg.get_value("perception", "memory_s", 0.0)), 3.0, 0.01, "perception memory 3.0s")

	# (b) Tiers differ only in reaction delay and aim error.
	var easy := BotPilot.new("easy")
	var standard := BotPilot.new("standard")
	var sharp := BotPilot.new("sharp")
	check_close(float(easy.reaction_ms), 250.0, 0.01, "easy pilot reaction 250")
	check_close(float(standard.reaction_ms), 140.0, 0.01, "standard pilot reaction 140")
	check_close(float(sharp.reaction_ms), 70.0, 0.01, "sharp pilot reaction 70")
	check_close(float(easy.aim_error_deg), 8.0, 0.01, "easy pilot aim 8.0")
	check_close(float(standard.aim_error_deg), 4.0, 0.01, "standard pilot aim 4.0")
	check_close(float(sharp.aim_error_deg), 1.5, 0.01, "sharp pilot aim 1.5")
	check(easy._reaction_ticks() > standard._reaction_ticks(), "easy reacts slower than standard")
	check(standard._reaction_ticks() > sharp._reaction_ticks(), "standard reacts slower than sharp")
	check(easy._aim_error_rad() > standard._aim_error_rad(), "easy aims wider than standard")
	check(standard._aim_error_rad() > sharp._aim_error_rad(), "standard aims wider than sharp")
	# Identical perception yields identical utility scores on every tier.
	var packed := load("res://scenes/soldier.tscn") as PackedScene
	check(packed != null, "soldier.tscn loads for tier-parity probe")
	var probe_host := packed.instantiate() as CharacterBody2D
	root.add_child(probe_host)
	await process_frame
	await process_frame
	var seen := {
		"foe": null,
		"foe_pos": Vector2.INF,
		"visible": false,
		"remembered": Vector2.INF,
		"pickup": null,
	}
	var se: Dictionary = easy._score_actions(probe_host, seen)
	var ss: Dictionary = standard._score_actions(probe_host, seen)
	var sh: Dictionary = sharp._score_actions(probe_host, seen)
	for key in ["engage", "seek_cover", "grab_pickup", "retreat"]:
		check(is_equal_approx(float(se[key]), float(ss[key])) and is_equal_approx(float(ss[key]), float(sh[key])), "shared utility path: %s identical on all tiers" % key)
	probe_host.queue_free()
	easy.queue_free()
	standard.queue_free()
	sharp.queue_free()
	await process_frame

	# (c) Empty mag under fire: reload or retreat within 60 ticks.
	var floor_body := make_floor()
	var bot := await make_soldier(Vector2(0, -40), "standard")
	var foe := packed.instantiate() as CharacterBody2D
	foe.position = Vector2(300, -40)
	root.add_child(foe)
	await process_frame
	await process_frame
	var bot_pilot := bot.get("pilot") as BotPilot
	check(bot_pilot != null, "bot seats a BotPilot")
	var weapon := bot.get_node_or_null("Weapon")
	check(weapon != null, "bot has Weapon")
	weapon.set("ammo", 0)
	check(int(weapon.get("reserve_left")) > 0, "bot keeps reserve for reload")
	bot.call("take_damage", 20.0)
	var responded := false
	var retreated := false
	var reloaded := false
	for i in 60:
		var cmd: Pilot.Command = bot_pilot.get_command(1.0 / 60.0)
		var away := signf(bot.global_position.x - foe.global_position.x)
		if away == 0.0:
			away = 1.0
		if bool(cmd.reload):
			reloaded = true
		if float(cmd.move_x) * away > 0.1:
			retreated = true
		if reloaded or retreated:
			responded = true
			break
		await physics_frame
	check(responded, "empty-mag bot under fire reloads or retreats within 60 ticks (reload=%s retreat=%s)" % [str(reloaded), str(retreated)])
	bot.queue_free()
	foe.queue_free()
	floor_body.queue_free()
	await process_frame

	# (d) LOS occlusion: last-seen aim persists, fire stops, memory clears.
	var floor2 := make_floor()
	var watcher := await make_soldier(Vector2(0, -40), "sharp")
	var target := packed.instantiate() as CharacterBody2D
	target.position = Vector2(400, -40)
	root.add_child(target)
	await process_frame
	await wait_physics(30)
	var watch_pilot := watcher.get("pilot") as BotPilot
	var chest := target.global_position + Vector2(0, -32)
	var aim_open: Vector2 = (watch_pilot.get_command(1.0 / 60.0) as Pilot.Command).aim_point
	await wait_physics(10)
	chest = target.global_position + Vector2(0, -32)
	var aimed := false
	for i in 12:
		var c: Pilot.Command = watch_pilot.get_command(1.0 / 60.0)
		chest = target.global_position + Vector2(0, -32)
		if (c.aim_point as Vector2).distance_to(chest) < 60.0:
			aimed = true
			break
		await physics_frame
	check(aimed, "open LOS aims at foe chest (last aim off by %f)" % aim_open.distance_to(chest))
	# Raise a wall between the soldiers: chest ray must now be occluded.
	var wall := StaticBody2D.new()
	wall.position = Vector2(200, -100)
	var wall_shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 200)
	wall_shape.shape = rect
	wall.add_child(wall_shape)
	root.add_child(wall)
	await wait_physics(3)
	var occluded_fire := false
	var remembered_aim := false
	for i in 10:
		var c2: Pilot.Command = watch_pilot.get_command(1.0 / 60.0)
		chest = target.global_position + Vector2(0, -32)
		if bool(c2.fire):
			occluded_fire = true
		if (c2.aim_point as Vector2).distance_to(chest) < 5.0:
			remembered_aim = true
		await physics_frame
	check(not occluded_fire, "occluded bot never fires at remembered ghost")
	check(remembered_aim, "occluded bot aims at last-seen chest from 3s memory")
	# Age the memory past 180 ticks: the ghost is forgotten.
	for i in 200:
		watch_pilot.get_command(1.0 / 60.0)
	var cold: Pilot.Command = watch_pilot.get_command(1.0 / 60.0)
	chest = target.global_position + Vector2(0, -32)
	check((cold.aim_point as Vector2).distance_to(chest) > 200.0, "memory older than 180 ticks is forgotten")
	check(not bool(cold.fire), "forgotten ghost draws no fire")
	watcher.queue_free()
	target.queue_free()
	wall.queue_free()
	floor2.queue_free()
	await process_frame

	# (e) Movement smoke: 2 bots in the greybox displace and shoot.
	var grey_packed := load("res://scenes/arena/greybox.tscn") as PackedScene
	check(grey_packed != null, "greybox.tscn loads for bot smoke")
	var grey := grey_packed.instantiate() as Node2D
	root.add_child(grey)
	await process_frame
	var bot_a := packed.instantiate() as CharacterBody2D
	bot_a.position = Vector2(0, 360)
	root.add_child(bot_a)
	await process_frame
	await process_frame
	bot_a.call("set_pilot", BotPilot.new("sharp"))
	var bot_b := packed.instantiate() as CharacterBody2D
	bot_b.position = Vector2(300, 360)
	root.add_child(bot_b)
	await process_frame
	await process_frame
	bot_b.call("set_pilot", BotPilot.new("standard"))
	await wait_physics(30)
	var spawn_a := bot_a.global_position
	var spawn_b := bot_b.global_position
	var wa := bot_a.get_node_or_null("Weapon")
	var wb := bot_b.get_node_or_null("Weapon")
	var ammo0 := int(wa.get("ammo")) + int(wa.get("reserve_left")) + int(wb.get("ammo")) + int(wb.get("reserve_left"))
	var max_a := 0.0
	var max_b := 0.0
	for i in 1200:
		await physics_frame
		max_a = maxf(max_a, bot_a.global_position.distance_to(spawn_a))
		max_b = maxf(max_b, bot_b.global_position.distance_to(spawn_b))
	check(max_a > 100.0, "bot A roams from spawn (max %f)" % max_a)
	check(max_b > 100.0, "bot B roams from spawn (max %f)" % max_b)
	var ammo1 := int(wa.get("ammo")) + int(wa.get("reserve_left")) + int(wb.get("ammo")) + int(wb.get("reserve_left"))
	check(ammo0 - ammo1 > 0, "bots fired live rounds in smoke (spent %d)" % (ammo0 - ammo1))
	bot_a.queue_free()
	bot_b.queue_free()
	grey.queue_free()
	await process_frame

	# (f) Source gate: the scripted driver never touches raw input devices.
	var f := FileAccess.open("res://scripts/pilots/bot_pilot.gd", FileAccess.READ)
	check(f != null, "bot_pilot.gd reads from disk")
	if f != null:
		var text := f.get_as_text()
		f.close()
		check(not text.contains("Input."), "bot_pilot.gd has zero Input. lines")
		for token in ["engage", "seek_cover", "grab_pickup", "retreat", "get_command", "reaction_ms", "aim_error_deg"]:
			check(text.contains(token), "bot_pilot.gd defines %s" % token)
