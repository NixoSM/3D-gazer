class_name InspectorPanel
extends PanelContainer
## The editor's right-hand column: what the analysis found, the selected
## holes' exact numbers, the level's settings and colours, and generated
## patterns to drop in.
##
## Everything here edits through LevelDocument, so it is all undoable.

signal jump_to(s: float)
signal insert_pattern(section: Dictionary)
signal bots_toggled

var document: LevelDocument
var strip: StripView
var analysis: LevelAnalysis

var _updating := false
var _checks: VBoxContainer
var _bot_rows: Array[Dictionary] = []
var _selection_box: VBoxContainer
var _hole_fields := {}
var _selection_note: Label
var _level_fields := {}
var _duration_note: Label
var _palette_box: VBoxContainer
var _spin_direction: OptionButton
var _spin_rate: SpinBox
var _spin_ramp: SpinBox
var _spin_note: Label
var _pattern: OptionButton
var _pattern_count: SpinBox
var _pattern_intensity: HSlider


func setup(p_document: LevelDocument, p_strip: StripView, p_analysis: LevelAnalysis) -> void:
	document = p_document
	strip = p_strip
	analysis = p_analysis
	add_theme_stylebox_override("panel", EditorTheme.panel(EditorTheme.PAPER))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)

	_build_checks(column)
	_build_selection(column)
	_build_pattern(column)
	_build_level(column)
	_build_spin(column)
	_build_palette(column)


func set_document(p_document: LevelDocument) -> void:
	document = p_document
	refresh_level()
	refresh_selection()


# --- Checks: what the analysis says --------------------------------------------

func _build_checks(column: VBoxContainer) -> void:
	column.add_child(EditorTheme.heading("CAN IT BE BEATEN?"))
	for i in LevelAnalysis.BOT_DELAYS.size():
		var row := HBoxContainer.new()
		var toggle := CheckBox.new()
		toggle.button_pressed = true
		toggle.toggled.connect(func(on: bool) -> void:
			strip.show_bots[i] = on
			strip.queue_redraw_all()
			bots_toggled.emit())
		row.add_child(toggle)
		var swatch := ColorRect.new()
		swatch.color = EditorTheme.BOT_COLORS[i]
		swatch.custom_minimum_size = Vector2(16, 16)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var text := Button.new()
		text.flat = true
		text.alignment = HORIZONTAL_ALIGNMENT_LEFT
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_font_size_override("font_size", 15)
		text.pressed.connect(func() -> void: jump_to.emit(analysis.bots[i].end_s))
		row.add_child(text)
		column.add_child(row)
		_bot_rows.append({"label": text})
	column.add_child(EditorTheme.note("Bots play your level in the background after every edit, reacting 0, 0.2 and 0.35 s late. Solid line = rolling, dotted = in the air, ✕ = where it falls. Click a row to go there."))
	_checks = VBoxContainer.new()
	column.add_child(_checks)


func refresh_analysis() -> void:
	var level := document.level
	for i in _bot_rows.size():
		var trace := analysis.bots[i]
		var label: Button = _bot_rows[i]["label"]
		var name := LevelAnalysis.BOT_NAMES[i]
		match trace.outcome:
			"finished":
				label.text = "%s — finishes ✓" % name
			"fell":
				label.text = "%s — falls at %.0f m (%d%%, %.1f s)" % [name, trace.end_s, int(level.progress_at(trace.end_s) * 100.0), level.time_at(trace.end_s)]
			_:
				label.text = "%s — playing… %d%%" % [name, int(level.progress_at(trace.end_s) * 100.0)]
	for child in _checks.get_children():
		child.queue_free()
	var problems := 0
	var errors := LevelSerializer.validate(level, level.id)
	for error in errors:
		_check_row(error, EditorTheme.BAD, -1.0)
		problems += 1
	if analysis.report:
		for gap in analysis.report.gaps:
			if gap.too_long():
				_check_row("Gap at %.0f m is %.1f m long: the biggest jump covers %.1f m there." % [gap.s_start, gap.length(), gap.jumpable], EditorTheme.BAD, gap.s_start)
				problems += 1
			elif gap.too_close():
				_check_row("Only %.1f m of floor before the gap at %.0f m: nowhere to land and take off." % [gap.run_up, gap.s_start], EditorTheme.WARN, gap.s_start)
				problems += 1
	if problems == 0 and analysis.report:
		_checks.add_child(EditorTheme.note("No unjumpable gaps or missing run-ups.", EditorTheme.GOOD))
	elif analysis.report == null:
		_checks.add_child(EditorTheme.note("Checking gaps…"))


