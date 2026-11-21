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
## Shape the squash spring settles to (1 = round): the smash holds the ball
## coiled, stretched while it dives and flattened through the hit-stop.
var _squash_rest := 1.0
## Extra forward tumble (rad/s) on top of rolling, for the smash's flip.
var _flip_speed := 0.0
## The smear behind a diving ball: a tapering tail up the line of the dive,
## flat white with the ball's black outline, like a cartoon's motion smear.
var _smear := MeshInstance3D.new()
var _smear_outline := MeshInstance3D.new()
var _smear_mesh := CylinderMesh.new()
var _smear_hull := CylinderMesh.new()
var _smear_material := StandardMaterial3D.new()
var _smear_length := 0.0


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
	_smear_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smear.name = "Smear"
	_smear.mesh = _smear_mesh
	_smear.material_override = _smear_material
	_smear_outline.name = "SmearOutline"
	_smear_outline.mesh = _smear_hull
	_smear_outline.material_override = outline_material
	for part in [_smear, _smear_outline]:
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		part.visible = false
		part.top_level = true
		add_child(part)
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
	# Unit-height tails; scaled to the dive's length each frame.
	_smear_mesh.top_radius = radius * 0.1
	_smear_mesh.bottom_radius = radius * 0.62
	_smear_mesh.height = 1.0
	_smear_mesh.radial_segments = 24
	_smear_mesh.rings = 1
	_smear_mesh.cap_top = true
	_smear_mesh.cap_bottom = false
	var grow := radius * skin.outline_width
	_smear_hull.top_radius = _smear_mesh.top_radius + grow
	_smear_hull.bottom_radius = _smear_mesh.bottom_radius + grow
	_smear_hull.height = 1.0 + grow
	_smear_hull.radial_segments = 24
	_smear_hull.rings = 1
	_smear_hull.cap_bottom = false
	_smear_material.albedo_color = skin.body_color


func reset_spin() -> void:
	_spin = Basis.IDENTITY
	_squash = 1.0
	_squash_velocity = 0.0
	_flash = 0.0
	_squash_rest = 1.0
	_flip_speed = 0.0
	_smear_length = 0.0
	_smear.visible = false
	_smear_outline.visible = false


## Positions the ball. `height` is the gap between ball and wall.
func update_view(delta: float, s: float, angle: float, height: float, tunnel_radius: float,
		forward_speed: float, lateral_speed: float) -> void:
	var up := TunnelMath.inward(angle)
	var frame := Basis(TunnelMath.tangent(angle), up, Vector3(0.0, 0.0, 1.0))
	position = TunnelMath.point(s, angle, tunnel_radius - _radius - height)

	# Rolling without slipping: angular velocity = up × velocity / radius.
	var velocity := TunnelMath.forward() * forward_speed + TunnelMath.tangent(angle) * lateral_speed
	var omega := up.cross(velocity) / _radius
	# The smash's flip: a fast forward tumble about the ball's sideways axis.
	if _flip_speed > 0.01:
		omega += TunnelMath.tangent(angle) * -_flip_speed
		_flip_speed = lerpf(_flip_speed, 0.0, 1.0 - exp(-9.0 * delta))
	if omega.length_squared() > 0.000001:
		_spin = Basis(omega.normalized(), omega.length() * delta) * _spin
		_spin = _spin.orthonormalized()

	# Damped spring back to round.
	var stiffness := 260.0
	var damping := 16.0
	_squash_velocity += (-(_squash - _squash_rest) * stiffness - _squash_velocity * damping) * delta
	_squash += _squash_velocity * delta
	var sq := clampf(_squash, 0.5, 1.7)
	var side := 1.0 / sqrt(sq)
	basis = frame * Basis.from_scale(Vector3(side, sq, side))
	_mesh.basis = frame.inverse() * _spin

	_flash = move_toward(_flash, 0.0, delta * 3.0)
	material.set_shader_parameter("flash", _flash)
	_update_smear(up)


## The tail runs from the ball's centre up the dive, `_smear_length` long.
func _update_smear(up: Vector3) -> void:
	var show := _smear_length > _radius * 0.5
	_smear.visible = show
	_smear_outline.visible = show
	if not show:
		return
	var side := TunnelMath.forward().cross(up).normalized()
	var frame := Basis(side, up, side.cross(up))
	var shape := frame * Basis.from_scale(Vector3(1.0, _smear_length, 1.0))
	var centre := global_position + up * (_smear_length * 0.5)
	_smear.global_transform = Transform3D(shape, centre)
	_smear_outline.global_transform = Transform3D(shape, centre)


## How far up the dive the smear reaches (0 hides it).
func set_smear(length: float) -> void:
	_smear_length = maxf(length, 0.0)


## The shape the ball relaxes towards (1 = round, <1 flat, >1 tall).
func hold_squash(rest: float) -> void:
	_squash_rest = rest


## A forward flip, in radians per second, that dies away.
func flip(speed: float) -> void:
	_flip_speed = maxf(_flip_speed, speed)


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
