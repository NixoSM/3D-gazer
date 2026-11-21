class_name LevelEditor
extends Control
## The Gazer level editor: a desktop app built from the game's own code.
##
## Layout, left to right: the whole level (Minimap), the unrolled tunnel
## you edit (StripView, with its time ruler, spin lane and bot lane), the
## game running live (PreviewPanel) and the numbers (InspectorPanel).
##
## Nothing here is a second implementation of the game: levels are
## LevelData saved by LevelSerializer, the analysis plays them with
## BallSimulation and Autopilot, and the preview is GameSession + WorldView.
## So what the editor shows is what the phone will do.
##
## Runs as the main scene of the "Level editor" exports (feature tag
## `level_editor`, see project.godot), or from the Godot editor with this
## scene open (F6). docs/LEVEL_EDITOR.md is the user guide.

const TUNING := preload("res://resources/ball_tuning.tres")
const CONFIG := "user://editor.cfg"
const BUNDLED := "res://levels"
## Seconds of quiet after an edit before the 3D preview rebuilds.
const PREVIEW_DELAY := 0.25
## Seconds between analysis restarts while you keep editing.
const ANALYSIS_DELAY := 0.2

var document := LevelDocument.new()
var analysis := LevelAnalysis.new(TUNING)
var input_router: InputRouter

var _strip: StripView
var _minimap: Minimap
var _preview: PreviewPanel
var _inspector: InspectorPanel
var _status: Label
var _hint: Label
var _tool_buttons := {}
var _snap_toggle: CheckButton
var _reach_toggle: CheckButton
var _follow_toggle: CheckButton
var _file_menu: MenuButton
var _bundled_menu: PopupMenu
var _open_dialog: FileDialog
var _save_dialog: FileDialog
var _confirm: ConfirmationDialog
var _help: AcceptDialog
var _after_confirm: Callable

var _analysis_from := INF
var _analysis_timer := 0.0
var _preview_timer := -1.0
var _last_hover := Vector2(NAN, 0.0)
var _restart_timer := -1.0
var _stop_timer := -1.0


func _ready() -> void:
	_setup_window()
	theme = EditorTheme.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	input_router = InputRouter.new()
	add_child(input_router)
	_build_ui()
	_build_dialogs()
	document.changed.connect(_on_level_changed)
	document.file_state_changed.connect(_update_title)
	get_tree().auto_accept_quit = false
	get_window().files_dropped.connect(_on_files_dropped)
	_open_start_level()
	_strip.reset_zoom()
	_strip.center_on(0.0)
	var config := ConfigFile.new()
	if config.load(CONFIG) != OK or not config.get_value("editor", "seen_help", false):
		_show_help.call_deferred()


func _setup_window() -> void:
	var window := get_window()
	# The game's project settings are for a portrait phone. The editor wants
	# a normal desktop window at the screen's own pixel density.
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var scale := DisplayServer.screen_get_scale()
	if OS.has_feature("windows"):
		scale = DisplayServer.screen_get_dpi() / 96.0
	window.content_scale_factor = clampf(scale, 1.0, 3.0)
	window.title = "Gazer Level Editor"
	if not OS.has_feature("level_editor") and DisplayServer.get_name() != "headless":
		# Started from the Godot editor: the window has the phone's shape.
		var screen := DisplayServer.screen_get_usable_rect()
		var wanted := Vector2i(Vector2(1500, 920) * window.content_scale_factor)
		window.size = Vector2i(mini(wanted.x, screen.size.x), mini(wanted.y, screen.size.y))
		window.position = screen.position + (screen.size - window.size) / 2
	window.min_size = Vector2i(Vector2(1100, 640) * window.content_scale_factor)


