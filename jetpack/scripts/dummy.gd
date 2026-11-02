extends StaticBody2D
## Target dummy: measurable shoot target with HP reporting, a white hit flash,
## and a one-shot death signal. On death collisions turn off and the grey
## corpse stays readable through `corpse_lifetime`, then frees itself.

@export_group("Health")
@export var max_hp := 100.0
## How long the grey corpse stays readable after death before freeing.
@export var corpse_lifetime := 3.0

signal died
signal health_changed(hp: float, max_hp: float)

var hp: float = 100.0
var is_dead := false
var flash_t := 0.0
var corpse_age := 0.0

var _base_color := Color(1.0, 0.55, 0.15, 1.0)

@onready var _visual: Polygon2D = get_node_or_null("Visual") as Polygon2D


func _ready() -> void:
	add_to_group("damageable")
	hp = max_hp
	if _visual != null:
		_base_color = _visual.color


func _process(delta: float) -> void:
	if is_dead:
		corpse_age += delta
		if corpse_age >= corpse_lifetime:
			queue_free()
			return
	if flash_t <= 0.0:
		return
	flash_t -= delta
	if flash_t <= 0.0 and not is_dead and _visual != null:
		_visual.color = _base_color
		_visual.modulate = Color.WHITE


func take_damage(amount: float) -> void:
	if is_dead:
		return
	hp = maxf(0.0, hp - amount)
	health_changed.emit(hp, max_hp)
	var visual := _visual if _visual != null else get_node_or_null("Visual") as Polygon2D
	if visual != null:
		visual.color = Color.WHITE
		visual.modulate = Color.WHITE
	flash_t = 0.1
	if hp <= 0.0:
		is_dead = true
		# Let later rays pass through the corpse.
		collision_layer = 0
		collision_mask = 0
		corpse_age = 0.0
		if visual != null:
			visual.color = Color(0.45, 0.45, 0.48, 1.0)
		died.emit()
