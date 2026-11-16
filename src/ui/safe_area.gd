class_name SafeArea
extends MarginContainer
## Keeps its children clear of the notch, Dynamic Island and home indicator.
## Margins follow DisplayServer.get_display_safe_area(), converted to the
## stretched viewport's coordinates, plus a small design margin.

const EXTRA := 24


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_update)
	_update()


func _update() -> void:
	var window := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	var viewport := get_viewport_rect().size
	var top := 0.0
	var bottom := 0.0
	var left := 0.0
	var right := 0.0
	# Desktop windows report the whole monitor as "safe": only trust phones.
	if OS.has_feature("mobile") and window.x > 0 and window.y > 0 and safe.size.x > 0:
		var scale := viewport / Vector2(window)
		top = safe.position.y * scale.y
		left = safe.position.x * scale.x
		bottom = (window.y - safe.end.y) * scale.y
		right = (window.x - safe.end.x) * scale.x
	add_theme_constant_override("margin_top", int(maxf(top, 0.0)) + EXTRA)
	add_theme_constant_override("margin_bottom", int(maxf(bottom, 0.0)) + EXTRA)
	add_theme_constant_override("margin_left", int(maxf(left, 0.0)) + EXTRA)
	add_theme_constant_override("margin_right", int(maxf(right, 0.0)) + EXTRA)
