class_name BallView
extends Node3D
## Draws the ball: position from the simulation, plus purely visual extras
## (rolling spin, squash and stretch, flash) that never affect gameplay.
##
## This node's basis is the ball's local frame (X right, Y up from the wall,
## Z backwards). Its scale carries the squash; the child mesh carries spin.

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


func set_radius(radius: float) -> void:
	_radius = radius
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
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


func set_colors(environment: Color, ink: Color, fade_amount: float, fade_color: Color) -> void:
	material.set_shader_parameter("environment_color", environment)
	material.set_shader_parameter("ink_color", ink)
	material.set_shader_parameter("fade", fade_amount)
	material.set_shader_parameter("fade_color", fade_color)
