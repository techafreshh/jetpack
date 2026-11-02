class_name Health
extends RefCounted
## Authoritative HP math for soldiers: exact damage/heal accounting plus the
## tick-exact respawn delay. Pure static functions with no tree access; the
## soldier owns lifecycle (collision, teleport, countdown) and calls these.

const DEFAULT_MAX_HP := 100.0
const RESPAWN_TICKS := 180


static func apply_damage(hp: float, amount: float) -> float:
	return maxf(0.0, hp - amount)


static func heal_to(hp: float, max_hp: float, amount: float) -> float:
	return minf(max_hp, hp + amount)


## Single home of the foe-alive duck-type idiom: whether a node exposes an
## `is_alive` flag. Null-safe; nodes without the flag return false.
static func has_alive_flag(node: Object) -> bool:
	return node != null and node.has_method("get") and "is_alive" in node


## Strict allowlist for foe selection: only nodes exposing a true `is_alive`
## count as live foes. Dummies (no flag), the dead, and null never count.
static func is_live_foe(node: Object) -> bool:
	return has_alive_flag(node) and bool(node.get("is_alive"))


## Permissive host check for guns: hosts without the flag (bare guns, plain
## nodes) and null parents count as alive; only an explicit false denies fire.
static func is_host_alive(node: Object) -> bool:
	return not has_alive_flag(node) or bool(node.get("is_alive"))
