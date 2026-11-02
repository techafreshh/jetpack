class_name Scoreboard
extends RefCounted
## Pure per-id FFA table: kills, deaths, and score (one point per kill).
## No tree access; ids are stable Strings. A self-kill records a death only,
## so unattributed or own-goal deaths never corrupt the leader.

var _rows: Dictionary = {}


func ensure(participant_id: String) -> bool:
	var pid := participant_id.strip_edges()
	if pid == "":
		return false
	if not _rows.has(pid):
		_rows[pid] = {"kills": 0, "deaths": 0, "score": 0}
	return true


func register_kill(killer_id: String, victim_id: String) -> void:
	var killer := killer_id.strip_edges()
	var victim := victim_id.strip_edges()
	if victim != "":
		ensure(victim)
	if killer != "" and killer != victim:
		ensure(killer)
		var k: Dictionary = _rows[killer]
		k["kills"] = int(k["kills"]) + 1
		k["score"] = int(k["score"]) + 1
	if victim != "":
		var v: Dictionary = _rows[victim]
		v["deaths"] = int(v["deaths"]) + 1


func record_death(victim_id: String) -> void:
	var victim := victim_id.strip_edges()
	if victim == "":
		return
	ensure(victim)
	var v: Dictionary = _rows[victim]
	v["deaths"] = int(v["deaths"]) + 1


func reset() -> void:
	for pid in _rows:
		_rows[pid] = {"kills": 0, "deaths": 0, "score": 0}


func clear() -> void:
	_rows.clear()


func size() -> int:
	return _rows.size()


func has(participant_id: String) -> bool:
	return _rows.has(participant_id.strip_edges())


func entry(participant_id: String) -> Dictionary:
	var pid := participant_id.strip_edges()
	if _rows.has(pid):
		var r: Dictionary = _rows[pid]
		return {"kills": int(r["kills"]), "deaths": int(r["deaths"]), "score": int(r["score"])}
	return {"kills": 0, "deaths": 0, "score": 0}


func kills_for(participant_id: String) -> int:
	return int(entry(participant_id)["kills"])


func deaths_for(participant_id: String) -> int:
	return int(entry(participant_id)["deaths"])


func score_for(participant_id: String) -> int:
	return int(entry(participant_id)["score"])


## Most kills wins; exact ties break to the lowest id. Empty table has none.
func leader_id() -> String:
	var best := ""
	var best_kills := -1
	for pid in _rows:
		var k := int((_rows[pid] as Dictionary)["kills"])
		if k > best_kills or (k == best_kills and String(pid) < best):
			best_kills = k
			best = String(pid)
	return best


## True when one id strictly outscores every other (empty table ties at zero).
func has_unique_leader() -> bool:
	var best := -1
	var count := 0
	for pid in _rows:
		var k := int((_rows[pid] as Dictionary)["kills"])
		if k > best:
			best = k
			count = 1
		elif k == best:
			count += 1
	return count == 1


## Ids sorted by kills desc, lowest id first on ties.
func standings() -> Array:
	var ids: Array = _rows.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ka := int((_rows[a] as Dictionary)["kills"])
		var kb := int((_rows[b] as Dictionary)["kills"])
		if ka != kb:
			return ka > kb
		return a < b)
	return ids
