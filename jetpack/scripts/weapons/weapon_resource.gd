class_name WeaponResource
extends Resource
## Data-driven gun stats: every tunable a weapon needs lives here so adding
## a gun is a file drop. One generic driver reads these fields at runtime.

enum ProjectileKind { HITSCAN, PELLET }

@export_group("Identity")
@export var display_name: String = ""
@export_group("Fire")
@export var damage: float = 10.0
@export var fire_rate: float = 5.0
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
