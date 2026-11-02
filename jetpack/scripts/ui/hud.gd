extends CanvasLayer
## Live HUD: HP bar, mag/reserve, grenade pips, match timer, score target,
## fuel bar, crosshair, and a death overlay with killer plus respawn
## countdown. Self-sufficient polling widget: re-discovers its soldier and
## match clock every physics tick (60 Hz sim) via duck-typed lookups, so it
## renders with no API knowledge. Explicit bind_soldier/refresh exist for
## determinism; per-tick polling is the primary contract.
## Crash-free with no soldier, no weapon, and no manager.

const MATCH_CONFIG_PATH := "res://resources/config/match.cfg"

const FALLBACK_TIME_S := 300.0
const FALLBACK_TARGET := 25
const LIT_COLOR := Color(1.0, 0.8, 0.2, 1.0)
const DIM_COLOR := Color(0.25, 0.25, 0.25, 0.6)

## Explicit soldier override; when empty, auto-discovery applies.
var soldier_path: NodePath = NodePath("")

var _soldier: Node = null
var _manager: Node = null
var _death_killer := ""
var _fallback_time: float = FALLBACK_TIME_S
var _fallback_target: int = FALLBACK_TARGET


func _ready() -> void:
	_load_match_config()


func bind_soldier(s: Node) -> void:
	_soldier = s
	_death_killer = ""
	_connect_soldier()
	refresh()


func show_death(killer: String) -> void:
	_death_killer = killer
	refresh()


func hide_death() -> void:
	_death_killer = ""
	var overlay := get_node_or_null("death_overlay") as Control
	if overlay != null:
		overlay.visible = false


func _physics_process(delta: float) -> void:
	_ensure_targets()
	if _manager == null:
		_fallback_time = maxf(0.0, _fallback_time - delta)
	refresh()


func _ensure_targets() -> void:
	if _soldier != null and not is_instance_valid(_soldier):
		_soldier = null
	if _soldier == null:
		_soldier = _discover_soldier()
	if _soldier != null:
		_connect_soldier()
	if _manager != null and not is_instance_valid(_manager):
		_manager = null
	if _manager == null:
		_manager = _discover_manager()


func _discover_soldier() -> Node:
	if soldier_path != NodePath(""):
		var via_path := get_node_or_null(soldier_path) as Node
		if via_path != null and via_path.get("hp") != null:
			return via_path
	var parent := get_parent()
	if parent != null:
		var seated := parent.get_node_or_null("Soldier") as Node
		if seated != null and seated.get("hp") != null:
			return seated
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("damageable"):
		if node == null or not is_instance_valid(node):
			continue
		if not (node is Node):
			continue
		if (node as Node).get("hp") != null:
			return node as Node
	return null


func _discover_manager() -> Node:
	var parent := get_parent()
	if parent != null:
		if parent.get("time_left") != null:
			return parent
		for child in parent.get_children():
			if child == self:
				continue
			if not (child is Node):
				continue
			if (child as Node).get("time_left") != null:
				return child as Node
		var grand := parent.get_parent()
		if grand != null:
			for child in grand.get_children():
				if child == self:
					continue
				if not (child is Node):
					continue
				if (child as Node).get("time_left") != null:
					return child as Node
	return null


func _connect_soldier() -> void:
	if _soldier == null or not is_instance_valid(_soldier):
		return
	if _soldier.has_signal("died"):
		if not _soldier.is_connected("died", _on_soldier_died):
			_soldier.connect("died", _on_soldier_died)
	if _soldier.has_signal("respawned"):
		if not _soldier.is_connected("respawned", _on_soldier_respawned):
			_soldier.connect("respawned", _on_soldier_respawned)


func _on_soldier_died() -> void:
	var killer := _death_killer
	if _soldier != null and is_instance_valid(_soldier):
		var recorded: Variant = _soldier.get("last_killer")
		if recorded != null and str(recorded) != "":
			killer = str(recorded)
	_death_killer = killer
	refresh()


func _on_soldier_respawned() -> void:
	_death_killer = ""
	refresh()


func refresh() -> void:
	_refresh_hp()
	_refresh_ammo()
	_refresh_pips()
	_refresh_fuel()
	_refresh_timer()
	_refresh_score()
	_refresh_death()


func _refresh_hp() -> void:
	var bar := get_node_or_null("hp_bar") as ProgressBar
	if bar == null:
		return
	var hp := 100.0
	var max_hp := 100.0
	if _soldier != null and is_instance_valid(_soldier):
		var raw_hp: Variant = _soldier.get("hp")
		var raw_max: Variant = _soldier.get("max_hp")
		if raw_hp != null:
			hp = float(raw_hp)
		if raw_max != null and float(raw_max) > 0.0:
			max_hp = float(raw_max)
	bar.max_value = max_hp
	bar.value = hp


func _refresh_ammo() -> void:
	var label := get_node_or_null("ammo_label") as Label
	if label == null:
		return
	var ammo := -1
	var reserve := -1
	if _soldier != null and is_instance_valid(_soldier):
		var weapon := (_soldier as Node).get_node_or_null("Weapon")
		if weapon != null:
			var raw_ammo: Variant = weapon.get("ammo")
			var raw_reserve: Variant = weapon.get("reserve_left")
			if raw_ammo != null:
				ammo = int(raw_ammo)
			if raw_reserve != null:
				reserve = int(raw_reserve)
	if ammo < 0 or reserve < 0:
		label.text = "0 / 0"
	else:
		label.text = "%d / %d" % [ammo, reserve]


