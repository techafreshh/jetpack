extends Node2D
## Match host: instances the greybox arena with a pre-spawned soldier and
## seats the soldier via the spawner (no-enemy pick) on ready. Seating only:
## fall deaths below the kill-plane are enforced by the soldier via KILL_Y.
## No scoring.

var _spawner: Spawner

@onready var _soldier: CharacterBody2D = $Soldier
@onready var _spawn0: Marker2D = $Greybox/Spawn0


func _ready() -> void:
	_spawner = Spawner.new()
	add_child(_spawner)
	var points := _spawner.spawn_points()
	var idx := Spawner.choose_spawn(points, [])
	if idx >= 0 and idx < points.size():
		_soldier.global_position = points[idx]
	else:
		_soldier.global_position = _spawn0.global_position
	_soldier.velocity = Vector2.ZERO
	print("MATCH READY")
