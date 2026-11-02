extends CharacterBody2D
## Playable soldier: ground run, half-height crouch, rocket-boot thrust with a
## fuel tank that refuels faster when grounded, and momentum-preserving air
## control. Fixed 60 Hz physics; tunables load from movement.cfg over exports.
## Falling below KILL_Y (arena safety net under the wall bottoms) kills via _die().

const FX_CONFIG_PATH := "res://resources/config/fx.cfg"
const CONFIG_PATH := "res://resources/config/movement.cfg"
const GRENADE_CONFIG_PATH := "res://resources/config/grenade.cfg"
const SPAWN_CONFIG_PATH := "res://resources/config/spawns.cfg"
const GRENADE_SCENE := preload("res://scenes/grenade.tscn")
## World-space safety net below the arena wall bottoms; matches test_arena gate.
const KILL_Y := 2000.0
const MAX_GRENADES := 2
const CHEST_OFFSET := Vector2(0, -32)
const ARC_STEP := 0.08

@export_group("Run")
@export var run_speed := 260.0
@export var ground_accel := 1700.0
@export var ground_friction := 650.0
@export var air_control := 0.55
@export var gravity := 1200.0
@export_group("Rocket Boots")
@export var thrust_force := 2600.0
@export var max_rise_speed := 420.0
@export var max_fall_speed := 640.0
@export_group("Fuel")
@export var fuel_max := 100.0
@export var fuel_burn_s := 2.5
@export var ground_refuel_mult := 4.0
@export var air_refuel_mult := 1.0
@export_group("Crouch")
@export var crouch_height_mult := 0.5
@export var crouch_speed_mult := 0.4
@export_group("Grenades")
@export var throw_speed := 700.0
@export var grenade_gravity := 1200.0
@export var arc_points := 24

var grenade_count := 2
var grenade_max := 2
var hp := 100.0
var max_hp := 100.0
## Killer attribution seam: optional attacker id from the last damaging hit.
## Cleared on respawn; falls back to "" (HUD shows "the arena").
var last_killer := ""
var _last_attacker := ""
var is_alive := true:
	set(value):
		is_alive = value
		if value:
			if not is_in_group("damageable"):
				add_to_group("damageable")
		else:
			if is_in_group("damageable"):
				remove_from_group("damageable")
var respawn_ticks_left := 0
## Why the soldier last died: "fall" (kill-plane) or "damage" (lethal take_damage); "" before any death.
var last_death_cause := ""
## Compiled-in spawner-less fallback; matches spawns.cfg spawn0.
const SAFE_FALLBACK := Vector2(200, 300)
## Most recent above-plane position; spawner-less respawn prefers it.
var _last_safe_position := Vector2.INF
## Cached spawn config loaded once in _ready: per-death disk reads removed.
var _spawn_delay_ticks: int = Health.RESPAWN_TICKS
var _spawn_points: Array[Vector2] = []
var slots: Array[String] = ["ranger_ar"]

signal died
signal health_changed(hp: float, max_hp: float)
signal respawned

var fuel: float = 100.0
var crouched: bool = false
var thrusting: bool = false
var _trail: CPUParticles2D
var _flash_ticks := 0
# Script-level aim override for headless tests: the display server has no
# cursor headlessly, so steer aim via this seam.
var aim_override := Vector2.ZERO
var has_aim_override := false
## Per-tick driver: the sole reader of raw input (HumanPilot) or a scripted
## Pilot subclass. The sim consumes only Pilot.Command, never devices.
var pilot: Pilot
var _cmd_aim := Vector2.ZERO
var _has_cmd_aim := false

var _stand_h: float = 64.0
var _saved_layer := 1
var _saved_mask := 1

@onready var _body: CollisionShape2D = get_node_or_null("Body") as CollisionShape2D
@onready var _head_check: RayCast2D = get_node_or_null("HeadCheck") as RayCast2D
@onready var _visual: Polygon2D = get_node_or_null("Visual") as Polygon2D
@onready var _arc: Line2D = get_node_or_null("ArcPreview") as Line2D


func _ready() -> void:
	_load_config()
	_load_spawn_config()
	add_to_group("damageable")
	_saved_layer = collision_layer
	_saved_mask = collision_mask
	# Never mutate the shared sub-resource when crouch-resizing.
	if _body != null and _body.shape != null:
		_body.shape = _body.shape.duplicate()
		var rect := _body.shape as RectangleShape2D
		if rect != null:
			_stand_h = rect.size.y
	fuel = fuel_max
	_build_trail()
	if pilot == null:
		pilot = HumanPilot.new()
		add_child(pilot)
	elif pilot.get_parent() == null:
		add_child(pilot)
	_record_safe_position()


