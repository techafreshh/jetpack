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
const MIN_DAMAGE := 1.0
const MAX_DAMAGE := 200.0
const MIN_SPREAD_DEG := 0.0
const MAX_SPREAD_DEG := 45.0
const MIN_RANGE := 100.0
const MAX_RANGE := 5000.0
const MIN_MAG_SIZE := 1
const MAX_MAG_SIZE := 100
const MIN_ZOOM := 1.0
const MAX_ZOOM := 8.0
## Last-resort refusal for direct-storage/bulk-load smuggles: only
## sub-MIN or non-finite rates refuse; over-MAX rates stay fireable.
static func is_fireable_rate(rate: float) -> bool:
	return is_finite(rate) and rate >= MIN_FIRE_RATE
# Edit-time damage guard: same clamp-and-warn idiom as fire_rate, so a
# typo'd .tres can never silently heal via Health.apply_damage.
@export_range(1.0, 200.0, 0.5) var damage: float = 10.0:
	set(value):
		var cleaned: float = value
		if not is_finite(cleaned):
			cleaned = MIN_DAMAGE
		cleaned = clampf(cleaned, MIN_DAMAGE, MAX_DAMAGE)
		if cleaned != value:
			push_warning("weapon: invalid damage %f, clamped to %f" % [value, cleaned])
		damage = cleaned
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
# Edit-time spread guard: same clamp-and-warn idiom as fire_rate, so an
# absurd cone can never silently stick.
@export_range(0.0, 45.0, 0.1) var spread_deg: float = 2.0:
	set(value):
		var cleaned: float = value
		if not is_finite(cleaned):
			cleaned = MIN_SPREAD_DEG
		cleaned = clampf(cleaned, MIN_SPREAD_DEG, MAX_SPREAD_DEG)
		if cleaned != value:
			push_warning("weapon: invalid spread_deg %f, clamped to %f" % [value, cleaned])
		spread_deg = cleaned
# Edit-time range guard: same clamp-and-warn idiom as fire_rate, so a
# degenerate or backwards ray can never silently stick.
@export_range(100.0, 5000.0, 10.0) var range: float = 1000.0:
	set(value):
		var cleaned: float = value
		if not is_finite(cleaned):
			cleaned = MIN_RANGE
		cleaned = clampf(cleaned, MIN_RANGE, MAX_RANGE)
		if cleaned != value:
			push_warning("weapon: invalid range %f, clamped to %f" % [value, cleaned])
		range = cleaned
@export_group("Ammo")
# Edit-time mag guard: same clamp-and-warn idiom as fire_rate (ints are
# always finite, so no is_finite check), keeping can_fire reachable.
@export_range(1, 100, 1) var mag_size: int = 10:
	set(value):
		var cleaned: int = value
		cleaned = clampi(cleaned, MIN_MAG_SIZE, MAX_MAG_SIZE)
		if cleaned != value:
			push_warning("weapon: invalid mag_size %d, clamped to %d" % [value, cleaned])
		mag_size = cleaned
@export var reserve: int = 30
@export_group("Shot")
@export var projectile: ProjectileKind = ProjectileKind.HITSCAN
@export var pellet_count: int = 1
@export_group("Audio")
@export var sfx_name: String = "shot"
@export_group("Optics")
# Edit-time zoom guard: same clamp-and-warn idiom as fire_rate, keeping
# the 1.0 no-scope identity as the floor.
@export_range(1.0, 8.0, 0.1) var zoom: float = 1.0:
	set(value):
		var cleaned: float = value
		if not is_finite(cleaned):
			cleaned = MIN_ZOOM
		cleaned = clampf(cleaned, MIN_ZOOM, MAX_ZOOM)
		if cleaned != value:
			push_warning("weapon: invalid zoom %f, clamped to %f" % [value, cleaned])
		zoom = cleaned