# --- UI ------------------------------------------------------------------------

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = EditorTheme.PAPER_DARK
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	column.add_child(_build_toolbar())

	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	var left := HBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 2.2
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)

	_strip = StripView.new()
	_strip.document = document
	_strip.analysis = analysis
	_strip.tuning = TUNING
	_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_strip.custom_minimum_size = Vector2(420, 300)
	_minimap = Minimap.new()
	_minimap.strip = _strip
	_minimap.analysis = analysis
	left.add_child(_minimap)
	left.add_child(_strip)
	_strip.hovered.connect(_on_hovered)
	_strip.play_requested.connect(func(s: float, angle: float) -> void: _play(s, angle))
	_strip.selection_changed.connect(func() -> void:
		_inspector.refresh_selection()
		_strip.queue_redraw_all())
	_strip.status.connect(_set_status)
	_strip.view_changed.connect(func() -> void:
		_minimap.refresh()
		if _follow_toggle.button_pressed != _strip.follow_route:
			_follow_toggle.set_pressed_no_signal(_strip.follow_route))
	_minimap.jump_to.connect(func(s: float) -> void:
		_strip.center_on(s)
		_minimap.refresh())

	var right := HSplitContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	_preview = PreviewPanel.new()
	_preview.custom_minimum_size = Vector2(300, 0)
	right.add_child(_preview)
	_preview.setup(TUNING, input_router)
	_preview.run_ended.connect(_on_run_ended)
	_inspector = InspectorPanel.new()
	_inspector.custom_minimum_size = Vector2(330, 0)
	right.add_child(_inspector)
	_inspector.setup(document, _strip, analysis)
	_inspector.jump_to.connect(func(s: float) -> void:
		_strip.center_on(s)
		_minimap.refresh())
	_inspector.insert_pattern.connect(_insert_pattern)
	_inspector.bots_toggled.connect(_minimap.refresh)

	var status_bar := HBoxContainer.new()
	column.add_child(status_bar)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.clip_text = true
	_status.add_theme_font_size_override("font_size", 15)
	status_bar.add_child(_status)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", EditorTheme.MUTED)
	status_bar.add_child(_hint)
	_update_hint()


func _build_toolbar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	_file_menu = MenuButton.new()
	_file_menu.text = "File"
	_file_menu.flat = false
	var popup := _file_menu.get_popup()
	popup.add_item("New level", 0)
	popup.add_item("Open...", 1)
	_bundled_menu = PopupMenu.new()
	_bundled_menu.name = "Bundled"
	for id in _bundled_ids():
		_bundled_menu.add_item(id)
	_bundled_menu.index_pressed.connect(func(index: int) -> void:
		_confirm_discard(func() -> void: _open_bundled(_bundled_menu.get_item_text(index))))
	popup.add_child(_bundled_menu)
	popup.add_submenu_item("Open a bundled level", "Bundled")
	popup.add_separator()
	popup.add_item("Save", 2)
	popup.add_item("Save as...", 3)
	popup.add_separator()
	popup.add_item("Add to the game's level list", 4)
	popup.add_item("Show the levels folder", 5)
	popup.id_pressed.connect(_on_file_menu)
	bar.add_child(_file_menu)
	_toolbar_button(bar, "Undo", _undo)
	_toolbar_button(bar, "Redo", _redo)
	bar.add_child(VSeparator.new())

	var group := ButtonGroup.new()
	for entry in [[StripView.Tool.SELECT, "Select  V"], [StripView.Tool.HOLE, "Hole  H"], [StripView.Tool.RING, "Ring  R"]]:
		var button := Button.new()
		button.text = entry[1]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = entry[0] == StripView.Tool.SELECT
		var tool: StripView.Tool = entry[0]
		button.pressed.connect(func() -> void: _set_tool(tool))
		bar.add_child(button)
		_tool_buttons[tool] = button
	_snap_toggle = CheckButton.new()
	_snap_toggle.text = "Snap"
	_snap_toggle.button_pressed = true
	_snap_toggle.tooltip_text = "Snap to 0.25 m and 2.5°. Hold Alt (Option) to place freely."
	_snap_toggle.toggled.connect(func(on: bool) -> void: _strip.snap = on)
	bar.add_child(_snap_toggle)
	_reach_toggle = CheckButton.new()
	_reach_toggle.text = "Reach"
	_reach_toggle.button_pressed = true
	_reach_toggle.tooltip_text = "Under the mouse: where a rolling ball can steer to in 1.2 s, and where jumps land."
	_reach_toggle.toggled.connect(func(on: bool) -> void:
		_strip.show_reach = on
		_strip.queue_redraw_all())
	bar.add_child(_reach_toggle)
	_follow_toggle = CheckButton.new()
	_follow_toggle.text = "Follow route"
	_follow_toggle.button_pressed = true
	_follow_toggle.tooltip_text = "Turn the strip so the bots' route stays in the middle, like the game's camera keeps the ball at the bottom. Shift+scroll turns it by hand."
	_follow_toggle.toggled.connect(func(on: bool) -> void: _strip.follow_route = on)
	bar.add_child(_follow_toggle)
	bar.add_child(VSeparator.new())
	_toolbar_button(bar, "Play from start  F5", func() -> void: _play(0.0, 0.0))
	_toolbar_button(bar, "Bot plays  B", _bot_play_from_mouse)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	_toolbar_button(bar, "Help  F1", _show_help)
	return bar


