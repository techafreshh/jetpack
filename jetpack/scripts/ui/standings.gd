class_name Standings
extends Control
## Live 8-combatant FFA table plus the last-4 kill feed and the `You N / 25`
## HUD standings line. Thin tree widget over a plain score dictionary (the
## Scoreboard self-kill rule: own-goal deaths never score) owning one
## KillFeed. Score target loads from match.cfg over compiled defaults via the
## soldier guarded-cast idiom; every node access is get_node_or_null guarded
## so a bare Standings.new() never errors. Optional manager polling is
## read-only duck-typing (get_standings/score_for/target_score): no manager
## means the static table stands. Crash-free with no Rows/HudLine/Feed.

const CONFIG_PATH := "res://resources/config/match.cfg"
const TARGET_DEFAULT := 25
const LOCAL_DEFAULT := "You"

var local_id := LOCAL_DEFAULT
var target_score := TARGET_DEFAULT
var feed: KillFeed
## Probe-readable feed size; delegates to the owned KillFeed.
var feed_count: int:
	get:
		_ensure_feed()
		return feed.feed_count

var _table: Dictionary = {}
## Fingerprint of the last actually-rendered tree; steady-state physics
## ticks match it and touch nothing (bot_pilot _last_hp latch idiom).
var _last_render: String = ""


func _init() -> void:
	_ensure_feed()


func _ready() -> void:
	_load_config()
	_ensure_feed()
	_refresh()


func _physics_process(_delta: float) -> void:
	var mgr := _find_manager()
	if mgr != null:
		_poll_manager(mgr)
	_refresh()


func set_scores(scores: Dictionary, local: String = "") -> void:
	if local != "":
		local_id = local.strip_edges() if local.strip_edges() != "" else local_id
	_table.clear()
	for pid in scores:
		var name := str(pid).strip_edges()
		if name == "":
			continue
		_table[name] = _coerce_row(scores[pid])
	_refresh()


func set_entry(participant: String, score: int, kills: int = 0, deaths: int = 0) -> void:
	var pid := participant.strip_edges()
	if pid == "":
		return
	_table[pid] = {"score": score, "kills": kills, "deaths": deaths}
	_refresh()


func set_local_id(id: String) -> void:
	var pid := id.strip_edges()
	if pid == "":
		return
	local_id = pid
	_refresh()


func clear() -> void:
	_table.clear()
	_ensure_feed()
	feed.clear()
	_refresh()


func push_kill(killer: String, victim: String, weapon: String = "") -> void:
	_ensure_feed()
	feed.push_kill(killer, victim, weapon)
	var k := killer.strip_edges()
	var v := victim.strip_edges()
	if v != "" and not _table.has(v):
		_table[v] = {"score": 0, "kills": 0, "deaths": 0}
	if k != "" and k != v and not _table.has(k):
		_table[k] = {"score": 0, "kills": 0, "deaths": 0}
	if k != "" and k != v and _table.has(k):
		var kr: Dictionary = _table[k]
		kr["kills"] = int(kr["kills"]) + 1
		kr["score"] = int(kr["score"]) + 1
	if v != "" and _table.has(v):
		var vr: Dictionary = _table[v]
		vr["deaths"] = int(vr["deaths"]) + 1
	_refresh()


## Rows sorted by score desc, name asc on ties; local row has highlight true.
func get_rows() -> Array:
	var ids: Array = _table.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var sa := int((_table[a] as Dictionary)["score"])
		var sb := int((_table[b] as Dictionary)["score"])
		if sa != sb:
			return sa > sb
		return a < b)
	var out: Array = []
	for pid in ids:
		var r: Dictionary = (_table[pid] as Dictionary).duplicate()
		r["name"] = str(pid)
		r["highlight"] = str(pid) == local_id
		out.append(r)
	return out


func row_for(participant: String) -> Dictionary:
	var pid := participant.strip_edges()
	if _table.has(pid):
		var r: Dictionary = (_table[pid] as Dictionary).duplicate()
		r["name"] = pid
		r["highlight"] = pid == local_id
		return r
	return {"name": pid, "score": 0, "kills": 0, "deaths": 0, "highlight": pid == local_id}


func score_for(participant: String) -> int:
	return int(row_for(participant)["score"])


func kills_for(participant: String) -> int:
	return int(row_for(participant)["kills"])


func deaths_for(participant: String) -> int:
	return int(row_for(participant)["deaths"])


## Exactly "You N / 25": no rank suffix, so the HudLine and the regex agree.
func hud_standings_string() -> String:
	return "%s %d / %d" % [local_id, score_for(local_id), target_score]


## Comparison string for exactly what _refresh renders: one segment per
## row in sorted order plus the HUD line, feed texts, target, and local id.
func _render_fingerprint(rows_data: Array, hud_text: String, feed_texts: Array) -> String:
	var parts := PackedStringArray()
	for row in rows_data:
		var r := row as Dictionary
		parts.append("%s=%d=%d=%d=%s" % [str(r.get("name", "")), int(r.get("score", 0)), int(r.get("kills", 0)), int(r.get("deaths", 0)), str(bool(r.get("highlight", false)))])
	parts.append("hud=" + hud_text)
	for text in feed_texts:
		parts.append("feed=" + str(text))
	parts.append("target=%d" % target_score)
	parts.append("local=" + local_id)
	return "|".join(parts)


