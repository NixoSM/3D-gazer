class_name MenuScreen
extends Control
## Title and level list. The tunnel keeps turning slowly behind it.

signal level_chosen(index: int)

var _list: VBoxContainer
var _entries: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	ScreenLayout.changed.connect(func(_landscape: bool) -> void: _build())
	_build()


func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	add_child(_scrim())
	var safe := SafeArea.new()
	add_child(safe)
	if ScreenLayout.landscape:
		_build_landscape(safe)
	else:
		_build_portrait(safe)
	if not _entries.is_empty():
		populate(_entries)


func _build_portrait(safe: Control) -> void:
	var layout := VBoxContainer.new()
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_theme_constant_override("separation", 0)
	safe.add_child(layout)

	var top_gap := Control.new()
	top_gap.custom_minimum_size = Vector2(0, 40)
	layout.add_child(top_gap)
	layout.add_child(UiStyle.display("GAZER", 150, 6))
	var subtitle := UiStyle.caption("a tunnel that turns around you", 24)
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
	_add_how_to(layout)


## Wide screen: title and how-to on the left, levels on the right, and the
## ball rolling between them.
func _build_landscape(safe: Control) -> void:
	var columns := HBoxContainer.new()
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_theme_constant_override("separation", 0)
	safe.add_child(columns)

	var left := VBoxContainer.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.custom_minimum_size = Vector2(500, 0)
	left.add_theme_constant_override("separation", 0)
	columns.add_child(left)
	left.add_child(UiStyle.display("GAZER", 132, 5))
	left.add_child(UiStyle.caption("a tunnel that turns around you", 22))
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(gap)
	_add_how_to(left)

	var middle := Control.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_child(middle)

	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(420, 0)
	_list.alignment = BoxContainer.ALIGNMENT_CENTER
	_list.add_theme_constant_override("separation", 0)
	columns.add_child(_list)


func _add_how_to(layout: Control) -> void:
	for line in ["tilt to roll", "swipe up to jump", "tap as you land to echo"]:
		layout.add_child(UiStyle.caption(line, 24))


## levels: Array of {level: LevelData, palette: LevelPalette, unlocked: bool, best: float, completed: bool}
func populate(levels: Array) -> void:
	_entries = levels
	for child in _list.get_children():
		child.queue_free()
	for i in levels.size():
		_list.add_child(_row_compact(i, levels[i]) if ScreenLayout.landscape else _row(i, levels[i]))


func _row(index: int, info: Dictionary) -> Control:
	var level: LevelData = info["level"]
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	var button := UiStyle.button(level.display_name, true)
	button.disabled = not info["unlocked"]
	button.custom_minimum_size = Vector2(0, 76)
	button.pressed.connect(level_chosen.emit.bind(index))
	row.add_child(button)

	var swatch := _swatch(info)
	row.add_child(swatch)

	var caption := UiStyle.caption(_status(index, info), 24)
	row.add_child(caption)
	if not info["unlocked"]:
		# Solid grey, not transparency: see-through outlined text turns to mud.
		caption.add_theme_color_override("font_color", UiStyle.LOCKED)
	return row


## Landscape row: the whole row (name, colours, status) is one button, so
## the touch target stays over 44 pt while seven rows fit 390 pt of height.
func _row_compact(index: int, info: Dictionary) -> Control:
	var level: LevelData = info["level"]
	var button := UiStyle.button(level.display_name, true)
	button.disabled = not info["unlocked"]
	button.add_theme_font_size_override("font_size", 44)
	button.add_theme_constant_override("outline_size", 10)
	button.custom_minimum_size = Vector2(0, 86)
	var pad := StyleBoxEmpty.new()
	pad.content_margin_bottom = 34
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, pad)
	button.pressed.connect(level_chosen.emit.bind(index))

	var under := VBoxContainer.new()
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	under.add_theme_constant_override("separation", 0)
	under.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	under.offset_top = -36
	under.offset_bottom = -2
	button.add_child(under)
	var swatch := _swatch(info)
	swatch.custom_minimum_size = Vector2(300, 8)
	under.add_child(swatch)
	var caption := UiStyle.caption(_status(index, info), 19)
	under.add_child(caption)
	if not info["unlocked"]:
		caption.add_theme_color_override("font_color", UiStyle.LOCKED)
	return button


func _swatch(info: Dictionary) -> TextureRect:
	var swatch := TextureRect.new()
	var texture := GradientTexture2D.new()
	texture.gradient = (info["palette"] as LevelPalette).wall
	texture.width = 256
	texture.height = 4
	swatch.texture = texture
	swatch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	swatch.stretch_mode = TextureRect.STRETCH_SCALE
	swatch.custom_minimum_size = Vector2(340, 12)
	swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not info["unlocked"]:
		swatch.modulate = Color(0.6, 0.6, 0.6)
	return swatch


func _status(index: int, info: Dictionary) -> String:
	if not info["unlocked"]:
		return "finish the one above"
	if info["completed"]:
		return "complete" + (" · best echo ×%d" % info["best_chain"] if info["best_chain"] > 1 else "")
	if info["best"] > 0.0:
		return "best %d%%" % int(info["best"] * 100.0)
	return "%02d · new" % (index + 1)


static func _scrim() -> TextureRect:
	# A soft vertical darkening so text reads over any tunnel colour.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.2))
	gradient.set_color(1, Color(0, 0, 0, 0.3))
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