func _toolbar_button(bar: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	bar.add_child(button)
	return button


func _build_dialogs() -> void:
	_open_dialog = FileDialog.new()
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_dialog.use_native_dialog = true
	_open_dialog.filters = PackedStringArray(["*.json ; Gazer level"])
	_open_dialog.file_selected.connect(_open_path)
	add_child(_open_dialog)
	_save_dialog = FileDialog.new()
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_dialog.use_native_dialog = true
	_save_dialog.filters = PackedStringArray(["*.json ; Gazer level"])
	_save_dialog.file_selected.connect(_save_to)
	add_child(_save_dialog)
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Unsaved changes"
	_confirm.dialog_text = "This level has changes that are not saved."
	_confirm.ok_button_text = "Save"
	_confirm.add_button("Don't save", true, "discard")
	_confirm.confirmed.connect(func() -> void:
		_save()
		if not document.dirty and _after_confirm.is_valid():
			_after_confirm.call())
	_confirm.custom_action.connect(func(action: StringName) -> void:
		if action == &"discard":
			_confirm.hide()
			if _after_confirm.is_valid():
				_after_confirm.call())
	add_child(_confirm)
	_help = AcceptDialog.new()
	_help.title = "How the editor works"
	_help.ok_button_text = "Got it"
	_help.confirmed.connect(func() -> void:
		var config := ConfigFile.new()
		config.load(CONFIG)
		config.set_value("editor", "seen_help", true)
		config.save(CONFIG))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.custom_minimum_size = Vector2(720, 0)
	text.add_theme_color_override("default_color", EditorTheme.INK)
	text.add_theme_font_size_override("normal_font_size", 16)
	text.add_theme_font_size_override("bold_font_size", 18)
	text.text = _help_text()
	_help.add_child(text)
	add_child(_help)


func _help_text() -> String:
	var mod := "Cmd" if OS.has_feature("macos") else "Ctrl"
	return """[b]The strip is the tunnel, unrolled.[/b] Distance runs up (the way you travel), the angle runs across: the middle line is the floor where the ball starts, the left and right edges are the ceiling, and they wrap. Holes look exactly as the game cuts them.

[b]You can read a level without playing it.[/b]
• Three bots play it after every edit: [color=#00b4d8]instant[/color], [color=#7b2ff7]quick (0.2 s)[/color] and [color=#ff4f79]relaxed (0.35 s)[/color]. Solid = rolling, dotted = flying, ✕ = where it falls. If the relaxed bot gets through, most people will.
• Every stretch you must jump gets a bracket: green is fine, orange is close to the limit or has no run-up, red cannot be jumped.
• Under the mouse, the white cone is where a rolling ball can steer to in 1.2 s (the dashed line is hands off, so you see the spin push). The yellow bar is where the smallest and biggest jumps land.
• The left ruler counts seconds of play; the lane right of the strip graphs the spin (set it in the inspector).

[b]Editing[/b]  V select · H draw a hole · R place a ring
Drag a hole to move it, the yellow squares to resize, the pink dot to twist it. Shift-click or drag a box to select several. %s-drag copies. Alt (Option) turns snapping off.
%s+D repeats the selection further on · M mirrors it · Delete removes · arrows nudge (Shift = more)
Spin: in the inspector, a direction, a speed and how much it speeds up by the finish.
Scroll to move · %s+scroll to zoom · Shift+scroll to turn the tunnel · middle-drag to pan.

[b]Playing[/b]  Double-click anywhere on the strip to play from there. F5 plays from the start, B lets the quick bot play from the mouse. A/D or arrows tilt, W hops, Space jumps big, S or Down smashes, Esc stops. A fall is marked on the strip and you restart from the same spot.

[b]Files[/b]  Levels are small .json files: send them to each other, or put them in the game's levels/ folder and use File > Add to the game's level list.""" % [mod, mod, mod]


# --- Shortcuts -------------------------------------------------------------------

func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	if _preview.playing:
		if key.keycode == KEY_ESCAPE:
			_stop_play()
			get_viewport().set_input_as_handled()
		return
	var command := key.is_command_or_control_pressed()
	var handled := true
	var nudge_s := 5.0 if key.shift_pressed else 0.5
	var nudge_a := deg_to_rad(15.0 if key.shift_pressed else 2.5)
	match key.keycode:
		KEY_Z when command and key.shift_pressed:
			_redo()
		KEY_Z when command:
			_undo()
		KEY_Y when command:
			_redo()
		KEY_S when command and key.shift_pressed:
			_save_as()
		KEY_S when command:
			_save()
		KEY_O when command:
			_confirm_discard(_open_dialog_at_levels)
		KEY_N when command:
			_confirm_discard(_new_level)
		KEY_D when command:
			_strip.repeat_selection()
		KEY_A when command:
			_strip.select_all_visible()
		KEY_V:
			_set_tool(StripView.Tool.SELECT)
		KEY_H:
			_set_tool(StripView.Tool.HOLE)
		KEY_R:
			_set_tool(StripView.Tool.RING)
		KEY_M:
			_strip.mirror_selection()
		KEY_DELETE, KEY_BACKSPACE:
			_strip.delete_selection()
		KEY_UP:
			_strip.nudge_selection(nudge_s, 0.0)
		KEY_DOWN:
			_strip.nudge_selection(-nudge_s, 0.0)
		KEY_LEFT:
			_strip.nudge_selection(0.0, -nudge_a)
		KEY_RIGHT:
			_strip.nudge_selection(0.0, nudge_a)
		KEY_ESCAPE:
			_strip.selection = []
			_strip.selection_changed.emit()
		KEY_F5:
			_play(0.0, 0.0)
		KEY_B:
			_bot_play_from_mouse()
		KEY_F1:
			_show_help()
		KEY_HOME:
			_strip.center_on(0.0)
		KEY_END:
			_strip.center_on(document.level.length)
		KEY_PAGEUP:
			_strip.s_bottom += _strip.visible_metres() * 0.8
			_strip.center_on(_strip.s_bottom + _strip.visible_metres() * 0.33)
		KEY_PAGEDOWN:
			_strip.s_bottom -= _strip.visible_metres() * 0.8
			_strip.center_on(_strip.s_bottom + _strip.visible_metres() * 0.33)
		_:
			handled = false
	if handled:
		_minimap.refresh()
		get_viewport().set_input_as_handled()


func _set_tool(tool: StripView.Tool) -> void:
	_strip.tool = tool
	(_tool_buttons[tool] as Button).button_pressed = true
	_update_hint()


func _update_hint() -> void:
	match _strip.tool:
		StripView.Tool.SELECT:
			_hint.text = "Drag holes to move · squares resize · pink dot twists · double-click to play from there"
		StripView.Tool.HOLE:
			_hint.text = "Drag a rectangle to cut a hole · Alt: no snapping"
		StripView.Tool.RING:
			_hint.text = "Click for a ring as long as the last one, or drag to set its length"


# --- The loop ------------------------------------------------------------------------

func _process(delta: float) -> void:
	_strip.update_follow(delta)
	if _analysis_from < INF:
		_analysis_timer -= delta
		if _analysis_timer <= 0.0:
			analysis.request(document.level, _analysis_from)
			_analysis_from = INF
			_analysis_timer = ANALYSIS_DELAY
	if analysis.poll():
		_strip.queue_redraw_all()
		_minimap.refresh()
		_inspector.refresh_analysis()
	if _preview_timer >= 0.0:
		_preview_timer -= delta
		if _preview_timer < 0.0:
			_preview.set_level(document.level)
			if not is_nan(_last_hover.x):
				_preview.show_at(_last_hover.x, _last_hover.y)
	if _preview.playing:
		_follow_ball()
	if _restart_timer >= 0.0:
		_restart_timer -= delta
		if _restart_timer < 0.0 and _preview.playing:
			_strip.live_trail.clear()
			_preview.restart()
	if _stop_timer >= 0.0:
		_stop_timer -= delta
		if _stop_timer < 0.0:
			_stop_play()


func _on_level_changed(from_s: float) -> void:
	_strip.level_changed()
	_minimap.level_changed()
	if from_s < INF:
		# Gameplay changed: re-analyse from there, and old falls are stale.
		_analysis_from = minf(_analysis_from, from_s)
		_strip.player_falls.clear()
	_preview_timer = PREVIEW_DELAY


func _on_hovered(s: float, angle: float) -> void:
	_last_hover = Vector2(s, angle)
	if not _preview.playing and _preview_timer < 0.0:
		_preview.show_at(clampf(s, 0.0, document.level.length), angle)


# --- Playtesting -----------------------------------------------------------------

func _play(s: float, angle: float, bot_delay: float = -1.0) -> void:
	if _preview_timer >= 0.0:
		_preview_timer = -1.0
		_preview.set_level(document.level)
	if s > 0.5 and document.level.is_hole(s, angle):
		# Starting over a hole is a fall: start on the bots' route instead.
		for i in [1, 0, 2]:
			var route := analysis.bots[i].angle_at(s)
			if not is_nan(route):
				angle = route
				break
	get_viewport().gui_release_focus()
	_restart_timer = -1.0
	_stop_timer = -1.0
	_strip.live_trail.clear()
	_preview.play(clampf(s, 0.0, document.level.length - 1.0), angle, bot_delay)
	var who := "You're" if bot_delay < 0.0 else "The %.2f s bot is" % bot_delay
	_set_status("%s playing from %.0f m (%.1f s in). Esc stops." % [who, s, document.level.time_at(s)])


func _bot_play_from_mouse() -> void:
	var s := 0.0 if is_nan(_last_hover.x) else maxf(_last_hover.x, 0.0)
	_play(s, 0.0 if is_nan(_last_hover.x) else _last_hover.y, LevelAnalysis.BOT_DELAYS[1])


func _stop_play() -> void:
	_preview.stop()
	_restart_timer = -1.0
	_stop_timer = -1.0
	_strip.live_ball = Vector2(NAN, 0.0)
	_strip.live_trail.clear()
	_strip.queue_redraw_all()
	if not is_nan(_last_hover.x):
		_preview.show_at(clampf(_last_hover.x, 0.0, document.level.length), _last_hover.y)


func _follow_ball() -> void:
	if not _preview.session.simulation.is_alive():
		return  # Falling: leave the marker where the fall began.
	var ball := _preview.ball_position()
	_strip.live_ball = ball
	if _strip.live_trail.is_empty() or ball.x - _strip.live_trail[_strip.live_trail.size() - 1].x > 0.4:
		_strip.live_trail.append(ball)
	# Keep the ball in the lower third of the strip, like the game's camera.
	var target := ball.x - _strip.visible_metres() * 0.3
	if absf(_strip.s_bottom - target) > 0.01:
		_strip.s_bottom = lerpf(_strip.s_bottom, target, 0.35)
		_strip.center_on(_strip.s_bottom + _strip.visible_metres() * 0.33)
	_strip.queue_redraw_all()
	_minimap.refresh()


func _on_run_ended(fell: bool, s: float, angle: float) -> void:
	var level := document.level
	if fell:
		if not _preview.bot_playing:
			_strip.player_falls.append(Vector2(s, angle))
		_set_status("Fell at %.0f m (%.1f s, %d%%). Restarting from the same spot... Esc stops." % [s, level.time_at(s), int(level.progress_at(s) * 100.0)])
		_restart_timer = 0.9
	else:
		_set_status("Made it to the finish!")
		_stop_timer = 1.5


# --- Patterns ------------------------------------------------------------------------

func _insert_pattern(section: Dictionary) -> void:
	var level := document.level
	var s := _last_hover.x if not is_nan(_last_hover.x) else _strip.s_bottom + _strip.visible_metres() * 0.33
	s = clampf(snappedf(s, 0.25), 0.0, level.length - 10.0)
	# Start the pattern's safe path where the relaxed bot actually is.
	var path_angle := 0.0
	for i in range(analysis.bots.size() - 1, -1, -1):
		var angle := analysis.bots[i].angle_at(s)
		if not is_nan(angle):
			path_angle = angle
			break
	document.begin("Insert pattern")
	# Generate on an empty twin of the level (same speed and spin), measure
	# it, make room (everything after s moves on), then copy the holes in.
	var twin := LevelData.new()
	twin.length = level.length
	twin.base_speed = level.base_speed
	twin.speed_ramp = level.speed_ramp
	twin.tunnel_radius = level.tunnel_radius
	twin.spin = level.spin
	twin.speed_keys = level.speed_keys
	var seed := int(Time.get_ticks_usec() % 100000)
	var result := LevelGenerator.new().stamp(twin, TUNING, section, s, path_angle, seed)
	var span: float = float(result["end"]) - s + level.speed_at(s) * 0.8
	for hole in level.holes:
		if hole.s_start >= s:
			hole.s_start += span
	for key in level.spin:
		if key.s >= s:
			key.s += span
	for key in level.speed_keys:
		if key.s >= s:
			key.s += span
	for hint in level.hints:
		if hint.s >= s:
			hint.s += span
	level.length += span
	var added: Array[HoleData] = []
	added.assign(result["holes"])
	level.holes.append_array(added)
	document.changed_from(s)
	_strip.selection = added
	_strip.selection_changed.emit()
	_set_status("Inserted %d × %s (%.1f s). Everything after it moved %.0f m further on; the level is now %.1f s long." % [
		int(section["n"]), str(section["p"]).replace("_", " "), span / level.speed_at(s), span, level.duration()])
	_inspector.refresh_level()


# --- Files -------------------------------------------------------------------------------

## Where level files live: the repository's levels/ when running from
## source, otherwise a "Gazer Levels" folder in Documents, seeded with the
## bundled levels on first use.
func _levels_folder() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path(BUNDLED)
	var documents := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if documents.is_empty():
		documents = OS.get_user_data_dir()
	var folder := documents.path_join("Gazer Levels")
	if not DirAccess.dir_exists_absolute(folder):
		DirAccess.make_dir_recursive_absolute(folder)
		for file in DirAccess.get_files_at(BUNDLED):
			if file.ends_with(".json"):
				var text := FileAccess.get_file_as_string(BUNDLED.path_join(file))
				var out := FileAccess.open(folder.path_join(file), FileAccess.WRITE)
				if out:
					out.store_string(text)
	return folder


func _bundled_ids() -> PackedStringArray:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(BUNDLED.path_join("manifest.json")))
	var ids := PackedStringArray()
	if typeof(manifest) == TYPE_DICTIONARY:
		for id in manifest.get("levels", []):
			ids.append(str(id))
	return ids


