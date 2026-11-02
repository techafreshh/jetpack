class_name CameraShake
extends Camera2D
## Trauma camera: explosions feed add_trauma, per-frame offset/rotation play
## trauma^2-scaled summed sines times the shake slider, and zero trauma
## yields exactly zero offset/rotation. Joins group camera_shake on ready so
## explosions find it duck-typed; fully guarded tree-less/Settings-less.

## Peak positional kick at full trauma, in pixels.
@export var max_offset := 24.0
## Peak roll at full trauma, in radians.
@export var max_roll := 0.05
## Trauma drained per second.
@export var decay := 1.2

var trauma := 0.0
var _t := 0.0


func _ready() -> void:
	add_to_group("camera_shake")
	enabled = true
	make_current()


func add_trauma(amount: float) -> void:
	if not is_finite(amount):
		return
	trauma = clampf(trauma + amount, 0.0, 1.0)


func _process(delta: float) -> void:
	trauma = maxf(0.0, trauma - decay * delta)
	_t += delta
	var scale := Accessibility.shake_scale(self)
	var mag := trauma * trauma * scale
	if mag <= 0.0:
		offset = Vector2.ZERO
		rotation = 0.0
		return
	offset = Vector2(
		max_offset * mag * (0.6 * sin(_t * 39.0) + 0.4 * sin(_t * 71.0)),
		max_offset * mag * (0.6 * cos(_t * 47.0) + 0.4 * sin(_t * 83.0))
	)
	rotation = max_roll * mag * sin(_t * 59.0)
