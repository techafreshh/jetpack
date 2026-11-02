extends Control
## Main menu front door: Play starts the match, Setup/HowTo navigate to
## their scenes, Settings toggles the in-menu volume panel. All node access
## is get_node_or_null guarded so a bare instance never errors, mirroring
## the hud.gd guarded style. Unpauses on ready (quit-to-menu arrives paused).

const MATCH_SCENE := "res://scenes/match.tscn"
const SETUP_SCENE := "res://scenes/ui/setup.tscn"
const HOWTO_SCENE := "res://scenes/ui/howto.tscn"


func _ready() -> void:
	var tree := get_tree()
	if tree != null:
		tree.paused = false
	_connect_button("Play", _on_play)
	_connect_button("Setup", _on_setup)
	_connect_button("HowTo", _on_howto)
	_connect_button("Settings", _on_settings)
	_connect_button("SettingsPanel/BackButton", _on_settings_back)
	_connect_volume()
	_hide_settings()


func _on_play() -> void:
	_go(MATCH_SCENE)


func _on_setup() -> void:
	_go(SETUP_SCENE)


func _on_howto() -> void:
	_go(HOWTO_SCENE)


func _on_settings() -> void:
	var panel := get_node_or_null("SettingsPanel") as Control
	if panel != null:
		panel.visible = not panel.visible


func _on_settings_back() -> void:
	_hide_settings()


func _on_volume_changed(v: float) -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings != null and settings.has_method("set_master_volume"):
		settings.call("set_master_volume", v)


func _go(scene_path: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.paused = false
	tree.change_scene_to_file(scene_path)


func _hide_settings() -> void:
	var panel := get_node_or_null("SettingsPanel") as Control
	if panel != null:
		panel.visible = false


func _connect_button(path: String, method: Callable) -> void:
	var button := get_node_or_null(path) as BaseButton
	if button == null:
		return
	if not button.is_connected("pressed", method):
		button.connect("pressed", method)


func _connect_volume() -> void:
	var slider := get_node_or_null("SettingsPanel/VolumeSlider") as HSlider
	if slider == null:
		return
	var settings := get_node_or_null("/root/Settings")
	if settings != null and settings.get("master_volume") != null:
		slider.set_value_no_signal(clampf(float(settings.get("master_volume")), 0.0, 1.0))
	if not slider.is_connected("value_changed", _on_volume_changed):
		slider.connect("value_changed", _on_volume_changed)
