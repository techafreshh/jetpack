class_name MatchSetup
extends RefCounted
## Static match-setup handoff: the setup screen writes validated values here
## (and persists them to user://match_setup.cfg); MatchManager applies them
## at the end of _load_config. A static holder carries the choice across the
## scene change for free, without touching res:// config files or adding an
## autoload. Empty/negative sentinels mean "no override", so a clear holder
## is a no-op and compiled defaults hold. Guarded casts mirror
## match_manager.gd:_load_config so corrupt files fall back safely.

const SETUP_PATH := "user://match_setup.cfg"

static var difficulty: String = ""
static var target_score: int = -1
static var time_limit_s: float = -1.0


static func has_override() -> bool:
	return difficulty != "" or target_score > 0 or time_limit_s > 0.0


static func clear() -> void:
	difficulty = ""
	target_score = -1
	time_limit_s = -1.0


## Copies validated values onto the manager (duck-typed via set so there is
## no hard scene assumption). Invalid entries are skipped, never applied.
static func apply_to(manager: Node) -> void:
	if manager == null:
		return
	if difficulty.to_lower() in ["easy", "standard", "sharp"]:
		manager.set("difficulty", difficulty.to_lower())
	if target_score >= 1:
		manager.set("target_score", target_score)
	if time_limit_s > 0.0 and is_finite(time_limit_s):
		manager.set("time_limit_s", time_limit_s)


static func save_config(path: String = SETUP_PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("match", "difficulty", difficulty)
	cfg.set_value("match", "target_score", target_score)
	cfg.set_value("match", "time_limit_s", time_limit_s)
	if cfg.save(path) != OK:
		push_warning("matchsetup: failed to save %s" % path)


static func load_config(path: String = SETUP_PATH) -> void:
	clear()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	var raw_diff: Variant = cfg.get_value("match", "difficulty", "")
	if raw_diff is String and String(raw_diff).to_lower() in ["easy", "standard", "sharp"]:
		difficulty = String(raw_diff).to_lower()
	target_score = _cfg_int(cfg, "match", "target_score", -1)
	if target_score < 1:
		target_score = -1
	time_limit_s = _cfg_float(cfg, "match", "time_limit_s", -1.0)
	if not is_finite(time_limit_s) or time_limit_s <= 0.0:
		time_limit_s = -1.0


static func _cfg_float(cfg: ConfigFile, section: String, key: String, fallback: float) -> float:
	var raw: Variant = cfg.get_value(section, key, fallback)
	if raw is float:
		if is_finite(raw):
			return raw
		push_warning("matchsetup: invalid %s/%s, keeping default" % [section, key])
		return fallback
	if raw is int:
		return float(raw)
	push_warning("matchsetup: invalid %s/%s, keeping default" % [section, key])
	return fallback


static func _cfg_int(cfg: ConfigFile, section: String, key: String, fallback: int) -> int:
	var raw: Variant = cfg.get_value(section, key, fallback)
	if raw is int:
		return raw
	push_warning("matchsetup: invalid %s/%s, keeping default" % [section, key])
	return fallback
