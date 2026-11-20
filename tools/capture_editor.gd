extends Node
## Screenshots of the level editor, for docs and visual review.
##
##   xvfb-run godot --rendering-driver opengl3 --resolution 1600x960 \
##       res://tools/capture_editor.tscn -- <output_dir> [level_id]
##
## Opens a bundled level, waits for the analysis bots to finish, then
## captures the editor idle, with the mouse over a busy stretch, with a
## hole selected, and during a playtest.

var _out := "user://editor_shots"
var _level_id := "02_bubblegum"
var _editor: LevelEditor


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_level_id = args[1]
	DirAccess.make_dir_recursive_absolute(_out)
	_editor = load("res://src/editor/level_editor.tscn").instantiate()
	add_child(_editor)
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	_editor._help.hide()
	_editor._open_bundled(_level_id)
	await _frames(5)
	# Wait for the bots (they run on threads).
	var waited := 0
	while (_editor.analysis.busy or _editor.analysis.report == null) and waited < 3000:
		await _frames(1)
		waited += 1
	await _frames(3)
	var strip := _editor._strip
	var level := _editor.document.level
	# Somewhere with something going on: the first hole after 25% of the level.
	var focus := level.length * 0.25
	for hole in level.holes:
		if hole.s_start > focus:
			focus = hole.s_start
			break
	strip.center_on(focus - 4.0)
	await _frames(3)
	await _shot("editor_overview")

	var hole := level.holes_between(focus, focus + 1.0)[0]
	# Hover where the quick bot rolls, a little before the hole: on floor.
	var hover_s := focus - 8.0
	var hover_angle := _editor.analysis.bots[1].angle_at(hover_s)
	if is_nan(hover_angle):
		hover_angle = 0.0
	var mouse := strip.global_position + strip.to_screen(hover_s, hover_angle)
	_move(mouse)
	await _frames(8)
	await _shot("editor_hover")

	strip.selection = [hole]
	strip.selection_changed.emit()
	await _frames(3)
	await _shot("editor_selected")

	# The spin, set like the speed: right, 30 °/s, +50% by the finish.
	var inspector := _editor._inspector
	# Through the fields' own signals, as a click and typing would.
	inspector._spin_direction.select(2)
	inspector._spin_direction.item_selected.emit(2)
	inspector._spin_rate.value = 30.0
	inspector._spin_ramp.value = 50.0
	var scroll: ScrollContainer = inspector.get_child(0)
	scroll.ensure_control_visible(inspector._spin_note)
	await _frames(5)
	await _shot("editor_spin")

	var start := focus - 30.0
	var start_angle := _editor.analysis.bots[1].angle_at(start)
	_editor._play(start, 0.0 if is_nan(start_angle) else start_angle, 0.2)
	await _frames(60)
	await _shot("editor_playtest")
	get_tree().quit(0)


func _move(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	get_viewport().push_input(event)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(_out.path_join(name + ".png"))
	print("saved ", name)
