class_name TunnelView
extends Node3D
## Streams tunnel chunks around the camera and feeds the tunnel shader.
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

var _chunks := {}  # chunk index -> MeshInstance3D
var _ripples: Array[Vector4] = []
var _next_ripple := 0


func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/tunnel.gdshader")
	_ripples.resize(MAX_RIPPLES)


func set_level(p_level: LevelData, p_palette: LevelPalette, tuning: BallTuning) -> void:
	level = p_level
	palette = p_palette
	for index in _chunks.keys():
		_chunks[index].queue_free()
	_chunks.clear()
	clear_ripples()
	material.set_shader_parameter("wall_gradient", palette.wall_texture)
	material.set_shader_parameter("accent_gradient", palette.accent_texture)
	material.set_shader_parameter("level_length", level.length)
	material.set_shader_parameter("tunnel_radius", level.tunnel_radius)
	material.set_shader_parameter("ball_radius", tuning.ball_radius)
	material.set_shader_parameter("band_length", band_length_for(level))


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
	material.set_shader_parameter("fog_color", color)


func set_fade(amount: float, color: Color) -> void:
	material.set_shader_parameter("fade", amount)
	material.set_shader_parameter("fade_color", color)


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
	var instance := MeshInstance3D.new()
	instance.name = "Chunk%d" % index
	instance.mesh = TunnelMeshBuilder.build_chunk(level, index * CHUNK_LENGTH, (index + 1) * CHUNK_LENGTH)
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	_chunks[index] = instance
