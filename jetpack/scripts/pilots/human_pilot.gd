class_name HumanPilot
extends Pilot
## Live keyboard/mouse driver: the only node that reads raw input devices.
## Polls held actions and the parent soldier's mouse position each tick and
## emits one Pilot.Command. Edge fields (grenade, reload, switch_to) pulse
## for a single tick via is_action_just_pressed.

var _last_aim := Vector2.ZERO


func _ready() -> void:
	_ensure_input_actions()


func get_command(_delta: float) -> Pilot.Command:
	var cmd := Pilot.Command.new()
	cmd.move_x = Input.get_axis("move_left", "move_right")
	cmd.fly = Input.is_action_pressed("fly")
	cmd.crouch = Input.is_action_pressed("crouch")
	cmd.fire = Input.is_action_pressed("fire")
	cmd.grenade = Input.is_action_just_pressed("throw_grenade")
	cmd.reload = Input.is_action_just_pressed("reload")
	cmd.switch_to = -1
	for i in 8:
		if Input.is_action_just_pressed("slot_%d" % (i + 1)):
			cmd.switch_to = i
			break
	var parent := get_parent() as CanvasItem
	if parent != null:
		_last_aim = parent.get_global_mouse_position()
		cmd.aim_point = _last_aim
	else:
		cmd.aim_point = _last_aim
	return cmd


func _ensure_input_actions() -> void:
	var keys := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"crouch": [KEY_S, KEY_DOWN],
		"fly": [KEY_SPACE, KEY_W, KEY_UP],
		"throw_grenade": [KEY_G],
		"reload": [KEY_R],
		"slot_1": [KEY_1],
		"slot_2": [KEY_2],
		"slot_3": [KEY_3],
		"slot_4": [KEY_4],
		"slot_5": [KEY_5],
		"slot_6": [KEY_6],
		"slot_7": [KEY_7],
		"slot_8": [KEY_8],
	}
	for action in keys:
		# Leave Settings-applied remaps alone: only backfill compiled
		# defaults for actions that currently have zero events.
		if InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty():
			continue
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for keycode in keys[action]:
			var exists := false
			for ev in InputMap.action_get_events(action):
				if ev is InputEventKey and (ev as InputEventKey).physical_keycode == keycode:
					exists = true
					break
			if not exists:
				var press := InputEventKey.new()
				press.physical_keycode = keycode
				InputMap.action_add_event(action, press)
	_ensure_mouse_action("fire", MOUSE_BUTTON_LEFT)


func _ensure_mouse_action(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var exists := false
	for ev in InputMap.action_get_events(action):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == button:
			exists = true
			break
	if not exists:
		var press := InputEventMouseButton.new()
		press.button_index = button
		InputMap.action_add_event(action, press)
