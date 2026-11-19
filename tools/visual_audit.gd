extends Node
## Material-ID renders of the tunnel for the pixel oracle (tools/visual_oracle.py).
##
##   xvfb-run -a godot --rendering-driver vulkan --rendering-method mobile \
##       --resolution 585x1266 res://tools/visual_audit.tscn -- <output_dir> [bot_step_s] [levels|all] [msaa]
##
## For every bundled level it renders designed views (approaching, beside,
## under and over holes of every kind: rings, gates, twisted holes, the
## narrowest and widest) and views along an Autopilot run, every `bot_step_s`
## seconds (default 1.5). The tunnel shaders draw flat material IDs instead
## of colours (gazer_debug_ids = 1), MSAA is off and the ball, HUD and
## effects are hidden, so every pixel is exactly one material.
##
## Next to each PNG goes a JSON file with the camera (transform and
## projection) and the stretch of tunnel that was built. The oracle ray-casts
## the same view from the level file alone and reports every pixel that
## disagrees. `levels` is an optional comma-separated list of level indices.
## `msaa` keeps the game's 4x MSAA on (the oracle then accepts blended
## colours along real edges, and still catches anything stray elsewhere).
##
## Use the Mobile renderer (Vulkan; lavapipe in the cloud): it is the one
## the iPhone runs.

const SHOT_FRAMES := 2

var _main: Node
var _out := "user://visual_audit"
var _bot_step := 1.5
var _only: Array[int] = []
var _msaa := false
var _count := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	if args.size() > 1:
		_bot_step = float(args[1])
	if args.size() > 2 and args[2] != "all":
		for part in args[2].split(","):
			_only.append(int(part))
	_msaa = args.size() > 3 and args[3] == "msaa"
	DirAccess.make_dir_recursive_absolute(_out)
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	_run.call_deferred()


func _run() -> void:
	await _frames(10)
	get_viewport().msaa_3d = Viewport.MSAA_4X if _msaa else Viewport.MSAA_DISABLED
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	RenderingServer.global_shader_parameter_set("gazer_debug_ids", 1)
	_main.get_node("UI").visible = false
	var session: GameSession = _main.session
	var world: WorldView = _main.world
	world.camera.speed_rumble = 0.0
	for index in _main.levels.size():
		if not _only.is_empty() and not _only.has(index):
			continue
		_main._play_level(index)
		await _frames(3)
		session.stop_run()
		var level: LevelData = session.level
		for pose in _designed_poses(level) + _bot_poses(level):
			await _render(session, world, level, pose)
	print("visual_audit: %d frames in %s" % [_count, _out])
	get_tree().quit(0)


## Views chosen to look at every kind of edge from close up.
func _designed_poses(level: LevelData) -> Array:
	var picks: Array[HoleData] = []
	var ring := _first(level, func(h: HoleData) -> bool: return h.is_ring())
	var gate := _first(level, func(h: HoleData) -> bool: return not h.is_ring() and h.twist == 0.0)
	for hole in [ring, gate]:
		if hole:
			picks.append(hole)
	var twisted := level.holes.filter(func(h: HoleData) -> bool: return h.twist != 0.0)
	for i in mini(twisted.size(), 3):
		picks.append(twisted[i * twisted.size() / 3])
	var gates := level.holes.filter(func(h: HoleData) -> bool: return not h.is_ring())
	if not gates.is_empty():
		gates.sort_custom(func(a: HoleData, b: HoleData) -> bool: return a.angle_width < b.angle_width)
		picks.append(gates[0])
		picks.append(gates[-1])
	var poses := []
	for i in picks.size():
		var hole: HoleData = picks[i]
		var edge := hole.angle_center + hole.angle_width * 0.5
		var tag := "h%d" % i
		poses.append([tag + "_approach", hole.s_start - 6.0, edge + 0.3, 0.0])
		poses.append([tag + "_beside", hole.s_start + hole.length * 0.5 - 2.0, hole.center_at(hole.s_start + hole.length * 0.5) + hole.angle_width * 0.5 + 0.2, 0.0])
		poses.append([tag + "_overhead", hole.s_start - 3.0, hole.angle_center + PI, 0.0])
		poses.append([tag + "_over", hole.s_start + 0.4, hole.angle_center, 0.0])
		poses.append([tag + "_jump", hole.s_start - 1.0, hole.angle_center + 0.5, 2.2])
	return poses


