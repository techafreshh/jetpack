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
