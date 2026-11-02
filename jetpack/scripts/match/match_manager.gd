class_name MatchManager
extends Node
## Tick-driven FFA session: countdown -> live (first to target_score, or best
## score when the 5:00 clock expires) -> results. A tied clock expiry latches
## sudden_death and extends the live clock by exactly sudden_death_s; any kill
## during sudden death wins at once. Kills arrive via register_kill; soldiers
## seated by seat_bots feed unattributed deaths through died signals. One
## physics tick is 1/60s; all durations derive from the 60 Hz tick.

signal state_changed(new_state: String)
signal match_ended(winner: String)

const CONFIG_PATH := "res://resources/config/match.cfg"
const SOLDIER_SCENE := "res://scenes/soldier.tscn"
const BOT_PILOT_SCRIPT := "res://scripts/pilots/bot_pilot.gd"
const STATE_COUNTDOWN := "countdown"
const STATE_LIVE := "live"
const STATE_RESULTS := "results"

## Override before adding to the tree to load a different cfg in probes.
var config_path: String = CONFIG_PATH
var match_state: String = STATE_COUNTDOWN
var winner_id: String = ""
var sudden_death: bool = false
var target_score: int = 25
var time_limit_s: float = 300.0
var sudden_death_s: float = 30.0
var countdown_s: float = 3.0
var countdown_left: float = 3.0
var time_left: float = 300.0
var duration: float = 0.0
var difficulty: String = "standard"
var bot_count: int = 8
## Seat bots from _ready when true; false keeps scene-embedded use inert.
var auto_seat: bool = false
var scoreboard: Scoreboard
var match_results: Dictionary:
	get:
		return get_match_results()

var _bots: Dictionary = {}
var _seated: bool = false


func _ready() -> void:
	if scoreboard == null:
		scoreboard = Scoreboard.new()
	_load_config()
	time_left = time_limit_s
	countdown_left = countdown_s
	duration = 0.0
	match_state = STATE_COUNTDOWN
	winner_id = ""
	sudden_death = false
	if auto_seat:
		seat_bots()


func _physics_process(delta: float) -> void:
	if match_state == STATE_COUNTDOWN:
		countdown_left -= delta
		if countdown_left <= 0.0:
			countdown_left = 0.0
			_enter_live()
	elif match_state == STATE_LIVE:
		duration += delta
		time_left -= delta
		if time_left <= 0.0:
			time_left = 0.0
			_on_clock_expired()


func register_kill(killer_id: String, victim_id: String) -> void:
	# Frozen once results are up: seated bots keep dying via died signals
	# while the results screen shows, and those must not drift the table.
	if match_state == STATE_RESULTS:
		return
	if scoreboard == null:
		scoreboard = Scoreboard.new()
	var killer := killer_id.strip_edges()
	scoreboard.register_kill(killer_id, victim_id)
	# A target-score hit ends the match on the same tick, from countdown or
	# live, so the sub-60-tick gate holds however the probe drives the clock.
	if sudden_death:
		if killer == "":
			_finish(scoreboard.leader_id())
		else:
			_finish(killer)
		return
	if killer != "" and scoreboard.kills_for(killer) >= target_score:
		_finish(scoreboard.leader_id())


func record_death(victim_id: String) -> void:
	if match_state == STATE_RESULTS:
		return
	if scoreboard == null:
		scoreboard = Scoreboard.new()
	scoreboard.record_death(victim_id)


func ensure_participant(participant_id: String) -> bool:
	if scoreboard == null:
		scoreboard = Scoreboard.new()
	return scoreboard.ensure(participant_id)


func entry(participant_id: String) -> Dictionary:
	if scoreboard == null:
		scoreboard = Scoreboard.new()
	return scoreboard.entry(participant_id)


func kills_for(participant_id: String) -> int:
	if scoreboard == null:
		return 0
	return scoreboard.kills_for(participant_id)


func score_for(participant_id: String) -> int:
	if scoreboard == null:
		return 0
	return scoreboard.score_for(participant_id)


func get_standings() -> Array:
	if scoreboard == null:
		return []
	return scoreboard.standings()


func get_match_results() -> Dictionary:
	var wid := winner_id
	if wid == "":
		var table := get_standings()
		wid = String(table[0]) if not table.is_empty() else ""
	var row := {"kills": 0, "deaths": 0, "score": 0}
	if wid != "":
		row = entry(wid)
	return {
		"kills": int(row["kills"]),
		"deaths": int(row["deaths"]),
		"score": int(row["score"]),
		"duration": duration,
		"difficulty": difficulty,
	}


func rematch() -> void:
	if scoreboard == null:
		scoreboard = Scoreboard.new()
	scoreboard.reset()
	winner_id = ""
	sudden_death = false
	duration = 0.0
	time_left = time_limit_s
	countdown_left = countdown_s
	match_state = STATE_COUNTDOWN
	_reposition_bots()
	state_changed.emit(match_state)
	print("MATCH REMATCH")


## Seats bot_count soldiers at spawn points (spawner group, else Spawn*
## markers, else compiled fallback). Soldiers are repositioned, never freed,
## on rematch. Returns the seated participant count.
func seat_bots() -> int:
	if scoreboard == null:
		scoreboard = Scoreboard.new()
	if _seated:
		return _bots.size()
	_seated = true
	var points := _resolve_spawn_points()
	var packed: PackedScene = null
	if ResourceLoader.exists(SOLDIER_SCENE):
		packed = load(SOLDIER_SCENE) as PackedScene
	for i in bot_count:
		var pid := "bot_%d" % i
		ensure_participant(pid)
		if packed == null:
			continue
		var bot := packed.instantiate() as CharacterBody2D
		bot.name = "Bot%d" % i
		add_child(bot)
		if points.size() > 0:
			bot.global_position = points[i % points.size()]
		bot.set("velocity", Vector2.ZERO)
		if ResourceLoader.exists(BOT_PILOT_SCRIPT) and bot.has_method("set_pilot"):
			var pilot = load(BOT_PILOT_SCRIPT).new(difficulty)
			bot.call("set_pilot", pilot)
		_bots[pid] = bot
		if not bot.is_connected("died", _on_seated_died):
			bot.connect("died", _on_seated_died.bind(pid))
	return _bots.size()


