extends Control
## How-to-play screen: static controls/goal copy only. Back returns to the
## main menu. All node access is get_node_or_null guarded.

const MENU_SCENE := "res://scenes/main_menu.tscn"


func _ready() -> void:
	var back := get_node_or_null("BackButton") as BaseButton
	if back != null and not back.is_connected("pressed", _on_back):
		back.connect("pressed", _on_back)


func _on_back() -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.paused = false
	tree.change_scene_to_file(MENU_SCENE)
