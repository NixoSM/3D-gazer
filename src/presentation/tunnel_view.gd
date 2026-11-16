class_name TunnelView
extends Node3D
## Streams tunnel chunks around the camera and feeds the tunnel shaders.
##
## Each chunk is two tubes: the inner surface (tunnel.gdshader, floor and
## holes) and, just outside it, the shell's outer surface
## (tunnel_shell.gdshader), which draws the cut faces seen through holes
## and so gives the shell its thickness.
##
## Only the stretch near the camera exists as geometry: chunks are built
## ahead of the player and freed behind, so level length has no effect on
## memory or draw cost.

const CHUNK_LENGTH := 18.0
const BEHIND := 1
## How far ahead geometry exists. Keep above the shader's fog distance.
const VIEW_DISTANCE := 150.0
const MAX_BUILDS_PER_FRAME := 2
const MAX_RIPPLES := 6

var level: LevelData
var palette: LevelPalette
var material: ShaderMaterial
var shell_material: ShaderMaterial
## Thickness (m) the cut faces are drawn with. Defaults to the shell the
## simulation uses; changing it rebuilds the chunks (for look tests).
var shell_thickness := TunnelMath.WALL_THICKNESS:
	set(value):
		shell_thickness = value
		if shell_material:
			shell_material.set_shader_parameter("shell_thickness", value)
		_clear_chunks()

## Floor look (see tunnel.gdshader `pattern`): 0 bands, 1 tiles, 2 stripes, 3 diamonds, 4 plain.
var pattern := 1:
	set(value):
		pattern = value
		if material:
			material.set_shader_parameter("pattern", value)

var _chunks := {}  # chunk index -> MeshInstance3D
var _ripples: Array[Vector4] = []
var _next_ripple := 0


func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/tunnel.gdshader")
	shell_material = ShaderMaterial.new()
	shell_material.shader = preload("res://shaders/tunnel_shell.gdshader")
	shell_material.set_shader_parameter("shell_thickness", shell_thickness)
	_ripples.resize(MAX_RIPPLES)


func set_level(p_level: LevelData, p_palette: LevelPalette, tuning: BallTuning) -> void:
	level = p_level
	palette = p_palette
	_clear_chunks()
	clear_ripples()
	_set_both("wall_gradient", palette.wall_texture)
	material.set_shader_parameter("accent_gradient", palette.accent_texture)
	_set_both("level_length", level.length)
	_set_both("tunnel_radius", level.tunnel_radius)
	material.set_shader_parameter("ball_radius", tuning.ball_radius)
	material.set_shader_parameter("band_length", band_length_for(level))
	_set_both("hole_data", hole_texture(level))
	material.set_shader_parameter("pattern", pattern)
	set_spin_offset(0.0)


## The level's holes packed for the shader: two RGBA float texels each,
## (s_start, length, angle_center, angle_width) and (twist, 0, 0, 0).
static func hole_texture(level: LevelData) -> ImageTexture:
	var count := maxi(level.holes.size(), 1)
	var data := PackedFloat32Array()
	data.resize(count * 8)
	for i in level.holes.size():
		var hole := level.holes[i]
		data[i * 8 + 0] = hole.s_start
		data[i * 8 + 1] = hole.length
		data[i * 8 + 2] = hole.angle_center
		data[i * 8 + 3] = hole.angle_width
		data[i * 8 + 4] = hole.twist
	var image := Image.create_from_data(count * 2, 1, false, Image.FORMAT_RGBAF, data.to_byte_array())
	return ImageTexture.create_from_image(image)


## How far (radians) the floor pattern has slid with the ground spin.
func set_spin_offset(radians: float) -> void:
	material.set_shader_parameter("spin_offset", wrapf(radians, -PI, PI))


## Faster levels get shorter light/dark bands, so the rings flicker past
## noticeably quicker than the speed difference alone would suggest.
static func band_length_for(level: LevelData) -> float:
	return clampf(3.0 - (level.base_speed - 13.65) * 0.14, 1.8, 3.0)


## Call every frame with the camera's distance along the tunnel.
func update_view(camera_s: float, ball_s: float, ball_angle: float, ball_height: float, now: float) -> void:
	if level == null:
		return
	var first := int(floor(camera_s / CHUNK_LENGTH)) - BEHIND
	var last := int(floor((camera_s + VIEW_DISTANCE) / CHUNK_LENGTH))
	for index in _chunks.keys():
		if index < first or index > last:
			_chunks[index].queue_free()
			_chunks.erase(index)
	var built := 0
	for index in range(first, last + 1):
		if _chunks.has(index):
			continue
		# Always build what is close; spread far chunks over several frames.
		if built >= MAX_BUILDS_PER_FRAME and index > first + 3:
			break
		_build_chunk(index)
		built += 1

	material.set_shader_parameter("ball", Vector3(ball_s, ball_angle, ball_height))
	material.set_shader_parameter("now", now)


func set_best_marker(s: float) -> void:
	material.set_shader_parameter("best_s", s)


func set_fog(color: Color) -> void:
	_set_both("fog_color", color)


func set_fade(amount: float, color: Color) -> void:
	_set_both("fade", amount)
	_set_both("fade_color", color)


func _set_both(parameter: String, value: Variant) -> void:
	material.set_shader_parameter(parameter, value)
	shell_material.set_shader_parameter(parameter, value)


func _clear_chunks() -> void:
	for index in _chunks.keys():
		_chunks[index].queue_free()
	_chunks.clear()


## Starts a ripple at a point on the wall. strength ~0.3 (soft) .. 1.5 (huge).
func add_ripple(s: float, angle: float, now: float, strength: float) -> void:
	_ripples[_next_ripple] = Vector4(s, angle, now, strength)
	_next_ripple = (_next_ripple + 1) % MAX_RIPPLES
	material.set_shader_parameter("ripples", _ripples)


func clear_ripples() -> void:
	for i in MAX_RIPPLES:
		_ripples[i] = Vector4.ZERO
	material.set_shader_parameter("ripples", _ripples)


func _build_chunk(index: int) -> void:
	var start := index * CHUNK_LENGTH
	var end := (index + 1) * CHUNK_LENGTH
	var holes := TunnelMeshBuilder.hole_range(level, start, end)
	var instance := _tube("Chunk%d" % index, TunnelMeshBuilder.build_chunk(level, start, end), material, holes)
	add_child(instance)
	if shell_thickness > 0.0:
		var shell := _tube("Shell", TunnelMeshBuilder.build_chunk(level, start, end, shell_thickness), shell_material, holes)
		instance.add_child(shell)
	_chunks[index] = instance


static func _tube(tube_name: String, mesh: ArrayMesh, tube_material: ShaderMaterial, holes: Vector2i) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = tube_name
	instance.mesh = mesh
	instance.material_override = tube_material
	instance.set_instance_shader_parameter("hole_first", holes.x)
	instance.set_instance_shader_parameter("hole_count", holes.y)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance
