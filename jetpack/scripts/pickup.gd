extends Area2D
## Generic arena pickup: ground crates and floating pads for weapons,
## health, and grenade/ammo restock. `kind` selects the effect; a `kind`
## naming a weapon id directly (e.g. "scatter") acts as that weapon crate.
## After `apply_to` the pad goes `disabled` for `respawn_s` seconds with a
## visible `TimerLabel` countdown, then re-enables. Tunables load from
## pickups.cfg over the exports.

const CONFIG_PATH := "res://resources/config/pickups.cfg"
const WEAPON_IDS := ["ranger_ar", "scatter", "longbow"]

@export var kind: String = "weapon"
@export var weapon_id := "scatter"
@export var respawn_s := 15.0
@export var floating := false
@export var heal_amount := 30.0

var disabled := false
var time_left := 0.0

var _bob_t := 0.0
var _pulse_t := 0.0
var _base_y := 0.0

@onready var _visual: Polygon2D = get_node_or_null("Visual") as Polygon2D
@onready var _label: Label = get_node_or_null("TimerLabel") as Label


func _ready() -> void:
	_load_config()
	add_to_group("pickup")
	_apply_kind_color()
	if _visual != null:
		_base_y = _visual.position.y
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func apply_to(body: Node) -> bool:
	if disabled:
		return false
	if body == null:
		return false
	var wid := effective_weapon_id()
	match kind:
		"health":
			if not body.has_method("heal"):
				return false
			if not Health.is_host_alive(body):
				return false
			var cur_hp = body.get("hp")
			var cur_max = body.get("max_hp")
			if cur_hp != null and cur_max != null and float(cur_hp) >= float(cur_max):
				return false
			body.call("heal", heal_amount)
			print("PICKUP health healed")
		"weapon":
			if not body.has_method("add_weapon"):
				return false
			if not bool(body.call("add_weapon", wid)):
				return false
			print("PICKUP weapon granted %s" % wid)
		"ammo":
			if not body.has_method("restock_ammo"):
				return false
			if not Health.is_host_alive(body):
				return false
			var pad_weapon := body.get_node_or_null("Weapon")
			if pad_weapon != null:
				var pad_stats = pad_weapon.get("stats")
				if pad_stats != null:
					var pad_ammo = pad_weapon.get("ammo")
					var pad_reserve = pad_weapon.get("reserve_left")
					if pad_ammo != null and pad_reserve != null and int(pad_ammo) >= int(pad_stats.get("mag_size")) and int(pad_reserve) >= int(pad_stats.get("reserve")):
						return false
			if not bool(body.call("restock_ammo")):
				return false
			print("PICKUP ammo restocked")
		"grenade":
			if not body.has_method("add_grenades"):
				return false
			if not Health.is_host_alive(body):
				return false
			var cur_nades = body.get("grenade_count")
			var cur_max = body.get("grenade_max")
			if cur_nades != null and cur_max != null and int(cur_nades) >= int(cur_max):
				return false
			body.call("add_grenades", 99)
			print("PICKUP grenades restocked")
		_:
			if wid != "":
				if not body.has_method("add_weapon"):
					return false
				if not bool(body.call("add_weapon", wid)):
					return false
				print("PICKUP weapon granted %s" % wid)
			else:
				return false
	_disable()
	return true


func effective_weapon_id() -> String:
	if kind == "weapon":
		return weapon_id
	if WEAPON_IDS.has(kind):
		return kind
	return ""


func _on_body_entered(body: Node2D) -> void:
	apply_to(body)


func _physics_process(delta: float) -> void:
	if not disabled:
		return
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_enable()


func _process(delta: float) -> void:
	_pulse_t += delta
	if _visual != null and floating and not disabled:
		_bob_t += delta
		_visual.position.y = _base_y + sin(_bob_t * 3.0) * 6.0
	if disabled:
		if _visual != null:
			var pulse := 0.3 + 0.1 * sin(_pulse_t * 6.0)
			_visual.modulate.a = pulse
		if _label != null:
			_label.text = "%d" % int(ceil(time_left))


func _disable() -> void:
	disabled = true
	time_left = respawn_s
	set_deferred("monitoring", false)
	if _visual != null:
		_visual.modulate.a = 0.3
	if _label != null:
		_label.text = "%d" % int(ceil(time_left))
	print("PICKUP disabled for %.1fs" % respawn_s)


func _enable() -> void:
	disabled = false
	time_left = 0.0
	set_deferred("monitoring", true)
	_apply_kind_color()
	if _label != null:
		_label.text = ""
	print("PICKUP respawned")


func _apply_kind_color() -> void:
	if _visual == null:
		return
	_visual.modulate.a = 1.0
	match kind:
		"health":
			_visual.color = Color(0.25, 1.0, 0.35, 1.0)
		"weapon":
			_visual.color = Color(1.0, 0.6, 0.15, 1.0)
		"ammo":
			_visual.color = Color(1.0, 0.9, 0.3, 1.0)
		"grenade":
			_visual.color = Color(1.0, 0.3, 0.25, 1.0)
		_:
			if WEAPON_IDS.has(kind):
				_visual.color = Color(1.0, 0.6, 0.15, 1.0)
			else:
				_visual.color = Color(0.3, 0.9, 0.4, 1.0)


func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		push_warning("pickup: missing %s, using export defaults" % CONFIG_PATH)
		return
	var section := kind
	if section == "weapon" or WEAPON_IDS.has(section):
		section = "weapon"
	# Config supplies defaults; an explicitly set export always wins so
	# placed instances (and headless probes) can tune one pad in isolation.
	if is_equal_approx(respawn_s, 15.0):
		respawn_s = _cfg_float(cfg, section, "respawn_s", respawn_s)
	if is_equal_approx(heal_amount, 30.0):
		heal_amount = _cfg_float(cfg, "health", "heal_amount", heal_amount)
	if weapon_id == "scatter":
		weapon_id = String(cfg.get_value("weapon", "weapon_id", weapon_id))


static func _cfg_float(cfg: ConfigFile, section: String, key: String, fallback: float) -> float:
	var raw: Variant = cfg.get_value(section, key, fallback)
	if raw is float:
		if is_finite(raw):
			return raw
		push_warning("pickup: invalid %s/%s, keeping default" % [section, key])
		return fallback
	if raw is int:
		return float(raw)
	push_warning("pickup: invalid %s/%s, keeping default" % [section, key])
	return fallback
