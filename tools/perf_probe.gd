extends Node
## Rough cost probe: average frame time, triangles and draw calls at the
## view with the most floor and the one with the most void ahead, per level.
## Absolute times are meaningless on a software renderer; read the ratios.
##
##   xvfb-run godot --rendering-driver opengl3 --resolution 585x1266 res://tools/perf_probe.tscn

var _main: Node


func _ready() -> void:
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
		# The view with the most void ahead, and one with the least.
		var best_s := 0.0
		var best_open := -1.0
		var least_s := 0.0
		var least_open := INF
		var s := 30.0
		while s < level.length - 30.0:
			var open := 0
			for k in 20:
				for j in 12:
					if level.is_hole(s + k * 1.5, TAU * j / 12.0, 0.0):
						open += 1
			if open > best_open:
				best_open = open
				best_s = s
			if open < least_open:
				least_open = open
				least_s = s
			s += 5.0
		for spot in [[least_s, "floor"], [best_s, "void"]]:
			_place(session, world, spot[0], 0.0)
			world.tunnel.build_visible_now(-world.camera.global_position.z)
			await _frames(5)
			var start := Time.get_ticks_usec()
			await _frames(20)
			var ms := (Time.get_ticks_usec() - start) / 20000.0
			var drawn := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
			var calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			print("L%d %-5s %.1f ms/frame  %d triangles in scene, %d drawn, %d draw calls" % [index + 1, spot[1], ms, world.tunnel.triangle_count(), drawn, calls])
			if OS.get_cmdline_user_args().size() > 0:
				get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0] + "/L%d_%s.png" % [index + 1, spot[1]])
	get_tree().quit(0)


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
