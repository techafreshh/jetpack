extends CharacterBody2D
## Playable soldier: ground run, half-height crouch, rocket-boot thrust with a
## fuel tank that refuels faster when grounded, and momentum-preserving air
## control. Fixed 60 Hz physics; tunables load from movement.cfg over exports.

const CONFIG_PATH := "res://resources/config/movement.cfg"
const GRENADE_CONFIG_PATH := "res://resources/config/grenade.cfg"
const GRENADE_SCENE := preload("res://scenes/grenade.tscn")
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
var slots: Array[String] = ["ranger_ar"]

var fuel: float = 100.0
var crouched: bool = false
var thrusting: bool = false

var _stand_h: float = 64.0

@onready var _body: CollisionShape2D = $Body
@onready var _head_check: RayCast2D = $HeadCheck
@onready var _visual: Polygon2D = $Visual
@onready var _arc: Line2D = get_node_or_null("ArcPreview") as Line2D


func _ready() -> void:
	_load_config()
	add_to_group("damageable")
	# Never mutate the shared sub-resource when crouch-resizing.
	if _body.shape != null:
		_body.shape = _body.shape.duplicate()
		_stand_h = (_body.shape as RectangleShape2D).size.y
	fuel = fuel_max
	_ensure_input_actions()


func _physics_process(delta: float) -> void:
	var was_floor := is_on_floor()

	# Crouch first so height and speed mult apply to the rest of the tick.
	if Input.is_action_pressed("crouch"):
		_set_crouched(true)
	else:
		_head_check.force_raycast_update()
		if not _head_check.is_colliding():
			_set_crouched(false)

	thrusting = Input.is_action_pressed("fly") and fuel > 0.0

	var burn_rate := fuel_max / fuel_burn_s
	if not was_floor:
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)
	if thrusting:
		velocity.y = maxf(velocity.y - thrust_force * delta, -max_rise_speed)
		fuel = maxf(0.0, fuel - burn_rate * delta)
	else:
		var mult := ground_refuel_mult if was_floor else air_refuel_mult
		fuel = minf(fuel_max, fuel + burn_rate * mult * delta)

	var dir := Input.get_axis("move_left", "move_right")
	var target := dir * run_speed * (crouch_speed_mult if crouched else 1.0)
	if dir != 0.0:
		var accel := ground_accel if was_floor else ground_accel * air_control
		velocity.x = move_toward(velocity.x, target, accel * delta)
	elif was_floor:
		velocity.x = move_toward(velocity.x, 0.0, ground_friction * delta)
	# Airborne with no input: velocity.x untouched, momentum preserved.

	if Input.is_action_just_pressed("throw_grenade"):
		throw_grenade()
	_update_arc_preview()

	move_and_slide()


func take_damage(amount: float) -> void:
	hp = maxf(0.0, hp - amount)


func apply_knockback(impulse: Vector2) -> void:
	velocity += impulse


func add_grenades(n: int) -> int:
	grenade_count = mini(grenade_max, grenade_count + n)
	_update_arc_preview()
	return grenade_count


func heal(amount: float) -> float:
	hp = minf(max_hp, hp + amount)
	return hp


func add_weapon(id: String) -> bool:
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


func restock_ammo() -> void:
	var weapon := get_node_or_null("Weapon")
	if weapon == null:
		return
	var stats = weapon.get("stats")
	if stats == null:
		return
	weapon.set("ammo", int(stats.get("mag_size")))
	weapon.set("reserve_left", int(stats.get("reserve")))


func throw_grenade() -> bool:
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


func _aim_direction() -> Vector2:
	var from := global_position + CHEST_OFFSET
	var d := get_global_mouse_position() - from
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
	var rect := _body.shape as RectangleShape2D
	if rect == null:
		return
	var h := _stand_h * crouch_height_mult if on else _stand_h
	rect.size = Vector2(rect.size.x, h)
	# Re-seat the shape so the feet stay planted at the same floor point.
	_body.position.y = -h * 0.5
	_visual.position.y = -h * 0.5
	_visual.scale.y = h / _stand_h


func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		push_warning("soldier: missing %s, using export defaults" % CONFIG_PATH)
		return
	run_speed = float(cfg.get_value("movement", "run_speed", run_speed))
	ground_accel = float(cfg.get_value("movement", "ground_accel", ground_accel))
	ground_friction = float(cfg.get_value("movement", "ground_friction", ground_friction))
	air_control = float(cfg.get_value("movement", "air_control", air_control))
	gravity = float(cfg.get_value("movement", "gravity", gravity))
	thrust_force = float(cfg.get_value("movement", "thrust_force", thrust_force))
	max_rise_speed = float(cfg.get_value("movement", "max_rise_speed", max_rise_speed))
	max_fall_speed = float(cfg.get_value("movement", "max_fall_speed", max_fall_speed))
	crouch_height_mult = float(cfg.get_value("movement", "crouch_height_mult", crouch_height_mult))
	crouch_speed_mult = float(cfg.get_value("movement", "crouch_speed_mult", crouch_speed_mult))
	fuel_max = float(cfg.get_value("movement", "fuel_max", fuel_max))
	fuel_burn_s = float(cfg.get_value("movement", "fuel_burn_s", fuel_burn_s))
	ground_refuel_mult = float(cfg.get_value("movement", "ground_refuel_mult", ground_refuel_mult))
	air_refuel_mult = float(cfg.get_value("movement", "air_refuel_mult", air_refuel_mult))

	var gcfg := ConfigFile.new()
	if gcfg.load(GRENADE_CONFIG_PATH) != OK:
		push_warning("soldier: missing %s, using export defaults" % GRENADE_CONFIG_PATH)
		return
	throw_speed = float(gcfg.get_value("grenade", "throw_speed", throw_speed))
	grenade_max = int(gcfg.get_value("grenade", "max_grenades", grenade_max))
	grenade_count = mini(grenade_count, grenade_max)


func _ensure_input_actions() -> void:
	var keys := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"crouch": [KEY_S, KEY_DOWN],
		"fly": [KEY_SPACE, KEY_W, KEY_UP],
		"throw_grenade": [KEY_G],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for keycode in keys[action]:
			var exists := false
			for ev in InputMap.action_get_events(action):
				if ev is InputEventKey and (ev as InputEventKey).physical_keycode == keycode:
					exists = true
					break
			if not exists:
				var press := InputEventKey.new()
				press.physical_keycode = keycode
				InputMap.action_add_event(action, press)
