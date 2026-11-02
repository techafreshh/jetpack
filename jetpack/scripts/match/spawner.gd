class_name Spawner
extends Node
## Enemy-aware respawn selection: pure argmax over spawn points of the
## minimum distance to any live enemy. Thin tree helpers collect spawn
## points (greybox Spawn* markers overridden by spawns.cfg) and live-enemy
## positions (live soldiers only: damageable nodes exposing a true is_alive;
## dummies never count as foes, alive or dead).

const CONFIG_PATH := "res://resources/config/spawns.cfg"
## Ready-once spawn config cache (mirrors soldier._load_spawn_config): raw cfg
## values per spawn index, Vector2.INF for absent/non-Vector2 entries.
var _cfg_points: Array[Vector2] = []
## Whether the cfg file loaded at ready; false keeps the marker fallback.
var _has_cfg := false


func _ready() -> void:
	add_to_group("spawner")
	_load_config()


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


func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		push_warning("spawner: missing %s, using scene markers" % CONFIG_PATH)
		return
	_has_cfg = true
	_cfg_points.clear()
	for i in 8:
		var raw: Variant = cfg.get_value("spawn%d" % i, "pos", Vector2.INF)
		if raw is Vector2:
			_cfg_points.append(raw)
		else:
			_cfg_points.append(Vector2.INF)


func load_points(fallback: Array[Vector2]) -> Array[Vector2]:
	if not _has_cfg:
		return fallback
	var points: Array[Vector2] = []
	for i in 8:
		var cached: Vector2 = _cfg_points[i] if i < _cfg_points.size() else Vector2.INF
		if cached != Vector2.INF:
			points.append(cached)
		else:
			points.append(fallback[i] if i < fallback.size() else Vector2.ZERO)
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
