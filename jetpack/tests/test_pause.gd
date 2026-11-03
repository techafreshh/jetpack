extends SceneTree
## Headless behavior proof for the pause menu: overlay seating, pause-flag
## plus visibility on toggle, hold-1.0 confirm vs 0.2s tap, restart zeroing
## scores, quit landing in main_menu.tscn unpaused, and match.tscn seating.
## Run: godot --headless --path jetpack --script res://tests/test_pause.gd

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


## Deterministic hold driver: real _process delta is wall-clock noise in
## headless runs, so inject fixed 60 Hz steps directly (the method is the
## contract; the engine calls it with the same delta live).
func drive_hold(button: Node, seconds: float) -> void:
	var steps := int(ceil(seconds * 60.0))
	for i in steps:
		button.call("_process", 1.0 / 60.0)
		if i % 15 == 14:
			await process_frame


func run_tests() -> void:
	await process_frame

	# (a) pause.tscn loads with the acceptance node names and hold wiring.
	var packed := load("res://scenes/ui/pause.tscn") as PackedScene
	check(packed != null, "pause.tscn loads as PackedScene")
	if packed == null:
		return
	var pause := packed.instantiate() as CanvasLayer
	check(pause != null, "pause.tscn instantiates CanvasLayer")
	if pause == null:
		return
	check(pause.name == "Pause", "pause root is named Pause (got %s)" % pause.name)
	check(pause.is_in_group("pause_menu"), "pause root is in group pause_menu")
	for child in ["ResumeButton", "RestartButton", "QuitButton", "SettingsButton", "SettingsPanel"]:
		check(pause.get_node_or_null("Menu/" + child) != null or pause.get_node_or_null(child) != null, "pause exposes %s" % child)
	var resume := pause.get_node_or_null("Menu/ResumeButton")
	var restart := pause.get_node_or_null("Menu/RestartButton")
	var quit_b := pause.get_node_or_null("Menu/QuitButton")
	var settings := pause.get_node_or_null("Menu/SettingsButton")
	check(resume != null and (resume as Button).text == "Resume", "ResumeButton reads Resume")
	check(restart != null and (restart as Button).text == "Restart", "RestartButton reads Restart")
	check(quit_b != null and (quit_b as Button).text == "Quit to Menu", "QuitButton reads Quit to Menu")
	check(settings != null and (settings as Button).text == "Settings", "SettingsButton reads Settings")
	for path in ["Menu/RestartButton", "Menu/QuitButton"]:
		var hold := pause.get_node_or_null(path)
		check(hold != null and hold.get("hold_time") != null, "%s exposes hold_time" % path)
		check(hold != null and hold.get("progress") != null, "%s exposes progress" % path)
		if hold != null:
			check_close(float(hold.get("hold_time")), 1.0, 0.001, "%s hold_time is 1.0s" % path)
			check_close(float(hold.get("progress")), 0.0, 0.001, "%s progress starts at 0.0" % path)
		check(hold != null and (hold as Node).process_mode == Node.PROCESS_MODE_ALWAYS, "%s is process_mode ALWAYS" % path)
		check(hold != null and hold.get_node_or_null("Fill") != null, "%s owns Fill ring" % path)
	var panel := pause.get_node_or_null("SettingsPanel") as CanvasLayer
	check(panel != null and not panel.visible, "SettingsPanel starts hidden")
	check(panel != null and panel.get_node_or_null("BackButton") != null, "SettingsPanel exposes BackButton")
	if panel != null:
		for child in ["MasterSlider", "MusicSlider", "SfxSlider", "RemapFly", "RemapMoveLeft", "RemapMoveRight", "RemapCrouch", "RemapGrenade", "RemapReload", "ColorblindToggle", "FlashToggle", "AimAssistToggle", "ResetButton", "BackButton"]:
			check(panel.get_node_or_null(child) != null, "SettingsPanel exposes %s" % child)
	root.add_child(pause)
	await process_frame
	await process_frame
	check(not pause.visible, "pause overlay starts hidden")
	paused = false
	# Button wiring end to end via pressed emission.
	var settings_btn := pause.get_node_or_null("Menu/SettingsButton") as BaseButton
	settings_btn.emit_signal("pressed")
	check(panel.visible, "SettingsButton opens SettingsPanel")
	var back_btn := pause.get_node_or_null("SettingsPanel/BackButton") as BaseButton
	back_btn.emit_signal("pressed")
	check(not panel.visible, "BackButton closes SettingsPanel")
	var resume_btn := pause.get_node_or_null("Menu/ResumeButton") as BaseButton
	pause.call("show_pause")
	check(paused and pause.visible, "show_pause before resume wiring check")
	resume_btn.emit_signal("pressed")
	check(not paused and not pause.visible, "ResumeButton resumes and hides overlay")

	# (b) Toggle flips the pause flag and visibility; resume mutates nothing.
	var mgr := MatchManager.new()
	root.add_child(mgr)
	await process_frame
	await process_frame
	mgr.register_kill("bot_a", "bot_x")
	mgr.register_kill("bot_a", "bot_y")
	var staged_time := float(mgr.get("time_left"))
	check(pause.has_method("toggle_pause"), "pause exposes toggle_pause")
	pause.call("show_pause")
	check(paused, "show_pause sets get_tree().paused true")
	check(pause.visible, "show_pause makes overlay visible")
	await wait_physics(5)
	check(paused, "tree stays paused under physics ticks")
	pause.call("resume_game")
	check(not paused, "resume_game clears get_tree().paused")
	check(not pause.visible, "resume_game hides overlay")
	check(mgr.score_for("bot_a") == 2, "pause cycle preserves staged kills (got %d)" % mgr.score_for("bot_a"))
	check_close(float(mgr.get("time_left")), staged_time, 0.001, "pause cycle preserves clock")
	# Esc-equivalent toggle flips both ways.
	pause.call("toggle_pause")
	check(paused and pause.visible, "toggle_pause pauses and shows")
	pause.call("toggle_pause")
	check(not paused and not pause.visible, "toggle_pause resumes and hides")

	# (c) Full 1.0s hold confirms and zeroes scores; a 0.2s tap does not.
	var confirms := [0]
	var restart_btn := pause.get_node_or_null("Menu/RestartButton") as Node
	restart_btn.connect("confirmed", func() -> void: confirms[0] += 1)
	pause.call("show_pause")
	restart_btn.call("begin_hold")
	await drive_hold(restart_btn, 1.1)
	check(float(restart_btn.get("progress")) >= 1.0, "1.0s hold reaches progress 1.0 (got %f)" % float(restart_btn.get("progress")))
	check(confirms[0] == 1, "1.0s hold emits confirmed once (got %d)" % confirms[0])
	check(mgr.score_for("bot_a") == 0, "restart zeroes scores (got %d)" % mgr.score_for("bot_a"))
	check(mgr.match_state == "countdown", "restart returns manager to countdown")
	check(not paused and not pause.visible, "restart unpauses and hides overlay")
	# Short tap: stage fresh kills, hold 0.2s, release.
	mgr.register_kill("bot_a", "bot_x")
	mgr.register_kill("bot_a", "bot_y")
	var taps := [0]
	restart_btn.connect("confirmed", func() -> void: taps[0] += 100)
	var before: int = confirms[0]
	pause.call("show_pause")
	restart_btn.call("begin_hold")
	await drive_hold(restart_btn, 0.2)
	restart_btn.call("release_hold")
	check(float(restart_btn.get("progress")) < 1.0, "0.2s tap keeps progress below 1.0 (got %f)" % float(restart_btn.get("progress")))
	check(confirms[0] == before, "0.2s tap emits no confirm")
	check(mgr.score_for("bot_a") == 2, "0.2s tap leaves staged kills intact (got %d)" % mgr.score_for("bot_a"))
	pause.call("resume_game")

	# (d) Quit held to confirm lands in main_menu.tscn unpaused.
	var quit_btn := pause.get_node_or_null("Menu/QuitButton") as Node
	pause.call("show_pause")
	check(paused, "quit test starts paused")
	quit_btn.call("begin_hold")
	await drive_hold(quit_btn, 1.1)
	check(float(quit_btn.get("progress")) >= 1.0, "quit hold reaches progress 1.0 (got %f)" % float(quit_btn.get("progress")))
	await process_frame
	await process_frame
	await process_frame
	check(not paused, "quit clears get_tree().paused")
	var current := current_scene
	check(current != null, "quit leaves a current scene")
	if current != null:
		check(current.scene_file_path == "res://scenes/main_menu.tscn", "quit lands in main_menu.tscn (got %s)" % current.scene_file_path)
		check(current.get_node_or_null("Play") != null or current.get_node_or_null("PlayButton") != null, "main menu exposes Play")
		var title := current.get_node_or_null("Title") as Label
		check(title != null, "main menu exposes Title")
		current.queue_free()
		await process_frame
	pause.queue_free()
	mgr.queue_free()
	await process_frame
	paused = false

	# (e) match.tscn seats Pause beside hud and Standings.
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
	var seated := host.get_node_or_null("Pause")
	check(seated != null, "match seats Pause child")
	check(host.get_node_or_null("hud") != null, "match still seats hud")
	check(host.get_node_or_null("Standings") != null, "match still seats Standings")
	if seated != null:
		check(not (seated as CanvasLayer).visible, "seated Pause starts hidden")
		check(not paused, "match ready leaves tree unpaused")
		(seated as Node).call("toggle_pause")
		check(paused and (seated as CanvasLayer).visible, "seated toggle pauses and shows")
		(seated as Node).call("toggle_pause")
		check(not paused and not (seated as CanvasLayer).visible, "seated toggle resumes and hides")
	host.queue_free()
	await process_frame
	paused = false
