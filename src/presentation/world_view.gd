class_name WorldView
extends Node3D
## The 3D scene: tunnel, ball, camera and sky, kept in sync with a GameSession.
##
## Reads the session's interpolated state each frame and pushes it into the
## views and shaders. Owns the per-level colours and the fade used between
## attempts. Event-driven feedback (ripples, sounds) lives in EffectsDirector.

@export var session: GameSession

@onready var tunnel: TunnelView = $Tunnel
@onready var ball: BallView = $Ball
@onready var camera: CameraRig = $Camera
@onready var environment_node: WorldEnvironment = $WorldEnvironment

var palette: LevelPalette
## 0 = clear, 1 = fully faded to the void colour.
var fade := 0.0

var _sky_material: ShaderMaterial
var _time := 0.0


func _ready() -> void:
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = preload("res://shaders/void_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.glow_enabled = false
	environment_node.environment = env


func set_level(level: LevelData, tuning: BallTuning) -> void:
	palette = LevelPalette.new(level.palette)
	tunnel.set_level(level, palette, tuning)
	ball.set_radius(tuning.ball_radius)
	reset_view()


func reset_view() -> void:
	ball.reset_spin()
	camera.snap(session.view_s)
	tunnel.clear_ripples()


## Seconds on the effects clock shared with the tunnel shader.
func now() -> float:
	return _time


func _process(delta: float) -> void:
	if session == null or session.simulation == null:
		return
	_time += delta
	var sim := session.simulation
	var level := session.level
	var s := session.view_s
	var angle := session.view_angle
	var height := session.view_height
	var progress := level.progress_at(s)
	var frozen := sim.phase == BallSimulation.Phase.FALLING
	# During the echo hit-stop everything holds still except the shockwave.
	var held := sim.phase == BallSimulation.Phase.FROZEN

	var speed := level.speed_at(s)
	camera.update_view(delta, s, angle, height, level.tunnel_radius, speed, frozen or held)
	ball.update_view(delta, s, angle, height, level.tunnel_radius,
		0.0 if held else sim.forward_speed, 0.0 if held else sim.lateral_speed)
	tunnel.update_view(camera.global_position.z * -1.0, s, angle, height, _time)

	var void_color := palette.void_at(progress)
	tunnel.set_fog(void_color)
	tunnel.set_fade(fade, void_color)
	_sky_material.set_shader_parameter("void_color", void_color)
	_sky_material.set_shader_parameter("fade", fade)
	_sky_material.set_shader_parameter("fade_color", void_color)
	ball.set_fade(fade, void_color)
