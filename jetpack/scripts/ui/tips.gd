class_name TipsOverlay
extends CanvasLayer
## First-match contextual tips: builds a tips_label Label in code with
## move/fly/shoot copy, initially hidden. Any move_left/move_right/fly/fire
## fire/throw_grenade press resets the public idle_s clock (duck-typed, no hard
## parent assumptions, mirroring hud.gd:_discover_manager); after
## IDLE_THRESHOLD idle seconds the label shows and user://seen_tips is
## written so it never repeats. A present flag file hides it permanently.

const SEEN_FLAG := "user://seen_tips"
const IDLE_THRESHOLD := 5.0
const TIP_TEXT := "Move: A / D — Fly: hold Space — Shoot: left mouse button"

## Public idle clock (seconds); probes may set it directly.
var idle_s: float = 0.0

var _tips_label: Label = null
var _seen: bool = false


func _ready() -> void:
	layer = 64
	_seen = FileAccess.file_exists(SEEN_FLAG)
	_ensure_label()
	if _seen:
		_hide()
	else:
		idle_s = 0.0


func _physics_process(delta: float) -> void:
	if _seen:
		return
	if _tips_label == null:
		_ensure_label()
	if _tips_label == null:
		return
	if _any_tip_action_pressed():
		idle_s = 0.0
		return
	idle_s += delta
	if idle_s >= IDLE_THRESHOLD:
		_tips_label.visible = true
		_mark_seen()


func _ensure_label() -> void:
	_tips_label = get_node_or_null("tips_label") as Label
	if _tips_label != null:
		return
	var label := Label.new()
	label.name = "tips_label"
	label.text = TIP_TEXT
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.anchor_top = 0.85
	label.anchor_bottom = 0.85
	label.offset_left = -400.0
	label.offset_right = 400.0
	label.offset_top = -20.0
	label.offset_bottom = 20.0
	add_child(label)
	_tips_label = label
	_tips_label.visible = false


func _any_tip_action_pressed() -> bool:
	for action in ["move_left", "move_right", "fly", "fire", "throw_grenade"]:
		if Input.is_action_pressed(action):
			return true
	return false


func _mark_seen() -> void:
	_seen = true
	var file := FileAccess.open(SEEN_FLAG, FileAccess.WRITE)
	if file != null:
		file.store_string("1")
		file.close()


func _hide() -> void:
	if _tips_label != null:
		_tips_label.visible = false
