class_name MenuScreen
extends Control
## Title and level list. The tunnel keeps turning slowly behind it.

signal level_chosen(index: int)

var _list: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scrim := _scrim()
	add_child(scrim)
	var safe := SafeArea.new()
	add_child(safe)
	var layout := VBoxContainer.new()
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_theme_constant_override("separation", 0)
	safe.add_child(layout)

	var top_gap := Control.new()
	top_gap.custom_minimum_size = Vector2(0, 40)
	layout.add_child(top_gap)
	layout.add_child(UiStyle.display("GAZER", 120, 34))
	var subtitle := UiStyle.caption("a tunnel that turns around you", 20)
	subtitle.modulate.a = 0.8
	layout.add_child(subtitle)

	var title_gap := Control.new()
	title_gap.custom_minimum_size = Vector2(0, 36)
	layout.add_child(title_gap)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	layout.add_child(_list)

	# The ball rolls in this space.
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(gap)
	for line in ["tilt to roll", "swipe up to jump", "tap as you land to echo"]:
		var hint := UiStyle.caption(line, 18)
		hint.modulate.a = 0.7
		layout.add_child(hint)


## levels: Array of {level: LevelData, palette: LevelPalette, unlocked: bool, best: float, completed: bool}
func populate(levels: Array) -> void:
	for child in _list.get_children():
		child.queue_free()
	for i in levels.size():
		_list.add_child(_row(i, levels[i]))


func _row(index: int, info: Dictionary) -> Control:
	var level: LevelData = info["level"]
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	var button := UiStyle.button(level.display_name, true)
	button.disabled = not info["unlocked"]
	button.custom_minimum_size = Vector2(0, 76)
	button.pressed.connect(level_chosen.emit.bind(index))
	row.add_child(button)

	var swatch := TextureRect.new()
	var texture := GradientTexture2D.new()
	texture.gradient = (info["palette"] as LevelPalette).void_color
	texture.width = 256
	texture.height = 4
	swatch.texture = texture
	swatch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	swatch.stretch_mode = TextureRect.STRETCH_SCALE
	swatch.custom_minimum_size = Vector2(340, 6)
	swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(swatch)

	var status := ""
	if not info["unlocked"]:
		status = "finish the one above"
	elif info["completed"]:
		status = "complete" + (" · best echo ×%d" % info["best_chain"] if info["best_chain"] > 1 else "")
	elif info["best"] > 0.0:
		status = "best %d%%" % int(info["best"] * 100.0)
	else:
		status = "%02d · new" % (index + 1)
	var caption := UiStyle.caption(status, 18)
	caption.modulate.a = 0.75 if info["unlocked"] else 0.4
	row.add_child(caption)
	if not info["unlocked"]:
		row.modulate.a = 0.5
	return row


static func _scrim() -> TextureRect:
	# A soft vertical darkening so text reads over any tunnel colour.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.45))
	gradient.set_color(1, Color(0, 0, 0, 0.55))
	gradient.add_point(0.45, Color(0, 0, 0, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	var rect := TextureRect.new()
	rect.texture = texture
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect
