extends Node2D
## Generic data-driven gun driver: every number comes from the `stats`
## resource (cooldown from fire_rate, cone from spread_deg, pellet loop from
## pellet_count, ammo from mag_size/reserve, scope from zoom). Pellet kind
## means N hitscan rays in one trigger pull; no per-gun branches live here.

const FX_CONFIG_PATH := "res://resources/config/fx.cfg"

@export var stats: WeaponResource
@export var tracer_lifetime := 1.5
@export var max_tracers := 32

var muzzle_flash: Polygon2D
var _flash_ticks := 0

var _tracers: Array[Line2D] = []

var ammo: int = 0
var reserve_left: int = 0
# Script-level aim override for headless tests: the display server has no
# cursor headlessly, so steer aim via this seam.
var aim_override := Vector2.ZERO
var has_aim_override := false

var _cooldown := 0.0

@onready var _muzzle: Marker2D = get_node_or_null("Muzzle") as Marker2D


func _ready() -> void:
	if stats != null and ammo <= 0 and reserve_left <= 0:
		ammo = stats.mag_size
		reserve_left = stats.reserve
	_build_muzzle_flash()
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
	if stats != null and not WeaponResource.is_fireable_rate(stats.fire_rate):
		push_error("weapon: invalid fire_rate %f, refusing to fire" % stats.fire_rate)


func _host_alive() -> bool:
	return Health.is_host_alive(get_parent())


func can_fire() -> bool:
	if stats == null:
		return false
	if not _host_alive():
		return false
	if ammo <= 0:
		return false
	if not WeaponResource.is_fireable_rate(stats.fire_rate):
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
	if not WeaponResource.is_fireable_rate(rate):
		push_error("weapon: invalid fire_rate %f, refusing to fire" % rate)
		return false
	ammo -= 1
	_cooldown = 1.0 / rate
	return true


func try_fire() -> bool:
	if consume_shot():
		_fire()
		return true
	return false


func reload() -> bool:
	if stats == null:
		return false
	if not _host_alive():
		return false
	if reserve_left <= 0:
		return false
	if ammo >= stats.mag_size:
		return false
	var need: int = stats.mag_size - ammo
	var take: int = mini(need, reserve_left)
	ammo += take
	reserve_left -= take
	_cooldown = 0.0
	if is_inside_tree():
		Sfx.ensure_buses()
		get_tree().call_group("sfx", "play_sfx", "reload")
	return true


func get_zoom() -> float:
	if stats == null:
		return 1.0
	return stats.zoom


func _physics_process(delta: float) -> void:
	if _flash_ticks > 0:
		_flash_ticks -= 1
		if _flash_ticks <= 0 and muzzle_flash != null:
			muzzle_flash.visible = false
	if stats == null:
		return
	_cooldown = maxf(0.0, _cooldown - delta)


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
	_show_muzzle_flash()
	if is_inside_tree():
		Sfx.ensure_buses()
		get_tree().call_group("sfx", "play_sfx", stats.sfx_name)
		get_tree().call_group("camera_shake", "add_shake")


func _fire_ray(from: Vector2, dir: Vector2) -> void:
	if stats == null:
		return
	var end := from + dir * stats.range
	if is_inside_tree():
		var world := get_world_2d()
		if world != null:
			var space := world.direct_space_state
			if space != null:
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


func _build_muzzle_flash() -> void:
	if muzzle_flash != null:
		return
	var tip := Vector2(20.0, -32.0)
	if _muzzle != null:
		tip = _muzzle.position
	elif has_node("Muzzle"):
		tip = (get_node("Muzzle") as Marker2D).position
	var flash := Polygon2D.new()
	flash.name = "MuzzleFlash"
	flash.color = Color(1.0, 0.8, 0.3, 1.0)
	flash.polygon = PackedVector2Array([
		tip + Vector2(-6, -8), tip + Vector2(14, 0), tip + Vector2(-6, 8),
	])
	flash.visible = false
	flash.add_to_group("muzzle_flash")
	add_child(flash)
	muzzle_flash = flash


func _show_muzzle_flash() -> void:
	var ticks := 3
	var cfg := ConfigFile.new()
	if cfg.load(FX_CONFIG_PATH) == OK:
		var raw: Variant = cfg.get_value("flash", "ticks", 3)
		if raw is int:
			ticks = maxi(2, mini(4, raw))
		elif raw is float and is_finite(raw):
			ticks = maxi(2, mini(4, int(raw)))
	_flash_ticks = ticks
	if muzzle_flash != null:
		muzzle_flash.visible = true


func _spawn_tracer(a: Vector2, b: Vector2) -> void:
	var cap: int = maxi(1, max_tracers)
	var live: Array[Line2D] = []
	for t in _tracers:
		if is_instance_valid(t) and not t.is_queued_for_deletion():
			live.append(t)
	_tracers = live
	while _tracers.size() >= cap:
		var oldest: Line2D = _tracers.pop_front()
		if is_instance_valid(oldest) and not oldest.is_queued_for_deletion():
			oldest.queue_free()
	var tracer := Line2D.new()
	tracer.top_level = true
	tracer.width = 3.0
	tracer.default_color = Color(1.0, 0.85, 0.4, 1.0)
	add_child(tracer)
	tracer.global_position = Vector2.ZERO
	tracer.add_point(a)
	tracer.add_point(b)
	var tween: Tween = null
	if is_inside_tree():
		tween = tracer.create_tween()
	if tween != null:
		tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
		tween.tween_property(tracer, "modulate:a", 0.0, tracer_lifetime)
		tween.tween_callback(tracer.queue_free)
	_tracers.append(tracer)