func _check_row(text: String, color: Color, s: float) -> void:
	var button := Button.new()
	button.text = text
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_stylebox_override("normal", EditorTheme.box(color.lightened(0.6), 2, 2))
	button.disabled = s < 0.0
	if s >= 0.0:
		button.pressed.connect(func() -> void: jump_to.emit(s))
	_checks.add_child(button)


# --- Selection -------------------------------------------------------------------

func _build_selection(column: VBoxContainer) -> void:
	column.add_child(EditorTheme.heading("SELECTED"))
	_selection_note = EditorTheme.note("")
	column.add_child(_selection_note)
	_selection_box = VBoxContainer.new()
	column.add_child(_selection_box)
	var grid := GridContainer.new()
	grid.columns = 2
	_selection_box.add_child(grid)
	_hole_fields["s"] = _number_row(grid, "Starts at (m)", 0.0, 10000.0, 0.05, _set_hole_value.bind("s"))
	_hole_fields["length"] = _number_row(grid, "Length (m)", 0.1, 2000.0, 0.05, _set_hole_value.bind("length"))
	_hole_fields["angle"] = _number_row(grid, "Centre (°)", -180.0, 180.0, 0.5, _set_hole_value.bind("angle"))
	_hole_fields["width"] = _number_row(grid, "Width (°)", 1.0, 360.0, 0.5, _set_hole_value.bind("width"))
	_hole_fields["twist"] = _number_row(grid, "Twist (°/m)", -30.0, 30.0, 0.1, _set_hole_value.bind("twist"))
	var buttons := HFlowContainer.new()
	_selection_box.add_child(buttons)
	_action(buttons, "Repeat ⌃D", strip.repeat_selection)
	_action(buttons, "Mirror M", strip.mirror_selection)
	_action(buttons, "Delete ⌫", strip.delete_selection)


func refresh_selection() -> void:
	var selection := strip.selection
	_selection_box.visible = not selection.is_empty()
	var single := selection.size() == 1
	var ring := single and selection[0].is_ring()
	for key in _hole_fields:
		(_hole_fields[key] as SpinBox).editable = single and not (ring and key in ["angle", "width", "twist"])
	if selection.is_empty():
		_selection_note.text = "Nothing selected. Click a hole, Shift-click to add, or drag a box around several."
		return
	if not single:
		_selection_note.text = "%d holes selected. Drag to move them together, or use the buttons." % selection.size()
		return
	var hole := selection[0]
	_selection_note.text = "Ring: the whole tunnel is open, it must be jumped." if hole.is_ring() else "Drag the yellow squares to resize, the pink dot to twist."
	_updating = true
	(_hole_fields["s"] as SpinBox).value = hole.s_start
	(_hole_fields["length"] as SpinBox).value = hole.length
	(_hole_fields["angle"] as SpinBox).value = rad_to_deg(TunnelMath.wrap_angle(hole.angle_center))
	(_hole_fields["width"] as SpinBox).value = rad_to_deg(hole.angle_width)
	(_hole_fields["twist"] as SpinBox).value = rad_to_deg(hole.twist)
	_updating = false


func _set_hole_value(value: float, key: String) -> void:
	if _updating or strip.selection.size() != 1:
		return
	var hole := strip.selection[0]
	document.begin("Edit hole " + key, true)
	var from := hole.s_start
	match key:
		"s":
			hole.s_start = clampf(value, 0.0, document.level.length - hole.length)
		"length":
			hole.length = clampf(value, 0.1, document.level.length - hole.s_start)
		"angle":
			hole.angle_center = TunnelMath.wrap_angle_positive(deg_to_rad(value))
		"width":
			hole.angle_width = deg_to_rad(value)
		"twist":
			hole.twist = deg_to_rad(value)
	document.changed_from(minf(from, hole.s_start))
	strip.queue_redraw_all()


# --- Generated patterns ------------------------------------------------------------

func _build_pattern(column: VBoxContainer) -> void:
	column.add_child(EditorTheme.heading("INSERT A PATTERN"))
	column.add_child(EditorTheme.note("Generated by the same code that made the bundled levels, around the path the bots take. It lands where the mouse last was on the strip, selected, so you can move or tweak it."))
	var grid := GridContainer.new()
	grid.columns = 2
	column.add_child(grid)
	grid.add_child(_label("Pattern"))
	_pattern = OptionButton.new()
	for name in LevelGenerator.PATTERNS:
		if name != "rest":
			_pattern.add_item(name.replace("_", " "))
			_pattern.set_item_metadata(_pattern.item_count - 1, name)
	grid.add_child(_pattern)
	grid.add_child(_label("How many"))
	_pattern_count = SpinBox.new()
	_pattern_count.min_value = 1
	_pattern_count.max_value = 12
	_pattern_count.value = 3
	grid.add_child(_pattern_count)
	grid.add_child(_label("Intensity"))
	_pattern_intensity = HSlider.new()
	_pattern_intensity.min_value = 0.0
	_pattern_intensity.max_value = 1.0
	_pattern_intensity.step = 0.05
	_pattern_intensity.value = 0.5
	_pattern_intensity.custom_minimum_size = Vector2(120, 24)
	grid.add_child(_pattern_intensity)
	var insert := Button.new()
	insert.text = "Insert pattern"
	insert.pressed.connect(func() -> void:
		insert_pattern.emit({
			"p": _pattern.get_item_metadata(_pattern.selected),
			"n": int(_pattern_count.value),
			"i": _pattern_intensity.value,
		}))
	column.add_child(insert)


# --- Level settings ------------------------------------------------------------------

func _build_level(column: VBoxContainer) -> void:
	column.add_child(EditorTheme.heading("LEVEL"))
	var grid := GridContainer.new()
	grid.columns = 2
	column.add_child(grid)
	grid.add_child(_label("Name"))
	var name_edit := LineEdit.new()
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(func(text: String) -> void:
		if _updating:
			return
		document.begin("Rename level", true)
		document.level.display_name = text
		document.changed_from(INF))
	grid.add_child(name_edit)
	_level_fields["name"] = name_edit
	grid.add_child(_label("File id"))
	var id_edit := LineEdit.new()
	id_edit.tooltip_text = "Used for save data and the file name. Never rename a level that has shipped."
	id_edit.text_changed.connect(func(text: String) -> void:
		if _updating:
			return
		document.begin("Change id", true)
		document.level.id = text.strip_edges().to_snake_case()
		document.changed_from(INF))
	grid.add_child(id_edit)
	_level_fields["id"] = id_edit
	_level_fields["base_speed"] = _number_row(grid, "Speed (m/s)", 4.0, 45.0, 0.05, _set_level_value.bind("base_speed"))
	_level_fields["speed_ramp"] = _number_row(grid, "Speeds up by (%)", 0.0, 100.0, 1.0, _set_level_value.bind("speed_ramp"))
	_level_fields["length"] = _number_row(grid, "Length (m)", 50.0, 10000.0, 1.0, _set_level_value.bind("length"))
	_duration_note = EditorTheme.note("")
	column.add_child(_duration_note)
	var fit := Button.new()
	fit.text = "Make it last 60 s"
	fit.tooltip_text = "Sets the length so the level takes a minute at its speed."
	fit.pressed.connect(func() -> void:
		var level := document.level
		_set_level_value(roundf(SpeedProfile.length_for_duration(60.0, level.base_speed, level.speed_ramp)), "length")
		refresh_level())
	column.add_child(fit)


func _set_level_value(value: float, key: String) -> void:
	if _updating:
		return
	var level := document.level
	document.begin("Edit level " + key, true)
	var simple := _spin_is_simple(level)
	match key:
		"base_speed":
			level.base_speed = value
		"speed_ramp":
			level.speed_ramp = value / 100.0
		"length":
			var last := 0.0
			for hole in level.holes:
				last = maxf(last, hole.s_end())
			level.length = maxf(value, last)
	if key == "length" and simple:
		_apply_spin(level)
	document.changed_from(0.0)
	_update_duration()


