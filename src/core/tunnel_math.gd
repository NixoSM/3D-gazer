class_name TunnelMath
extends RefCounted
## Geometry helpers shared by simulation, rendering and (later) the level editor.
##
## World convention (Godot is right-handed, -Z is "forward"):
##   * The tunnel axis is the Z axis; the ball travels towards -Z.
##   * A surface point (s, angle) at distance r from the axis lives at
##       x =  r * sin(angle)
##       y = -r * cos(angle)
##       z = -s
##     so angle 0 is the bottom of the tunnel (y = -r) and the angle grows
##     towards +X, i.e. to the player's right when looking down the tunnel.

## Thickness (m) of the tunnel's shell. Holes are cut through it, so a ball
## that falls has to clear this much wall, and the renderer draws it.
const WALL_THICKNESS := 0.45


## Wraps an angle to (-PI, PI].
static func wrap_angle(angle: float) -> float:
	return wrapf(angle, -PI, PI)


## Wraps an angle to [0, TAU).
static func wrap_angle_positive(angle: float) -> float:
	return fposmod(angle, TAU)


## Shortest signed difference a - b, in (-PI, PI].
static func angle_difference(a: float, b: float) -> float:
	return wrap_angle(a - b)


## Point at distance `r` from the axis, `angle` around it, `s` along it.
static func point(s: float, angle: float, r: float) -> Vector3:
	return Vector3(r * sin(angle), -r * cos(angle), -s)


## Unit vector from the axis towards the wall at `angle` ("down" for a ball there).
static func outward(angle: float) -> Vector3:
	return Vector3(sin(angle), -cos(angle), 0.0)


## Unit vector from the wall towards the axis at `angle` ("up" for a ball there).
static func inward(angle: float) -> Vector3:
	return -outward(angle)


## Unit vector along the wall, in the direction of increasing angle ("right").
static func tangent(angle: float) -> Vector3:
	return Vector3(cos(angle), sin(angle), 0.0)


## Direction of travel.
static func forward() -> Vector3:
	return Vector3(0.0, 0.0, -1.0)
