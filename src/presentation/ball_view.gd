class_name BallView
extends Node3D
## Draws the ball: position from the simulation, plus purely visual extras
## (rolling spin, squash and stretch, flash) that never affect gameplay.
##
## This node's basis is the ball's local frame (X right, Y up from the wall,
## Z backwards). Its scale carries the squash; the child mesh carries spin.

## The default look. Swap at runtime with apply_skin().
@export var skin: BallSkin = preload("res://resources/balls/graphite.tres")

@onready var _mesh: MeshInstance3D = $Mesh

var material: ShaderMaterial
var _radius := 0.42
var _spin := Basis.IDENTITY
var _squash := 1.0
var _squash_velocity := 0.0
var _flash := 0.0


func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/ball.gdshader")
	_mesh.material_override = material
	apply_skin(skin)


func apply_skin(new_skin: BallSkin) -> void:
	skin = new_skin
	material.set_shader_parameter("base_color", skin.base_color)
	material.set_shader_parameter("seam_color", skin.seam_color)
	material.set_shader_parameter("seam_width", skin.seam_width)
	material.set_shader_parameter("glossiness", skin.glossiness)
	material.set_shader_parameter("specular", skin.specular)
	material.set_shader_parameter("reflectivity", skin.reflectivity)
	material.set_shader_parameter("reflection_tint", skin.reflection_tint)


func set_radius(radius: float) -> void:
	_radius = radius
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	_mesh.mesh = sphere


func reset_spin() -> void:
	_spin = Basis.IDENTITY
	_squash = 1.0
	_squash_velocity = 0.0
	_flash = 0.0


## Positions the ball. `height` is the gap between ball and wall.
func update_view(delta: float, s: float, angle: float, height: float, tunnel_radius: float,
		forward_speed: float, lateral_speed: float) -> void:
	var up := TunnelMath.inward(angle)
	var frame := Basis(TunnelMath.tangent(angle), up, Vector3(0.0, 0.0, 1.0))
	position = TunnelMath.point(s, angle, tunnel_radius - _radius - height)

	# Rolling without slipping: angular velocity = up × velocity / radius.
	var velocity := TunnelMath.forward() * forward_speed + TunnelMath.tangent(angle) * lateral_speed
	var omega := up.cross(velocity) / _radius
	if omega.length_squared() > 0.000001:
		_spin = Basis(omega.normalized(), omega.length() * delta) * _spin
		_spin = _spin.orthonormalized()

	# Damped spring back to round.
	var stiffness := 260.0
	var damping := 16.0
	_squash_velocity += (-(_squash - 1.0) * stiffness - _squash_velocity * damping) * delta
	_squash += _squash_velocity * delta
	var sq := clampf(_squash, 0.6, 1.4)
	var side := 1.0 / sqrt(sq)
	basis = frame * Basis.from_scale(Vector3(side, sq, side))
	_mesh.basis = frame.inverse() * _spin

	_flash = move_toward(_flash, 0.0, delta * 3.0)
	material.set_shader_parameter("flash", _flash)


## Visual kick: negative = squash (landing), positive = stretch (take-off).
func kick(amount: float) -> void:
	_squash_velocity += amount * 12.0


func flash(amount: float, color: Color) -> void:
	_flash = maxf(_flash, amount)
	material.set_shader_parameter("flash_color", color)


## Scene lighting the ball responds to, all in world space.
func set_lighting(lamp_position: Vector3, lamp_color: Color, up: Vector3, glow: Color, floor_color: Color,
		fade_amount: float, fade_color: Color) -> void:
	material.set_shader_parameter("lamp_position", lamp_position)
	material.set_shader_parameter("lamp_color", lamp_color)
	material.set_shader_parameter("up_direction", up)
	material.set_shader_parameter("glow_color", glow)
	material.set_shader_parameter("floor_color", floor_color)
	material.set_shader_parameter("fade", fade_amount)
	material.set_shader_parameter("fade_color", fade_color)
