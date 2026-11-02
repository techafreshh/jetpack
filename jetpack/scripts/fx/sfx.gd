class_name Sfx
extends Node
## Pooled one-shot SFX player on the `sfx` group: sim code fires
## get_tree().call_group("sfx", "play_sfx", name) with no direct reference.
## Buses SFX/UI are created at runtime by ensure_buses (static, callable
## with no Sfx node in the tree); ui_* names route to UI, the rest to SFX.
## Pool exhaustion drops the sound instead of erroring.

const BUS_SFX := "SFX"
const BUS_UI := "UI"
const POOL_SIZE := 8
const SOUND_FILES := {
	"ar_shot": "res://assets/audio/ar_shot.wav",
	"scatter_shot": "res://assets/audio/scatter_shot.wav",
	"longbow_shot": "res://assets/audio/longbow_shot.wav",
	"explosion": "res://assets/audio/explosion.wav",
	"hit": "res://assets/audio/hit.wav",
	"pickup": "res://assets/audio/pickup.wav",
	"reload": "res://assets/audio/reload.wav",
	"ui_click": "res://assets/audio/ui_click.wav",
	"grenade_beep": "res://assets/audio/grenade_beep.wav",
}

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	add_to_group("sfx")
	Sfx.ensure_buses()
	_build_pool()
	_load_streams()


func play_sfx(sfx_name: String) -> void:
	if sfx_name == "":
		return
	if _players.is_empty():
		return
	if not _streams.has(sfx_name):
		return
	var stream: AudioStream = _streams[sfx_name]
	if stream == null:
		return
	var player := _idle_player()
	if player == null:
		return
	player.stream = stream
	player.bus = BUS_UI if sfx_name.begins_with("ui_") else BUS_SFX
	player.play()


static func ensure_buses() -> void:
	for bus in [BUS_SFX, BUS_UI]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
		var idx := AudioServer.get_bus_index(bus)
		if idx > 0:
			AudioServer.set_bus_send(idx, "Master")


static func set_bus_volume01(bus: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1:
		return
	var vol := 1.0
	if is_finite(v):
		vol = clampf(v, 0.0, 1.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(vol, 0.0001)))


static func get_bus_volume01(bus: String) -> float:
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1:
		return 0.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(idx)), 0.0, 1.0)


func _build_pool() -> void:
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "Voice%d" % i
		add_child(player)
		_players.append(player)


func _load_streams() -> void:
	for sfx_name in SOUND_FILES:
		var path := String(SOUND_FILES[sfx_name])
		if ResourceLoader.exists(path):
			_streams[sfx_name] = load(path)


func _idle_player() -> AudioStreamPlayer:
	for player in _players:
		if is_instance_valid(player) and not player.playing:
			return player
	return null
