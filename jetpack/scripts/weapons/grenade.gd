extends RigidBody2D
## Thrown grenade: ballistic body with a fixed-tick 2.5 s fuse. `prime()`
## starts the countdown; `_physics_process` ticks it down at 60 Hz and
## `explode()` swaps the shell for an `explosion` FX node. Audible fuse is
## structural: a `FuseBeep` player plus GRENADE print logs, no audio asset.

const CONFIG_PATH := "res://resources/config/grenade.cfg"
const EXPLOSION_SCRIPT := preload("res://scripts/fx/explosion.gd")

@export var fuse_time := 2.5
@export var blast_radius := 180.0
@export var max_damage := 60.0
@export var knockback_max := 900.0
@export var flight_gravity := 1200.0
@export var beep_interval := 0.5

var fuse_left := 0.0
var primed := false

var _exploded := false
var _beep_accum := 0.0

@onready var _beep: AudioStreamPlayer2D = get_node_or_null("FuseBeep") as AudioStreamPlayer2D


func _ready() -> void:
	_load_config()
	var default_grav: float = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)
	if default_grav > 0.0:
		gravity_scale = flight_gravity / default_grav


func prime() -> void:
	if primed:
		return
	primed = true
	fuse_left = fuse_time
	_beep_accum = 0.0
	print("GRENADE PRIMED")
	_play_beep()


func _physics_process(delta: float) -> void:
	if not primed or _exploded:
		return
	fuse_left = maxf(0.0, fuse_left - delta)
	_beep_accum += delta
	if _beep_accum >= beep_interval:
		_beep_accum = 0.0
		print("GRENADE TICK fuse_left=%.2f" % maxf(fuse_left, 0.0))
		_play_beep()
	if fuse_left <= 0.0:
		explode()


func explode() -> void:
	if _exploded:
		return
	_exploded = true
	var host := get_parent()
	var boom := EXPLOSION_SCRIPT.new() as Node2D
	boom.name = "Explosion"
	boom.set("blast_radius", blast_radius)
	boom.set("max_damage", max_damage)
	boom.set("knockback_max", knockback_max)
	if host != null:
		if host is Node2D:
			boom.position = (host as Node2D).to_local(global_position)
		else:
			boom.position = global_position
		host.add_child(boom)
		boom.global_position = global_position
		boom.call("detonate")
	else:
		add_sibling(boom)
		boom.global_position = global_position
		boom.call("detonate")
	print("GRENADE EXPLODED")
	queue_free()


func _play_beep() -> void:
	if _beep != null and _beep.stream != null:
		_beep.play()


func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		push_warning("grenade: missing %s, using export defaults" % CONFIG_PATH)
		return
	fuse_time = float(cfg.get_value("grenade", "fuse_time", fuse_time))
	blast_radius = float(cfg.get_value("grenade", "blast_radius", blast_radius))
	max_damage = float(cfg.get_value("grenade", "max_damage", max_damage))
	knockback_max = float(cfg.get_value("grenade", "knockback_max", knockback_max))
