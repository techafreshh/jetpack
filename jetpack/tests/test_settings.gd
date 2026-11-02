extends SceneTree
## Headless proof for the Settings autoload: volume round-trip persists to
## user://settings.cfg, garbage bytes boot to defaults with a rewritten file,
## fly remaps to Space in both the cfg string and InputMap, and invalid
## per-key values keep compiled defaults without faulting. Temp fixtures live
## only in a user:// temp copy via the injectable settings_path; the live
## user://settings.cfg is backed up and restored byte-identical.
## Run: godot --headless --path jetpack --script res://tests/test_settings.gd

var passed := 0
var failed := 0

const SETTINGS_SCRIPT := "res://scripts/settings.gd"
const LIVE_PATH := "user://settings.cfg"
const TMP_PATH := "user://test_settings_tmp.cfg"
const REMAPPABLE := ["move_left", "move_right", "crouch", "fly", "throw_grenade", "reload"]


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


func make_settings() -> Node:
	var node: Node = load(SETTINGS_SCRIPT).new()
	node.set("settings_path", TMP_PATH)
	root.add_child(node)
	await process_frame
	await process_frame
	return node


func drop_settings(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.queue_free()
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


func run_tests() -> void:
	await process_frame

	var had_live := FileAccess.file_exists(LIVE_PATH)
	var live_bytes := PackedByteArray()
	if had_live:
		live_bytes = FileAccess.get_file_as_bytes(LIVE_PATH)
	var bind_snap := snapshot_binds()
	DirAccess.remove_absolute(TMP_PATH)

	# Pass 1: volume round-trip on a user:// temp path.
	var s := await make_settings()
	check(s != null and is_instance_valid(s), "settings node instantiates and enters tree")
	if s != null:
		s.call("set_master_volume", 0.5)
		var reread := ConfigFile.new()
		check(reread.load(TMP_PATH) == OK, "temp settings.cfg reloads OK after save")
		check_close(float(reread.get_value("audio", "master_volume", -1.0)), 0.5, 0.01, "master_volume persists as 0.5")
		var fresh: Node = await make_settings()
		check(fresh != null and is_instance_valid(fresh), "fresh settings node loads without crash")
		if fresh != null:
			check_close(float(fresh.get("master_volume")), 0.5, 0.01, "fresh instance reads master_volume 0.5")
			await drop_settings(fresh)
		await drop_settings(s)

	# Pass 2: garbage bytes boot to defaults and rewrite a valid file.
	var garbage := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	check(garbage != null, "garbage temp file opens for write")
	if garbage != null:
		garbage.store_buffer(PackedByteArray([0xFF, 0x00, 0x13, 0x7F, 0x41, 0x0A, 0xFF]))
		garbage.close()
	var corrupt: Node = await make_settings()
	check(corrupt != null and is_instance_valid(corrupt), "garbage load keeps node alive (no crash)")
	if corrupt != null:
		check_close(float(corrupt.get("master_volume")), 1.0, 0.001, "garbage load falls back to master default 1.0")
		check_close(float(corrupt.get("music_volume")), 1.0, 0.001, "garbage load falls back to music default 1.0")
		check_close(float(corrupt.get("sfx_volume")), 1.0, 0.001, "garbage load falls back to sfx default 1.0")
		var healed := ConfigFile.new()
		check(healed.load(TMP_PATH) == OK, "garbage file rewritten to a valid cfg")
		if healed.load(TMP_PATH) == OK:
			check_close(float(healed.get_value("audio", "master_volume", -1.0)), 1.0, 0.001, "rewritten file holds default master_volume")
		await drop_settings(corrupt)

	# Pass 3: fly remaps to Space in cfg string and InputMap.
	var mapper: Node = await make_settings()
	check(mapper != null, "remap settings node instantiates")
	if mapper != null:
		mapper.call("set_keybind", "fly", KEY_SPACE)
		var bound := ConfigFile.new()
		check(bound.load(TMP_PATH) == OK, "remapped temp cfg reloads OK")
		var fly_str := str(bound.get_value("input", "fly", ""))
		check(fly_str == OS.get_keycode_string(KEY_SPACE), "input/fly persists as keycode string (got %s)" % fly_str)
		check(fly_str == "Space", "input/fly equals Space (got %s)" % fly_str)
		var space_found := false
		for ev in InputMap.action_get_events("fly"):
			if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_SPACE:
				space_found = true
				break
		check(space_found, "InputMap fly holds a physical_keycode SPACE event")
		await drop_settings(mapper)

	# Pass 4: invalid per-key values keep defaults, no crash.
	var bad := ConfigFile.new()
	bad.set_value("audio", "master_volume", "CORRUPT")
	bad.set_value("audio", "music_volume", Vector2(1, 2))
	bad.set_value("input", "fly", "FROBNICATE")
	bad.set_value("accessibility", "colorblind_mode", "maybe")
	check(bad.save(TMP_PATH) == OK, "invalid-value temp cfg saves")
	var guarded: Node = await make_settings()
	check(guarded != null and is_instance_valid(guarded), "invalid-value load keeps node alive (no crash)")
	if guarded != null:
		check_close(float(guarded.get("master_volume")), 1.0, 0.001, "CORRUPT master_volume keeps default 1.0")
		check_close(float(guarded.get("music_volume")), 1.0, 0.001, "non-numeric music_volume keeps default 1.0")
		check(str(guarded.call("get_keybind_string", "fly")) != "FROBNICATE", "unknown key string rejected for fly")
		check(bool(guarded.call("get_toggle", "colorblind_mode")) == false, "non-bool toggle keeps default false")
		await drop_settings(guarded)

	# Pass 5: settings.tscn seats every contract node and binds headless.
	var packed := load("res://scenes/ui/settings.tscn") as PackedScene
	check(packed != null, "settings.tscn loads as PackedScene")
	if packed != null:
		var menu := packed.instantiate() as CanvasLayer
		check(menu != null, "settings.tscn instantiates CanvasLayer")
		if menu != null:
			for child in ["MasterSlider", "MusicSlider", "SfxSlider", "RemapFly", "RemapMoveLeft", "RemapMoveRight", "RemapCrouch", "RemapGrenade", "RemapReload", "ColorblindToggle", "FlashToggle", "AimAssistToggle", "ResetButton", "BackButton"]:
				check(menu.get_node_or_null(child) != null, "settings menu exposes %s" % child)
			root.add_child(menu)
			await process_frame
			await process_frame
			check(is_instance_valid(menu), "settings menu _ready completes with live autoloads")
			var master := menu.get_node_or_null("MasterSlider") as HSlider
			if master != null:
				var expect := 1.0
				var live_settings := root.get_node_or_null("Settings")
				if live_settings != null and live_settings.get("master_volume") != null:
					expect = clampf(float(live_settings.get("master_volume")), 0.0, 1.0)
				check_close(master.value, expect, 0.001, "MasterSlider reflects Settings master volume")
			menu.queue_free()
			await process_frame

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
