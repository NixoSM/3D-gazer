extends Node
## Close-up renders for checking rendering quality (edges, outlines, stray
## lines) and the hole-edge fall, at phone resolution.
##
##   xvfb-run godot --rendering-driver opengl3 --resolution 1170x2532 --fixed-fps 60 \
##       res://tools/render_audit.tscn -- <output_dir>

var _main: Node
var _out := "user://audit"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_run.call_deferred()


func _run() -> void:
	await _frames(10)
	var session: GameSession = _main.session
	var world: WorldView = _main.world
	for index in _main.levels.size():
		_main._play_level(index)
		await _frames(3)
		session.stop_run()
		var level: LevelData = session.level
		var ring := _first_hole(level, true)
		var gate := _first_hole(level, false)
		if ring:
			_place(session, world, ring.s_start - 6.0, 0.0)
			await _frames(12)
			await _shot("L%d_ring_close" % (index + 1))
		if gate:
			_place(session, world, gate.s_start - 3.0, gate.angle_center + gate.angle_width * 0.5 + 0.25)
			await _frames(12)
			await _shot("L%d_gate_edge" % (index + 1))
		_place(session, world, level.length * 0.6, 1.0)
		await _frames(12)
		await _shot("L%d_mid" % (index + 1))

	# Twisted holes (corkscrews and bridges), seen from just before them.
	_main._play_level(2)
	await _frames(3)
	session.stop_run()
	var twisted := 0
	for hole in session.level.holes:
		if hole.twist != 0.0 and twisted < 2:
			_place(session, world, hole.s_start - 4.0, hole.angle_center + PI)
			await _frames(12)
			await _shot("L3_twist_%d" % twisted)
			twisted += 1

	# The floor looks to choose from, on the same Tide view.
	_main._play_level(1)
	await _frames(3)
	session.stop_run()
	var spot := _first_hole(session.level, false)
	for pattern in 5:
		world.tunnel.pattern = pattern
		_place(session, world, spot.s_start - 7.0, spot.angle_center + PI + 0.3)
		await _frames(12)
		await _shot("pattern_%d" % pattern)
	world.tunnel.pattern = 1

	# Cut-face textures to choose from: a gate edge, a corkscrew, a ring.
	for style in 4:
		world.tunnel.face_style = style
		_main._play_level(1)
		await _frames(3)
		session.stop_run()
		var gate := _first_hole(session.level, false)
		_place(session, world, gate.s_start - 3.0, gate.angle_center + gate.angle_width * 0.5 + 0.25)
		await _frames(12)
		await _shot("face_%d_gate" % style)
		_main._play_level(2)
		await _frames(3)
		session.stop_run()
		for hole in session.level.holes:
			if hole.twist != 0.0:
				_place(session, world, hole.s_start - 4.0, hole.angle_center + PI)
				break
		await _frames(12)
		await _shot("face_%d_twist" % style)
		_main._play_level(0)
		await _frames(3)
		session.stop_run()
		var ring := _first_hole(session.level, true)
		_place(session, world, ring.s_start - 2.5, 0.0)
		await _frames(12)
		await _shot("face_%d_ring" % style)
	world.tunnel.face_style = 1

	# The fall: roll straight into the first ring of level 1, frame by frame.
	_main._play_level(0)
	await _frames(3)
	var ring1 := _first_hole(session.level, true)
	_place(session, world, ring1.s_start - 3.0, 0.0)
	session.running = true
	for i in 9:
		await _frames(3)
		await _shot("fall_%d" % i)
	get_tree().quit(0)


func _first_hole(level: LevelData, ring: bool) -> HoleData:
	for hole in level.holes:
		if (hole.angle_width >= TAU - 0.01) == ring:
			return hole
	return null


func _place(session: GameSession, world: WorldView, s: float, angle: float) -> void:
	var sim := session.simulation
	sim.reset()
	sim.s = s
	sim.angle = TunnelMath.wrap_angle_positive(angle)
	sim.forward_speed = session.level.speed_at(s)
	session._previous = Vector3(s, sim.angle, 0.0)
	session._sync_view(1.0)
	world.camera.snap(s)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(_out.path_join(name + ".png"))