## True when the live tree already shows the expected content. A missing
## Rows/Feed/HudLine node counts as matching so a bare Standings.new()
## stays crash-free and cheap.
func _tree_matches(expected_rows: int, expected_feed: int, hud_text: String) -> bool:
	var line := get_node_or_null("HudLine") as Label
	if line != null and line.text != hud_text:
		return false
	var rows := get_node_or_null("Rows")
	if rows != null and rows is Container and (rows as Node).get_child_count() != expected_rows:
		return false
	var feed_box := get_node_or_null("Feed")
	if feed_box != null and feed_box is Container and (feed_box as Node).get_child_count() != expected_feed:
		return false
	return true


func _refresh() -> void:
	_ensure_feed()
	var rows_data := get_rows()
	var hud_text := hud_standings_string()
	var feed_texts: Array = []
	for entry in feed.get_entries():
		feed_texts.append(str((entry as Dictionary)["text"]))
	var fingerprint := _render_fingerprint(rows_data, hud_text, feed_texts)
	if fingerprint == _last_render and _tree_matches(rows_data.size(), feed_texts.size(), hud_text):
		return
	var line := get_node_or_null("HudLine") as Label
	if line != null:
		line.text = hud_text
	var rows := get_node_or_null("Rows")
	if rows != null and rows is Container:
		for child in (rows as Node).get_children():
			(rows as Node).remove_child(child)
			child.queue_free()
		for row in rows_data:
			var label := Label.new()
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.text = "%s  %d" % [str(row["name"]), int(row["score"])]
			if bool(row["highlight"]):
				label.modulate = Color(1.0, 0.85, 0.25)
			(rows as Node).add_child(label)
	var feed_box := get_node_or_null("Feed")
	if feed_box != null and feed_box is Container:
		for child in (feed_box as Node).get_children():
			(feed_box as Node).remove_child(child)
			child.queue_free()
		for text in feed_texts:
			var label := Label.new()
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.text = text
			(feed_box as Node).add_child(label)
	_last_render = fingerprint


func _find_manager() -> Node:
	var parent := get_parent()
	if parent == null:
		return null
	if parent.get("time_left") != null:
		return parent
	for child in parent.get_children():
		if child == self:
			continue
		if not (child is Node):
			continue
		var n := child as Node
		if n.get("time_left") != null:
			return n
		if n.has_method("get_standings") or n.has_method("score_for"):
			return n
	return null


## Read-only poll: refreshes the table from the manager without writing it.
func _poll_manager(mgr: Node) -> void:
	if not is_instance_valid(mgr):
		return
	var raw_target: Variant = mgr.get("target_score")
	if raw_target != null and int(raw_target) > 0:
		target_score = int(raw_target)
	var ids: Array = []
	if mgr.has_method("get_standings"):
		var raw: Variant = mgr.call("get_standings")
		if raw is Array:
			ids = raw
	if ids.is_empty() and mgr.has_method("score_for"):
		return
	for pid in ids:
		var name := str(pid)
		var score := 0
		var kills := 0
		var deaths := 0
		if mgr.has_method("score_for"):
			score = int(mgr.call("score_for", name))
			kills = score
		if mgr.has_method("kills_for"):
			kills = int(mgr.call("kills_for", name))
		var entry: Variant = null
		if mgr.has_method("entry"):
			entry = mgr.call("entry", name)
		if entry is Dictionary:
			kills = int((entry as Dictionary).get("kills", kills))
			deaths = int((entry as Dictionary).get("deaths", deaths))
			score = int((entry as Dictionary).get("score", score))
		_table[name] = {"score": score, "kills": kills, "deaths": deaths}


func _ensure_feed() -> void:
	if feed == null:
		feed = KillFeed.new()


func _coerce_row(raw: Variant) -> Dictionary:
	if raw is int:
		return {"score": raw, "kills": raw, "deaths": 0}
	if raw is float:
		return {"score": int(raw), "kills": int(raw), "deaths": 0}
	if raw is Dictionary:
		return {
			"score": int((raw as Dictionary).get("score", 0)),
			"kills": int((raw as Dictionary).get("kills", (raw as Dictionary).get("score", 0))),
			"deaths": int((raw as Dictionary).get("deaths", 0)),
		}
	return {"score": 0, "kills": 0, "deaths": 0}


func _load_config(path: String = CONFIG_PATH) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		push_warning("standings: missing %s, using compiled defaults" % CONFIG_PATH)
		return
	target_score = _cfg_int(cfg, "match", "target_score", target_score)
	if target_score < 1:
		push_warning("standings: invalid match/target_score, keeping default")
		target_score = TARGET_DEFAULT


static func _cfg_float(cfg: ConfigFile, section: String, key: String, fallback: float) -> float:
	var raw: Variant = cfg.get_value(section, key, fallback)
	if raw is float:
		if is_finite(raw):
			return raw
		push_warning("standings: invalid %s/%s, keeping default" % [section, key])
		return fallback
	if raw is int:
		return float(raw)
	push_warning("standings: invalid %s/%s, keeping default" % [section, key])
	return fallback


static func _cfg_int(cfg: ConfigFile, section: String, key: String, fallback: int) -> int:
	var raw: Variant = cfg.get_value(section, key, fallback)
	if raw is int:
		return raw
	push_warning("standings: invalid %s/%s, keeping default" % [section, key])
	return fallback
