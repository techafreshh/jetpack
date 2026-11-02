extends Node2D
## Match host: instances the greybox arena with a pre-spawned soldier and
## seats the soldier via the spawner (no-enemy pick) on ready. Seating only:
## fall deaths below the kill-plane are enforced by the soldier via KILL_Y.
## No scoring.

var _spawner: Spawner
var _manager: MatchManager
## Default arena scene for new matches; the static Greybox child below is the
## instanced form of this path (kept static for sim determinism).
@export var arena_path := "res://scenes/arena/main.tscn"
# HUD-readable hook state: latest soldier HP seen via health_changed.
# Sentinel -1.0 means "no event yet".
var last_hp := -1.0
var last_max_hp := -1.0
var death_count := 0
var respawn_count := 0
var last_death_cause := ""

signal soldier_died
signal soldier_respawned

@onready var _soldier: CharacterBody2D = $Soldier
@onready var _spawn0: Marker2D = $Greybox/Spawn0
@onready var camera_shake: Camera2D = get_node_or_null("CameraShake") as Camera2D


func _ready() -> void:
	get_tree().paused = false
	var pause_menu := get_node_or_null("Pause")
	if pause_menu != null:
		pause_menu.visible = false
	_spawner = Spawner.new()
	add_child(_spawner)
	_manager = get_node_or_null("MatchManager") as MatchManager
	if _manager == null:
		_manager = MatchManager.new()
		_manager.name = "MatchManager"
		add_child(_manager)
	var points := _spawner.spawn_points()
	var idx := Spawner.choose_spawn(points, [])
	if idx >= 0 and idx < points.size():
		_soldier.global_position = points[idx]
	else:
		_soldier.global_position = _spawn0.global_position
	_soldier.velocity = Vector2.ZERO
	if not _soldier.is_connected("health_changed", _on_soldier_health_changed):
		_soldier.connect("health_changed", _on_soldier_health_changed)
	if not _soldier.is_connected("died", _on_soldier_died):
		_soldier.connect("died", _on_soldier_died)
	if not _soldier.is_connected("respawned", _on_soldier_respawned):
		_soldier.connect("respawned", _on_soldier_respawned)
	var hud := get_node_or_null("hud")
	if hud != null and hud.has_method("bind_soldier"):
		hud.call("bind_soldier", _soldier)
	print("MATCH READY")


func _on_soldier_health_changed(hp: float, max_hp: float) -> void:
	last_hp = hp
	last_max_hp = max_hp
	print("MATCH HP %f / %f" % [hp, max_hp])


func _on_soldier_died() -> void:
	if is_instance_valid(_manager):
		_manager.record_death("soldier_0")
	death_count += 1
	last_death_cause = str(_soldier.get("last_death_cause"))
	soldier_died.emit()
	print("MATCH DIED %s" % last_death_cause)


func _on_soldier_respawned() -> void:
	respawn_count += 1
	last_hp = float(_soldier.get("hp"))
	last_max_hp = float(_soldier.get("max_hp"))
	soldier_respawned.emit()
	print("MATCH RESPAWNED %f / %f" % [last_hp, last_max_hp])
