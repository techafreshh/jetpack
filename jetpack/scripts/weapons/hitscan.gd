extends Node2D
## Prototype hitscan AR: mouse-aim raycast fired on the fixed physics tick at
## 10 rps, duck-typed damage via take_damage, and one fading Line2D tracer per
## shot for tuning read. Tunables mirror the soldier export style.

@export_group("Weapon")
@export var damage := 12.0
@export var fire_rate := 10.0
@export var range := 1200.0
@export var tracer_lifetime := 0.9

var _cooldown := 0.0

@onready var _muzzle: Marker2D = get_node_or_null("Muzzle") as Marker2D


func _ready() -> void:
	_ensure_fire_action()


func _physics_process(delta: float) -> void:
	_cooldown -= delta
	if Input.is_action_pressed("fire") and _cooldown <= 0.0:
		_cooldown = 1.0 / fire_rate
		_fire()


func _fire() -> void:
	var from := global_position
	if _muzzle != null:
		from = _muzzle.global_position
	elif has_node("Muzzle"):
		from = (get_node("Muzzle") as Marker2D).global_position
	var to_mouse := get_global_mouse_position()
	var dir := to_mouse - from
	if dir.length() < 1.0:
		dir = Vector2.RIGHT
	else:
		dir = dir.normalized()
	var end := from + dir * range
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, end)
	var parent := get_parent()
	if parent is CollisionObject2D:
		query.exclude = [(parent as CollisionObject2D).get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		end = hit["position"]
		var collider := hit.get("collider") as Object
		if collider != null and collider.has_method("take_damage"):
			collider.call("take_damage", damage)
	_spawn_tracer(from, end)


func _spawn_tracer(a: Vector2, b: Vector2) -> void:
	var tracer := Line2D.new()
	tracer.top_level = true
	tracer.width = 3.0
	tracer.default_color = Color(1.0, 0.85, 0.4, 1.0)
	add_child(tracer)
	tracer.global_position = Vector2.ZERO
	tracer.add_point(a)
	tracer.add_point(b)
	var tween := tracer.create_tween()
	tween.tween_property(tracer, "modulate:a", 0.0, tracer_lifetime)
	tween.tween_callback(tracer.queue_free)


func _ensure_fire_action() -> void:
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
	var exists := false
	for ev in InputMap.action_get_events("fire"):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			exists = true
			break
	if not exists:
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire", press)
