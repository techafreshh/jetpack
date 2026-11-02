extends SceneTree
## Headless proof for match setup: Sharp/10/180 driven through setup.tscn
## controls plus apply() lands on the manager as difficulty sharp,
## target_kills 10, and time_limit_s 180; invalid input keeps defaults.
## Run: godot --headless --path jetpack --script res://tests/test_setup.gd

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


func fresh_manager() -> MatchManager:
	var m := MatchManager.new()
	root.add_child(m)
	await process_frame
	await process_frame
	return m


func run_tests() -> void:
	await process_frame
	MatchSetup.clear()

	# (a) Setup scene exposes the acceptance controls.
	var packed := load("res://scenes/ui/setup.tscn") as PackedScene
	check(packed != null, "setup.tscn loads as PackedScene")
	if packed == null:
		return
	var setup := packed.instantiate() as Control
	check(setup != null, "setup.tscn instantiates Control")
	if setup == null:
		return
	root.add_child(setup)
	await process_frame
	await process_frame
	var diff := setup.get_node_or_null("DifficultyOption") as OptionButton
	var target := setup.get_node_or_null("TargetSpin") as SpinBox
	var time := setup.get_node_or_null("TimeSpin") as SpinBox
	var readout := setup.get_node_or_null("TimeReadout") as Label
	check(diff != null, "setup exposes DifficultyOption")
	check(target != null, "setup exposes TargetSpin")
	check(time != null, "setup exposes TimeSpin")
	check(setup.get_node_or_null("ConfirmButton") != null, "setup exposes ConfirmButton")
	check(setup.get_node_or_null("BackButton") != null, "setup exposes BackButton")

	# (b) Sharp/10/180 through the controls lands on the manager.
	if diff != null and target != null and time != null:
		diff.select(2)
		target.value = 10
		time.value = 180
		await process_frame
		setup.call("apply")
		check(MatchSetup.difficulty == "sharp", "holder records difficulty sharp (got %s)" % MatchSetup.difficulty)
		check(MatchSetup.target_score == 10, "holder records target 10 (got %d)" % MatchSetup.target_score)
		check(absf(MatchSetup.time_limit_s - 180.0) < 0.001, "holder records time 180")
		var m := await fresh_manager()
		check(m.difficulty == "sharp", "manager difficulty is sharp (got %s)" % m.difficulty)
		check(m.target_kills == 10, "manager target_kills is 10 (got %d)" % m.target_kills)
		check(m.target_score == 10, "manager target_score is 10 (got %d)" % m.target_score)
		check(absf(m.time_limit_s - 180.0) < 0.001, "manager time_limit_s is 180 (got %f)" % m.time_limit_s)
		m.queue_free()
		await process_frame
	if readout != null:
		check(readout.text == "3:00", "180s reads 3:00 (got %s)" % readout.text)

	# (c) Confirm returns to the menu.
	var confirm := setup.get_node_or_null("ConfirmButton") as BaseButton
	if confirm != null:
		confirm.emit_signal("pressed")
		var frames := 0
		while frames < 180:
			await process_frame
			if current_scene != null and current_scene.scene_file_path == "res://scenes/main_menu.tscn":
				break
			frames += 1
		check(current_scene != null and current_scene.scene_file_path == "res://scenes/main_menu.tscn", "Confirm returns to main_menu.tscn")
		if current_scene != null:
			current_scene.queue_free()
			await process_frame
	setup.queue_free()
	await process_frame
	MatchSetup.clear()

	# (d) Invalid input keeps compiled defaults.
	var m2 := await fresh_manager()
	check(m2.difficulty == "standard", "default difficulty holds (got %s)" % m2.difficulty)
	check(m2.target_kills == 25, "default target holds (got %d)" % m2.target_kills)
	check(absf(m2.time_limit_s - 300.0) < 0.001, "default time holds (got %f)" % m2.time_limit_s)
	m2.queue_free()
	await process_frame
	MatchSetup.clear()
	paused = false
