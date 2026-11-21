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
## True if the player swiped down during this step (the smash).
var smash: bool = false
## True while a finger is down and could still become a swipe. The smash
## hit-stop waits for it (up to a limit) so a swipe can reshape the bounce.
var holding: bool = false


func _init(p_tilt: float = 0.0, p_jump_strength: float = -1.0, p_smash: bool = false) -> void:
	tilt = p_tilt
	jump_strength = p_jump_strength
	smash = p_smash


func has_jump() -> bool:
	return jump_strength >= 0.0
