extends Control
## Minimal menu landing scene for pause Quit-to-menu. Unpauses on ready
## (quit leaves the tree paused behind it) and returns to the match via
## PlayButton. All node access is get_node_or_null guarded so a bare
## instance never errors.

const MATCH_SCENE := "res://scenes/match.tscn"


func _ready() -> void:
	var tree := get_tree()
	if tree != null:
		tree.paused = false
	var play := get_node_or_null("PlayButton") as BaseButton
	if play != null and not play.is_connected("pressed", _on_play):
		play.connect("pressed", _on_play)


func _on_play() -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.paused = false
	tree.change_scene_to_file(MATCH_SCENE)
