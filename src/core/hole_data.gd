class_name HoleData
extends RefCounted
## A rectangular hole cut into the tunnel wall.
##
## A hole is a rectangle in *tunnel-surface coordinates*:
##   s      distance along the tunnel axis, in metres
##   angle  position around the circumference, in radians (0 = the "floor" at level start)
## Because the surface is a cylinder, a rectangle in (s, angle) is a curved
## patch in 3D. Angles wrap, so a hole may straddle angle 0 / TAU.

## Where the hole starts along the tunnel (metres).
var s_start: float
## How long the hole is along the tunnel (metres, > 0).
var length: float
## Centre of the hole around the circumference (radians, wrapped to [0, TAU)).
var angle_center: float
## Angular width of the hole (radians, 0 < width <= TAU).
var angle_width: float


func _init(p_s_start: float = 0.0, p_length: float = 1.0, p_angle_center: float = 0.0, p_angle_width: float = PI / 4.0) -> void:
	s_start = p_s_start
	length = p_length
	angle_center = TunnelMath.wrap_angle_positive(p_angle_center)
	angle_width = p_angle_width


func s_end() -> float:
	return s_start + length


## True if the surface point (s, angle) is inside this hole after shrinking
## the hole by `margin_s` metres along the tunnel and `margin_arc` metres
## around the circumference (positive margins forgive near-misses).
func contains(s: float, angle: float, radius: float, margin_s: float = 0.0, margin_arc: float = 0.0) -> bool:
	if s < s_start + margin_s or s > s_end() - margin_s:
		return false
	var half_width := angle_width * 0.5 - margin_arc / radius
	if half_width <= 0.0:
		return false
	return absf(TunnelMath.angle_difference(angle, angle_center)) <= half_width


## Returns the hole as one or two non-wrapping angle ranges [a0, a1] inside
## [0, TAU]. Mesh building wants ranges that never cross the seam.
func angle_ranges() -> Array[Vector2]:
	var ranges: Array[Vector2] = []
	if angle_width >= TAU:
		ranges.append(Vector2(0.0, TAU))
		return ranges
	var a0 := angle_center - angle_width * 0.5
	var a1 := angle_center + angle_width * 0.5
	if a0 < 0.0:
		ranges.append(Vector2(0.0, a1))
		ranges.append(Vector2(a0 + TAU, TAU))
	elif a1 > TAU:
		ranges.append(Vector2(a0, TAU))
		ranges.append(Vector2(0.0, a1 - TAU))
	else:
		ranges.append(Vector2(a0, a1))
	return ranges
