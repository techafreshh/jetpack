extends CanvasLayer
## Standalone settings menu: sliders for master/music/SFX volume, one remap
## button per keyboard action with press-a-key capture, toggles for the
## accessibility set, plus reset and back. Bound to /root/Settings; every
## node access is get_node_or_null guarded so a bare scene never errors,
## mirroring the hud.gd guarded style. Never writes files, only Settings API.

const REMAP_BUTTONS := {
	"RemapMoveLeft": "move_left",
	"RemapMoveRight": "move_right",
	"RemapCrouch": "crouch",
	"RemapFly": "fly",
	"RemapGrenade": "throw_grenade",
	"RemapReload": "reload",
}
const ACTION_LABELS := {
	"move_left": "Move Left",
	"move_right": "Move Right",
	"crouch": "Crouch",
	"fly": "Fly",
	"throw_grenade": "Grenade",
	"reload": "Reload",
}

var _settings: Node = null
var _capture_action := ""


func _ready() -> void:
	_settings = get_node_or_null("/root/Settings")
	_refresh_all()
	_connect_slider("MasterSlider", _on_master_changed)
	_connect_slider("MusicSlider", _on_music_changed)
	_connect_slider("SfxSlider", _on_sfx_changed)
	_connect_toggle("ColorblindToggle", _on_colorblind_toggled)
	_connect_toggle("FlashToggle", _on_flash_toggled)
	_connect_toggle("AimAssistToggle", _on_aim_assist_toggled)
	for button in REMAP_BUTTONS:
		_connect_remap(String(button), String(REMAP_BUTTONS[button]))
	_connect_button("ResetButton", _on_reset_pressed)
	_connect_button("BackButton", _on_back_pressed)


func _input(event: InputEvent) -> void:
	if _capture_action == "":
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var key_event := event as InputEventKey
		if key_event.physical_keycode == KEY_ESCAPE or key_event.keycode == KEY_ESCAPE:
			_capture_action = ""
			_refresh_remap_buttons()
			get_viewport().set_input_as_handled()
			return
		var kc := key_event.physical_keycode
		if kc == KEY_NONE:
			kc = key_event.keycode
		if kc != KEY_NONE and _settings != null and _settings.has_method("set_keybind"):
			_settings.call("set_keybind", _capture_action, kc)
		_capture_action = ""
		_refresh_remap_buttons()
		get_viewport().set_input_as_handled()


func _refresh_all() -> void:
	_refresh_sliders()
	_refresh_remap_buttons()
	_refresh_toggles()


func _refresh_sliders() -> void:
	_set_slider("MasterSlider", "MasterValue", _volume("master_volume"))
	_set_slider("MusicSlider", "MusicValue", _volume("music_volume"))
	_set_slider("SfxSlider", "SfxValue", _volume("sfx_volume"))


func _volume(key: String) -> float:
	if _settings != null and _settings.get(key) != null:
		return clampf(float(_settings.get(key)), 0.0, 1.0)
	return 1.0


func _set_slider(slider_path: String, value_path: String, v: float) -> void:
	var slider := get_node_or_null(slider_path) as HSlider
	if slider != null:
		slider.set_value_no_signal(v)
	var label := get_node_or_null(value_path) as Label
	if label != null:
		label.text = "%d%%" % int(round(v * 100.0))


func _refresh_remap_buttons() -> void:
	for button in REMAP_BUTTONS:
		var action := String(REMAP_BUTTONS[button])
		var btn := get_node_or_null(String(button)) as Button
		if btn == null:
			continue
		var label := String(ACTION_LABELS.get(action, action))
		if _capture_action == action:
			btn.text = "%s: press a key…" % label
		else:
			btn.text = "%s: %s" % [label, _bind_text(action)]


func _bind_text(action: String) -> String:
	if _settings != null and _settings.has_method("get_keybind_string"):
		return String(_settings.call("get_keybind_string", action))
	return ""


func _refresh_toggles() -> void:
	_set_toggle("ColorblindToggle", _toggle("colorblind_mode"))
	_set_toggle("FlashToggle", _toggle("reduced_flashing"))
	_set_toggle("AimAssistToggle", _toggle("aim_assist"))


func _set_toggle(toggle_path: String, enabled: bool) -> void:
	var toggle := get_node_or_null(toggle_path) as BaseButton
	if toggle != null:
		toggle.set_pressed_no_signal(enabled)


func _toggle(key: String) -> bool:
	if _settings != null and _settings.has_method("get_toggle"):
		return bool(_settings.call("get_toggle", key))
	return false


func _begin_capture(action: String) -> void:
	_capture_action = action
	_refresh_remap_buttons()


func _connect_slider(path: String, method: Callable) -> void:
	var slider := get_node_or_null(path) as HSlider
	if slider == null:
		return
	if not slider.is_connected("value_changed", method):
		slider.connect("value_changed", method)


func _connect_toggle(path: String, method: Callable) -> void:
	var toggle := get_node_or_null(path) as BaseButton
	if toggle == null:
		return
	if not toggle.is_connected("toggled", method):
		toggle.connect("toggled", method)


func _connect_remap(path: String, action: String) -> void:
	var button := get_node_or_null(path) as BaseButton
	if button == null:
		return
	var method := _begin_capture.bind(action)
	if not button.is_connected("pressed", method):
		button.connect("pressed", method)


func _connect_button(path: String, method: Callable) -> void:
	var button := get_node_or_null(path) as BaseButton
	if button == null:
		return
	if not button.is_connected("pressed", method):
		button.connect("pressed", method)


func _on_master_changed(v: float) -> void:
	if _settings != null and _settings.has_method("set_master_volume"):
		_settings.call("set_master_volume", v)
	_refresh_sliders()


func _on_music_changed(v: float) -> void:
	if _settings != null and _settings.has_method("set_music_volume"):
		_settings.call("set_music_volume", v)
	_refresh_sliders()


func _on_sfx_changed(v: float) -> void:
	if _settings != null and _settings.has_method("set_sfx_volume"):
		_settings.call("set_sfx_volume", v)
	_refresh_sliders()


func _on_colorblind_toggled(enabled: bool) -> void:
	if _settings != null and _settings.has_method("set_toggle"):
		_settings.call("set_toggle", "colorblind_mode", enabled)


func _on_flash_toggled(enabled: bool) -> void:
	if _settings != null and _settings.has_method("set_toggle"):
		_settings.call("set_toggle", "reduced_flashing", enabled)


func _on_aim_assist_toggled(enabled: bool) -> void:
	if _settings != null and _settings.has_method("set_toggle"):
		_settings.call("set_toggle", "aim_assist", enabled)


func _on_reset_pressed() -> void:
	if _settings != null and _settings.has_method("reset_to_defaults"):
		_settings.call("reset_to_defaults")
	_refresh_all()


func _on_back_pressed() -> void:
	visible = false
