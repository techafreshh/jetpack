extends SceneTree
## Headless proof for the accessibility lap: colour-blind tracers read the
## exact blue/orange hexes with gold defaults off, muzzle flash() peaks at
## exactly half under reduced flashing, aim assist moves aim_point >=30%
## closer inside the 10 deg cone (no-op past it/off), and the shake slider
## round-trips through settings.cfg with clamp-to-default sanitizing.
## Temp fixtures live only in a user:// temp copy via the injectable
## settings_path; the live user://settings.cfg and InputMap are backed up
## and restored byte-identical.
## Run: godot --headless --path jetpack --script res://tests/test_accessibility.gd

var passed := 0
var failed := 0

const SETTINGS_SCRIPT := "res://scripts/settings.gd"
const LIVE_PATH := "user://settings.cfg"
const TMP_PATH := "user://test_accessibility_tmp.cfg"
const REMAPPABLE := ["move_left", "move_right", "crouch", "fly", "throw_grenade", "reload"]
const GOLD := Color(1.0, 0.85, 0.4, 1.0)


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


func make_settings() -> Array:
	# Reuse the live autoload when present so /root/Settings resolves to the
	# temp file; otherwise seat a temp node under the same name. Returns
	# [node, created].
	var live := root.get_node_or_null("Settings")
	if live != null and live.has_method("load_settings"):
		live.set("settings_path", TMP_PATH)
		live.call("load_settings")
		return [live, false]
	var node: Node = load(SETTINGS_SCRIPT).new()
	node.name = "Settings"
	node.set("settings_path", TMP_PATH)
	root.add_child(node)
	return [node, true]


func settle_settings(pair: Array) -> Node:
	var node: Node = pair[0]
	await process_frame
	await process_frame
	return node


func drop_settings(pair: Array) -> void:
	var node: Node = pair[0]
	var created: bool = pair[1]
	if created:
		if node != null and is_instance_valid(node):
			node.queue_free()
			await process_frame
	else:
		if node != null and is_instance_valid(node):
			node.set("settings_path", LIVE_PATH)
			node.call("load_settings")
			await process_frame


func snapshot_binds() -> Dictionary:
	var snap := {}
	for action in REMAPPABLE:
		if InputMap.has_action(StringName(action)):
			snap[action] = InputMap.action_get_events(StringName(action)).duplicate()
		else:
			snap[action] = null
	return snap


func restore_binds(snap: Dictionary) -> void:
	for action in REMAPPABLE:
		var sname := StringName(action)
		if snap.get(action) == null:
			if InputMap.has_action(sname):
				InputMap.action_erase_events(sname)
			continue
		if not InputMap.has_action(sname):
			InputMap.add_action(sname)
		InputMap.action_erase_events(sname)
		for ev in snap[action]:
			InputMap.action_add_event(sname, ev)


func make_soldier_at(pos: Vector2) -> CharacterBody2D:
	var packed := load("res://scenes/soldier.tscn") as PackedScene
	var s := packed.instantiate() as CharacterBody2D
	s.position = pos
	root.add_child(s)
	return s


