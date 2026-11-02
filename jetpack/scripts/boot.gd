extends Node2D
## Boot splash: prints the boot contract line, then forwards to the main
## menu on a deferred call so the 10-second path starts at launch without
## moving run/main_scene off boot.tscn.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"


func _ready() -> void:
	print("JETPACK BOOT OK")
	call_deferred("_forward_to_menu")


func _forward_to_menu() -> void:
	var tree := get_tree()
	if tree == null:
		return
	if tree.current_scene != null and tree.current_scene.scene_file_path == MAIN_MENU_SCENE:
		return
	tree.change_scene_to_file(MAIN_MENU_SCENE)
