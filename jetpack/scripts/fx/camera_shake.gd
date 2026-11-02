class_name CameraShake
extends Camera2D
## Presentation-only trauma shake: add_shake sets offset synchronously so
## probes see offset.length() > 0 on the very next frame, then trauma
## decays in _process. Tunables load from fx.cfg over the exports.

const CONFIG_PATH := "res://resources/config/fx.cfg"

var trauma := 0.0
var trauma_add := 0.35
var max_offset := 14.0
var decay := 2.2


func _ready() -> void:
	add_to_group("camera_shake")
	_load_config()


func add_shake(amount := -1.0) -> void:
	var add := trauma_add if amount < 0.0 else amount
	trauma = minf(1.0, trauma + add)
	_apply_offset()


func _process(delta: float) -> void:
	if trauma <= 0.0:
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
		return
	trauma = maxf(0.0, trauma - decay * delta)
	_apply_offset()


func _apply_offset() -> void:
	if trauma <= 0.0:
		offset = Vector2.ZERO
		return
	var mag := trauma * trauma * max_offset
	var ang := randf() * TAU
	offset = Vector2(cos(ang), sin(ang)) * mag


func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		push_warning("camerashake: missing %s, using export defaults" % CONFIG_PATH)
		return
	trauma_add = _cfg_float(cfg, "shake", "trauma_add", trauma_add)
	max_offset = _cfg_float(cfg, "shake", "max_offset", max_offset)
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
