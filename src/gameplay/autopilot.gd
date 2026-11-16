class_name Autopilot
extends RefCounted
## A simple bot that plays the game through InputFrames, like a player would.
##
## Used by tests to prove levels can be finished, and handy later for the
## menu attract mode or the level editor's "test play". It only sees the
## level data and the ball state, never the simulation internals.
##
## Strategy: look a short distance ahead, pick the closest angle that stays
## solid across that window and steer to it; if nothing is solid (a ring),
## jump with just enough height to clear it, then echo if the next landing
## comes up on another ring.

const ANGLE_BINS := 72

var level: LevelData
var tuning: BallTuning
var _ring_cache := {}  # quarter-metre slice -> is every angle a hole?


func _init(p_level: LevelData, p_tuning: BallTuning) -> void:
	level = p_level
	tuning = p_tuning


func decide(sim: BallSimulation) -> InputFrame:
	var frame := InputFrame.new()
	var speed := sim.forward_speed

	# Rings: nothing to steer to, so jump. Take off half a landing strip
	# before the gap, so a run of evenly spaced rings can be echoed.
	var gap := _next_blocked_stretch(sim.s, sim.s + speed * 1.5)
	if sim.phase == BallSimulation.Phase.ROLLING and gap.x < INF:
		var after := _next_blocked_stretch(gap.y + 0.1, gap.y + 6.0)
		var in_series := after.x < gap.y + 6.0
		var lead := (after.x - gap.y) * 0.5 if in_series else 1.4
		if gap.x - sim.s < lead:
			# Like a human: a full swipe for an echo run, a measured one otherwise.
			frame.jump_strength = 1.0 if in_series else _strength_to_clear(gap.y - sim.s + lead, speed)

	# Steering: the nearest angle that stays solid over the longest window
	# we can find one for (rings are ignored here, they are jumped).
	var target := NAN
	for seconds in [1.3, 0.9, 0.6, 0.35]:
		target = _best_angle(sim.angle, sim.s + 0.5, sim.s + speed * seconds)
		if not is_nan(target):
			break
	if is_nan(target):
		target = sim.angle
	var difference := TunnelMath.angle_difference(target, sim.angle) * level.tunnel_radius
	frame.tilt = clampf(difference * 0.9 - sim.lateral_speed * 0.35, -1.0, 1.0)

	# Echo: if airborne and the landing spot is over a hole, tap to bounce again.
	if sim.phase == BallSimulation.Phase.AIRBORNE:
		var landing_in := sim.time_to_land()
		var landing_s := sim.s + speed * landing_in
		var bounce_end := landing_s + speed * 2.0 * sqrt(2.0 * sim.last_jump_height / tuning.gravity)
		if landing_in < 0.05 and _blocked(landing_s + 0.5, sim.angle) or (landing_in < 0.05 and _blocked_between(landing_s + 0.5, bounce_end - 1.0, sim.angle)):
			frame.tap = true
	return frame


func _strength_to_clear(distance: float, speed: float) -> float:
	var air_time := distance / speed
	var height := tuning.gravity * air_time * air_time / 8.0
	var fraction := inverse_lerp(tuning.min_jump_height, tuning.max_jump_height, height)
	return pow(clampf(fraction, 0.0, 1.0), 1.0 / tuning.jump_strength_exponent)


## Nearest angle (searching outwards from `current`) that is solid over [s0, s1].
func _best_angle(current: float, s0: float, s1: float) -> float:
	var step := TAU / ANGLE_BINS
	for k in ANGLE_BINS / 2 + 1:
		for side in [1.0, -1.0]:
			var angle: float = current + side * k * step
			if not _blocked_between(s0, s1, angle):
				return TunnelMath.wrap_angle_positive(angle)
	return NAN


func _blocked_between(s0: float, s1: float, angle: float) -> bool:
	var margin := tuning.ball_radius * 0.6
	var s := s0
	while s <= s1:
		if _is_ring(s):
			s += 0.5
			continue
		for offset in [-margin, 0.0, margin]:
			if _blocked(s, angle + offset / level.tunnel_radius):
				return true
		s += 0.5
	return false


func _blocked(s: float, angle: float) -> bool:
	return level.hole_at(s, angle) != null


func _is_ring(s: float) -> bool:
	var key := int(s * 4.0)
	if not _ring_cache.has(key):
		var ring := true
		for i in 24:
			if not _blocked(key / 4.0, TAU * i / 24.0):
				ring = false
				break
		_ring_cache[key] = ring
	return _ring_cache[key]


## Start and end (s) of the next stretch where every angle is a hole.
func _next_blocked_stretch(s0: float, s1: float) -> Vector2:
	var s := s0
	var start := -1.0
	while s < s1 + 20.0:
		var all_blocked := _is_ring(s)
		if all_blocked and start < 0.0:
			start = s
		elif not all_blocked and start >= 0.0:
			return Vector2(start, s)
		s += 0.25
	return Vector2(INF, INF) if start < 0.0 else Vector2(start, s)
