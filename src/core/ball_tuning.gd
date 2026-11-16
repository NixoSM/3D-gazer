class_name BallTuning
extends Resource
## Every number that shapes how the ball *feels*, in one inspectable place.
##
## Edit res://resources/ball_tuning.tres in the Godot inspector to tune feel
## without touching code. Units are SI (metres, seconds, radians).

@export_group("Body")
## Radius of the ball in metres.
@export var ball_radius: float = 0.42
## Gravity towards the wall under the ball, m/s². Games feel better well above 9.8.
@export var gravity: float = 34.0

@export_group("Tilt")
## Phone tilt (in degrees) that counts as "fully tilted".
@export_range(5.0, 80.0) var max_tilt_degrees: float = 32.0
## A solid sphere rolling down a slope accelerates at 5/7 g sin(θ).
@export var rolling_factor: float = 5.0 / 7.0
## Exponential decay of lateral speed per second. Low = icy, high = sticky.
@export var rolling_resistance: float = 1.15
## Cap on sideways speed, m/s.
@export var max_lateral_speed: float = 13.0
## Fraction of tilt authority kept while airborne.
@export_range(0.0, 1.0) var air_control: float = 0.45

@export_group("Jump")
## Jump height (m) for the smallest recognised swipe.
@export var min_jump_height: float = 0.7
## Jump height (m) for a full-size swipe.
@export var max_jump_height: float = 3.4
## Curve applied to swipe strength before mapping to height (<1 favours big jumps).
@export var jump_strength_exponent: float = 0.85
## A swipe this close (s) before landing is remembered and fired on landing.
@export var jump_buffer_time: float = 0.12

@export_group("Echo")
## A tap this long (s) before landing queues an echo jump.
@export var echo_buffer_time: float = 0.2
## A tap this long (s) after landing still counts as an echo.
@export var echo_grace_time: float = 0.1
## Taps within this window (s) of touchdown count as "perfect".
@export var perfect_window: float = 0.06
## Hit-stop: on an echo the world freezes this long (s) before the ball
## leaves the ground, while the shockwave keeps spreading. A swipe during
## the freeze sets the echo's height (and ends the freeze at once).
@export_range(0.0, 0.4) var echo_freeze_time: float = 0.14
## While the finger is still down (maybe mid-swipe) the hit-stop may stretch
## up to this long (s) to let the swipe finish.
@export_range(0.0, 0.6) var echo_freeze_max: float = 0.3

@export_group("Holes")
## Metres of forgiveness at hole edges: the ball keeps its footing until its
## centre is this far past the edge. Beyond it the ball really drops, and the
## edge of the cut can still catch it (see BallSimulation).
@export var hole_forgiveness: float = 0.06
## After the ground goes from under the ball, a jump is still accepted for
## this long (s): "coyote time", so a swipe a frame late is not punished.
@export var coyote_time: float = 0.07
## Share of speed kept when the ball bounces off the walls of a hole.
@export_range(0.0, 1.0) var wall_restitution: float = 0.3


func max_tilt_radians() -> float:
	return deg_to_rad(max_tilt_degrees)