func _refresh_pips() -> void:
	var pips := get_node_or_null("grenade_pips") as BoxContainer
	if pips == null:
		return
	if _soldier == null or not is_instance_valid(_soldier):
		return
	var raw_count: Variant = _soldier.get("grenade_count")
	var raw_max: Variant = _soldier.get("grenade_max")
	if raw_count == null or raw_max == null:
		return
	var count := clampi(int(raw_count), 0, maxi(0, int(raw_max)))
	var total := maxi(0, int(raw_max))
	while pips.get_child_count() < total:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(14, 18)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips.add_child(pip)
	while pips.get_child_count() > total:
		var extra := pips.get_child(pips.get_child_count() - 1)
		pips.remove_child(extra)
		extra.queue_free()
	for i in pips.get_child_count():
		var rect := pips.get_child(i) as ColorRect
		if rect == null:
			continue
		rect.color = LIT_COLOR if i < count else DIM_COLOR


func _refresh_fuel() -> void:
	var bar := get_node_or_null("fuel_bar") as ProgressBar
	if bar == null:
		return
	var fuel := 100.0
	var fuel_max := 100.0
	if _soldier != null and is_instance_valid(_soldier):
		var raw_fuel: Variant = _soldier.get("fuel")
		var raw_max: Variant = _soldier.get("fuel_max")
		if raw_fuel != null:
			fuel = float(raw_fuel)
		if raw_max != null and float(raw_max) > 0.0:
			fuel_max = float(raw_max)
	bar.max_value = fuel_max
	bar.value = fuel


func _refresh_timer() -> void:
	var label := get_node_or_null("timer_label") as Label
	if label == null:
		return
	var seconds := _fallback_time
	if _manager != null and is_instance_valid(_manager):
		var raw: Variant = _manager.get("time_left")
		if raw != null:
			seconds = maxf(0.0, float(raw))
	label.text = _format_clock(seconds)


func _format_clock(seconds: float) -> String:
	var total := maxi(0, int(ceil(seconds)))
	return "%d:%02d" % [total / 60, total % 60]


func _refresh_score() -> void:
	var label := get_node_or_null("score_label") as Label
	if label == null:
		return
	var kills := 0
	var target := _fallback_target
	if _manager != null and is_instance_valid(_manager):
		var raw_target: Variant = _manager.get("target_score")
		if raw_target != null and int(raw_target) > 0:
			target = int(raw_target)
		kills = _manager_kills()
	label.text = "%d / %d" % [kills, target]


func _manager_kills() -> int:
	if _manager == null or not is_instance_valid(_manager):
		return 0
	for pid in ["soldier_0", "player", "player_0"]:
		if _manager.has_method("kills_for"):
			var kills: Variant = _manager.call("kills_for", pid)
			if kills != null and int(kills) > 0:
				return int(kills)
		if _manager.has_method("score_for"):
			var score: Variant = _manager.call("score_for", pid)
			if score != null and int(score) > 0:
				return int(score)
	return 0


func _refresh_death() -> void:
	var overlay := get_node_or_null("death_overlay") as Control
	var label := get_node_or_null("death_overlay/death_label") as Label
	if overlay == null:
		return
	var dead := false
	if _soldier != null and is_instance_valid(_soldier):
		var alive: Variant = _soldier.get("is_alive")
		if alive != null:
			dead = not bool(alive)
	overlay.visible = dead
	if not dead or label == null:
		return
	var killer := _death_killer
	if killer == "" and _soldier != null and is_instance_valid(_soldier):
		var recorded: Variant = _soldier.get("last_killer")
		if recorded != null and str(recorded) != "":
			killer = str(recorded)
	if killer == "":
		killer = "the arena"
	var seconds := 3.0
	if _soldier != null and is_instance_valid(_soldier):
		if _soldier.has_method("respawn_seconds_left"):
			seconds = maxf(0.0, float(_soldier.call("respawn_seconds_left")))
		else:
			var raw_ticks: Variant = _soldier.get("respawn_ticks_left")
			if raw_ticks != null:
				seconds = maxf(0.0, float(raw_ticks) / 60.0)
	label.text = "Killed by %s\nRespawning in %.1f" % [killer, seconds]


func _load_match_config(path: String = MATCH_CONFIG_PATH) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		push_warning("hud: missing %s, using compiled defaults" % MATCH_CONFIG_PATH)
		return
	_fallback_time = _cfg_float(cfg, "match", "time_limit_s", _fallback_time)
	_fallback_target = _cfg_int(cfg, "match", "target_score", _fallback_target)


static func _cfg_float(cfg: ConfigFile, section: String, key: String, fallback: float) -> float:
	var raw: Variant = cfg.get_value(section, key, fallback)
	if raw is float:
		if is_finite(raw):
			return raw
		push_warning("hud: invalid %s/%s, keeping default" % [section, key])
		return fallback
	if raw is int:
		return float(raw)
	push_warning("hud: invalid %s/%s, keeping default" % [section, key])
	return fallback


static func _cfg_int(cfg: ConfigFile, section: String, key: String, fallback: int) -> int:
	var raw: Variant = cfg.get_value(section, key, fallback)
	if raw is int:
		return raw
	push_warning("hud: invalid %s/%s, keeping default" % [section, key])
	return fallback
