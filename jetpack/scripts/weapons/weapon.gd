extends Node2D
## Generic data-driven gun driver: every number comes from the `stats`
## resource (cooldown from fire_rate, cone from spread_deg, pellet loop from
## pellet_count, ammo from mag_size/reserve, scope from zoom). Pellet kind
## means N hitscan rays in one trigger pull; no per-gun branches live here.

@export var stats: WeaponResource
@export var tracer_lifetime := 1.5

var ammo: int = 0
var reserve_left: int = 0
# Script-level aim override for headless tests: raw Input.warp_mouse is a
# display-server no-op with no cursor headlessly, so steer aim via this seam.
var aim_override := Vector2.ZERO
var has_aim_override := false

var _cooldown := 0.0

@onready var _muzzle: Marker2D = get_node_or_null("Muzzle") as Marker2D


func _ready() -> void:
	_ensure_fire_action()
	if stats != null and ammo <= 0 and reserve_left <= 0:
		ammo = stats.mag_size
		reserve_left = stats.reserve
	_report_bad_rate()


func equip(r: WeaponResource) -> void:
	stats = r
	_cooldown = 0.0
	if stats == null:
		ammo = 0
		reserve_left = 0
		return
	ammo = stats.mag_size
	reserve_left = stats.reserve
	_report_bad_rate()


func _report_bad_rate() -> void:
	if stats != null and stats.fire_rate <= 0.0:
		push_error("weapon: invalid fire_rate %f, refusing to fire" % stats.fire_rate)


func _host_alive() -> bool:
	var parent := get_parent()
	if parent == null:
		return true
	if parent.has_method("get") and "is_alive" in parent:
		return bool(parent.get("is_alive"))
	return true


func can_fire() -> bool:
	if stats == null:
		return false
	if not _host_alive():
		return false
	if ammo <= 0:
		return false
	if stats.fire_rate <= 0.0:
		return false
	return _cooldown <= 0.0


func consume_shot() -> bool:
	if stats == null:
		return false
	if not _host_alive():
		return false
	if ammo <= 0:
		return false
	if _cooldown > 0.0:
		return false
	var rate: float = stats.fire_rate
	if rate <= 0.0:
		push_error("weapon: invalid fire_rate %f, refusing to fire" % rate)
		return false
	ammo -= 1
	_cooldown = 1.0 / rate
	return true


func reload() -> bool:
	if stats == null:
		return false
	if reserve_left <= 0:
		return false
	if ammo >= stats.mag_size:
		return false
	var need: int = stats.mag_size - ammo
	var take: int = mini(need, reserve_left)
	ammo += take
	reserve_left -= take
	return true


func get_zoom() -> float:
	if stats == null:
		return 1.0
	return stats.zoom


func _physics_process(delta: float) -> void:
	if stats == null:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	if Input.is_action_pressed("fire") and can_fire():
		if consume_shot():
			_fire()


func set_aim_point(p: Vector2) -> void:
	aim_override = p
	has_aim_override = true


func clear_aim_override() -> void:
	has_aim_override = false


func _aim_point() -> Vector2:
	if has_aim_override:
		return aim_override
	return get_global_mouse_position()


func _fire() -> void:
	if stats == null:
		return
	var from := global_position
	if _muzzle != null:
		from = _muzzle.global_position
	elif has_node("Muzzle"):
		from = (get_node("Muzzle") as Marker2D).global_position
	var to_mouse := _aim_point()
	var base := to_mouse - from
	if base.length() < 1.0:
		base = Vector2.RIGHT
	else:
		base = base.normalized()
	var count: int = maxi(1, stats.pellet_count)
	for i in count:
		var ang := deg_to_rad(randf_range(-stats.spread_deg * 0.5, stats.spread_deg * 0.5))
		var dir := base.rotated(ang)
		_fire_ray(from, dir)


func _fire_ray(from: Vector2, dir: Vector2) -> void:
	var end := from + dir * stats.range
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
			collider.call("take_damage", stats.damage)
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
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
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
