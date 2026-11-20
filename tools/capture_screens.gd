extends Node
## Renders reference screenshots of the menu and of gameplay moments.
##
##   godot res://tools/capture_screens.tscn -- <output_dir>
##
## Needs a real renderer (not --headless). On Linux CI use xvfb-run. The
## shots let reviewers see visual changes without building to a phone.

var _main: Node
var _out := "user://screens"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_run.call_deferred()


func _run() -> void:
	await _frames(30)
	await _shot("01_menu")

	_main._play_level(0)
	var session: GameSession = _main.session
	var world: WorldView = _main.world
	await _frames(5)
	session.stop_run()
	_main.hud.visible = true
	var level := session.level
	# A tour of moments, driven by placing the ball directly.
	var moments := [
		["02_start", 30.0, 0.0, 0.0],
		["03_holes_ahead", _first_hole_s(level) - 18.0, 0.0, 0.0],
		["04_up_the_wall", level.length * 0.35, deg_to_rad(120.0), 0.0],
		["05_jump", level.length * 0.55, deg_to_rad(-60.0), 1.8],
		["06_late", level.length * 0.85, deg_to_rad(200.0), 0.0],
	]
	for m in moments:
		_place(session, world, m[1], m[2], m[3])
		await _frames(20)
		await _shot(m[0])

	# Echo ripple, a few frames after it starts.
	_place(session, world, level.length * 0.45, deg_to_rad(30.0), 0.0)
	await _frames(10)
	world.tunnel.add_ripple(level.length * 0.45, deg_to_rad(30.0), world.now(), 1.2)
	world.ball.flash(0.8, world.palette.accent_at(0.45))
	await _frames(14)
	await _shot("07_echo_ripple")
	await _frames(16)
	await _shot("08_echo_ripple_wrapping")

	for i in range(1, _main.levels.size()):
		_main._select_level(i)
		_place(session, world, _main.levels[i].length * 0.5, deg_to_rad(40.0), 0.0)
		await _frames(25)
		await _shot("09_level_%d" % (i + 1))

	# Overlays, which have their own portrait and landscape layouts.
	_main.hud.visible = false
	_main.pause_screen.visible = true
	await _frames(5)
	await _shot("10_pause")
	_main.pause_screen.visible = false
	_main.results.present(_main.levels[0].display_name, 3, 4, true)
	_main.results.visible = true
	await _frames(5)
	await _shot("11_results")
	get_tree().quit(0)


func _first_hole_s(level: LevelData) -> float:
	return level.holes[0].s_start if not level.holes.is_empty() else 50.0


func _place(session: GameSession, world: WorldView, s: float, angle: float, height: float) -> void:
	var sim := session.simulation
	sim.s = s
	sim.angle = TunnelMath.wrap_angle_positive(angle)
	sim.height = height
	sim.forward_speed = session.level.speed_at(s)
	session._previous = Vector3(s, sim.angle, height)
	session._sync_view(1.0)
	world.camera.snap(s)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := _out.path_join(name + ".png")
	image.save_png(path)
	print("saved ", path)