func _open_start_level() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG) == OK:
		var last: String = config.get_value("editor", "last_file", "")
		if not last.is_empty() and FileAccess.file_exists(last) and _open_path(last):
			return
	var folder := _levels_folder()
	var ids := _bundled_ids()
	if not ids.is_empty() and FileAccess.file_exists(folder.path_join(ids[0] + ".json")):
		_open_path(folder.path_join(ids[0] + ".json"))
	else:
		_new_level()


func _on_file_menu(id: int) -> void:
	match id:
		0:
			_confirm_discard(_new_level)
		1:
			_confirm_discard(_open_dialog_at_levels)
		2:
			_save()
		3:
			_save_as()
		4:
			_set_status(document.add_to_manifest())
		5:
			OS.shell_open(_levels_folder())


func _new_level() -> void:
	_stop_play()
	document.replace(LevelDocument.new_level(), "")
	_after_load()
	_set_status("New level. Draw holes with H, rings with R; double-click to try it.")


func _open_dialog_at_levels() -> void:
	_open_dialog.current_dir = _levels_folder()
	_open_dialog.popup_centered_ratio(0.6)


func _open_bundled(id: String) -> void:
	var path := _levels_folder().path_join(id + ".json")
	if FileAccess.file_exists(path):
		_open_path(path)
		return
	var result := LevelSerializer.load_file(BUNDLED.path_join(id + ".json"))
	if result.level:
		document.replace(result.level, "")
		_after_load()
		_set_status("Opened the bundled %s. Save it somewhere to keep your changes." % id)


