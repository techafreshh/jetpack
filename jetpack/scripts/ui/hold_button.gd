class_name HoldButton
extends Button
## Press-and-hold confirm button: accumulates probe-readable `progress`
## 0.0->1.0 in _process(delta) while pressed and emits `confirmed` once at
## 1.0. A short tap released before 1.0 resets progress to 0.0 and emits
## nothing, so mid-fight taps cannot wipe match progress. The visual
## fill-ring is the `Fill` ColorRect child whose width mirrors progress.
## Frame-rate independent: progress advances delta / hold_time per tick and
## needs no Timer child. process_mode is ALWAYS so the hold still fills
## while the tree is paused (pause menu use).

## Seconds of continuous press required to confirm.
@export var hold_time := 1.0
## Probe-readable fill-ring state, 0.0..1.0.
var progress := 0.0
## True while the press is held down.
var holding := false

## Emitted exactly once per completed hold.
signal confirmed

var _emitted := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hold_time = maxf(hold_time, 0.001)
	if not is_connected("button_down", begin_hold):
		connect("button_down", begin_hold)
	if not is_connected("button_up", release_hold):
		connect("button_up", release_hold)
	_mirror_fill()


func _process(delta: float) -> void:
	if not holding or _emitted:
		return
	progress = clampf(progress + delta / maxf(hold_time, 0.001), 0.0, 1.0)
	_mirror_fill()
	if progress >= 1.0:
		_emitted = true
		confirmed.emit()


func begin_hold() -> void:
	holding = true


func release_hold() -> void:
	reset_hold()


## Clears the hold state; used by release and by the pause menu after a
## confirmed restart/quit so the next open starts empty.
func reset_hold() -> void:
	holding = false
	_emitted = false
	progress = 0.0
	_mirror_fill()


func _mirror_fill() -> void:
	var fill := get_node_or_null("Fill") as Control
	if fill == null:
		return
	fill.anchor_right = clampf(progress, 0.0, 1.0)
