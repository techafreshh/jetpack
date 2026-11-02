extends Node
## RunState autoload: in-memory last-match results for standings/rematch
## continuity across scene changes. Pure memory, never touches disk.

var last_match: Dictionary = {}
var last_difficulty: String = ""


func record_match(results: Dictionary) -> void:
	last_match = results.duplicate(true)
	if results.has("difficulty"):
		last_difficulty = str(results["difficulty"])


func get_last_match() -> Dictionary:
	return last_match.duplicate(true)


func clear() -> void:
	last_match = {}
	last_difficulty = ""
