class_name WeaponResource
extends Resource
## Data-driven gun stats: every tunable a weapon needs lives here so adding
## a gun is a file drop. One generic driver reads these fields at runtime.

enum ProjectileKind { HITSCAN, PELLET }

@export_group("Identity")
@export var display_name: String = ""
@export_group("Fire")
const MIN_FIRE_RATE := 0.1
const MAX_FIRE_RATE := 60.0
@export var damage: float = 10.0
# Edit-time rate guard: the Inspector slider (@export_range) plus this
# setter clamp every assignment (edits, script writes, .tres loads) and
# warn when correcting, so an unfireable rate can never silently stick.
@export_range(0.1, 60.0, 0.1) var fire_rate: float = 5.0:
	set(value):
		var cleaned: float = value
		if not is_finite(cleaned):
			cleaned = MIN_FIRE_RATE
		cleaned = clampf(cleaned, MIN_FIRE_RATE, MAX_FIRE_RATE)
		if cleaned != value:
			push_warning("weapon: invalid fire_rate %f, clamped to %f" % [value, cleaned])
		fire_rate = cleaned
@export var spread_deg: float = 2.0
@export var range: float = 1000.0
@export_group("Ammo")
@export var mag_size: int = 10
@export var reserve: int = 30
@export_group("Shot")
@export var projectile: ProjectileKind = ProjectileKind.HITSCAN
@export var pellet_count: int = 1
@export_group("Optics")
@export var zoom: float = 1.0
