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
## Sideways acceleration at full tilt, m/s². Tilt gives acceleration, not
## velocity, like a ball on a tilted plane, but steeper than real physics
## would allow (a rolling ball on a 32° slope manages ~13 m/s²): a quick
## ball makes for sharper, flashier lines.
@export var steering_acceleration: float = 30.0
## Exponential decay of lateral speed per second. Low = icy, high = sticky.
## Also how quickly the ball settles once the phone is level again.
@export var rolling_resistance: float = 2.4
## Cap on sideways speed, m/s.
@export var max_lateral_speed: float = 13.0
## Fraction of tilt authority kept while airborne.
@export_range(0.0, 1.0) var air_control: float = 0.7

@export_group("Jump")
## Jump height (m) for the smallest recognised swipe.
@export var min_jump_height: float = 0.7
## Jump height (m) for a full-size swipe.
@export var max_jump_height: float = 3.4
## Curve applied to swipe strength before mapping to height (<1 favours big jumps).
@export var jump_strength_exponent: float = 0.85
## A swipe this close (s) before landing is remembered and fired on landing.
@export var jump_buffer_time: float = 0.12

@export_group("Smash")
## Swipe down in the air: the ball hangs this long (s) before it dives, the
## wind-up that makes the hit read. Short, or the input feels late.
@export_range(0.0, 0.2) var smash_windup_time: float = 0.045
## No wind-up when the ball would land within this long (s) anyway.
@export var smash_windup_skip: float = 0.14
## Speed (m/s) the ball shoots down at; gravity adds to it.
@export var smash_speed: float = 34.0
## Share of sideways speed (relative to the spin) the dive keeps: low = a
## straight plunge onto the spot under the ball.
@export_range(0.0, 1.0) var smash_lateral_keep: float = 0.35
## A smash started at least this share of the jump's height up counts as
## "from the top": a bigger hit.
@export_range(0.0, 1.0) var smash_top_fraction: float = 0.7
## A swipe down this long (s) after an ordinary landing still bounces.
@export var smash_grace_time: float = 0.1
## Hit-stop: on impact the world freezes this long (s) before the bounce,
## while the shockwave keeps spreading. A swipe up during it sets the
## bounce's height (and ends the freeze at once).
@export_range(0.0, 0.4) var smash_freeze_time: float = 0.11
## While a finger is down (maybe mid-swipe) the hit-stop may stretch up to
## this long (s) to let the swipe finish.
@export_range(0.0, 0.6) var smash_freeze_max: float = 0.3
## The bounce throws away the ball's sideways momentum, so whatever the
## player tilts during the hit-stop takes over at once: the ball leaves the
## ground moving sideways at this speed (m/s) times the tilt.
@export_range(0.0, 10.0) var smash_redirect_speed: float = 4.0
## The trade-off: each smash adds this share of the level's speed, for the
## rest of the run (so smashing makes landings easy and the run faster).
@export_range(0.0, 0.3) var smash_speed_gain: float = 0.04
## Forward speed never goes past the level's times this.
@export_range(1.0, 3.0) var smash_speed_max: float = 1.6

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


## Sideways acceleration (m/s²) for a tilt in [-1, 1].
func tilt_acceleration(tilt: float) -> float:
	return clampf(tilt, -1.0, 1.0) * steering_acceleration