func _enter_live() -> void:
	if match_state != STATE_COUNTDOWN:
		return
	match_state = STATE_LIVE
	state_changed.emit(match_state)
	print("MATCH LIVE")


func _on_clock_expired() -> void:
	if match_state != STATE_LIVE:
		return
	if sudden_death:
		_finish(scoreboard.leader_id())
		return
	if scoreboard.has_unique_leader():
		_finish(scoreboard.leader_id())
	else:
		_enter_sudden_death()


func _enter_sudden_death() -> void:
	sudden_death = true
	time_left = sudden_death_s
	print("MATCH SUDDEN DEATH +%.1fs" % sudden_death_s)


func _finish(winner: String) -> void:
	if match_state == STATE_RESULTS:
		return
	winner_id = winner
	match_state = STATE_RESULTS
	state_changed.emit(match_state)
	match_ended.emit(winner_id)
	print("MATCH ENDED winner=%s" % winner_id)


func _on_seated_died(participant_id: String) -> void:
	record_death(participant_id)


func _reposition_bots() -> void:
	if _bots.is_empty():
		return
	var points := _resolve_spawn_points()
	var idx := 0
	for pid in _bots:
		var bot: Object = _bots[pid]
		if bot == null or not is_instance_valid(bot):
			continue
		var alive: Variant = (bot as Object).get("is_alive")
		if alive != null and not bool(alive):
			# Leave dead bots alone to respawn naturally: soldier._respawn
			# repairs collision layers, the damageable group, and timers,
			# which a manual is_alive=true here would bypass (ghost bot).
			idx += 1
			continue
		if bot is Node2D and points.size() > 0:
			(bot as Node2D).global_position = points[idx % points.size()]
		if (bot as Object).get("velocity") != null:
			(bot as Node).set("velocity", Vector2.ZERO)
		var max_hp: Variant = (bot as Object).get("max_hp")
		if max_hp != null and (bot as Object).get("hp") != null:
			(bot as Node).set("hp", float(max_hp))
		idx += 1


func _resolve_spawn_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	if get_tree() != null:
		var spawner: Node = get_tree().get_first_node_in_group("spawner")
		if spawner != null and spawner.has_method("spawn_points"):
			var pts: Array = spawner.call("spawn_points")
			for p in pts:
				out.append(p as Vector2)
			if not out.is_empty():
				return out
	var scope: Node = get_parent() if get_parent() != null else self
	for n in scope.find_children("Spawn*", "Marker2D", true, false):
		out.append((n as Node2D).global_position)
	if not out.is_empty():
		return out
	return [Vector2(200, 300), Vector2(1500, 300), Vector2(600, 300), Vector2(1100, 300)]


func _load_config(path: String = "") -> void:
	var use_path := path if path != "" else config_path
	var cfg := ConfigFile.new()
	if cfg.load(use_path) != OK:
		push_warning("matchmanager: missing %s, using compiled defaults" % use_path)
		return
	target_score = _cfg_int(cfg, "match", "target_score", target_score)
	if target_score < 1:
		push_warning("matchmanager: invalid match/target_score, keeping default")
		target_score = 25
	time_limit_s = _cfg_float(cfg, "match", "time_limit_s", time_limit_s)
	if not is_finite(time_limit_s) or time_limit_s <= 0.0:
		push_warning("matchmanager: invalid match/time_limit_s, keeping default")
		time_limit_s = 300.0
	sudden_death_s = _cfg_float(cfg, "match", "sudden_death_s", sudden_death_s)
	if not is_finite(sudden_death_s) or sudden_death_s <= 0.0:
		push_warning("matchmanager: invalid match/sudden_death_s, keeping default")
		sudden_death_s = 30.0
	countdown_s = _cfg_float(cfg, "match", "countdown_s", countdown_s)
	if not is_finite(countdown_s) or countdown_s < 0.0:
		push_warning("matchmanager: invalid match/countdown_s, keeping default")
		countdown_s = 3.0
	bot_count = _cfg_int(cfg, "match", "bot_count", bot_count)
	if bot_count < 0:
		push_warning("matchmanager: invalid match/bot_count, keeping default")
		bot_count = 8
	var raw_diff: Variant = cfg.get_value("match", "difficulty", difficulty)
	if raw_diff is String and String(raw_diff).to_lower() in ["easy", "standard", "sharp"]:
		difficulty = String(raw_diff).to_lower()
	else:
		push_warning("matchmanager: invalid match/difficulty, keeping default")


static func _cfg_float(cfg: ConfigFile, section: String, key: String, fallback: float) -> float:
	var raw: Variant = cfg.get_value(section, key, fallback)
	if raw is float:
		if is_finite(raw):
			return raw
		push_warning("matchmanager: invalid %s/%s, keeping default" % [section, key])
		return fallback
	if raw is int:
		return float(raw)
	push_warning("matchmanager: invalid %s/%s, keeping default" % [section, key])
	return fallback


static func _cfg_int(cfg: ConfigFile, section: String, key: String, fallback: int) -> int:
	var raw: Variant = cfg.get_value(section, key, fallback)
	if raw is int:
		return raw
	push_warning("matchmanager: invalid %s/%s, keeping default" % [section, key])
	return fallback
