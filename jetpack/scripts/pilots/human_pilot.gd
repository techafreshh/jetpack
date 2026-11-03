class_name HumanPilot
extends Pilot
## Live keyboard/mouse driver: the only node that reads raw input devices.
## Polls held actions and the parent soldier's mouse position each tick and
## emits one Pilot.Command. Edge fields (grenade, reload, switch_to) pulse
## for a single tick via is_action_just_pressed.

var _last_aim := Vector2.ZERO
## Right-stick deflection below this length keeps the mouse fallback.
const PAD_DEADZONE := 0.2
## World units the stick vector is scaled by when it steers aim.
const STICK_AIM_RANGE := 600.0


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
		var stick := _pad_stick()
		if stick != Vector2.ZERO and parent is Node2D:
			cmd.aim_point = (parent as Node2D).global_position + stick * STICK_AIM_RANGE
	else:
		cmd.aim_point = _last_aim
	return cmd


## Right-stick deflection across connected pads (device 0 covers synthetic
## motion events with no hardware attached). Returns ZERO inside the
## deadzone so the mouse fallback stays untouched for keyboard players.
func _pad_stick() -> Vector2:
	var ids := Input.get_connected_joypads()
	if ids.is_empty():
		ids = [0]
	for id in ids:
		var v := Vector2(
			Input.get_joy_axis(id, JOY_AXIS_RIGHT_X),
			Input.get_joy_axis(id, JOY_AXIS_RIGHT_Y))
		if v.length() > PAD_DEADZONE:
			return v
	return Vector2.ZERO


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
	_ensure_pad_action("move_left", [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_ensure_pad_action("move_right", [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_ensure_pad_action("fly", [JOY_BUTTON_A], [])
	_ensure_pad_action("fire", [JOY_BUTTON_RIGHT_SHOULDER], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_ensure_pad_action("throw_grenade", [JOY_BUTTON_LEFT_SHOULDER], [])
	_ensure_pad_action("crouch", [JOY_BUTTON_B], [])


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


## Mirrors _ensure_mouse_action for pads: dedupe before add, so the
## project.godot bindings and repeated _ready calls never double up.
func _ensure_pad_action(action: StringName, buttons: Array, motions: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for b in buttons:
		var exists := false
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == int(b):
				exists = true
				break
		if not exists:
			var press := InputEventJoypadButton.new()
			press.button_index = int(b) as JoyButton
			InputMap.action_add_event(action, press)
	for m in motions:
		var maxis := int(m[0])
		var mval := float(m[1])
		var mexists := false
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadMotion:
				var prev := ev as InputEventJoypadMotion
				if prev.axis == maxis and signf(prev.axis_value) == signf(mval):
					mexists = true
					break
		if not mexists:
			var motion := InputEventJoypadMotion.new()
			motion.axis = maxis as JoyAxis
			motion.axis_value = mval
			InputMap.action_add_event(action, motion)
