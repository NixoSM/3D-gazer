class_name InputFrame
extends RefCounted
## The player's intent for one simulation step, independent of the device.
##
## Touch screens, accelerometers, keyboards, gamepads, replays and bots all
## produce InputFrames; BallSimulation only ever sees these. This is the seam
## that keeps the simulation testable and portable (iOS, Android, desktop).

## Ground tilt in [-1, 1]. -1 = fully tilted left, +1 = fully tilted right.
var tilt: float = 0.0
## Jump request in [0, 1] (size of the swipe), or -1 for "no jump this step".
var jump_strength: float = -1.0
## True if the player tapped during this step (used for echo jumps).
var tap: bool = false


func _init(p_tilt: float = 0.0, p_jump_strength: float = -1.0, p_tap: bool = false) -> void:
	tilt = p_tilt
	jump_strength = p_jump_strength
	tap = p_tap


func has_jump() -> bool:
	return jump_strength >= 0.0