func run_tests() -> void:
	await process_frame

	var had_live := FileAccess.file_exists(LIVE_PATH)
	var live_bytes := PackedByteArray()
	if had_live:
		live_bytes = FileAccess.get_file_as_bytes(LIVE_PATH)
	var bind_snap := snapshot_binds()
	DirAccess.remove_absolute(TMP_PATH)

	var pair := make_settings()
	var s := await settle_settings(pair)
	check(s != null and is_instance_valid(s), "settings node instantiates and enters tree")

	# (a) Colour-blind palette: exact hexes on, legacy gold off.
	var weapon_scr := load("res://scripts/weapons/weapon.gd") as Script
	check(weapon_scr != null, "weapon.gd loads as Script")
	var gun = weapon_scr.new() if weapon_scr != null else null
	check(gun != null, "weapon instantiates standalone")
	if s != null and gun != null:
		root.add_child(gun)
		await process_frame
		s.call("set_toggle", "colorblind_mode", false)
		check((gun.call("tracer_color_for", true) as Color).is_equal_approx(GOLD), "CB off: friendly tracer is legacy gold")
		check((gun.call("tracer_color_for", false) as Color).is_equal_approx(GOLD), "CB off: enemy tracer is legacy gold")
		s.call("set_toggle", "colorblind_mode", true)
		var foe_col: Color = gun.call("tracer_color_for", false)
		var friend_col: Color = gun.call("tracer_color_for", true)
		check(foe_col == Color8(0, 102, 255), "CB on: enemy tracer is exactly #0066FF (got %s)" % foe_col.to_html())
		check(friend_col == Color8(255, 136, 0), "CB on: friendly tracer is exactly #FF8800 (got %s)" % friend_col.to_html())
		check(foe_col.to_html(false).to_upper() == "0066FF", "CB on: enemy hex reads 0066FF")
		check(friend_col.to_html(false).to_upper() == "FF8800", "CB on: friendly hex reads FF8800")
		gun.call("_spawn_tracer", Vector2.ZERO, Vector2(100, 0))
		var kids := []
		for c in gun.get_children():
			if c is Line2D:
				kids.append(c)
		check(kids.size() == 1, "CB on: _spawn_tracer leaves one tracer (got %d)" % kids.size())
		if kids.size() == 1:
			check((kids[0] as Line2D).default_color == Color8(255, 136, 0), "CB on: spawned tracer uses friendly orange by default")
		s.call("set_toggle", "colorblind_mode", false)
		gun.queue_free()
		await process_frame

	# (b) Muzzle peak: reduced flash is exactly half the full baseline.
	var muzzle_scr := load("res://scripts/fx/muzzle.gd") as Script
	check(muzzle_scr != null, "muzzle.gd loads as Script")
	var muzzle = muzzle_scr.new() if muzzle_scr != null else null
	check(muzzle != null, "muzzle instantiates standalone")
	if s != null and muzzle != null:
		root.add_child(muzzle)
		await process_frame
		s.call("set_toggle", "reduced_flashing", false)
		muzzle.call("flash")
		var baseline := float(muzzle.get("peak_energy"))
		check(baseline > 0.0, "full flash peaks above zero (got %f)" % baseline)
		check_close(float(muzzle.get("energy")), baseline, 0.0001, "full flash arms energy at peak")
		s.call("set_toggle", "reduced_flashing", true)
		muzzle.call("flash")
		var soft := float(muzzle.get("peak_energy"))
		check(soft <= 0.5 * baseline, "reduced peak <=50%% of baseline (%f vs %f)" % [soft, baseline])
		check_close(soft, 0.5 * baseline, 0.0001, "reduced peak is exactly half the baseline")
		muzzle.queue_free()
		await process_frame
		# Tree-less muzzle never errors and still halves via compiled default.
		var bare_muzzle = muzzle_scr.new()
		check(bare_muzzle != null, "tree-less muzzle instantiates")
		if bare_muzzle != null:
			bare_muzzle.call("flash")
			check(float(bare_muzzle.get("peak_energy")) > 0.0, "tree-less flash peaks without Settings")
			bare_muzzle.free()
		s.call("set_toggle", "reduced_flashing", false)

	# (c) Aim assist: >=30% closer inside the cone, no-op past it/off.
	var shooter := make_soldier_at(Vector2(0, 0))
	var foe := make_soldier_at(Vector2(900, 900))
	await wait_physics(2)
	check(shooter != null and foe != null, "assist pair instantiates")
	if s != null and shooter != null and foe != null:
		check(bool(shooter.get("is_alive")) and bool(foe.get("is_alive")), "assist pair is alive")
		shooter.global_position = Vector2(0, 0)
		var from: Vector2 = shooter.global_position + Vector2(0, -32)
		# Foe chest ~5 deg off an east raw ray at range 300.
		var raw := from + Vector2(300, 0)
		var off5 := Vector2(300 * cos(deg_to_rad(5.0)), 300 * sin(deg_to_rad(5.0)))
		foe.global_position = from + off5 - Vector2(0, -32)
		await process_frame
		from = shooter.global_position + Vector2(0, -32)
		raw = from + Vector2(300, 0)
		var chest: Vector2 = foe.global_position + Vector2(0, -32)
		var dist_before := raw.distance_to(chest)
		check(dist_before > 1.0, "assist fixture separates raw aim from foe chest (got %f)" % dist_before)
		s.call("set_toggle", "aim_assist", false)
		var off_result: Vector2 = shooter.call("apply_aim_assist", raw)
		check(off_result.is_equal_approx(raw), "assist off returns raw aim untouched")
		s.call("set_toggle", "aim_assist", true)
		var snapped: Vector2 = shooter.call("apply_aim_assist", raw)
		var dist_after := snapped.distance_to(chest)
		check(dist_after <= 0.7 * dist_before, "assist closes >=30%% of the gap (%f -> %f)" % [dist_before, dist_after])
		check_close(dist_after, 0.5 * dist_before, 0.5 * dist_before * 0.05 + 0.5, "assist halves the gap to the chest")
		# Foe pushed to ~20 deg: outside the cone, raw passes through.
		var off20 := Vector2(300 * cos(deg_to_rad(20.0)), 300 * sin(deg_to_rad(20.0)))
		foe.global_position = from + off20 - Vector2(0, -32)
		await process_frame
		from = shooter.global_position + Vector2(0, -32)
		raw = from + Vector2(300, 0)
		var wide: Vector2 = shooter.call("apply_aim_assist", raw)
		check(wide.is_equal_approx(raw), "assist past 10deg leaves raw aim untouched")
		# _aim_point flows overrides through the assist seam: foe back to
		# ~5 deg, then the override point must come back snapped.
		foe.global_position = from + off5 - Vector2(0, -32)
		await process_frame
		from = shooter.global_position + Vector2(0, -32)
		raw = from + Vector2(300, 0)
		chest = foe.global_position + Vector2(0, -32)
		dist_before = raw.distance_to(chest)
		shooter.call("set_aim_point", raw)
		var via_point: Vector2 = shooter.call("_aim_point")
		check(via_point.distance_to(chest) <= 0.7 * dist_before, "_aim_point routes overrides through assist")
		shooter.call("clear_aim_override")
		s.call("set_toggle", "aim_assist", false)
		shooter.queue_free()
		foe.queue_free()
		await process_frame

	# (d) Shake slider: round-trip, clamp, menu seating.
	if s != null:
		var fired := [0]
		var counter := func(): fired[0] += 1
		if not s.is_connected("toggles_changed", counter):
			s.connect("toggles_changed", counter)
		s.call("set_screen_shake", 0.25)
		check(fired[0] >= 1, "set_screen_shake emits toggles_changed")
		check_close(float(s.call("get_screen_shake")), 0.25, 0.001, "shake getter reads 0.25 back")
		var reread := ConfigFile.new()
		check(reread.load(TMP_PATH) == OK, "shake temp cfg reloads OK after save")
		check_close(float(reread.get_value("accessibility", "screen_shake", -1.0)), 0.25, 0.001, "shake persists as 0.25 in cfg")
		var fresh_pair := make_settings()
		var fresh := await settle_settings(fresh_pair)
		check(fresh != null and is_instance_valid(fresh), "fresh settings node loads without crash")
		if fresh != null:
			check_close(float(fresh.call("get_screen_shake")), 0.25, 0.001, "fresh instance reads shake 0.25")
			if fresh_pair[1]:
				await drop_settings(fresh_pair)
		# Garbage and out-of-range values clamp to the 1.0 default.
		var bad := ConfigFile.new()
		bad.set_value("accessibility", "screen_shake", "LOUD")
		check(bad.save(TMP_PATH) == OK, "garbage shake cfg saves")
		var guarded_pair := make_settings()
		var guarded := await settle_settings(guarded_pair)
		if guarded != null:
			check_close(float(guarded.call("get_screen_shake")), 1.0, 0.001, "non-numeric shake keeps default 1.0")
			if guarded_pair[1]:
				await drop_settings(guarded_pair)
		var far := ConfigFile.new()
		far.set_value("accessibility", "screen_shake", 2.5)
		check(far.save(TMP_PATH) == OK, "over-range shake cfg saves")
		var clamped_pair := make_settings()
		var clamped := await settle_settings(clamped_pair)
		if clamped != null:
			check_close(float(clamped.call("get_screen_shake")), 1.0, 0.001, "over-range shake clamps to 1.0")
			if clamped_pair[1]:
				await drop_settings(clamped_pair)
		s.call("set_screen_shake", 1.0)

	# (e) CameraShake: zero trauma is silent, trauma kicks, shake scales.
	var shake_scr := load("res://scripts/fx/camera_shake.gd") as Script
	check(shake_scr != null, "camera_shake.gd loads as Script")
	var cam = shake_scr.new() if shake_scr != null else null
	check(cam != null, "camera instantiates standalone")
	if s != null and cam != null:
		s.call("set_screen_shake", 1.0)
		root.add_child(cam)
		await process_frame
		await process_frame
		check((cam.get("offset") as Vector2).is_equal_approx(Vector2.ZERO), "zero trauma yields zero offset")
		check_close(float(cam.get("rotation")), 0.0, 0.0001, "zero trauma yields zero rotation")
		cam.call("add_trauma", 0.5)
		check_close(float(cam.get("trauma")), 0.5, 0.0001, "add_trauma banks 0.5")
		await process_frame
		check((cam.get("offset") as Vector2).length() > 0.01, "trauma offsets the camera at full shake")
		s.call("set_screen_shake", 0.0)
		await process_frame
		await process_frame
		check((cam.get("offset") as Vector2).is_equal_approx(Vector2.ZERO), "zero shake scale silences offset")
		check_close(float(cam.get("rotation")), 0.0, 0.0001, "zero shake scale silences rotation")
		s.call("set_screen_shake", 1.0)
		cam.queue_free()
		await process_frame
		var bare_cam = shake_scr.new()
		if bare_cam != null:
			bare_cam.call("add_trauma", 0.5)
			check_close(float(bare_cam.get("trauma")), 0.5, 0.0001, "tree-less add_trauma still banks")
			bare_cam.free()

	# (f) Explosion: reduced flash halves the Visual alpha and kicks trauma.
	var boom_scr := load("res://scripts/fx/explosion.gd") as Script
	check(boom_scr != null, "explosion.gd loads as Script")
	if s != null and boom_scr != null and shake_scr != null:
		var seat = shake_scr.new()
		root.add_child(seat)
		await process_frame
		s.call("set_toggle", "reduced_flashing", false)
		var full_boom = boom_scr.new()
		full_boom.global_position = Vector2(5000, 5000)
		root.add_child(full_boom)
		await process_frame
		await process_frame
		var full_visual := full_boom.get_node_or_null("Visual") as Polygon2D
		check(full_visual != null, "full-flash explosion builds a Visual")
		var full_alpha := 0.55
		if full_visual != null:
			full_alpha = full_visual.color.a
			check_close(full_alpha, 0.55, 0.001, "full-flash Visual alpha is 0.55")
		var kicked := float(seat.get("trauma"))
		check(kicked > 0.0, "detonate kicks camera trauma (got %f)" % kicked)
		full_boom.queue_free()
		await process_frame
		var calm = shake_scr.new()
		root.add_child(calm)
		await process_frame
		s.call("set_toggle", "reduced_flashing", true)
		var soft_boom = boom_scr.new()
		soft_boom.global_position = Vector2(-5000, -5000)
		root.add_child(soft_boom)
		await process_frame
		await process_frame
		var soft_visual := soft_boom.get_node_or_null("Visual") as Polygon2D
		check(soft_visual != null, "reduced-flash explosion builds a Visual")
		if soft_visual != null:
			check_close(soft_visual.color.a, 0.5 * full_alpha, 0.01, "reduced-flash Visual alpha is halved")
		soft_boom.queue_free()
		await process_frame
		s.call("set_toggle", "reduced_flashing", false)
		seat.queue_free()
		calm.queue_free()
		await process_frame

	# (g) Scene/menu seating for the new rows and nodes.
	var soldier_packed := load("res://scenes/soldier.tscn") as PackedScene
	check(soldier_packed != null, "soldier.tscn loads as PackedScene")
	if soldier_packed != null:
		var seated := soldier_packed.instantiate()
		check(seated.get_node_or_null("Weapon/Muzzle/MuzzleFlash") != null, "soldier seats MuzzleFlash under Weapon/Muzzle")
		var flash_node := seated.get_node_or_null("Weapon/Muzzle/MuzzleFlash")
		if flash_node != null:
			check(String(flash_node.get_script().resource_path) == "res://scripts/fx/muzzle.gd", "MuzzleFlash binds muzzle.gd")
		seated.queue_free()
		await process_frame
	var match_packed := load("res://scenes/match.tscn") as PackedScene
	check(match_packed != null, "match.tscn loads as PackedScene")
	if match_packed != null:
		var host := match_packed.instantiate() as Node2D
		check(host != null, "match.tscn instantiates Node2D")
		if host != null:
			root.add_child(host)
			await process_frame
			await process_frame
			check(host.get_node_or_null("CameraShake") != null, "match seats a CameraShake node")
			var match_cam := host.get_node_or_null("CameraShake")
			if match_cam != null:
				check(String(match_cam.get_script().resource_path) == "res://scripts/fx/camera_shake.gd", "match CameraShake binds camera_shake.gd")
			host.queue_free()
			await process_frame
	var menu_packed := load("res://scenes/ui/settings.tscn") as PackedScene
	check(menu_packed != null, "settings.tscn loads as PackedScene")
	if menu_packed != null:
		var menu := menu_packed.instantiate() as CanvasLayer
		check(menu != null, "settings.tscn instantiates CanvasLayer")
		if menu != null:
			for child in ["ShakeLabel", "ShakeSlider", "ShakeValue"]:
				check(menu.get_node_or_null(child) != null, "settings menu exposes %s" % child)
			var shake_slider := menu.get_node_or_null("ShakeSlider") as HSlider
			if shake_slider != null:
				check_close(shake_slider.min_value, 0.0, 0.0001, "ShakeSlider floors at 0.0")
				check_close(shake_slider.max_value, 1.0, 0.0001, "ShakeSlider caps at 1.0")
			root.add_child(menu)
			await process_frame
			await process_frame
			check(is_instance_valid(menu), "settings menu _ready completes with shake row")
			menu.queue_free()
			await process_frame

	await drop_settings(pair)
	restore_binds(bind_snap)
	DirAccess.remove_absolute(TMP_PATH)
	if had_live:
		var restore := FileAccess.open(LIVE_PATH, FileAccess.WRITE)
		if restore != null:
			restore.store_buffer(live_bytes)
			restore.close()
	else:
		if FileAccess.file_exists(LIVE_PATH):
			DirAccess.remove_absolute(LIVE_PATH)
	check(not FileAccess.file_exists(TMP_PATH), "temp cfg removed on all paths")
