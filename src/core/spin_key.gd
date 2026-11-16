class_name SpinKey
extends RefCounted
## One key of a level's ground spin.
##
## Spin is a constant sideways drift of everything inside the tunnel: left
## alone, the ball is carried around the tunnel at this rate, and because the
## camera is locked to the ball the player sees the tunnel turning. The
## player counters it by tilting. Between keys the rate is interpolated
## linearly along the tunnel, so two keys close together make a sudden change
## and two keys far apart a gradual one.

## Distance along the tunnel (metres) where this rate applies.
var s: float
## Drift rate in degrees per second. Positive carries the ball to the right
## (increasing angle), negative to the left.
var rate: float


func _init(p_s: float = 0.0, p_rate: float = 0.0) -> void:
	s = p_s
	rate = p_rate
