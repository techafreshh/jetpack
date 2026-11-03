class_name Accessibility
extends RefCounted
## Single home of the accessibility toggle reads: every effect resolves its
## toggle through one null-safe static, so tree-less and Settings-less use
## (headless probes, bare nodes) falls back to compiled defaults instead of
## erroring. Mirrors the Health single-home predicate idiom.


static func _settings_of(host: Object) -> Node:
	if host == null:
		return null
	if not (host is Node):
		return null
	var node := host as Node
	if not node.is_inside_tree():
		return null
	var tree := node.get_tree()
	if tree == null:
		return null
	var root := tree.root
	if root == null:
		return null
	return root.get_node_or_null("/root/Settings") as Node


static func _toggle_on(host: Object, toggle: String) -> bool:
	var settings := _settings_of(host)
	if settings == null:
		return false
	if not settings.has_method("get_toggle"):
		return false
	return bool(settings.call("get_toggle", toggle))


static func colorblind_on(host: Object) -> bool:
	return _toggle_on(host, "colorblind_mode")


static func reduced_flash_on(host: Object) -> bool:
	return _toggle_on(host, "reduced_flashing")


static func aim_assist_on(host: Object) -> bool:
	return _toggle_on(host, "aim_assist")


static func shake_scale(host: Object) -> float:
	var settings := _settings_of(host)
	if settings == null:
		return 1.0
	if not settings.has_method("get_screen_shake"):
		return 1.0
	var raw: Variant = settings.call("get_screen_shake")
	if raw is float:
		if is_finite(raw):
			return clampf(raw, 0.0, 1.0)
		return 1.0
	if raw is int:
		return clampf(float(raw), 0.0, 1.0)
	return 1.0
