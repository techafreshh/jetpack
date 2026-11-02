extends SceneTree
## Headless proof for the main menu: the scene loads, Play/Setup/HowTo/
## Settings buttons exist, Setup/HowTo navigate to their scenes, Settings
## toggles its panel, and Play reaches match.tscn within 3s.
## Run: godot --headless --path jetpack --script res://tests/test_main_menu.gd

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


func fresh_menu() -> Control:
	var packed := load("res://scenes/main_menu.tscn") as PackedScene
	if packed == null:
		return null
	var menu := packed.instantiate() as Control
	root.add_child(menu)
	await process_frame
	await process_frame
	return menu


func await_scene(path: String, max_frames: int = 180) -> bool:
	var frames := 0
	while frames < max_frames:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == path:
			return true
		frames += 1
	return current_scene != null and current_scene.scene_file_path == path


func run_tests() -> void:
	await process_frame

	# (a) Menu loads with the four acceptance buttons.
	var menu := await fresh_menu()
	check(menu != null, "main_menu.tscn instantiates")
	if menu == null:
		return
	for child in ["Play", "Setup", "HowTo", "Settings"]:
		check(menu.get_node_or_null(child) != null, "menu exposes %s button" % child)
	menu.queue_free()
	await process_frame

	# (b) Setup navigates to setup.tscn.
	var menu_b := await fresh_menu()
	var setup_btn := menu_b.get_node_or_null("Setup") as BaseButton
	check(setup_btn != null, "Setup button resolves")
	if setup_btn != null:
		setup_btn.emit_signal("pressed")
		check(await await_scene("res://scenes/ui/setup.tscn"), "Setup navigates to setup.tscn")
	if current_scene != null:
		current_scene.queue_free()
		await process_frame

	# (c) HowTo navigates to howto.tscn.
	var menu_c := await fresh_menu()
	var howto_btn := menu_c.get_node_or_null("HowTo") as BaseButton
	check(howto_btn != null, "HowTo button resolves")
	if howto_btn != null:
		howto_btn.emit_signal("pressed")
		check(await await_scene("res://scenes/ui/howto.tscn"), "HowTo navigates to howto.tscn")
	if current_scene != null:
		current_scene.queue_free()
		await process_frame

	# (d) Settings toggles its panel.
	var menu_d := await fresh_menu()
	var settings_btn := menu_d.get_node_or_null("Settings") as BaseButton
	var panel := menu_d.get_node_or_null("SettingsPanel") as Control
	check(settings_btn != null, "Settings button resolves")
	check(panel != null and not panel.visible, "SettingsPanel starts hidden")
	if settings_btn != null and panel != null:
		settings_btn.emit_signal("pressed")
		check(panel.visible, "Settings opens SettingsPanel")
		settings_btn.emit_signal("pressed")
		check(not panel.visible, "Settings toggles SettingsPanel closed")
	menu_d.queue_free()
	await process_frame

	# (e) Play reaches the live match within 3s.
	var menu_e := await fresh_menu()
	var play_btn := menu_e.get_node_or_null("Play") as BaseButton
	check(play_btn != null, "Play button resolves")
	if play_btn != null:
		play_btn.emit_signal("pressed")
		check(await await_scene("res://scenes/match.tscn"), "Play reaches match.tscn within 3s")
	if current_scene != null:
		current_scene.queue_free()
		await process_frame
	paused = false
