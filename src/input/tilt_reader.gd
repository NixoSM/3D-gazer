class_name TiltReader
extends RefCounted
## Converts device orientation (or keys, on desktop) into a tilt in [-1, 1].
##
## On a phone, we read the gravity vector and measure *roll*: rotation about
## the phone's long axis. atan2(x, length(y, z)) is independent of how far
## the phone is tipped towards the player, so it works whether they hold it
## upright or nearly flat.
##
## Level is *absolute*: a phone not rolled relative to gravity reads 0, so
## "holding it straight" always means no steering. (Earlier builds took the
## pose at the start of every attempt as level, so a retry that began
## mid-tilt left a permanent bias and the ball drifted on its own.) Players
## who hold the phone at an angle can store their own level with
## set_level_here(); it persists in Settings.

## Degrees of physical tilt treated as full tilt (before sensitivity).
const FULL_TILT_DEGREES := 28.0
## Small rolls are ignored, then blended in over the same width again, so
## the hand's natural wobble never steers and there is no jump at the edge.
const DEAD_ZONE_DEGREES := 2.5
## A stored level beyond this is surely a mistake (phone was being waved about).
const MAX_LEVEL_OFFSET_DEGREES := 35.0
## Low-pass filter rate (1/s): high enough to feel instant, low enough to hide sensor jitter.
const SMOOTHING := 22.0
## How quickly keyboard tilt ramps, to imitate an analogue tilt.
const KEY_RAMP := 5.0

var _filtered := 0.0
var _key_tilt := 0.0


func has_sensor() -> bool:
	return Input.get_gravity().length_squared() > 0.01


## Stores the current pose as level (pause menu). Returns the offset in degrees.
func set_level_here() -> float:
	if not has_sensor():
		return Settings.tilt_zero_degrees
	var offset := clampf(rad_to_deg(_raw_roll()), -MAX_LEVEL_OFFSET_DEGREES, MAX_LEVEL_OFFSET_DEGREES)
	Settings.tilt_zero_degrees = offset
	_filtered = 0.0
	return offset


## Back to "phone straight is level".
func reset_level() -> void:
	Settings.tilt_zero_degrees = 0.0


## Current roll relative to level, in degrees (for the pause screen).
func roll_degrees() -> float:
	if not has_sensor():
		return 0.0
	return rad_to_deg(angle_difference(deg_to_rad(Settings.tilt_zero_degrees), _raw_roll()))


## Maps degrees of roll to steering degrees: zero inside the dead zone, then
## a quadratic knee that joins the straight line smoothly.
static func shape_degrees(degrees: float) -> float:
	var magnitude := absf(degrees)
	var dz := DEAD_ZONE_DEGREES
	var shaped := 0.0
	if magnitude >= 2.0 * dz:
		shaped = magnitude - 1.5 * dz
	elif magnitude > dz:
		shaped = (magnitude - dz) * (magnitude - dz) / (2.0 * dz)
	return signf(degrees) * shaped


func read(delta: float) -> float:
	var target := 0.0
	if has_sensor():
		target = shape_degrees(roll_degrees()) / FULL_TILT_DEGREES * Settings.tilt_sensitivity
		if Settings.invert_tilt:
			target = -target
	# Keyboard / gamepad (desktop testing, and Android TV one day).
	var key_target := Input.get_axis(&"tilt_left", &"tilt_right")
	_key_tilt = move_toward(_key_tilt, key_target, KEY_RAMP * delta)
	target += _key_tilt
	_filtered = lerpf(_filtered, clampf(target, -1.0, 1.0), 1.0 - exp(-SMOOTHING * delta))
	return _filtered


func _raw_roll() -> float:
	var g := Input.get_gravity()
	return atan2(g.x, Vector2(g.y, g.z).length())
