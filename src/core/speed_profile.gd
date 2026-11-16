class_name SpeedProfile
extends RefCounted
## Forward speed along a level.
##
## Speed grows linearly with *progress*: v(s) = base * (1 + ramp * s / L).
## With ramp = 0.2 the ball finishes 20% faster than it started.
## Because v depends on s, ds/dt = v(s) is an exponential ODE, which lets us
## compute the exact level duration (and the length needed for a duration).


static func speed_at(s: float, length: float, base_speed: float, ramp: float) -> float:
	var progress := clampf(s / length, 0.0, 1.0) if length > 0.0 else 0.0
	return base_speed * (1.0 + ramp * progress)


## Exact time (seconds) to cover the whole level.
static func duration(length: float, base_speed: float, ramp: float) -> float:
	if ramp <= 0.0001:
		return length / base_speed
	return length / (ramp * base_speed) * log(1.0 + ramp)


## Seconds from the start to distance s (the inverse of the ODE above).
## The editor labels its distance ruler with this.
static func time_at(s: float, length: float, base_speed: float, ramp: float) -> float:
	var clamped := clampf(s, 0.0, length)
	var t: float
	if ramp <= 0.0001 or length <= 0.0:
		t = clamped / base_speed
	else:
		t = length / (ramp * base_speed) * log(1.0 + ramp * clamped / length)
	# Past the end the speed holds at its final value.
	return t + maxf(s - length, 0.0) / speed_at(length, length, base_speed, ramp)


## Length (metres) that makes a level last `seconds`.
static func length_for_duration(seconds: float, base_speed: float, ramp: float) -> float:
	if ramp <= 0.0001:
		return seconds * base_speed
	return seconds * ramp * base_speed / log(1.0 + ramp)