func _record_safe_position() -> void:
	if global_position.y < KILL_Y:
		_last_safe_position = global_position


func _physics_process(delta: float) -> void:
	if _flash_ticks > 0:
		_flash_ticks -= 1
		if _flash_ticks <= 0 and _visual != null:
			_visual.modulate = Color.WHITE
	if not is_alive:
		if _trail != null:
			_trail.emitting = false
		respawn_ticks_left -= 1
		if respawn_ticks_left <= 0:
			respawn_ticks_left = 0
			_respawn()
		return
	_record_safe_position()
	if global_position.y > KILL_Y:
		_die("fall")
		return
	var cmd := Pilot.Command.new()
	if pilot != null and is_instance_valid(pilot):
		cmd = pilot.get_command(delta)
	apply_command(cmd, delta)


func set_pilot(p: Pilot) -> void:
	if p == pilot:
		return
	if pilot != null and is_instance_valid(pilot):
		pilot.queue_free()
	pilot = p
	if pilot != null and pilot.get_parent() == null:
		add_child(pilot)


func apply_command(cmd: Pilot.Command, delta: float) -> void:
	var was_floor := is_on_floor()

	# Crouch first so height and speed mult apply to the rest of the tick.
	if cmd.crouch:
		_set_crouched(true)
	else:
		if _head_check == null:
			_set_crouched(false)
		else:
			_head_check.force_raycast_update()
			if not _head_check.is_colliding():
				_set_crouched(false)

	thrusting = cmd.fly and fuel > 0.0
	if _trail != null:
		_trail.emitting = thrusting and is_alive

	var burn_rate := fuel_max / fuel_burn_s
	if not was_floor:
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)
	if thrusting:
		velocity.y = maxf(velocity.y - thrust_force * delta, -max_rise_speed)
		fuel = maxf(0.0, fuel - burn_rate * delta)
	else:
		var mult := ground_refuel_mult if was_floor else air_refuel_mult
		fuel = minf(fuel_max, fuel + burn_rate * mult * delta)

	var dir := clampf(cmd.move_x, -1.0, 1.0)
	var target := dir * run_speed * (crouch_speed_mult if crouched else 1.0)
	if dir != 0.0:
		var accel := ground_accel if was_floor else ground_accel * air_control
		velocity.x = move_toward(velocity.x, target, accel * delta)
	elif was_floor:
		velocity.x = move_toward(velocity.x, 0.0, ground_friction * delta)
	# Airborne with no input: velocity.x untouched, momentum preserved.

	if cmd.grenade:
		throw_grenade()
	_cmd_aim = cmd.aim_point
	_has_cmd_aim = true
	var weapon := get_node_or_null("Weapon")
	if weapon != null:
		weapon.call("set_aim_point", _aim_point())
		if cmd.fire and weapon.has_method("try_fire"):
			weapon.call("try_fire")
		if cmd.reload and weapon.has_method("reload"):
			weapon.call("reload")
	if cmd.switch_to >= 0:
		_switch_to(cmd.switch_to)
	_update_arc_preview()

	move_and_slide()


func _switch_to(idx: int) -> void:
	if idx < 0 or idx >= slots.size():
		return
	add_weapon(slots[idx])


func take_damage(amount: float, attacker: String = "") -> void:
	if not is_alive:
		return
	if attacker != "":
		_last_attacker = attacker
	hp = Health.apply_damage(hp, amount)
	health_changed.emit(hp, max_hp)
	if is_inside_tree():
		Sfx.ensure_buses()
		get_tree().call_group("sfx", "play_sfx", "hit")
		HitStop.trigger(get_tree())
	if hp <= 0.0:
		_die("damage")
		return
	_flash_ticks = 3
	if _visual != null:
		_visual.modulate = Color(3.0, 3.0, 3.0, 1.0)


func apply_knockback(impulse: Vector2) -> void:
	if not is_alive:
		return
	velocity += impulse


func add_grenades(n: int) -> int:
	if not is_alive:
		return grenade_count
	grenade_count = mini(grenade_max, grenade_count + n)
	_update_arc_preview()
	return grenade_count


func heal(amount: float) -> float:
	if not is_alive:
		return hp
	hp = Health.heal_to(hp, max_hp, amount)
	health_changed.emit(hp, max_hp)
	return hp


func respawn_seconds_left() -> float:
	return float(respawn_ticks_left) / 60.0


