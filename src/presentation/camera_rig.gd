class_name CameraRig
extends Camera3D
## Keeps the view locked to the ball so that gravity always points "down".
##
## The camera's roll *is* the ball's angle around the tunnel: when the ball
## drifts up the wall, the camera turns with it, and to the player it is the
## world that rotates. Roll is never smoothed (that would break the illusion
## that the ball always sits on the floor); only distance and height are.

@export var follow_distance := 5.4
@export var camera_height := 1.75
@export var look_ahead := 8.0
@export var look_height := 0.9
## Fraction of the ball's jump height the camera rises with.
@export var jump_follow := 0.45
## Field of view grows with forward speed, so faster levels (and the speed-up
## within a level) *feel* faster: more of the wall streams past at the edges.
@export var fov_at_12 := 64.0
## Extra degrees of FOV per m/s above 12 m/s.
@export var fov_per_speed := 1.5
@export var max_fov := 86.0
## Camera rumble from speed, in metres, reached at 24 m/s. Starts at 15 m/s.
@export var speed_rumble := 0.022

var _height := 0.0
var _focus_s := 0.0
var _punch := 0.0
var _shake := 0.0
var _rumble_phase := 0.0


func snap(s: float) -> void:
	_focus_s = s
	_height = 0.0
	_punch = 0.0
	_shake = 0.0


func update_view(delta: float, s: float, angle: float, height: float, tunnel_radius: float,
		speed: float, frozen: bool) -> void:
	# Once the ball falls, stop following it forward: watch it drop away.
	if frozen:
		_focus_s = lerpf(_focus_s, s, 1.0 - exp(-1.5 * delta))
	else:
		_focus_s = s
	_height = lerpf(_height, maxf(height, 0.0) * jump_follow, 1.0 - exp(-10.0 * delta))

	var eye := TunnelMath.point(_focus_s - follow_distance, angle, tunnel_radius - camera_height - _height)
	var target := TunnelMath.point(_focus_s + look_ahead, angle, tunnel_radius - look_height - _height * 0.6)
	if _shake > 0.0:
		eye += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * _shake * 0.08
		_shake = move_toward(_shake, 0.0, delta * 3.0)
	# A fine, fast rumble on the fast levels: the tunnel is rattling past.
	var rumble := speed_rumble * clampf((speed - 15.0) / 9.0, 0.0, 1.0)
	if rumble > 0.0 and not frozen:
		_rumble_phase += delta * speed * 2.1
		eye += TunnelMath.inward(angle) * sin(_rumble_phase * 6.3) * rumble \
			+ TunnelMath.tangent(angle) * sin(_rumble_phase * 4.1 + 1.3) * rumble * 0.6
	look_at_from_position(eye, target, TunnelMath.inward(angle))

	_punch = lerpf(_punch, 0.0, 1.0 - exp(-7.0 * delta))
	fov = fov_for_speed(speed) + _punch


func fov_for_speed(speed: float) -> float:
	return clampf(fov_at_12 + (speed - 12.0) * fov_per_speed, fov_at_12, max_fov)


## Brief FOV widening, for echo jumps.
func punch(amount: float) -> void:
	_punch = maxf(_punch, amount)


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)
