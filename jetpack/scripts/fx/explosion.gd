extends Node2D
## Timed-blast FX: linear-falloff radial damage plus directional knockback
## over the `damageable` group, then a short fade and free. Centre damage is
## full `max_damage`; the rim keeps 25% so edge hits always hurt. Knockback
## keeps 30% at the rim so self-damage launches grenade jumps.

@export var blast_radius := 180.0
@export var max_damage := 60.0
@export var knockback_max := 900.0
@export var lifetime := 0.5

var _age := 0.0
var _detonated := false
## Tracks whether the Visual already carries the reduced-flash halving so
## the alpha cut applies exactly once no matter which seam runs first.
var _softened := false

@onready var _visual: Polygon2D = get_node_or_null("Visual") as Polygon2D


func _ready() -> void:
	add_to_group("explosion")
	_build_visual()
	call_deferred("detonate")


func _process(delta: float) -> void:
	_age += delta
	if _visual != null:
		_visual.modulate.a = maxf(0.0, 1.0 - _age / lifetime)
	if _age >= lifetime:
		queue_free()


func detonate() -> void:
	if _detonated:
		return
	_detonated = true
	_apply_flash_softening()
	_kick_camera()
	var tree := get_tree()
	if tree == null:
		return
	var center := global_position
	for node in tree.get_nodes_in_group("damageable"):
		# Normally-killed dummies/soldiers already left damageable, so this
		# skip is backup for externally-set flags and re-added members.
		if Health.is_dead(node):
			continue
		if not Health.is_host_alive(node):
			continue
		if not (node is Node2D):
			continue
		var target := node as Node2D
		var offset := target.global_position - center
		var dist := offset.length()
		if dist > blast_radius:
			continue
		var frac := dist / blast_radius
		var dmg := max_damage * (1.0 - 0.75 * frac)
		if node.has_method("take_damage"):
			node.call("take_damage", dmg)
		var dir := Vector2.UP
		if offset.length() > 1.0:
			dir = offset.normalized()
		# Slight upward bias so blasts lift instead of burying.
		dir = (dir + Vector2(0.0, -0.35)).normalized()
		var impulse := dir * knockback_max * (1.0 - 0.7 * frac)
		if node.has_method("apply_knockback"):
			node.call("apply_knockback", impulse)
		elif "velocity" in node:
			node.set("velocity", node.get("velocity") + impulse)


## Reduced-flash softening: halves the Visual alpha exactly once while the
## toggle is on. Duck-typed camera kick: feeds trauma to the first seated
## CameraShake, ignored when none is present (older scenes, bare use).
func _apply_flash_softening() -> void:
	if _softened:
		return
	if not Accessibility.reduced_flash_on(self):
		return
	var visual := _visual if _visual != null else get_node_or_null("Visual") as Polygon2D
	if visual == null:
		return
	var c := visual.color
	c.a *= 0.5
	visual.color = c
	_softened = true


func _kick_camera() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for cam in tree.get_nodes_in_group("camera_shake"):
		if cam != null and cam.has_method("add_trauma"):
			cam.call("add_trauma", 0.5)
		return


func _build_visual() -> void:
	if _visual != null:
		_apply_flash_softening()
		return
	var ring := Polygon2D.new()
	ring.name = "Visual"
	ring.color = Color(1.0, 0.6, 0.15, 0.55)
	var pts := PackedVector2Array()
	for i in 25:
		var ang := TAU * float(i) / 24.0
		pts.append(Vector2(cos(ang), sin(ang)) * blast_radius)
	ring.polygon = pts
	add_child(ring)
	_visual = ring
	_apply_flash_softening()