func _build_trail() -> void:
	if _trail != null:
		return
	var amount := 24
	var cfg := ConfigFile.new()
	if cfg.load(FX_CONFIG_PATH) == OK:
		var raw: Variant = cfg.get_value("trail", "amount", amount)
		if raw is int:
			amount = maxi(8, raw)
		elif raw is float and is_finite(raw):
			amount = maxi(8, int(raw))
	var trail := CPUParticles2D.new()
	trail.name = "JetpackTrail"
	trail.amount = amount
	trail.lifetime = 0.4
	trail.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	trail.emission_sphere_radius = 6.0
	trail.position = Vector2(0, -8)
	trail.direction = Vector2(0, 1)
	trail.spread = 25.0
	trail.initial_velocity_min = 120.0
	trail.initial_velocity_max = 220.0
	trail.gravity = Vector2.ZERO
	trail.scale_amount_min = 2.0
	trail.scale_amount_max = 4.0
	trail.color = Color(1.0, 0.6, 0.15, 0.8)
	trail.emitting = false
	add_child(trail)
	_trail = trail


func _die(cause: String = "damage") -> void:
	if _trail != null:
		_trail.emitting = false
	is_alive = false
	respawn_ticks_left = _respawn_delay_ticks()
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	last_death_cause = cause
	last_killer = _last_attacker
	remove_from_group("damageable")
	died.emit()
	print("SOLDIER DIED")


func _respawn() -> void:
	var point := global_position
	var spawner := get_tree().get_first_node_in_group("spawner") if get_tree() != null else null
	var spawner_hit := false
	if spawner != null and spawner.has_method("spawn_points") and spawner.has_method("live_enemy_positions"):
		var points: Array = spawner.call("spawn_points")
		var enemies: Array = spawner.call("live_enemy_positions", self)
		var pts: Array[Vector2] = []
		for p in points:
			pts.append(p as Vector2)
		var foes: Array[Vector2] = []
		for e in enemies:
			foes.append(e as Vector2)
		var idx := Spawner.choose_spawn(pts, foes)
		if idx >= 0 and idx < pts.size():
			point = pts[idx]
			spawner_hit = true
	if not spawner_hit:
		if _last_safe_position.y < KILL_Y:
			point = _last_safe_position
		else:
			point = _config_respawn_point()
	if point.y >= KILL_Y:
		point = _config_respawn_point()
	global_position = point
	hp = max_hp
	health_changed.emit(hp, max_hp)
	velocity = Vector2.ZERO
	collision_layer = _saved_layer
	collision_mask = _saved_mask
	is_alive = true
	last_killer = ""
	_last_attacker = ""
	add_to_group("damageable")
	respawned.emit()
	print("SOLDIER RESPAWNED")


func _respawn_delay_ticks() -> int:
	return _spawn_delay_ticks


func _config_respawn_point() -> Vector2:
	for p in _spawn_points:
		if p != Vector2.INF and p.y < KILL_Y:
			return p
	return SAFE_FALLBACK


func add_weapon(id: String) -> bool:
	if not is_alive:
		return false
	var path := "res://resources/weapons/%s.tres" % id
	if not ResourceLoader.exists(path):
		return false
	if not slots.has(id):
		slots.append(id)
	var res := load(path) as WeaponResource
	if res == null:
		return false
	var weapon := get_node_or_null("Weapon")
	if weapon != null and weapon.has_method("equip"):
		weapon.call("equip", res)
	return true


func restock_ammo() -> bool:
	if not is_alive:
		return false
	var weapon := get_node_or_null("Weapon")
	if weapon == null:
		return false
	var stats = weapon.get("stats")
	if stats == null:
		return false
	if int(weapon.get("ammo")) >= int(stats.get("mag_size")) and int(weapon.get("reserve_left")) >= int(stats.get("reserve")):
		return false
	weapon.set("ammo", int(stats.get("mag_size")))
	weapon.set("reserve_left", int(stats.get("reserve")))
	return true


func throw_grenade() -> bool:
	if not is_alive:
		return false
	if grenade_count <= 0:
		return false
	grenade_count -= 1
	var shell := GRENADE_SCENE.instantiate() as RigidBody2D
	var host := get_parent()
	if host == null:
		host = get_tree().root
	var dir := _aim_direction()
	host.add_child(shell)
	shell.global_position = global_position + CHEST_OFFSET
	shell.linear_velocity = dir * throw_speed
	shell.call("prime")
	_update_arc_preview()
	return true


func set_aim_point(p: Vector2) -> void:
	aim_override = p
	has_aim_override = true


func clear_aim_override() -> void:
	has_aim_override = false


func _aim_point() -> Vector2:
	if has_aim_override:
		return aim_override
	if _has_cmd_aim:
		return _cmd_aim
	return get_global_mouse_position()


