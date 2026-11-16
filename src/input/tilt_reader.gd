class_name TiltReader
extends RefCounted
## Converts device orientation (or keys, on desktop) into a tilt in [-1, 1].
##
## On a phone, we read the gravity vector and measure *roll*: rotation about
## the phone's long axis. atan2(x, length(y, z)) is independent of how far
## the phone is tipped towards the player, so it works whether they hold it
## upright or nearly flat. The reading is relative to a neutral pose captured
## by calibrate(), so "however you hold it when the run starts" is level.

## Degrees of physical tilt treated as full tilt (before sensitivity).
const FULL_TILT_DEGREES := 28.0
const DEAD_ZONE_DEGREES := 1.2
## Low-pass filter rate (1/s): high enough to feel instant, low enough to hide sensor jitter.
const SMOOTHING := 22.0
## How quickly keyboard tilt ramps, to imitate an analogue tilt.
const KEY_RAMP := 5.0

var _neutral_roll := 0.0
var _filtered := 0.0
var _key_tilt := 0.0


func has_sensor() -> bool:
	return Input.get_gravity().length_squared() > 0.01


## Treat the current pose as level.
func calibrate() -> void:
	_neutral_roll = _raw_roll()
	_filtered = 0.0


func read(delta: float) -> float:
	var target := 0.0
	if has_sensor():
		var degrees := rad_to_deg(angle_difference(_neutral_roll, _raw_roll()))
		var magnitude := maxf(absf(degrees) - DEAD_ZONE_DEGREES, 0.0)
		target = signf(degrees) * magnitude / FULL_TILT_DEGREES * Settings.tilt_sensitivity
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
