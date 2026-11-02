extends Node
## Audio autoload: ensures Music/SFX buses exist and applies Settings volumes
## to Master/Music/SFX via AudioServer. Fully guarded when Settings is absent
## (1.0 fallbacks, no crash) and follows Settings.volumes_changed live.

const FALLBACK_VOLUME := 1.0


func _ready() -> void:
	_ensure_buses()
	apply_volumes()
	var settings := get_node_or_null("/root/Settings")
	if settings != null and settings.has_signal("volumes_changed"):
		if not settings.is_connected("volumes_changed", apply_volumes):
			settings.connect("volumes_changed", apply_volumes)


func apply_volumes() -> void:
	var master := FALLBACK_VOLUME
	var music := FALLBACK_VOLUME
	var sfx := FALLBACK_VOLUME
	var settings := get_node_or_null("/root/Settings")
	if settings != null:
		if settings.get("master_volume") != null:
			master = float(settings.get("master_volume"))
		if settings.get("music_volume") != null:
			music = float(settings.get("music_volume"))
		if settings.get("sfx_volume") != null:
			sfx = float(settings.get("sfx_volume"))
	_apply_bus("Master", master)
	_apply_bus("Music", music)
	_apply_bus("SFX", sfx)


func _ensure_buses() -> void:
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
		var idx := AudioServer.get_bus_index(bus)
		if idx > 0:
			AudioServer.set_bus_send(idx, "Master")


func _apply_bus(bus: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1:
		return
	var vol := FALLBACK_VOLUME
	if is_finite(v):
		vol = clampf(v, 0.0, 1.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(vol, 0.0001)))
