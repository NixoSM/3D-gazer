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

## Where the travelling lamp sits relative to the ball (metres ahead, metres above the wall).
const LAMP_AHEAD := 1.2
const LAMP_HEIGHT := 2.4

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
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 0.9
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

	camera.update_view(delta, s, angle, height, level.tunnel_radius, progress, frozen)
	ball.update_view(delta, s, angle, height, level.tunnel_radius, sim.forward_speed, sim.lateral_speed)
	tunnel.update_view(camera.global_position.z * -1.0, s, angle, height, _time)

	# The lamp hangs just above and ahead of the ball, so the floor around it
	# is lit and the rest of the tunnel falls into darkness.
	var lamp := TunnelMath.point(s + LAMP_AHEAD, angle, level.tunnel_radius - LAMP_HEIGHT - maxf(height, 0.0) * 0.5)
	var accent := palette.accent_at(progress)
	var void_color := palette.void_at(progress)
	var lamp_color := Color.WHITE.lerp(accent, 0.22)
	var glow := palette.void_at(progress + 40.0 / level.length).lerp(Color.WHITE, 0.35)
	var fog := void_color.darkened(0.8)
	tunnel.set_lighting(lamp, lamp_color, fog)
	tunnel.set_fade(fade, fog)
	_sky_material.set_shader_parameter("void_color", void_color)
	_sky_material.set_shader_parameter("glow_color", glow)
	_sky_material.set_shader_parameter("mote_color", accent)
	_sky_material.set_shader_parameter("fade", fade)
	_sky_material.set_shader_parameter("fade_color", fog)
	var floor_color := palette.wall_at(progress) * lamp_color * 1.6
	ball.set_lighting(lamp, lamp_color, TunnelMath.inward(angle), glow, floor_color, fade, fog)
