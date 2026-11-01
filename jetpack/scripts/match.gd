extends Node2D
## Match host: instances the greybox arena with a pre-spawned soldier and
## seats the soldier via the spawner (no-enemy pick) on ready. Seating only:
## fall deaths below the kill-plane are enforced by the soldier via KILL_Y.
## No scoring.

var _spawner: Spawner
# HUD-readable hook state: latest soldier HP seen via health_changed.
# Sentinel -1.0 means "no event yet".
var last_hp := -1.0
var last_max_hp := -1.0

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
	if not _soldier.is_connected("health_changed", _on_soldier_health_changed):
		_soldier.connect("health_changed", _on_soldier_health_changed)
	print("MATCH READY")


func _on_soldier_health_changed(hp: float, max_hp: float) -> void:
	last_hp = hp
	last_max_hp = max_hp
	print("MATCH HP %f / %f" % [hp, max_hp])