func _update_duration() -> void:
	var level := document.level
	_duration_note.text = "Lasts %.1f s, from %.1f to %.1f m/s." % [level.duration(), level.base_speed, level.speed_at(level.length)]


func refresh_level() -> void:
	var level := document.level
	_updating = true
	var name_edit: LineEdit = _level_fields["name"]
	if name_edit.text != level.display_name:
		name_edit.text = level.display_name
	var id_edit: LineEdit = _level_fields["id"]
	if id_edit.text != level.id:
		id_edit.text = level.id
	(_level_fields["base_speed"] as SpinBox).value = level.base_speed
	(_level_fields["speed_ramp"] as SpinBox).value = level.speed_ramp * 100.0
	(_level_fields["length"] as SpinBox).value = level.length
	_updating = false
	_update_duration()
	_refresh_spin()
	_rebuild_palette()


# --- Spin ------------------------------------------------------------------------------
# Ground spin, set like the speed: a direction, how fast at the start, and how
# much faster by the end. Stored as two spin keys (start and finish), so the
# level format and the game are unchanged.

const DIRECTIONS := ["None", "Left", "Right"]


func _build_spin(column: VBoxContainer) -> void:
	column.add_child(EditorTheme.heading("SPIN"))
	column.add_child(EditorTheme.note("How fast the tunnel turns, pushing the ball sideways unless the player leans against it."))
	var grid := GridContainer.new()
	grid.columns = 2
	column.add_child(grid)
	grid.add_child(_label("Direction"))
	_spin_direction = OptionButton.new()
	for name in DIRECTIONS:
		_spin_direction.add_item(name)
	_spin_direction.item_selected.connect(func(_index: int) -> void: _spin_changed("direction"))
	grid.add_child(_spin_direction)
	_spin_rate = _number_row(grid, "Speed (°/s)", 0.0, 180.0, 1.0, func(_v: float) -> void: _spin_changed("rate"))
	_spin_ramp = _number_row(grid, "Speeds up by (%)", 0.0, 300.0, 1.0, func(_v: float) -> void: _spin_changed("ramp"))
	_spin_note = EditorTheme.note("")
	column.add_child(_spin_note)


## True if the level's spin is what these three fields can express: one
## direction, changing evenly from start to finish (or none at all).
static func _spin_is_simple(level: LevelData) -> bool:
	if level.spin.is_empty():
		return true
	if level.spin.size() > 2:
		return false
	var a := level.spin[0]
	var b := level.spin[level.spin.size() - 1]
	return a.s <= 0.01 and (level.spin.size() == 1 or absf(b.s - level.length) < 0.01) and a.rate * b.rate >= 0.0


func _refresh_spin() -> void:
	var level := document.level
	var start := level.spin_at(0.0)
	var end := level.spin_at(level.length)
	var reference := start
	for key in level.spin:
		if absf(reference) > 0.01:
			break
		reference = key.rate
	_updating = true
	_spin_direction.selected = 0 if absf(reference) < 0.01 else (1 if reference < 0.0 else 2)
	# A generator spin starts at 0 °/s and changes along the way: show the
	# first speed it reaches rather than a misleading 0.
	_spin_rate.value = absf(reference)
	_spin_ramp.value = 0.0 if absf(start) < 0.01 or not _spin_is_simple(level) else maxf((absf(end) / absf(start) - 1.0) * 100.0, 0.0)
	_updating = false
	_update_spin_note()


func _update_spin_note() -> void:
	var level := document.level
	var start := level.spin_at(0.0)
	var end := level.spin_at(level.length)
	if _spin_is_simple(level):
		_spin_note.text = "" if level.spin.is_empty() else "From %.0f to %.0f °/s by the finish." % [absf(start), absf(end)]
	else:
		var flips := 0
		for i in range(1, level.spin.size()):
			if level.spin[i].rate * level.spin[i - 1].rate < 0.0:
				flips += 1
		_spin_note.text = "This level's spin was made by the generator: it changes %d times along the way%s. Changing any field above replaces it with one steady spin." % [level.spin.size() - 1, (", %d of them switching direction" % flips) if flips > 0 else ""]


