extends Node
## Settings autoload: owns user://settings.cfg (ConfigFile) with validation
## plus InputMap application. Volumes clamp to 0.0-1.0, keybinds persist as
## human-readable strings via OS.get_keycode_string, toggles live under
## [accessibility]. A corrupt file resets to defaults and is rewritten, and
## per-key invalid values fall back to defaults with a normalizing save, so
## every boot ends with a valid file. settings_path is an injectable override
## (mirrors MatchManager.config_path) so probes use user:// temp copies.

signal volumes_changed
signal keybinds_changed
signal toggles_changed

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_MASTER := 1.0
const DEFAULT_MUSIC := 1.0
const DEFAULT_SFX := 1.0
const DEFAULT_SHAKE := 1.0
const DEFAULT_BINDS := {
	"move_left": ["A", "Left"],
	"move_right": ["D", "Right"],
	"crouch": ["S", "Down"],
	"fly": ["Space", "W", "Up"],
	"throw_grenade": ["G"],
	"reload": ["R"],
}
const DEFAULT_TOGGLES := {
	"colorblind_mode": false,
	"reduced_flashing": false,
	"aim_assist": false,
}
const REMAPPABLE_ACTIONS := ["move_left", "move_right", "crouch", "fly", "throw_grenade", "reload"]
const KNOWN_KEYS: Array = [
	KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F, KEY_G, KEY_H, KEY_I, KEY_J,
	KEY_K, KEY_L, KEY_M, KEY_N, KEY_O, KEY_P, KEY_Q, KEY_R, KEY_S, KEY_T,
	KEY_U, KEY_V, KEY_W, KEY_X, KEY_Y, KEY_Z,
	KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9,
	KEY_SPACE, KEY_ENTER, KEY_TAB, KEY_ESCAPE, KEY_BACKSPACE, KEY_DELETE,
	KEY_INSERT, KEY_HOME, KEY_END, KEY_PAGEUP, KEY_PAGEDOWN,
	KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN,
	KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6,
	KEY_F7, KEY_F8, KEY_F9, KEY_F10, KEY_F11, KEY_F12,
	KEY_MINUS, KEY_EQUAL, KEY_BRACKETLEFT, KEY_BRACKETRIGHT, KEY_BACKSLASH,
	KEY_SEMICOLON, KEY_APOSTROPHE, KEY_COMMA, KEY_PERIOD, KEY_SLASH, KEY_QUOTELEFT,
	KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META,
]

## Override before adding to the tree to load a different cfg in probes.
var settings_path: String = SETTINGS_PATH
var master_volume := DEFAULT_MASTER
var music_volume := DEFAULT_MUSIC
var sfx_volume := DEFAULT_SFX
var screen_shake := DEFAULT_SHAKE
var _binds: Dictionary = {}
var _toggles: Dictionary = {}


func _ready() -> void:
	load_settings()


## Loads from path (or settings_path when empty); an explicit path becomes
## the new settings_path so later setter autosaves stay on the same file.
func load_settings(path: String = "") -> void:
	var use_path := path if path != "" else settings_path
	if path != "":
		settings_path = path
	var cfg := ConfigFile.new()
	if cfg.load(use_path) != OK:
		push_warning("settings: missing %s, using compiled defaults" % use_path)
		_assign_defaults()
		apply_keybinds()
		save_settings()
		return
	master_volume = _cfg_volume(cfg, "audio", "master_volume", DEFAULT_MASTER)
	music_volume = _cfg_volume(cfg, "audio", "music_volume", DEFAULT_MUSIC)
	sfx_volume = _cfg_volume(cfg, "audio", "sfx_volume", DEFAULT_SFX)
	screen_shake = _cfg_shake(cfg, "accessibility", "screen_shake", DEFAULT_SHAKE)
	for action in DEFAULT_BINDS:
		_binds[action] = _cfg_bind(cfg, String(action), _default_bind(String(action)))
	for toggle in DEFAULT_TOGGLES:
		_toggles[toggle] = _cfg_toggle(cfg, "accessibility", String(toggle), bool(DEFAULT_TOGGLES[toggle]))
	apply_keybinds()
	save_settings()


func save_settings(path: String = "") -> void:
	var use_path := path if path != "" else settings_path
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("accessibility", "screen_shake", screen_shake)
	for action in DEFAULT_BINDS:
		var names: PackedStringArray = _binds.get(action, _default_bind(String(action)))
		cfg.set_value("input", String(action), ", ".join(names))
	for toggle in DEFAULT_TOGGLES:
		cfg.set_value("accessibility", String(toggle), _toggles.get(toggle, DEFAULT_TOGGLES[toggle]))
	if cfg.save(use_path) != OK:
		push_warning("settings: failed to save %s" % use_path)


func reset_to_defaults() -> void:
	_assign_defaults()
	apply_keybinds()
	volumes_changed.emit()
	keybinds_changed.emit()
	toggles_changed.emit()
	save_settings()


func set_master_volume(v: float) -> void:
	master_volume = _sanitize_volume(v, DEFAULT_MASTER)
	volumes_changed.emit()
	save_settings()


func set_music_volume(v: float) -> void:
	music_volume = _sanitize_volume(v, DEFAULT_MUSIC)
	volumes_changed.emit()
	save_settings()


func set_sfx_volume(v: float) -> void:
	sfx_volume = _sanitize_volume(v, DEFAULT_SFX)
	volumes_changed.emit()
	save_settings()


func get_master_volume() -> float:
	return master_volume


func get_music_volume() -> float:
	return music_volume


func get_sfx_volume() -> float:
	return sfx_volume


