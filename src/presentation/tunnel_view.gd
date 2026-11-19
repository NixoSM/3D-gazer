class_name TunnelView
extends Node3D
## Streams tunnel chunks around the camera and feeds the tunnel shaders.
##
## A chunk is one mesh built by TunnelMesher: the floor with its holes cut
## out (tunnel_floor.gdshader) and the shell's cut faces (tunnel_wall.gdshader).
## Only the stretch near the camera exists: chunks are built ahead of the
## player on worker threads and freed behind, so level length has no effect
## on memory or draw cost. The first chunks of the level are kept, so a
## retry (which jumps back to the start) never waits for geometry.

const CHUNK_LENGTH := 18.0
const BEHIND := 1
## How far ahead geometry exists. Keep above the shaders' fog distance.
const VIEW_DISTANCE := 150.0
## Chunks this close to the camera are built on the spot if no worker has
## delivered them yet (the camera must never see a missing chunk).
const MUST_HAVE := 2
const MAX_WORKERS := 3
## Chunks up to this index stay built for the whole level (fast retries).
const KEEP_FIRST := 9
const MAX_RIPPLES := 6

var level: LevelData
var palette: LevelPalette
var floor_material: ShaderMaterial
var wall_material: ShaderMaterial

var _chunks := {}    # chunk index -> MeshInstance3D (in the tree)
var _kept := {}      # chunk index -> ArrayMesh, the start of the level
var _tasks := {}     # chunk index -> WorkerThreadPool task id
var _results := {}   # chunk index -> TunnelMesher.Geometry (filled by workers)
var _mutex := Mutex.new()
## Bumped on every level change, so late results for an old level are dropped.
var _generation := 0
var _ripples: Array[Vector4] = []
var _next_ripple := 0


func _ready() -> void:
	floor_material = ShaderMaterial.new()
	floor_material.shader = preload("res://shaders/tunnel_floor.gdshader")
	floor_material.set_shader_parameter("outline_width", TunnelMesher.OUTLINE_WIDTH)
	wall_material = ShaderMaterial.new()
	wall_material.shader = preload("res://shaders/tunnel_wall.gdshader")
	_ripples.resize(MAX_RIPPLES)


func _exit_tree() -> void:
	_wait_for_workers()


func set_level(p_level: LevelData, p_palette: LevelPalette, tuning: BallTuning) -> void:
	_wait_for_workers()
	_generation += 1
	level = p_level
	palette = p_palette
	# Warm LevelData's lazy cache here, before worker threads read it.
	level.first_hole_index_near(0.0)
	_clear_chunks()
	_kept.clear()
	clear_ripples()
	_set_both("wall_gradient", palette.wall_texture)
	floor_material.set_shader_parameter("accent_gradient", palette.accent_texture)
	_set_both("level_length", level.length)
	_set_both("tunnel_radius", level.tunnel_radius)
	_set_both("band_length", band_length_for(level))
	floor_material.set_shader_parameter("ball_radius", tuning.ball_radius)


## Faster levels get shorter tiles, so the floor streams past noticeably
## quicker than the speed difference alone would suggest.
static func band_length_for(p_level: LevelData) -> float:
	return clampf(3.0 - (p_level.base_speed - 13.65) * 0.14, 1.8, 3.0)


## Range of chunk indices that should exist for a camera at `camera_s`.
static func wanted_range(camera_s: float) -> Vector2i:
	var first := int(floor(camera_s / CHUNK_LENGTH)) - BEHIND
	var last := int(floor((camera_s + VIEW_DISTANCE) / CHUNK_LENGTH))
	return Vector2i(first, last)


## Call every frame with the camera's distance along the tunnel.
func update_view(camera_s: float, ball_s: float, ball_angle: float, ball_height: float, now: float) -> void:
	if level == null:
		return
	var wanted := wanted_range(camera_s)
	for index in _chunks.keys():
		if index < wanted.x or index > wanted.y:
			_chunks[index].queue_free()
			_chunks.erase(index)
	_collect_results()
	for index in range(wanted.x, wanted.y + 1):
		if _chunks.has(index):
			continue
		if _kept.has(index):
			_add_chunk(index, _kept[index])
		elif index <= wanted.x + BEHIND + MUST_HAVE:
			_add_chunk(index, _build_now(index))
		elif not _tasks.has(index) and _tasks.size() < MAX_WORKERS:
			_dispatch(index)

	floor_material.set_shader_parameter("ball", Vector3(ball_s, ball_angle, ball_height))
	floor_material.set_shader_parameter("now", now)


