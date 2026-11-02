class_name HitStop
extends RefCounted
## Fire-and-forget hit-stop: dips Engine.time_scale for a real-time window,
## then restores 1.0. Static so any sim call site (dummy, soldier,
## explosion) can trigger it with no FX nodes in the tree. Re-entry while
## a stop is running returns immediately; the hold clamps to 40-80 ms.

const CONFIG_PATH := "res://resources/config/fx.cfg"
const MIN_HOLD_MS := 40.0
const MAX_HOLD_MS := 80.0

static var _active := false


static func trigger(tree: SceneTree) -> void:
	if _active:
		return
	if tree == null:
		return
	_active = true
	var scale := _cfg_scale()
	var hold_s := _cfg_hold_s()
	Engine.time_scale = scale
	await tree.create_timer(hold_s, true, false, true).timeout
	Engine.time_scale = 1.0
	_active = false


static func _cfg_scale() -> float:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return 0.2
	var raw: Variant = cfg.get_value("hitstop", "scale", 0.2)
	if raw is float or raw is int:
		var v := float(raw)
		if is_finite(v):
			return clampf(v, 0.0, 0.3)
	push_warning("hitstop: invalid hitstop/scale, keeping default")
	return 0.2


static func _cfg_hold_s() -> float:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return 0.06
	var raw: Variant = cfg.get_value("hitstop", "hold_ms", 60.0)
	if raw is float or raw is int:
		var ms := float(raw)
		if is_finite(ms):
			if ms < MIN_HOLD_MS or ms > MAX_HOLD_MS:
				push_warning("hitstop: invalid hitstop/hold_ms %f, clamped to 40-80" % ms)
			return clampf(ms, MIN_HOLD_MS, MAX_HOLD_MS) / 1000.0
	push_warning("hitstop: invalid hitstop/hold_ms, keeping default")
	return 0.06