func set_screen_shake(v: float) -> void:
	screen_shake = _sanitize_shake(v, DEFAULT_SHAKE)
	toggles_changed.emit()
	save_settings()


func get_screen_shake() -> float:
	return screen_shake


## Single-key remap: replaces the action's list, applies to InputMap at once.
func set_keybind(action: String, keycode: Key) -> void:
	if not DEFAULT_BINDS.has(action):
		push_warning("settings: unknown remappable action %s" % action)
		return
	if keycode == KEY_NONE or keycode_to_string(keycode).is_empty():
		push_warning("settings: invalid keycode for %s, keeping default" % action)
		return
	_binds[action] = PackedStringArray([keycode_to_string(keycode)])
	_apply_action_to_inputmap(StringName(action))
	keybinds_changed.emit()
	save_settings()


func get_keybind_string(action: String) -> String:
	var names: PackedStringArray = _binds.get(action, _default_bind(action))
	return ", ".join(names)


func get_keybinds(action: String) -> PackedStringArray:
	var names: PackedStringArray = _binds.get(action, _default_bind(action))
	return names.duplicate()


func set_toggle(toggle: String, enabled: bool) -> void:
	if not DEFAULT_TOGGLES.has(toggle):
		push_warning("settings: unknown toggle %s" % toggle)
		return
	_toggles[toggle] = enabled
	toggles_changed.emit()
	save_settings()


func get_toggle(toggle: String) -> bool:
	return bool(_toggles.get(toggle, DEFAULT_TOGGLES.get(toggle, false)))


func apply_keybinds() -> void:
	for action in _binds:
		_apply_action_to_inputmap(StringName(action))


static func keycode_to_string(keycode: Key) -> String:
	return OS.get_keycode_string(keycode)


## Reverse lookup through the same forward function: unknown names yield
## KEY_NONE and the caller falls back to the compiled default.
static func string_to_keycode(key_name: String) -> Key:
	var trimmed := key_name.strip_edges()
	if trimmed.is_empty():
		return KEY_NONE
	for candidate in KNOWN_KEYS:
		if OS.get_keycode_string(candidate) == trimmed:
			return candidate
	return KEY_NONE


func _assign_defaults() -> void:
	master_volume = DEFAULT_MASTER
	music_volume = DEFAULT_MUSIC
	sfx_volume = DEFAULT_SFX
	screen_shake = DEFAULT_SHAKE
	_binds.clear()
	for action in DEFAULT_BINDS:
		_binds[action] = _default_bind(String(action))
	_toggles.clear()
	for toggle in DEFAULT_TOGGLES:
		_toggles[toggle] = DEFAULT_TOGGLES[toggle]


func _apply_action_to_inputmap(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	var names: PackedStringArray = _binds.get(String(action), PackedStringArray())
	for key_name in names:
		var kc := string_to_keycode(key_name)
		if kc == KEY_NONE:
			continue
		var ev := InputEventKey.new()
		ev.physical_keycode = kc
		InputMap.action_add_event(action, ev)


static func _default_bind(action: String) -> PackedStringArray:
	if not DEFAULT_BINDS.has(action):
		return PackedStringArray()
	return PackedStringArray(DEFAULT_BINDS[action])


static func _sanitize_volume(v: float, fallback: float) -> float:
	if not is_finite(v):
		push_warning("settings: invalid volume, keeping default")
		return fallback
	return clampf(v, 0.0, 1.0)


static func _sanitize_shake(v: float, fallback: float) -> float:
	if not is_finite(v):
		push_warning("settings: invalid screen_shake, keeping default")
		return fallback
	return clampf(v, 0.0, 1.0)


static func _cfg_volume(cfg: ConfigFile, section: String, key: String, fallback: float) -> float:
	var raw: Variant = cfg.get_value(section, key, fallback)
	if raw is float:
		if is_finite(raw):
			return clampf(raw, 0.0, 1.0)
		push_warning("settings: invalid %s/%s, keeping default" % [section, key])
		return fallback
	if raw is int:
		return clampf(float(raw), 0.0, 1.0)
	push_warning("settings: invalid %s/%s, keeping default" % [section, key])
	return fallback


static func _cfg_shake(cfg: ConfigFile, section: String, key: String, fallback: float) -> float:
	var raw: Variant = cfg.get_value(section, key, fallback)
	if raw is float:
		if is_finite(raw):
			return clampf(raw, 0.0, 1.0)
		push_warning("settings: invalid %s/%s, keeping default" % [section, key])
		return fallback
	if raw is int:
		return clampf(float(raw), 0.0, 1.0)
	push_warning("settings: invalid %s/%s, keeping default" % [section, key])
	return fallback


static func _cfg_toggle(cfg: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	var raw: Variant = cfg.get_value(section, key, fallback)
	if raw is bool:
		return raw
	push_warning("settings: invalid %s/%s, keeping default" % [section, key])
	return fallback


static func _cfg_bind(cfg: ConfigFile, action: String, fallback: PackedStringArray) -> PackedStringArray:
	var raw: Variant = cfg.get_value("input", action, fallback)
	var names: Array = []
	if raw is String:
		names = raw.split(",")
	elif raw is PackedStringArray:
		names = Array(raw)
	elif raw is Array:
		names = raw
	else:
		push_warning("settings: invalid input/%s, keeping default" % action)
		return fallback.duplicate()
	var out := PackedStringArray()
	for entry in names:
		var s := str(entry).strip_edges()
		if s.is_empty():
			continue
		if string_to_keycode(s) == KEY_NONE:
			continue
		out.append(s)
	if out.is_empty():
		push_warning("settings: invalid input/%s, keeping default" % action)
		return fallback.duplicate()
	return out
