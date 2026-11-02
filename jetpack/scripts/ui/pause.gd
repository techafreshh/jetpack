class_name PauseMenu
extends CanvasLayer
## Esc pause overlay: freezes the sim behind a Resume / hold-to-confirm
## Restart / hold-to-confirm Quit-to-menu / Settings menu. Show sets
## get_tree().paused = true; resume restores exactly (zero score/clock
## writes). Restart drives the repo's MatchManager.rematch() contract
## (zeroes scores, restores the clock, returns to countdown) and unpauses;
## Quit unpauses then changes to res://scenes/main_menu.tscn. Every node
## access is get_node_or_null guarded so a bare PauseMenu.new() never
## errors, mirroring the hud.gd guarded style.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_hide_settings()
	_connect_button("Menu/ResumeButton", resume_game)
	_connect_hold("Menu/RestartButton", _on_restart)
	_connect_hold("Menu/QuitButton", _on_quit)
	_connect_button("Menu/SettingsButton", toggle_settings)
	_connect_button("SettingsPanel/BackButton", _hide_settings)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		if (event as InputEventKey).physical_keycode == KEY_ESCAPE or (event as InputEventKey).keycode == KEY_ESCAPE:
			toggle_pause()
			get_viewport().set_input_as_handled()


## Esc-equivalent entry point; probes drive this instead of real input.
func toggle_pause() -> void:
	if visible and get_tree() != null and get_tree().paused:
		resume_game()
	else:
		show_pause()


func show_pause() -> void:
	var tree := get_tree()
	if tree != null:
		tree.paused = true
	visible = true
	_reset_holds()


func resume_game() -> void:
	var tree := get_tree()
	if tree != null:
		tree.paused = false
	visible = false


func toggle_settings() -> void:
	var panel := get_node_or_null("SettingsPanel") as Control
	if panel == null:
		return
	panel.visible = not panel.visible


func _on_restart() -> void:
	var manager := _find_manager()
	if manager != null and manager.has_method("rematch"):
		manager.call("rematch")
	elif get_tree() != null:
		get_tree().reload_current_scene()
	# Leave the confirming hold latched at 1.0 so a post-hold progress read
	# still observes the completed ring; show_pause resets on next open.
	resume_game()


func _on_quit() -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.paused = false
	visible = false
	tree.change_scene_to_file(MAIN_MENU_SCENE)


func _find_manager() -> Node:
	var parent := get_parent()
	if parent != null:
		if parent.get("time_left") != null:
			return parent
		for child in parent.get_children():
			if child == self:
				continue
			if not (child is Node):
				continue
			var n := child as Node
			if n.get("time_left") != null:
				return n
			if n.has_method("rematch"):
				return n
	var tree := get_tree()
	if tree != null:
		for node in tree.get_nodes_in_group("match_manager"):
			return node as Node
		if tree.current_scene != null and tree.current_scene != self:
			if tree.current_scene.get("time_left") != null:
				return tree.current_scene
	return null


func _connect_button(path: String, method: Callable) -> void:
	var button := get_node_or_null(path) as BaseButton
	if button == null:
		return
	if not button.is_connected("pressed", method):
		button.connect("pressed", method)


func _connect_hold(path: String, method: Callable) -> void:
	var button := get_node_or_null(path) as BaseButton
	if button == null:
		return
	if button.has_signal("confirmed"):
		if not button.is_connected("confirmed", method):
			button.connect("confirmed", method)


func _reset_holds() -> void:
	for path in ["Menu/RestartButton", "Menu/QuitButton"]:
		var button := get_node_or_null(path) as Node
		if button != null and button.has_method("reset_hold"):
			button.call("reset_hold")


func _hide_settings() -> void:
	var panel := get_node_or_null("SettingsPanel") as Control
	if panel != null:
		panel.visible = false
