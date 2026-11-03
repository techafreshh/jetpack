extends SceneTree
## Headless proof that reload and slot_1..slot_8 exist as compiled defaults
## in project.godot [input] with the HumanPilot backfill keys, visible
## without spawning a HumanPilot.
## Run: godot --headless --path jetpack --script res://tests/test_input_map.gd

var passed := 0
var failed := 0

const EXPECTED_KEYS := {
	"reload": KEY_R,
	"slot_1": KEY_1,
	"slot_2": KEY_2,
	"slot_3": KEY_3,
	"slot_4": KEY_4,
	"slot_5": KEY_5,
	"slot_6": KEY_6,
	"slot_7": KEY_7,
	"slot_8": KEY_8,
}


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


func file_lines(path: String) -> Array[String]:
	var out: Array[String] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		out.append(f.get_line())
	return out


func run_tests() -> void:
	await process_frame

	# No HumanPilot may be in-tree: these actions must come from the compiled map.
	var humans := root.find_children("*", "HumanPilot", true, false)
	check(humans.is_empty(), "no HumanPilot in-tree while probing the compiled map (got %d)" % humans.size())

	for action in EXPECTED_KEYS:
		var want := int(EXPECTED_KEYS[action])
		check(InputMap.has_action(StringName(action)), "%s exists without a HumanPilot" % action)
		if not InputMap.has_action(StringName(action)):
			continue
		var events := InputMap.action_get_events(StringName(action))
		check(not events.is_empty(), "%s carries at least one event" % action)
		var keycodes: Array = []
		for ev in events:
			if ev is InputEventKey:
				keycodes.append(int((ev as InputEventKey).physical_keycode))
		check(not keycodes.is_empty(), "%s carries an InputEventKey" % action)
		check(keycodes.has(want), "%s binds physical_keycode %d (got %s)" % [action, want, str(keycodes)])

	var proj_lines := file_lines("res://project.godot")
	check(not proj_lines.is_empty(), "project.godot reads from disk")
	var proj_blob := "\n".join(proj_lines)
	check(proj_blob.contains("reload={"), "project.godot [input] declares reload")
	for i in 8:
		var slot := "slot_%d={" % (i + 1)
		check(proj_blob.contains(slot), "project.godot [input] declares %s" % slot)
