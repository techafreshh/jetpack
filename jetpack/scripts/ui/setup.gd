extends Control
## Match setup screen: difficulty (Easy/Standard/Sharp), score target, and
## time limit in seconds with an m:ss readout. Confirm writes the validated
## values into the MatchSetup handoff (persisted to user://match_setup.cfg)
## and returns to the menu; Back returns without applying. apply() accepts
## optional explicit args so headless callers need no UI; with no args it
## reads the live controls. All node access is get_node_or_null guarded.

const MENU_SCENE := "res://scenes/main_menu.tscn"
const DIFFICULTIES := ["easy", "standard", "sharp"]
const DIFFICULTY_LABELS := ["Easy", "Standard", "Sharp"]


func _ready() -> void:
	_fill_difficulty()
	_connect_button("ConfirmButton", _on_confirm)
	_connect_button("BackButton", _on_back)
	_connect_time()
	_refresh_readout()


## Headless entry point: explicit args win; empty/negative falls back to
## the live controls. Invalid values never reach the holder.
func apply(difficulty: String = "", target: int = -1, time_s: float = -1.0) -> void:
	var diff := difficulty.strip_edges().to_lower()
	if diff == "":
		diff = _ui_difficulty()
	var want_target := target
	if want_target < 1:
		want_target = _ui_target()
	var want_time := time_s
	if want_time <= 0.0:
		want_time = _ui_time()
	if diff in DIFFICULTIES and want_target >= 1 and want_time > 0.0:
		MatchSetup.difficulty = diff
		MatchSetup.target_score = want_target
		MatchSetup.time_limit_s = want_time
		MatchSetup.save_config()


func _on_confirm() -> void:
	apply()
	_go_menu()


func _on_back() -> void:
	_go_menu()


func _go_menu() -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.paused = false
	tree.change_scene_to_file(MENU_SCENE)


func _fill_difficulty() -> void:
	var option := get_node_or_null("DifficultyOption") as OptionButton
	if option == null:
		return
	if option.item_count == 0:
		for label in DIFFICULTY_LABELS:
			option.add_item(label)
	option.select(1)


func _connect_time() -> void:
	var spin := get_node_or_null("TimeSpin") as SpinBox
	if spin == null:
		return
	if not spin.is_connected("value_changed", _on_time_changed):
		spin.connect("value_changed", _on_time_changed)


func _on_time_changed(_v: float) -> void:
	_refresh_readout()


func _refresh_readout() -> void:
	var readout := get_node_or_null("TimeReadout") as Label
	if readout == null:
		return
	readout.text = _format_clock(_ui_time())


func _ui_difficulty() -> String:
	var option := get_node_or_null("DifficultyOption") as OptionButton
	if option == null or option.item_count == 0:
		return "standard"
	var idx := clampi(option.selected, 0, DIFFICULTIES.size() - 1)
	return DIFFICULTIES[idx]


func _ui_target() -> int:
	var spin := get_node_or_null("TargetSpin") as SpinBox
	if spin == null:
		return -1
	return int(round(spin.value))


func _ui_time() -> float:
	var spin := get_node_or_null("TimeSpin") as SpinBox
	if spin == null:
		return -1.0
	return float(spin.value)


func _format_clock(seconds: float) -> String:
	var total := maxi(0, int(round(seconds)))
	return "%d:%02d" % [total / 60, total % 60]


func _connect_button(path: String, method: Callable) -> void:
	var button := get_node_or_null(path) as BaseButton
	if button == null:
		return
	if not button.is_connected("pressed", method):
		button.connect("pressed", method)
