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

@export_group("Holes")
## Metres of forgiveness at hole edges: the ball's centre must be this far inside to fall.
@export var hole_forgiveness: float = 0.22


func max_tilt_radians() -> float:
	return deg_to_rad(max_tilt_degrees)