func _open_path(path: String) -> bool:
	var result := LevelDocument.open(path)
	if result.level == null:
		_set_status("Could not open %s: %s" % [path.get_file(), "; ".join(result.errors)])
		return false
	_stop_play()
	document.replace(result.level, path)
	_after_load()
	_remember_file(path)
	var problems := "" if result.errors.is_empty() else "  Warnings: " + "; ".join(result.errors)
	_set_status("Opened %s.%s" % [path, problems])
	return true


func _after_load() -> void:
	_strip.selection = []
	_inspector.set_document(document)
	_strip.reset_zoom()
	_strip.center_on(0.0)
	_preview_timer = 0.0


func _save() -> void:
	if document.path.is_empty():
		_save_as()
		return
	_save_to(document.path)


func _save_as() -> void:
	_save_dialog.current_dir = _levels_folder() if document.path.is_empty() else document.path.get_base_dir()
	_save_dialog.current_file = document.level.id + ".json"
	_save_dialog.popup_centered_ratio(0.6)


func _save_to(path: String) -> void:
	if not path.ends_with(".json"):
		path += ".json"
	var error := document.save(path)
	if error == OK:
		_remember_file(path)
		_set_status("Saved %s." % path)
	else:
		_set_status("Could not save %s (%s)." % [path, error_string(error)])


