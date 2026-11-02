extends PointLight2D
## Muzzle flash light: energy-only pop that decays to zero. Peak output is
## full energy by default and exactly half under reduced flashing, read via
## peak_energy so probes can compare against the full-flash baseline. Never
## errors off-tree or without Settings (Accessibility falls back to full).

## Full-flash peak output; reduced flashing scales it by REDUCED_SCALE.
@export var full_energy := 2.0
## Reduced-flash peak is exactly half the full baseline (<=50% contract).
const REDUCED_SCALE := 0.5
## Seconds for the flash to fade from peak to zero.
@export var flash_time := 0.12

## Most recent flash peak (full or reduced); 0.0 before the first flash.
var peak_energy := 0.0
var _age := 999.0


func _ready() -> void:
	energy = 0.0


func flash() -> void:
	if Accessibility.reduced_flash_on(self):
		peak_energy = full_energy * REDUCED_SCALE
	else:
		peak_energy = full_energy
	energy = peak_energy
	_age = 0.0


func _process(delta: float) -> void:
	if energy <= 0.0 or peak_energy <= 0.0:
		return
	_age += delta
	var frac := 1.0 - clampf(_age / maxf(flash_time, 0.001), 0.0, 1.0)
	energy = peak_energy * frac
