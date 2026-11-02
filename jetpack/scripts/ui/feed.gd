class_name KillFeed
extends RefCounted
## Last-4 kill attribution ring buffer: killer-victim-weapon events with no
## tree access. Pure-logic home mirroring the Health/Spawner shape; the
## Standings widget owns one and renders it. Newest entries evict the oldest
## past MAX_FEED; probes drive this headlessly via push_kill/add_kill plus
## the feed_count/latest/get_entries readers.

const MAX_FEED := 4

## Probe-readable count of retained events; mirrors match.gd last_hp style.
var feed_count := 0

## Newest-last ring; get_entries exposes it newest-first as duplicates.
var _entries: Array[Dictionary] = []


func push_kill(killer: String, victim: String, weapon: String = "") -> void:
	var k := killer.strip_edges()
	var v := victim.strip_edges()
	var w := weapon.strip_edges()
	if k == "" and v == "" and w == "":
		return
	var shown_k := k if k != "" else "The arena"
	_entries.append({
		"killer": k,
		"victim": v,
		"weapon": w,
		"text": "%s killed %s with %s" % [shown_k, v, w],
	})
	while _entries.size() > MAX_FEED:
		_entries.pop_front()
	feed_count = _entries.size()


func add_kill(killer: String, victim: String, weapon: String = "") -> void:
	push_kill(killer, victim, weapon)


## Newest entry as a duplicate; empty dict when the feed is empty.
func latest() -> Dictionary:
	if _entries.is_empty():
		return {}
	return (_entries.back() as Dictionary).duplicate()


## Newest entry text; "" when the feed is empty.
func latest_text() -> String:
	if _entries.is_empty():
		return ""
	return str((_entries.back() as Dictionary)["text"])


## Retained entries newest-first as duplicates; callers cannot mutate the ring.
func get_entries() -> Array:
	var out: Array = []
	for i in range(_entries.size() - 1, -1, -1):
		out.append((_entries[i] as Dictionary).duplicate())
	return out


func clear() -> void:
	_entries.clear()
	feed_count = 0
