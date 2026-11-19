class_name WorldView
extends Node3D
## The 3D scene: tunnel, ball, camera and the void, kept in sync with a GameSession.
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

## Radius of the void backdrop around the camera: beyond the farthest
## tunnel chunk (TunnelView.VIEW_DISTANCE + a chunk), inside the camera's far plane.
const BACKDROP_RADIUS := 200.0

var _backdrop := MeshInstance3D.new()
var _backdrop_material: ShaderMaterial
var _environment: Environment
var _time := 0.0


func _ready() -> void:
	_backdrop_material = ShaderMaterial.new()
	_backdrop_material.shader = preload("res://shaders/void_backdrop.gdshader")
	# Drawn after everything else that is opaque, so only open pixels shade it.
	_backdrop_material.render_priority = -100
	var sphere := SphereMesh.new()
	sphere.radius = BACKDROP_RADIUS
	sphere.height = BACKDROP_RADIUS * 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	_backdrop.name = "VoidBackdrop"
	_backdrop.mesh = sphere
	_backdrop.material_override = _backdrop_material
	_backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_backdrop)
	# No sky: a flat clear colour (the void's) behind the backdrop.
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	_environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_environment.glow_enabled = false
	environment_node.environment = _environment


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
	_backdrop.global_position = camera.global_position
	_backdrop_material.set_shader_parameter("void_color", void_color)
	_backdrop_material.set_shader_parameter("fade", fade)
	_backdrop_material.set_shader_parameter("fade_color", void_color)
	_environment.background_color = void_color
	ball.set_fade(fade, void_color)
