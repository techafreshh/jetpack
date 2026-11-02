class_name BotPilot
extends Pilot
## Utility-AI opponent driver: scores engage / seek-cover / grab-pickup /
## retreat-reload every tick and emits one Pilot.Command. Tiers (easy,
## standard, sharp) differ ONLY in reaction delay and aim error loaded from
## bots.cfg; the scoring code path is identical for all tiers. Perception is
## a self-excluding LOS raycast plus a 180-tick (3s at 60 Hz) last-seen
## memory. Fire is gated on live LOS plus the reaction delay, so bots never
## shoot through walls or at remembered ghosts. Bots never throw grenades.

const CONFIG_PATH := "res://resources/config/bots.cfg"
const MEMORY_TICKS := 180
const CHEST_OFFSET := Vector2(0, -32)
const MIN_REACTION_MS := 20.0
const MAX_REACTION_MS := 500.0
const MIN_AIM_ERROR_DEG := 0.0
const MAX_AIM_ERROR_DEG := 15.0
const ARENA_CENTER_X := 1200.0

@export var difficulty := "standard":
	set(v):
		difficulty = str(v).to_lower()
		_load_config()

var reaction_ms := 140.0
var aim_error_deg := 4.0
var memory_s := 3.0

var _tick := 0
## instance_id -> {"pos": Vector2, "tick": int}: last-seen chest positions.
var _memory := {}
var _pending_key := -1
var _pending_since_tick := -1000000
var _last_hp := -1.0
var _under_fire_until := -1000000
var _strafe_dir := 1.0
var _strafe_period := 80
var _strafe_changed := 0
var _last_pos := Vector2.INF
var _blocked_ticks := 0
var _last_move := 0.0


func _init(diff := "standard") -> void:
	difficulty = str(diff).to_lower()
	_load_config()


func _ready() -> void:
	_load_config()


func set_difficulty(d: String) -> void:
	difficulty = d.to_lower()
	_load_config()


func _reaction_ticks() -> int:
	return maxi(1, ceili(reaction_ms / 16.666))


func _aim_error_rad() -> float:
	return deg_to_rad(aim_error_deg)


func get_command(_delta: float) -> Pilot.Command:
	_tick += 1
	var cmd := Pilot.Command.new()
	var host := get_parent() as Node2D
	if host == null or get_tree() == null:
		return cmd
	if not Health.is_host_alive(host):
		return cmd
	var seen := _perceive(host)
	var scores := _score_actions(host, seen)
	return _command_for(host, seen, scores)


func _perceive(host: Node2D) -> Dictionary:
	var foe := _nearest_foe(host)
	var foe_pos := Vector2.INF
	var visible := false
	if foe != null:
		foe_pos = (foe as Node2D).global_position + CHEST_OFFSET
		visible = _has_los(host, foe)
		if visible:
			_memory[(foe as Object).get_instance_id()] = {"pos": foe_pos, "tick": _tick}
	# Age out entries older than the 3s window.
	var drop: Array = []
	for key in _memory:
		var entry: Dictionary = _memory[key]
		if _tick - int(entry["tick"]) > MEMORY_TICKS:
			drop.append(key)
	for key in drop:
		_memory.erase(key)
	# Freshest remembered chest pos when the foe is occluded.
	var remembered := Vector2.INF
	var remembered_tick := -1000000000
	for key in _memory:
		var entry: Dictionary = _memory[key]
		if int(entry["tick"]) > remembered_tick:
			remembered_tick = int(entry["tick"])
			remembered = entry["pos"] as Vector2
	# Reaction gate: (re)start the pending-aim timer on a new live target.
	if visible and foe != null:
		var fid := (foe as Object).get_instance_id()
		if fid != _pending_key:
			_pending_key = fid
			_pending_since_tick = _tick
	elif foe == null:
		_pending_key = -1
	# Under-fire latch from HP drops: crouch/cover for ~3s after taking hits.
	var hp := _host_hp(host)
	if _last_hp < 0.0:
		_last_hp = hp
	elif hp < _last_hp - 0.5:
		_under_fire_until = _tick + MEMORY_TICKS
	_last_hp = hp
	var pad := _nearest_pickup(host)
	return {
		"foe": foe,
		"foe_pos": foe_pos,
		"visible": visible,
		"remembered": remembered,
		"pickup": pad,
	}


func _nearest_foe(host: Node) -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node2D = null
	var best_d := INF
	var hp := host as Node2D
	for node in tree.get_nodes_in_group("damageable"):
		if node == host:
			continue
		if not (node is Node2D):
			continue
		if not Health.is_live_foe(node):
			continue
		var d := (node as Node2D).global_position.distance_to(hp.global_position)
		if d < best_d:
			best_d = d
			best = node as Node2D
	return best