func _aim_direction() -> Vector2:
	var from := global_position + CHEST_OFFSET
	var d := _aim_point() - from
	if d.length() < 1.0:
		return Vector2.RIGHT
	return d.normalized()


func _update_arc_preview() -> void:
	if _arc == null:
		return
	if grenade_count <= 0:
		_arc.visible = false
		return
	_arc.visible = true
	var pts := PackedVector2Array()
	var v := _aim_direction() * throw_speed
	for i in arc_points:
		var t := float(i) * ARC_STEP
		pts.append(CHEST_OFFSET + v * t + Vector2(0.0, 0.5 * grenade_gravity * t * t))
	_arc.points = pts


func _set_crouched(on: bool) -> void:
	if crouched == on:
		return
	crouched = on
	if _body == null:
		return
	var rect := _body.shape as RectangleShape2D
	if rect == null:
		return
	var h := _stand_h * crouch_height_mult if on else _stand_h
	rect.size = Vector2(rect.size.x, h)
	# Re-seat the shape so the feet stay planted at the same floor point.
	_body.position.y = -h * 0.5
	if _visual != null:
		_visual.position.y = -h * 0.5
		_visual.scale.y = h / _stand_h


func _load_config(movement_path: String = CONFIG_PATH, grenade_path: String = GRENADE_CONFIG_PATH) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(movement_path) != OK:
		push_warning("soldier: missing %s, using export defaults" % CONFIG_PATH)
		return
	run_speed = _cfg_float(cfg, "movement", "run_speed", run_speed)
	ground_accel = _cfg_float(cfg, "movement", "ground_accel", ground_accel)
	ground_friction = _cfg_float(cfg, "movement", "ground_friction", ground_friction)
	air_control = _cfg_float(cfg, "movement", "air_control", air_control)
	gravity = _cfg_float(cfg, "movement", "gravity", gravity)
	thrust_force = _cfg_float(cfg, "movement", "thrust_force", thrust_force)
	max_rise_speed = _cfg_float(cfg, "movement", "max_rise_speed", max_rise_speed)
	max_fall_speed = _cfg_float(cfg, "movement", "max_fall_speed", max_fall_speed)
	crouch_height_mult = _cfg_float(cfg, "movement", "crouch_height_mult", crouch_height_mult)
	crouch_speed_mult = _cfg_float(cfg, "movement", "crouch_speed_mult", crouch_speed_mult)
	fuel_max = _cfg_float(cfg, "movement", "fuel_max", fuel_max)
	fuel_burn_s = _cfg_float(cfg, "movement", "fuel_burn_s", fuel_burn_s)
	ground_refuel_mult = _cfg_float(cfg, "movement", "ground_refuel_mult", ground_refuel_mult)
	air_refuel_mult = _cfg_float(cfg, "movement", "air_refuel_mult", air_refuel_mult)

	var gcfg := ConfigFile.new()
	if gcfg.load(grenade_path) != OK:
		push_warning("soldier: missing %s, using export defaults" % GRENADE_CONFIG_PATH)
		return
	throw_speed = _cfg_float(gcfg, "grenade", "throw_speed", throw_speed)
	grenade_max = _cfg_int(gcfg, "grenade", "max_grenades", grenade_max)
	grenade_count = mini(grenade_count, grenade_max)


static func _cfg_float(cfg: ConfigFile, section: String, key: String, fallback: float) -> float:
	var raw: Variant = cfg.get_value(section, key, fallback)
	if raw is float:
		if is_finite(raw):
			return raw
		push_warning("soldier: invalid %s/%s, keeping default" % [section, key])
		return fallback
	if raw is int:
		return float(raw)
	push_warning("soldier: invalid %s/%s, keeping default" % [section, key])
	return fallback


static func _cfg_int(cfg: ConfigFile, section: String, key: String, fallback: int) -> int:
	var raw: Variant = cfg.get_value(section, key, fallback)
	if raw is int:
		return raw
	push_warning("soldier: invalid %s/%s, keeping default" % [section, key])
	return fallback


func _load_spawn_config(path: String = SPAWN_CONFIG_PATH) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		push_warning("soldier: missing %s, using export defaults" % SPAWN_CONFIG_PATH)
		return
	_spawn_delay_ticks = _cfg_int(cfg, "respawn", "delay_ticks", Health.RESPAWN_TICKS)
	_spawn_points.clear()
	for i in 8:
		var raw: Variant = cfg.get_value("spawn%d" % i, "pos", Vector2.INF)
		if raw is Vector2 and raw != Vector2.INF:
			_spawn_points.append(raw)

