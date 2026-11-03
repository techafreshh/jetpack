class_name CameraShake
extends Camera2D
## Presentation-only trauma shake: add_shake/add_trauma bank trauma and set
## offset and roll synchronously so probes see offset.length() > 0 and a
## trauma-squared random rotation on the very next frame, then trauma decays
## in _process. Output is trauma^2-scaled and gated by the accessibility
## shake slider (zero scale silences offset and roll). Tunables load from
## fx.cfg over the exports. Joins group camera_shake on ready so weapons
## and explosions find it duck-typed.

const CONFIG_PATH := "res://resources/config/fx.cfg"

var trauma := 0.0
var trauma_add := 0.35
var max_offset := 14.0
## Peak roll in radians at full trauma.
var max_roll := 0.02
var decay := 2.2


func _ready() -> void:
	add_to_group("camera_shake")
	_load_config()


func add_shake(amount := -1.0) -> void:
	var add := trauma_add if amount < 0.0 else amount
	if not is_finite(add):
		return
	trauma = minf(1.0, trauma + add)
	_apply_offset()


## Accessibility seam: the explosion kick feeds trauma through this alias,
## clamped to 0..1 and applied synchronously like add_shake.
func add_trauma(amount: float) -> void:
	if not is_finite(amount):
		return
	trauma = clampf(trauma + amount, 0.0, 1.0)
	_apply_offset()


func _process(delta: float) -> void:
	if trauma <= 0.0:
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
		if rotation != 0.0:
			rotation = 0.0
		return
	trauma = maxf(0.0, trauma - decay * delta)
	_apply_offset()


func _apply_offset() -> void:
	if trauma <= 0.0:
		offset = Vector2.ZERO
		rotation = 0.0
		return
	var mag := trauma * trauma * max_offset * Accessibility.shake_scale(self)
	if mag <= 0.0:
		offset = Vector2.ZERO
		rotation = 0.0
		return
	var ang := randf() * TAU
	offset = Vector2(cos(ang), sin(ang)) * mag
	rotation = (randf() * 2.0 - 1.0) * trauma * trauma * max_roll * Accessibility.shake_scale(self)


func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		push_warning("camerashake: missing %s, using export defaults" % CONFIG_PATH)
		return
	trauma_add = _cfg_float(cfg, "shake", "trauma_add", trauma_add)
	max_offset = _cfg_float(cfg, "shake", "max_offset", max_offset)
	max_roll = _cfg_float(cfg, "shake", "max_roll", max_roll)
	decay = _cfg_float(cfg, "shake", "decay", decay)


static func _cfg_float(cfg: ConfigFile, section: String, key: String, fallback: float) -> float:
	var raw: Variant = cfg.get_value(section, key, fallback)
	if raw is float:
		if is_finite(raw):
			return raw
		push_warning("camerashake: invalid %s/%s, keeping default" % [section, key])
		return fallback
	if raw is int:
		return float(raw)
	push_warning("camerashake: invalid %s/%s, keeping default" % [section, key])
	return fallback