func _remember_file(path: String) -> void:
	var config := ConfigFile.new()
	config.load(CONFIG)
	config.set_value("editor", "last_file", path)
	config.save(CONFIG)


func _on_files_dropped(files: PackedStringArray) -> void:
	for file in files:
		if file.ends_with(".json"):
			_confirm_discard(func() -> void: _open_path(file))
			return


## Runs `then` now, or after asking about unsaved changes.
func _confirm_discard(then: Callable) -> void:
	if not document.dirty:
		then.call()
		return
	_after_confirm = then
	_confirm.popup_centered()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_confirm_discard(func() -> void:
			analysis.shutdown()
			get_tree().quit())


func _undo() -> void:
	var label := document.undo()
	_set_status("Undid: %s" % label if not label.is_empty() else "Nothing to undo.")
	_inspector.refresh_level()
	_inspector.refresh_selection()


func _redo() -> void:
	var label := document.redo()
	_set_status("Redid: %s" % label if not label.is_empty() else "Nothing to redo.")
	_inspector.refresh_level()
	_inspector.refresh_selection()


func _update_title() -> void:
	get_window().title = "Gazer Level Editor — " + document.display_title()


func _set_status(text: String) -> void:
	_status.text = text


func _show_help() -> void:
	_help.popup_centered()


func _exit_tree() -> void:
	analysis.shutdown()
