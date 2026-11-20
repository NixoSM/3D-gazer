class_name SpeedKey
extends RefCounted
## One key of a level's speed surges.
##
## A level's forward speed is its base profile (base_speed, growing by
## speed_ramp towards the end) times a factor painted along the tunnel with
## these keys. Between keys the factor is interpolated linearly, so two keys
## close together make a sudden surge ("a gear change") and two far apart a
## gradual one. Without keys the factor is 1 everywhere.

## Distance along the tunnel (metres) where this factor applies.
var s: float
## Multiplier on the base speed profile (1 = unchanged, 1.25 = 25% faster).
var factor: float


func _init(p_s: float = 0.0, p_factor: float = 1.0) -> void:
	s = p_s
	factor = p_factor
