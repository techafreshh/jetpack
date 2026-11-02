class_name Spawner
extends Node
## Enemy-aware respawn selection: pure argmax over spawn points of the
## minimum distance to any live enemy. Thin tree helpers collect spawn
## points (greybox Spawn* markers overridden by spawns.cfg) and live-enemy
## positions (live soldiers only: damageable nodes exposing a true is_alive;
## dummies never count as foes, alive or dead).

const CONFIG_PATH := "res://resources/config/spawns.cfg"


func _ready() -> void:
	add_to_group("spawner")


static func choose_spawn(spawns: Array[Vector2], enemies: Array[Vector2]) -> int:
	if spawns.is_empty():
		return -1
	if enemies.is_empty():
		return 0
	var best := 0
	var best_d := -1.0
	for i in spawns.size():
		var d := nearest_enemy_dist(spawns[i], enemies)
		if d > best_d:
			best_d = d
			best = i
	return best


static func nearest_enemy_dist(p: Vector2, enemies: Array[Vector2]) -> float:
	var best := INF
	for e in enemies:
		best = minf(best, p.distance_to(e))
	return best


func load_points(fallback: Array[Vector2]) -> Array[Vector2]:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		push_warning("spawner: missing %s, using scene markers" % CONFIG_PATH)
		return fallback
	var points: Array[Vector2] = []
	for i in 8:
		var v: Vector2 = cfg.get_value("spawn%d" % i, "pos", fallback[i] if i < fallback.size() else Vector2.ZERO)
		points.append(v)
	if points.is_empty():
		return fallback
	return points


func spawn_points() -> Array[Vector2]:
	var fallback: Array[Vector2] = collect_markers()
	return load_points(fallback)


func collect_markers() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var parent := get_parent()
	var scope: Node = parent if parent != null else self
	for n in scope.find_children("Spawn*", "Marker2D", true, false):
		out.append((n as Node2D).global_position)
	return out


func live_enemy_positions(exclude: Node = null) -> Array[Vector2]:
	var tree := get_tree()
	if tree == null:
		return []
	var out: Array[Vector2] = []
	for node in tree.get_nodes_in_group("damageable"):
		if node == exclude:
			continue
		if not (node is Node2D):
			continue
		if not Health.is_live_foe(node):
			continue
		out.append((node as Node2D).global_position)
	return out
