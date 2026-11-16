class_name HoleData
extends RefCounted
## A hole cut into the tunnel wall.
##
## A hole is a rectangle in *tunnel-surface coordinates*:
##   s      distance along the tunnel axis, in metres
##   angle  position around the circumference, in radians (0 = the "floor" at level start)
## optionally *twisted*: its centre line turns `twist` radians per metre along
## the tunnel, so it becomes a slanted band (a parallelogram on the unrolled
## wall). Corkscrews and winding bridges are one twisted hole each, so their
## edges are straight diagonals rather than staircases of small rectangles.
##
## Corners are rounded (CORNER_RADIUS). The shape is defined by a signed
## distance (signed_distance()), and *both* the simulation and the renderer
## use that same function (the shader has a line-for-line copy), so the ball
## falls exactly where the picture shows a hole.

## Radius (m) of the rounded corners of every hole.
const CORNER_RADIUS := 0.6

## Where the hole starts along the tunnel (metres).
var s_start: float
## How long the hole is along the tunnel (metres, > 0).
var length: float
## Centre of the hole around the circumference at its *start* (radians, [0, TAU)).
var angle_center: float
## Angular width of the hole (radians, 0 < width <= TAU), measured around the tunnel.
var angle_width: float
## How fast the centre turns along the tunnel, radians per metre (0 = straight).
var twist: float


func _init(p_s_start: float = 0.0, p_length: float = 1.0, p_angle_center: float = 0.0, p_angle_width: float = PI / 4.0, p_twist: float = 0.0) -> void:
	s_start = p_s_start
	length = p_length
	angle_center = TunnelMath.wrap_angle_positive(p_angle_center)
	angle_width = p_angle_width
	twist = p_twist


func s_end() -> float:
	return s_start + length


## A full ring: every angle is open, so only the ends are edges.
func is_ring() -> bool:
	return angle_width >= TAU - 0.0001


## Centre angle at distance s along the tunnel.
func center_at(s: float) -> float:
	return angle_center + twist * (s - s_start)


## Signed distance (m, measured on the wall) from the surface point to the
## hole's edge: negative inside the hole, positive outside.
##
## The hole is a rounded box in sheared coordinates (arc relative to the
## twisted centre line, s relative to the middle); the arc part is scaled by
## cos(slant) so distances to the slanted sides are true perpendicular ones.
func signed_distance(s: float, angle: float, radius: float) -> float:
	var half_length := length * 0.5
	var y := absf(s - (s_start + half_length)) - half_length
	if is_ring():
		return y
	var slope := twist * radius
	var slant := 1.0 / sqrt(1.0 + slope * slope)
	var x := (absf(TunnelMath.angle_difference(angle, center_at(s))) * radius - angle_width * 0.5 * radius) * slant
	var corner := minf(CORNER_RADIUS, minf(angle_width * 0.5 * radius * slant, half_length) * 0.9)
	var qx := x + corner
	var qy := y + corner
	return Vector2(maxf(qx, 0.0), maxf(qy, 0.0)).length() + minf(maxf(qx, qy), 0.0) - corner


## True if the surface point is inside this hole alone, ignoring neighbours,
## shrunk by `margin` metres (positive margins forgive near-misses).
func contains(s: float, angle: float, radius: float, margin: float = 0.0) -> bool:
	return signed_distance(s, angle, radius) < -margin
