class_name Autopilot
extends RefCounted
## A simple bot that plays the game through InputFrames, like a player would.
##
## Used by tests to prove levels can be finished, and handy later for the
## menu attract mode or the level editor's "test play". It only sees the
## level data and the ball state, never the simulation internals.
##
## Strategy: look a short distance ahead, pick the nearest stretch of floor
## that stays solid across that window and steer well inside it, leaning
## against the ground spin; if nothing is solid (a ring), jump with just
## enough height to clear it, and echo when the landing is followed by
## trouble and the repeated jump comes down on solid floor.
##
## `steering_delay` makes it react late, like a person: its steering uses
## what it saw that long ago. Jumps and taps are not delayed (players
## anticipate those from what is coming, they do not react to them).

const ANGLE_BINS := 120
## Length of one lookup cell along the tunnel (m).
const CELL := 0.5
## The plan (where to steer) is refreshed this often, in simulation steps.
const REPLAN_STEPS := 4
## Simulation steps per second (GameSession.STEP_RATE; not referenced
## directly so the bot stays usable without the scene tree's autoloads).
const STEP_RATE := 120.0
## How far ahead (s) the way to a new lane must be floor: roughly how long
## the ball spends crossing to it.
const ROUTE_SECONDS := 0.25

var level: LevelData
var tuning: BallTuning
## Seconds between seeing something and steering for it.
var steering_delay := 0.0

var _ring_cache := {}   # quarter-metre slice -> is every angle a hole?
var _cell_cache := {}   # cell * ANGLE_BINS + bin -> blocked?
var _target := NAN
var _steps_to_replan := 0
var _delayed_tilt: Array[float] = []


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
		var strip := maxf(6.0, speed * 0.45)
		var after := _next_blocked_stretch(gap.y + 0.1, gap.y + strip)
		var in_series := after.x < gap.y + strip
		var lead := (after.x - gap.y) * 0.5 if in_series else 1.4
		if gap.x - sim.s < lead:
			# Like a human: a full swipe for an echo run, a measured one otherwise.
			frame.jump_strength = 1.0 if in_series else _strength_to_clear(maxf(gap.y - sim.s + lead, _air_distance_to_line_up(sim, gap)), speed)

	# Steering: the nearest angle that stays solid over the longest window
	# we can find one for (rings are ignored here, they are jumped).
	_steps_to_replan -= 1
	if _steps_to_replan <= 0 or is_nan(_target):
		_steps_to_replan = REPLAN_STEPS
		_target = NAN
		if sim.phase == BallSimulation.Phase.AIRBORNE and sim.height > 0.0:
			# In the air only the landing matters: aim for the middle of it.
			var landing_s := sim.s + speed * sim.time_to_land()
			_target = _best_angle(sim.angle, landing_s - 0.5, landing_s + speed * 0.3, true)
		elif gap.x < INF and gap.x - sim.s < speed * 1.0:
			# A ring is coming: line up with the middle of where we land after it,
			# but only if we can get there on floor. If holes lie between here and
			# there before take-off, stay on the floor and line up in the air.
			_target = _best_angle(sim.angle, gap.y + 0.5, gap.y + speed * 0.35, true, sim.s + 0.5, minf(gap.x, sim.s + speed * ROUTE_SECONDS), true)
		if is_nan(_target):
			for seconds in [2.0, 1.3, 0.9, 0.6, 0.35]:
				# Only lanes we can roll to: a long window can see floor past
				# the next ring, and the way there may be all holes.
				var reach_s := minf(gap.x, sim.s + speed * ROUTE_SECONDS)
				_target = _best_angle(sim.angle, sim.s + 0.5, sim.s + speed * seconds, false, sim.s + 0.5, reach_s)
				if not is_nan(_target):
					break
		if is_nan(_target):
			_target = sim.angle
	var difference := TunnelMath.angle_difference(_target, sim.angle) * level.tunnel_radius
	# A PD controller on position over the holes, plus a lean that cancels
	# the spin's pull (rolling resistance drags the ball towards the spin
	# drift), like a player holding the phone tilted against it.
	var full_tilt := tuning.steering_acceleration
	var pull := (sim.spin_speed() - sim.lateral_speed) * tuning.rolling_resistance
	var authority := tuning.air_control if sim.phase == BallSimulation.Phase.AIRBORNE else 1.0
	# Gains in m/s² (per metre off, per m/s of drift), so the bot's
	# reflexes stay those of a person, however quick the ball can be.
	var steer := (difference * 11.6 - sim.lateral_speed * 4.5) / full_tilt - pull / full_tilt / authority
	frame.tilt = _delay(clampf(steer, -1.0, 1.0))

	# Echo: just before touchdown, tap if trouble starts right after the
	# landing spot and the repeated jump would come down on solid floor.
	if sim.phase == BallSimulation.Phase.AIRBORNE and sim.time_to_land() < 0.05 and sim.height > 0.0:
		var landing_s := sim.s + speed * sim.time_to_land()
		var bounce := speed * 2.0 * sqrt(2.0 * sim.last_jump_height / tuning.gravity)
		var trouble := _raw_blocked_between(landing_s + 0.5, landing_s + speed * 0.45, sim.angle)
		var next_safe := not _raw_blocked_between(landing_s + bounce - 0.6, landing_s + bounce + 0.8, sim.angle)
		if trouble and next_safe:
			frame.tap = true
	return frame