func _has_los(host: Node2D, foe: Node2D) -> bool:
	if not is_instance_valid(foe):
		return false
	var space := _host_space()
	if space == null:
		return true
	var from := host.global_position + CHEST_OFFSET
	var to := foe.global_position + CHEST_OFFSET
	var query := PhysicsRayQueryParameters2D.create(from, to)
	if host is CollisionObject2D:
		query.exclude = [(host as CollisionObject2D).get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return true
	return hit.get("collider") == foe


func _host_space() -> PhysicsDirectSpaceState2D:
	var host := get_parent() as Node2D
	if host == null or not host.is_inside_tree():
		return null
	var world := host.get_world_2d()
	if world == null:
		return null
	return world.direct_space_state


func _nearest_pickup(host: Node2D) -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node2D = null
	var best_d := INF
	for node in tree.get_nodes_in_group("pickup"):
		if not (node is Node2D):
			continue
		var dis: Variant = node.get("disabled")
		if dis != null and bool(dis):
			continue
		var d := (node as Node2D).global_position.distance_to(host.global_position)
		if d < best_d:
			best_d = d
			best = node as Node2D
	return best


func _score_actions(host: Node2D, seen: Dictionary) -> Dictionary:
	var ammo := _ammo_count(host)
	var mag := _mag_size(host)
	var reserve := _reserve_count(host)
	var hp_frac := _hp_fraction(host)
	var under_fire := _tick <= _under_fire_until
	var foe: Node2D = seen["foe"] as Node2D
	var visible := bool(seen["visible"])
	var remembered: Vector2 = seen["remembered"] as Vector2
	var pad: Node2D = seen["pickup"] as Node2D
	var threat_known := foe != null or remembered != Vector2.INF
	var threat_dist := INF
	if foe != null:
		threat_dist = foe.global_position.distance_to(host.global_position)
	elif remembered != Vector2.INF:
		threat_dist = remembered.distance_to(host.global_position + CHEST_OFFSET)
	# Shared weights for every tier: only reaction/aim vary, never the path.
	var engage := 0.0
	if visible and ammo > 0:
		engage = clampf(1.2 - threat_dist / 1200.0, 0.2, 1.0)
	var seek_cover := 0.0
	if (hp_frac < 0.4 or under_fire) and (visible or remembered != Vector2.INF):
		seek_cover = 0.75
	var grab_pickup := 0.0
	if (float(ammo) < float(mag) * 0.5 or hp_frac < 0.6) and pad != null:
		grab_pickup = 0.65
	var retreat := 0.0
	if ammo <= 0 or (hp_frac < 0.4 and threat_known and threat_dist < 700.0):
		retreat = 1.3
	return {
		"engage": engage,
		"seek_cover": seek_cover,
		"grab_pickup": grab_pickup,
		"retreat": retreat,
		"reserve": reserve,
		"under_fire": under_fire,
	}


func _command_for(host: Node2D, seen: Dictionary, scores: Dictionary) -> Pilot.Command:
	var cmd := Pilot.Command.new()
	cmd.grenade = false
	var foe: Node2D = seen["foe"] as Node2D
	var foe_pos: Vector2 = seen["foe_pos"] as Vector2
	var visible := bool(seen["visible"])
	var remembered: Vector2 = seen["remembered"] as Vector2
	var pad: Node2D = seen["pickup"] as Node2D
	var ammo := _ammo_count(host)
	var reserve := int(scores.get("reserve", 0))
	var mag := _mag_size(host)
	var hp_frac := _hp_fraction(host)
	var fuel := _fuel_fraction(host)
	# Threat anchor: live chest first, freshest memory when occluded.
	var threat := Vector2.INF
	if foe != null:
		threat = foe_pos
	if not visible and remembered != Vector2.INF:
		threat = remembered
	# Aim: live chest with tier aim error; remembered chest while occluded;
	# forward probe point when nothing is known. Fire only on gated LOS.
	var from := host.global_position + CHEST_OFFSET
	var aim := from + Vector2(300.0 * _strafe_dir, 0.0)
	if visible:
		aim = _err_aim(from, foe_pos)
	elif remembered != Vector2.INF:
		aim = remembered
	cmd.aim_point = aim
	var elapsed := _tick - _pending_since_tick
	cmd.fire = visible and ammo > 0 and elapsed >= _reaction_ticks()
	# Winner-take-all over the four utility actions; shared for all tiers.
	var action := "wander"
	var best := 0.0
	if float(scores.get("engage", 0.0)) > best:
		best = float(scores.get("engage", 0.0))
		action = "engage"
	if float(scores.get("seek_cover", 0.0)) > best:
		best = float(scores.get("seek_cover", 0.0))
		action = "cover"
	if float(scores.get("grab_pickup", 0.0)) > best:
		best = float(scores.get("grab_pickup", 0.0))
		action = "pickup"
	if float(scores.get("retreat", 0.0)) > best:
		best = float(scores.get("retreat", 0.0))
		action = "retreat"
	# Locomotion targets per action.
	var move := 0.0
	var fly := false
	var crouch := false
	match action:
		"engage":
			move = _fight_move(host, foe_pos)
			fly = foe != null and (foe_pos.y < from.y - 120.0)
		"cover":
			move = _away_move(host, threat)
			crouch = true
			fly = threat != Vector2.INF and (threat.y < from.y - 200.0) and fuel > 0.25
		"pickup":
			if pad != null:
				move = _seek_move(host, (pad as Node2D).global_position)
				fly = (pad as Node2D).global_position.y < from.y - 120.0 and fuel > 0.15
			else:
				move = _fight_move(host, foe_pos if visible else remembered)
				crouch = false
		"retreat":
			move = _away_move(host, threat)
			crouch = hp_frac < 0.5
		_:
			move = _wander_move(host, foe if visible else null, remembered, pad)
	if action == "engage" and foe != null:
		crouch = false
	# Empty mag forces the observable response on EVERY action: reload plus
	# break-contact motion away from the threat, never a stationary wait.
	if ammo <= 0:
		if reserve > 0 and mag > 0:
			cmd.reload = true
		if threat != Vector2.INF:
			move = _away_move(host, threat)
			if move == 0.0:
				move = -signf((threat.x - host.global_position.x)) if threat.x != host.global_position.x else _strafe_dir
		elif move == 0.0:
			move = _strafe_dir
	# Low-ammo top-up outside contact keeps guns fed without stalling fights.
	if not bool(cmd.reload) and ammo < mag and reserve > 0 and not visible:
		cmd.reload = true
	# Anti-stall hop: commanded motion with no displacement burns a hop.
	_update_blocked(host)
	if _blocked_ticks > 20 and fuel > 0.25:
		fly = true
	cmd.move_x = clampf(move, -1.0, 1.0)
	if cmd.move_x == 0.0:
		cmd.move_x = _strafe_dir * 0.6
	cmd.fly = fly
	cmd.crouch = crouch
	cmd.switch_to = -1
	_last_move = cmd.move_x
	return cmd


func _fight_move(host: Node2D, target: Vector2) -> float:
	_tick_strafe()
	if target == Vector2.INF:
		return _strafe_dir
	var dx := target.x - host.global_position.x
	var dist := absf(dx)
	if dist > 350.0:
		return signf(dx)
	if dist < 140.0:
		return -signf(dx) * 0.8 + _strafe_dir * 0.4
	return _strafe_dir


func _away_move(host: Node2D, threat: Vector2) -> float:
	_tick_strafe()
	if threat == Vector2.INF:
		return _strafe_dir
	var dx := host.global_position.x - threat.x
	if absf(dx) < 1.0:
		return _strafe_dir
	return signf(dx)


func _seek_move(host: Node2D, target: Vector2) -> float:
	_tick_strafe()
	var dx := target.x - host.global_position.x
	if absf(dx) < 24.0:
		return _strafe_dir * 0.5
	return signf(dx)


func _wander_move(host: Node2D, foe: Node2D, remembered: Vector2, pad: Node2D) -> float:
	_tick_strafe()
	if foe != null:
		return _fight_move(host, (foe as Node2D).global_position + CHEST_OFFSET)
	if remembered != Vector2.INF:
		return _seek_move(host, remembered)
	if pad != null:
		return _seek_move(host, (pad as Node2D).global_position)
	var dx := ARENA_CENTER_X - host.global_position.x
	if absf(dx) > 900.0:
		return signf(dx)
	return _strafe_dir


func _tick_strafe() -> void:
	if _tick - _strafe_changed >= _strafe_period:
		_strafe_dir = -_strafe_dir
		_strafe_changed = _tick
		_strafe_period = 50 + (_tick * 37) % 60


func _update_blocked(host: Node2D) -> void:
	if _last_pos == Vector2.INF:
		_last_pos = host.global_position
		_blocked_ticks = 0
		return
	if absf(_last_move) > 0.1 and absf(host.global_position.x - _last_pos.x) < 2.0 and host.is_on_floor():
		_blocked_ticks += 1
	else:
		_blocked_ticks = 0
	_last_pos = host.global_position


func _err_aim(from: Vector2, target: Vector2) -> Vector2:
	var to := target - from
	var dist := to.length()
	if dist < 1.0:
		return target
	var err := randf_range(-_aim_error_rad(), _aim_error_rad())
	return from + to.normalized().rotated(err) * dist


func _host_hp(host: Node2D) -> float:
	var v: Variant = host.get("hp")
	if v == null:
		return 100.0
	return float(v)


func _hp_fraction(host: Node2D) -> float:
	var hp := _host_hp(host)
	var m: Variant = host.get("max_hp")
	if m == null or float(m) <= 0.0:
		return 1.0
	return clampf(hp / float(m), 0.0, 1.0)


func _fuel_fraction(host: Node2D) -> float:
	var f: Variant = host.get("fuel")
	var m: Variant = host.get("fuel_max")
	if f == null or m == null or float(m) <= 0.0:
		return 1.0
	return clampf(float(f) / float(m), 0.0, 1.0)


func _weapon(host: Node2D) -> Node:
	return host.get_node_or_null("Weapon")


func _ammo_count(host: Node2D) -> int:
	var w := _weapon(host)
	if w == null:
		return 1
	var v: Variant = w.get("ammo")
	if v == null:
		return 1
	return int(v)


func _reserve_count(host: Node2D) -> int:
	var w := _weapon(host)
	if w == null:
		return 1
	var v: Variant = w.get("reserve_left")
	if v == null:
		return 1
	return int(v)


func _mag_size(host: Node2D) -> int:
	var w := _weapon(host)
	if w == null:
		return 30
	var stats: Variant = w.get("stats")
	if stats == null:
		return 30
	var v: Variant = stats.get("mag_size")
	if v == null:
		return 30
	return int(v)


func _load_config(path: String = CONFIG_PATH) -> void:
	var section := difficulty.to_lower()
	if section != "easy" and section != "standard" and section != "sharp":
		push_warning("botpilot: invalid difficulty %s, using standard" % difficulty)
		section = "standard"
		difficulty = section
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		push_warning("botpilot: missing %s, using tier defaults" % CONFIG_PATH)
		_apply_tier_defaults(section)
		return
	reaction_ms = _cfg_ms(cfg, section, _tier_reaction(section))
	aim_error_deg = _cfg_deg(cfg, section, _tier_aim(section))
	memory_s = _cfg_memory(cfg, _tier_memory())


func _tier_reaction(section: String) -> float:
	match section:
		"easy":
			return 250.0
		"sharp":
			return 70.0
	return 140.0


func _tier_aim(section: String) -> float:
	match section:
		"easy":
			return 8.0
		"sharp":
			return 1.5
	return 4.0


func _tier_memory() -> float:
	return 3.0


func _apply_tier_defaults(section: String) -> void:
	reaction_ms = _tier_reaction(section)
	aim_error_deg = _tier_aim(section)
	memory_s = _tier_memory()


static func _cfg_ms(cfg: ConfigFile, section: String, fallback: float) -> float:
	for key in ["reaction_ms", "reaction_delay_ms", "delay_ms"]:
		if not cfg.has_section_key(section, key):
			continue
		var raw: Variant = cfg.get_value(section, key, fallback)
		var val := _to_float(raw, fallback)
		if not is_finite(val):
			push_warning("botpilot: invalid %s/%s, keeping default" % [section, key])
			return fallback
		if val < MIN_REACTION_MS or val > MAX_REACTION_MS:
			push_warning("botpilot: invalid %s/%s, keeping default" % [section, key])
			return fallback
		return val
	return fallback


static func _cfg_deg(cfg: ConfigFile, section: String, fallback: float) -> float:
	for key in ["aim_error_deg", "aim_error", "spread_deg"]:
		if not cfg.has_section_key(section, key):
			continue
		var raw: Variant = cfg.get_value(section, key, fallback)
		var val := _to_float(raw, fallback)
		if not is_finite(val):
			push_warning("botpilot: invalid %s/%s, keeping default" % [section, key])
			return fallback
		if val < MIN_AIM_ERROR_DEG or val > MAX_AIM_ERROR_DEG:
			push_warning("botpilot: invalid %s/%s, keeping default" % [section, key])
			return fallback
		return val
	return fallback


static func _cfg_memory(cfg: ConfigFile, fallback: float) -> float:
	if not cfg.has_section_key("perception", "memory_s"):
		return fallback
	var raw: Variant = cfg.get_value("perception", "memory_s", fallback)
	var val := _to_float(raw, fallback)
	if not is_finite(val) or val <= 0.0 or val > 10.0:
		push_warning("botpilot: invalid perception/memory_s, keeping default")
		return fallback
	return val


static func _to_float(raw: Variant, fallback: float) -> float:
	if raw is float:
		return raw
	if raw is int:
		return float(raw)
	if raw is String and (raw as String).is_valid_float():
		return float(raw)
	push_warning("botpilot: non-numeric config value, keeping default")
	return fallback
