extends Node2D
## Match host: instances the greybox arena with a pre-spawned soldier and
## seats the soldier at Spawn0 on ready. No rules, scoring, or kill logic.

@onready var _soldier: CharacterBody2D = $Soldier
@onready var _spawn0: Marker2D = $Greybox/Spawn0


func _ready() -> void:
	_soldier.global_position = _spawn0.global_position
	_soldier.velocity = Vector2.ZERO
	print("MATCH READY")