func _delay(tilt: float) -> float:
	var steps := int(round(steering_delay * STEP_RATE))
	if steps <= 0:
		return tilt
	_delayed_tilt.append(tilt)
	if _delayed_tilt.size() <= steps:
		return 0.0
	return _delayed_tilt.pop_front()


## How far (m along the tunnel) a jump must carry to leave time to steer,
## in the air, to the floor after the ring `gap`, as a player who sees the
## landing lane is off to the side jumps higher to have time to get there.
func _air_distance_to_line_up(sim: BallSimulation, gap: Vector2) -> float:
	var landing := _best_angle(sim.angle, gap.y + 0.5, gap.y + sim.forward_speed * 0.35, true)
	if is_nan(landing):
		return 0.0
	# Reaching the edge of the landing stretch is enough; its middle is ideal.
	var sideways := maxf(absf(TunnelMath.angle_difference(landing, sim.angle)) * level.tunnel_radius - 1.0, 0.0)
	var acceleration := tuning.steering_acceleration * tuning.air_control
	# Speed up half way and slow down the other half, after reacting.
	var seconds := steering_delay + 2.0 * sqrt(sideways / acceleration)
	# But not so far that it lands past the stretch it lined up for.
	return minf(seconds * sim.forward_speed, gap.y - sim.s + sim.forward_speed * 0.3)


func _strength_to_clear(distance: float, speed: float) -> float:
	var air_time := distance / speed
	var height := tuning.gravity * air_time * air_time / 8.0
	var fraction := inverse_lerp(tuning.min_jump_height, tuning.max_jump_height, height)
	return pow(clampf(fraction, 0.0, 1.0), 1.0 / tuning.jump_strength_exponent)