## Builds every chunk the camera could see right now, synchronously (tools
## and tests that capture a single frame). Returns the chunk range.
func build_visible_now(camera_s: float) -> Vector2i:
	_wait_for_workers()
	_collect_results()
	var wanted := wanted_range(camera_s)
	for index in _chunks.keys():
		if index < wanted.x or index > wanted.y:
			_chunks[index].queue_free()
			_chunks.erase(index)
	for index in range(wanted.x, wanted.y + 1):
		if not _chunks.has(index):
			_add_chunk(index, _kept[index] if _kept.has(index) else _build_now(index))
	return wanted


func set_best_marker(s: float) -> void:
	floor_material.set_shader_parameter("best_s", s)


func set_fog(color: Color) -> void:
	_set_both("fog_color", color)


func set_fade(amount: float, color: Color) -> void:
	_set_both("fade", amount)
	_set_both("fade_color", color)


## Starts a ripple at a point on the wall. strength ~0.3 (soft) .. 1.5 (huge).
func add_ripple(s: float, angle: float, now: float, strength: float) -> void:
	_ripples[_next_ripple] = Vector4(s, angle, now, strength)
	_next_ripple = (_next_ripple + 1) % MAX_RIPPLES
	floor_material.set_shader_parameter("ripples", _ripples)


func clear_ripples() -> void:
	for i in MAX_RIPPLES:
		_ripples[i] = Vector4.ZERO
	floor_material.set_shader_parameter("ripples", _ripples)


## Triangles currently in the scene (performance budget tests).
func triangle_count() -> int:
	var total := 0
	for index in _chunks:
		var mesh: ArrayMesh = _chunks[index].mesh
		for surface in mesh.get_surface_count():
			total += mesh.surface_get_array_index_len(surface) / 3
	return total


func _set_both(parameter: String, value: Variant) -> void:
	floor_material.set_shader_parameter(parameter, value)
	wall_material.set_shader_parameter(parameter, value)


func _clear_chunks() -> void:
	for index in _chunks.keys():
		_chunks[index].queue_free()
	_chunks.clear()
	_mutex.lock()
	_results.clear()
	_mutex.unlock()


func _chunk_span(index: int) -> Vector2:
	return Vector2(index * CHUNK_LENGTH, (index + 1) * CHUNK_LENGTH)


func _build_now(index: int) -> ArrayMesh:
	var span := _chunk_span(index)
	var mesh := TunnelMesher.to_mesh(TunnelMesher.build(level, span.x, span.y), floor_material, wall_material)
	if index <= KEEP_FIRST:
		_kept[index] = mesh
	return mesh


func _add_chunk(index: int, mesh: ArrayMesh) -> void:
	var instance := MeshInstance3D.new()
	instance.name = "Chunk%d" % index
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	_chunks[index] = instance


func _dispatch(index: int) -> void:
	var span := _chunk_span(index)
	var generation := _generation
	var built_level := level
	_tasks[index] = WorkerThreadPool.add_task(func() -> void:
		var geometry := TunnelMesher.build(built_level, span.x, span.y)
		_mutex.lock()
		if generation == _generation:
			_results[index] = geometry
		_mutex.unlock(), false, "Tunnel chunk %d" % index)


## Turns finished worker results into chunks (meshes are made on the main thread).
func _collect_results() -> void:
	for index in _tasks.keys():
		var task: int = _tasks[index]
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
			_tasks.erase(index)
	_mutex.lock()
	var ready := _results.duplicate()
	_results.clear()
	_mutex.unlock()
	for index in ready:
		var mesh := TunnelMesher.to_mesh(ready[index], floor_material, wall_material)
		if index <= KEEP_FIRST:
			_kept[index] = mesh
		if not _chunks.has(index):
			_add_chunk(index, mesh)


func _wait_for_workers() -> void:
	for index in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[index])
	_tasks.clear()