## Where an Autopilot run actually goes, sampled every `_bot_step` seconds.
func _bot_poses(level: LevelData) -> Array:
	var tuning: BallTuning = load("res://resources/ball_tuning.tres")
	var sim := BallSimulation.new(level, tuning)
	var bot := Autopilot.new(level, tuning)
	var poses := []
	var next := 0.5
	while sim.is_playing() and sim.time < 200.0:
		sim.step(1.0 / 120.0, bot.decide(sim))
		if sim.time >= next:
			poses.append(["bot_%05.1f" % sim.time, sim.s, sim.angle, sim.height])
			next += _bot_step
	return poses


func _render(session: GameSession, world: WorldView, level: LevelData, pose: Array) -> void:
	_place(session, world, pose[1], pose[2], pose[3])
	await _frames(SHOT_FRAMES)
	var chunks := world.tunnel.build_visible_now(-world.camera.global_position.z)
	for child in world.get_children():
		if child is Node3D and child != world.tunnel and child != world.camera and child.name != "VoidBackdrop":
			child.visible = false
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var name := "%s_%s" % [level.id, pose[0]]
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))
	var camera := world.camera
	var t := camera.global_transform
	var p := camera.get_camera_projection()
	var info := {
		"level": level.id,
		"pose": {"name": pose[0], "s": pose[1], "angle": pose[2], "height": pose[3]},
		"size": [get_viewport().size.x, get_viewport().size.y],
		"basis": [_v3(t.basis.x), _v3(t.basis.y), _v3(t.basis.z)],
		"origin": _v3(t.origin),
		"projection": [_v4(p.x), _v4(p.y), _v4(p.z), _v4(p.w)],
		"near": camera.near,
		"far": camera.far,
		"chunks": [chunks.x, chunks.y],
		"chunk_length": TunnelView.CHUNK_LENGTH,
		"tunnel_radius": level.tunnel_radius,
		"shell_thickness": TunnelMath.WALL_THICKNESS,
		"outline_width": TunnelMesher.OUTLINE_WIDTH,
		"outline_max_screen": _floor_parameter(world, "outline_max_screen"),
		"outline_min_pixels": _floor_parameter(world, "outline_min_pixels"),
		"outline_max_width": _floor_parameter(world, "outline_max_width"),
		"plain_distance": TunnelMesher.PLAIN_DISTANCE,
		"msaa": get_viewport().msaa_3d != Viewport.MSAA_DISABLED,
		"back_line": world.tunnel.wall_material.get_shader_parameter("back_line"),
		"triangles": world.tunnel.triangle_count(),
	}
	var file := FileAccess.open(_out.path_join(name + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(info, "  "))
	_count += 1


## A floor shader uniform, set or default.
func _floor_parameter(world: WorldView, name: String) -> float:
	var value = world.tunnel.floor_material.get_shader_parameter(name)
	if value == null:
		value = RenderingServer.shader_get_parameter_default(world.tunnel.floor_material.shader.get_rid(), name)
	return float(value)


func _first(level: LevelData, test: Callable) -> HoleData:
	for hole in level.holes:
		if test.call(hole):
			return hole
	return null


func _place(session: GameSession, world: WorldView, s: float, angle: float, height: float) -> void:
	var sim := session.simulation
	sim.reset()
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


func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func _v4(v: Vector4) -> Array:
	return [v.x, v.y, v.z, v.w]