## Angle to aim for: the nearest stretch of floor that stays solid over
## [s0, s1], searching outwards from `current`. Aims well inside that
## stretch (its middle if it is narrow), not at its edge.
##
## With a route window [route_s0, route_s1], the way there must be floor
## too (every angle in between, over that window): stretches past a hole are
## skipped, or with `approach`, still chosen but only gone towards as far as
## the floor allows (lining up for a landing: finish the move in the air).
func _best_angle(current: float, s0: float, s1: float, middle: bool = false, route_s0: float = 0.0, route_s1: float = -1.0, approach: bool = false) -> float:
	var start := int(round(current / TAU * ANGLE_BINS))
	# How many bins we can roll to on each side (all of them without a route).
	var reach := {1: ANGLE_BINS, -1: ANGLE_BINS}
	if route_s1 > route_s0:
		for side in [1, -1]:
			for k in range(1, ANGLE_BINS / 2 + 1):
				if _window_blocked(route_s0, route_s1, start + side * k):
					reach[side] = k - 1
					break
	for k in ANGLE_BINS / 2 + 1:
		for side in [1, -1]:
			if k > reach[side] and not approach:
				continue
			var bin: int = start + side * k
			if _window_blocked(s0, s1, bin):
				continue
			var aim := _centre_of_window(bin, s0, s1, 0 if k == 0 else side, current, middle)
			if is_nan(aim):
				return aim
			# The middle of a lane can lie past where the way is still floor:
			# go as far as we safely can and finish the move later (or in the air).
			var step := TAU / ANGLE_BINS
			var inset := 1.1 / level.tunnel_radius
			var high := maxf(reach[1] * step - inset, 0.0)
			var low := -maxf(reach[-1] * step - inset, 0.0)
			return TunnelMath.wrap_angle_positive(current + clampf(TunnelMath.angle_difference(aim, current), low, high))
	return NAN


## From a free `bin`, walks across the free window and returns an angle at
## least INSET metres from its edges (its middle if it is narrower), on the
## near side when arriving from `side`, or as close to `current` as allowed.
func _centre_of_window(bin: int, s0: float, s1: float, side: int, current: float, middle: bool = false) -> float:
	const INSET := 1.1
	var step := TAU / ANGLE_BINS
	var low := bin
	var high := bin
	for k in ANGLE_BINS:
		if _window_blocked(s0, s1, high + 1):
			break
		high += 1
	for k in ANGLE_BINS:
		if _window_blocked(s0, s1, low - 1):
			break
		low -= 1
	if high - low >= ANGLE_BINS - 1:
		# All floor: no middle to aim for.
		return NAN if middle else current
	var a_low := low * step
	var a_high := high * step
	# Keep well clear of the edges: at least INSET, more in wider windows.
	var inset := maxf(INSET / level.tunnel_radius, (a_high - a_low) * 0.3)
	if middle or a_high - a_low <= 2.0 * inset:
		return (a_low + a_high) * 0.5
	if side > 0:
		return a_low + inset
	if side < 0:
		return a_high - inset
	# Already inside: stay put unless too close to an edge.
	var here := a_low + TunnelMath.wrap_angle_positive(current - a_low)
	return clampf(here, a_low + inset, a_high - inset)


## Is angle bin `bin` blocked anywhere in [s0, s1] (rings ignored)?
func _window_blocked(s0: float, s1: float, bin: int) -> bool:
	var wrapped := posmod(bin, ANGLE_BINS)
	for cell in range(int(floor(s0 / CELL)), int(floor(s1 / CELL)) + 1):
		if _cell_blocked(cell, wrapped):
			return true
	return false


func _cell_blocked(cell: int, bin: int) -> bool:
	var key := cell * ANGLE_BINS + bin
	if _cell_cache.has(key):
		return _cell_cache[key]
	var s := cell * CELL
	var blocked := false
	if not _is_ring(s):
		var angle := bin * TAU / ANGLE_BINS
		var margin := tuning.ball_radius * 0.6 / level.tunnel_radius
		for sample in [s, s + CELL * 0.5]:
			for offset in [-margin, 0.0, margin]:
				if _blocked(sample, angle + offset):
					blocked = true
	_cell_cache[key] = blocked
	return blocked


## True if any point on the line at `angle` in [s0, s1] is a hole, rings included.
func _raw_blocked_between(s0: float, s1: float, angle: float) -> bool:
	var s := s0
	while s <= s1:
		if _blocked(s, angle):
			return true
		s += 0.5
	return false


func _blocked(s: float, angle: float) -> bool:
	return level.is_hole(s, angle)


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