## field: which one the person changed ("direction", "rate" or "ramp").
func _spin_changed(field: String) -> void:
	if _updating:
		return
	# A direction without a speed, or a speed without a direction, would be
	# no spin at all: fill in the missing half instead of ignoring the edit.
	# (The fields keep what was typed; only the level follows them.)
	_updating = true
	if field == "direction" and _spin_direction.selected != 0 and is_zero_approx(_spin_rate.value):
		_spin_rate.value = 20.0
	elif field == "rate" and _spin_direction.selected == 0 and _spin_rate.value > 0.0:
		_spin_direction.select(2)
	_updating = false
	document.begin("Change spin", true)
	_apply_spin(document.level)
	document.changed_from(0.0)
	_update_spin_note()


func _apply_spin(level: LevelData) -> void:
	var sign: float = [0.0, -1.0, 1.0][_spin_direction.selected]
	var start: float = sign * _spin_rate.value
	if is_zero_approx(start):
		level.spin = []
		return
	var end := clampf(start * (1.0 + _spin_ramp.value / 100.0), -180.0, 180.0)
	level.spin = [SpinKey.new(0.0, start), SpinKey.new(level.length, end)]


# --- Colours ---------------------------------------------------------------------------

func _build_palette(column: VBoxContainer) -> void:
	column.add_child(EditorTheme.heading("COLOURS"))
	column.add_child(EditorTheme.note("The tunnel's colour journey, start to finish: wall, void (seen through holes, keep it far from the wall colour) and accent. Each stop sits at a share of the level."))
	_palette_box = VBoxContainer.new()
	column.add_child(_palette_box)
	var add := Button.new()
	add.text = "+ Colour stop"
	add.pressed.connect(func() -> void:
		var level := document.level
		document.begin("Add colour stop")
		var palette := LevelPalette.new(level.palette)
		var at := 0.5
		level.palette.append(PaletteStop.new(at, palette.wall_at(at), palette.void_at(at), palette.accent_at(at)))
		document.changed_from(INF)
		_rebuild_palette())
	column.add_child(add)


func _rebuild_palette() -> void:
	for child in _palette_box.get_children():
		child.queue_free()
	var level := document.level
	for i in level.palette.size():
		var stop := level.palette[i]
		var row := HBoxContainer.new()
		var at := SpinBox.new()
		at.min_value = 0
		at.max_value = 100
		at.suffix = "%"
		at.value = stop.at * 100.0
		at.custom_minimum_size = Vector2(84, 0)
		at.value_changed.connect(func(value: float) -> void:
			document.begin("Move colour stop", true)
			stop.at = value / 100.0
			document.changed_from(INF))
		row.add_child(at)
		for field in ["wall", "void_color", "accent"]:
			var picker := ColorPickerButton.new()
			picker.color = stop.get(field)
			picker.edit_alpha = false
			picker.custom_minimum_size = Vector2(38, 30)
			picker.tooltip_text = {"wall": "Wall", "void_color": "Void", "accent": "Accent"}[field]
			picker.color_changed.connect(func(color: Color) -> void:
				document.begin("Change colour", true)
				stop.set(field, color)
				document.changed_from(INF))
			row.add_child(picker)
		var remove := Button.new()
		remove.text = "✕"
		remove.disabled = level.palette.size() <= 2
		remove.pressed.connect(func() -> void:
			document.begin("Remove colour stop")
			level.palette.erase(stop)
			document.changed_from(INF)
			_rebuild_palette.call_deferred())
		row.add_child(remove)
		_palette_box.add_child(row)


# --- Helpers -------------------------------------------------------------------------------

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	return label


func _number_row(grid: GridContainer, text: String, low: float, high: float, step: float, apply: Callable) -> SpinBox:
	grid.add_child(_label(text))
	var box := SpinBox.new()
	box.min_value = low
	box.max_value = high
	box.step = step
	box.custom_minimum_size = Vector2(120, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Apply while typing, not only on Enter or when the field loses focus.
	box.update_on_text_changed = true
	box.value_changed.connect(apply)
	grid.add_child(box)
	return box


func _action(parent: Control, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
