class_name BallView
extends Node3D
## Draws the ball: position from the simulation, plus purely visual extras
## (rolling spin, squash and stretch, flash) that never affect gameplay.
##
## This node's basis is the ball's local frame (X right, Y up from the wall,
## Z backwards). Its scale carries the squash; the child mesh carries spin.
## A second, slightly larger sphere drawn inside-out gives the black outline.

## The default look. Swap at runtime with apply_skin().
@export var skin: BallSkin = preload("res://resources/balls/classic.tres")

@onready var _mesh: MeshInstance3D = $Mesh

var material: ShaderMaterial
var outline_material: ShaderMaterial
var _outline := MeshInstance3D.new()
var _radius := 0.42
var _spin := Basis.IDENTITY
var _squash := 1.0
var _squash_velocity := 0.0
var _flash := 0.0


func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/ball.gdshader")
	_mesh.material_override = material
	outline_material = ShaderMaterial.new()
	outline_material.shader = preload("res://shaders/outline.gdshader")
	_outline.name = "Outline"
	_outline.material_override = outline_material
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_outline)
	apply_skin(skin)


func apply_skin(new_skin: BallSkin) -> void:
	skin = new_skin
	material.set_shader_parameter("body_color", skin.body_color)
	material.set_shader_parameter("stripe_color", skin.stripe_color)
	material.set_shader_parameter("stripe_width", skin.stripe_width)
	material.set_shader_parameter("line_color", skin.line_color)
	material.set_shader_parameter("shade_amount", skin.shade_amount)
	material.set_shader_parameter("shine_size", skin.shine_size)
	outline_material.set_shader_parameter("outline_color", skin.line_color)
	set_radius(_radius)


func set_radius(radius: float) -> void:
	_radius = radius
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	_mesh.mesh = sphere
	var hull := SphereMesh.new()
	hull.radius = radius * (1.0 + skin.outline_width)
	hull.height = hull.radius * 2.0
	hull.radial_segments = 48
	hull.rings = 24
	_outline.mesh = hull


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


func set_fade(amount: float, color: Color) -> void:
	material.set_shader_parameter("fade", amount)
	material.set_shader_parameter("fade_color", color)
	outline_material.set_shader_parameter("fade", amount)
	outline_material.set_shader_parameter("fade_color", color)
