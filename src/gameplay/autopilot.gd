class_name Autopilot
extends RefCounted
## A bot that plays the game through InputFrames, like a player would.
##
## Tests use it to prove levels can be finished, the level editor plays
## every edit with it, and tools/rate_levels.gd uses it to measure how hard
## a level is. It only sees the level data and the ball's state, never the
## simulation's internals.
##
## How it plays:
##   * It keeps a map of where the floor is safe to roll on (cells of CELL
##     metres by ANGLE_BINS around the tunnel, as bit masks).
##   * Steering: aim for the nearest stretch of floor that stays solid over
##     a look-ahead window, well inside it. The window bends where the holes
##     wind round, and the bot moves with the floor it is on: with the spin
##     on open floor, with a winding lane, leaning against the spin only
##     where the lane holds still (or turns against it).
##   * Jumping: a forward flood fill over that map finds where the floor it
##     can still *roll* to runs out (a ring, the end of a floating platform,
##     a break in a winding band). Before that dead end it plans a jump: for
##     a range of take-off points and swipe sizes it works out where the
##     ball comes down and how far sideways it can steer in the air, and
##     picks the landing that leaves the most floor around it. It takes off
##     when "now" is the best take-off point.
##   * Smash: just before touchdown, if the floor after the landing runs out
##     again soon, it swipes down (the bounce repeats the jump's height) when
##     that lands well, or swipes a different size (re-shaping the jump) when
##     that lands better.
##
## `steering_delay` makes it react late, like a person: its steering uses
## what it saw that long ago. Jumps and smashes are not delayed (players
## anticipate those from what is coming, they do not react to them).
##
## The `*_noise`/`*_jitter` settings make it imperfect in seeded, repeatable
## ways (a wobbling hand, swipes a little early or late, swipe sizes a
## little off), so that many runs with different seeds estimate how often a
## decent player would get through (tools/rate_levels.gd). All zero by default.

const ANGLE_BINS := 120
## Length of one map cell along the tunnel (m).
const CELL := 0.5
## The steering plan is refreshed this often, in simulation steps.
const REPLAN_STEPS := 4
## Simulation steps per second (GameSession.STEP_RATE; not referenced
## directly so the bot stays usable without the scene tree's autoloads).
const STEP_RATE := 120.0
## How far ahead (s) the way to a new lane must be floor: roughly how long
## the ball spends crossing to it.
const ROUTE_SECONDS := 0.25
## Floor at least this far (m) from every edge is "safe" on the map.
const SAFE := 0.25
## Sideways speed (m/s) the flood fill assumes the ball can roll at.
const ROLL_LATERAL := 8.0
## How far ahead (s) dead ends are looked for.
const HORIZON_SECONDS := 1.6
## Swipe sizes the jump planner considers.
const STRENGTHS: Array[float] = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
const COARSE_STRENGTHS: Array[float] = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
## Take-off points the planner considers before a dead end.
const TAKEOFF_SAMPLES := 20
const WORD := 60
const WORD_MASK := (1 << WORD) - 1

var level: LevelData
var tuning: BallTuning
## Seconds between seeing something and steering for it.
var steering_delay := 0.0

## Human-model imperfections (all zero: a machine). Seeded and repeatable.
var noise_seed := 0
## Size of a slow random wobble added to the tilt (in tilt units, -1..1).
var tilt_noise := 0.0
## Standard deviation (s) of how early or late jumps and taps come.
var timing_jitter := 0.0
## Standard deviation of measured swipe sizes (0..1 strength).
var strength_jitter := 0.0

var _rows := {}           # cell -> PackedInt64Array [low word, high word] of safe bins
var _landing_rows := {}   # cell -> rows AND-ed over a landing window
var _turns := {}          # cell -> bins the holes there wind round over the cell
var _target := NAN
var _steps_to_replan := 0
var _plan_steps := 0
var _delayed_tilt: Array[float] = []
## The jump being lined up while rolling: {} or take-off s, strength, landing s and angle.
var _plan := {}
## Where the ball is meant to come down while airborne (s, angle), or NAN.
var _landing := Vector2(NAN, NAN)
var _echo_decided := false
var _was_airborne := false
var _rng := RandomNumberGenerator.new()
var _noise_ready := false
var _wobble := 0.0
## This jump's timing error (s): positive = late, negative = early. NAN = not drawn yet.
var _jump_offset := NAN
var _fire_wait := 0.0
var _tap_offset := 0.0
var _late_tap := -1.0
var _late_tap_strength := -1.0
## The run's speed-up from smashes (BallSimulation.speed_boost).
var _boost := 1.0


func _init(p_level: LevelData, p_tuning: BallTuning) -> void:
	level = p_level
	tuning = p_tuning


func decide(sim: BallSimulation) -> InputFrame:
	_boost = sim.speed_boost
	if not _noise_ready:
		_noise_ready = true
		_rng.seed = noise_seed
	var frame := InputFrame.new()
	var speed := sim.forward_speed
	var dt := 1.0 / STEP_RATE
	var airborne := sim.phase == BallSimulation.Phase.AIRBORNE and sim.height > 0.0
	var rolling := sim.phase == BallSimulation.Phase.ROLLING
	if not airborne and _was_airborne:
		_landing = Vector2(NAN, NAN)
		_echo_decided = false
	_was_airborne = airborne

	# A tap or swipe meant for this landing that comes late (human model).
	if _late_tap >= 0.0:
		_late_tap -= dt
		if _late_tap < 0.0:
			if _late_tap_strength >= 0.0:
				frame.jump_strength = _late_tap_strength
			else:
				frame.smash = true
			_late_tap_strength = -1.0

	# --- Jumps: plan one before the floor we can roll on runs out ----------------
	var gap := Vector2(INF, INF)
	if rolling or sim.phase == BallSimulation.Phase.FROZEN:
		gap = _dead_end(sim.s, sim.angle, speed, speed * HORIZON_SECONDS)
		if gap.x == INF or sim.phase != BallSimulation.Phase.ROLLING:
			_plan = {}
			if gap.x == INF:
				_jump_offset = NAN
		else:
			_plan_steps -= 1
			if _plan.is_empty() or _plan_steps <= 0 or absf(float(_plan.get("gap", 0.0)) - gap.x) > 0.01:
				_plan_steps = REPLAN_STEPS
				_plan = _plan_jump(sim, gap)
				_plan["gap"] = gap.x
			if _plan.has("strength") and _should_fire(sim, speed, gap):
				frame.jump_strength = _swipe(_plan["strength"])
				_landing = Vector2(_plan["landing_s"], _plan["landing_angle"])
				_plan = {}
				_jump_offset = NAN
			elif not _plan.has("strength") and gap.x - sim.s < speed * 0.03:
				# No landing looks good, and the floor is gone: a person
				# would still jump for it rather than roll off the edge.
				frame.jump_strength = _swipe(1.0)
				_landing = Vector2(NAN, NAN)
				_plan = {}
				_jump_offset = NAN

	# --- Steering ----------------------------------------------------------------
	_steps_to_replan -= 1
	if _steps_to_replan <= 0 or is_nan(_target):
		_steps_to_replan = REPLAN_STEPS
		_target = _steering_target(sim, speed, gap, airborne)
	var difference := TunnelMath.angle_difference(_target, sim.angle) * level.tunnel_radius
	# A PD controller on position over the holes, plus a lean that cancels
	# the spin's pull (rolling resistance drags the ball towards the spin
	# drift), like a player holding the phone tilted against it.
	var full_tilt := tuning.steering_acceleration
	var pull := (sim.spin_speed() - sim.lateral_speed) * tuning.rolling_resistance
	var authority := tuning.air_control if sim.phase == BallSimulation.Phase.AIRBORNE else 1.0
	# Gains in m/s² (per metre off, per m/s of drift), so the bot's
	# reflexes stay those of a person, however quick the ball can be.
	# On floor that winds round (a corkscrew, a thread) the lane itself
	# moves sideways: match its speed rather than stopping dead.
	var lane_speed := _floor_flow(sim.s + speed * 0.15, speed) if rolling else 0.0
	var steer := (difference * 11.6 - (sim.lateral_speed - lane_speed) * 4.5) / full_tilt - pull / full_tilt / authority
	if tilt_noise > 0.0:
		# A slow wobble of the hand (Ornstein-Uhlenbeck, 0.3 s memory).
		const MEMORY := 0.3
		_wobble += -_wobble / MEMORY * dt + tilt_noise * sqrt(2.0 / MEMORY * dt) * _rng.randfn()
		steer += _wobble
	frame.tilt = _delay(clampf(steer, -1.0, 1.0))

	# --- Echo: just before touchdown --------------------------------------------
	if airborne and not _echo_decided:
		var ttl := sim.time_to_land()
		if timing_jitter > 0.0 and ttl > 0.3:
			_tap_offset = _rng.randfn() * timing_jitter
		if ttl < 0.05 + maxf(_tap_offset, 0.0):
			_echo_decided = true
			_decide_landing_action(sim, speed, frame)
	return frame


## How fast (m/s, sideways) the floor near s winds round: the twist of
## the holes there (their mean, when they turn different ways, as the two
## walls of a funnel do), times the forward speed. With no holes in sight
## the ball rolls with the spin, as a player who is not fighting it does.
func _floor_flow(s: float, speed: float) -> float:
	var total := 0.0
	var count := 0
	for hole in level.holes_between(s - 1.0, s + 1.0):
		if hole.angle_width >= TAU - 0.01 or hole.s_start > s or hole.s_start + hole.length < s:
			continue
		total += hole.twist
		count += 1
	if count == 0:
		return level.spin_speed_at(s)
	return total / count * speed * level.tunnel_radius


func _delay(tilt: float) -> float:
	var steps := int(round(steering_delay * STEP_RATE))
	if steps <= 0:
		return tilt
	_delayed_tilt.append(tilt)
	if _delayed_tilt.size() <= steps:
		return 0.0
	return _delayed_tilt.pop_front()


## A swipe of (about) `strength`: a full swipe is easy to repeat exactly,
## a measured one comes out a little off for a person.
func _swipe(strength: float) -> float:
	if strength_jitter <= 0.0 or strength >= 0.95:
		return strength
	return clampf(strength + _rng.randfn() * strength_jitter, 0.0, 1.0)


## Take off now? Yes if the plan's best take-off point is here (or, for a
## person who swipes early, close ahead; for one who swipes late, a moment
## after it was here, unless the floor is about to run out).
func _should_fire(sim: BallSimulation, speed: float, gap: Vector2) -> bool:
	if timing_jitter > 0.0 and is_nan(_jump_offset):
		_jump_offset = _rng.randfn() * timing_jitter
		_fire_wait = maxf(_jump_offset, 0.0)
	var early := maxf(-_jump_offset, 0.0) if not is_nan(_jump_offset) else 0.0
	var due: bool = _plan["takeoff_s"] <= sim.s + speed * (early + 1.0 / STEP_RATE) + 0.01
	if not due:
		return false
	if _fire_wait > 0.0 and gap.x - sim.s > speed * 0.04:
		_fire_wait -= 1.0 / STEP_RATE
		return false
	return true


## Where to steer. In the air: the planned landing. Lining up for a jump:
## towards the landing, as far as the floor we are on allows. Otherwise the
## nearest lane that stays floor the longest.
func _steering_target(sim: BallSimulation, speed: float, gap: Vector2, airborne: bool) -> float:
	var target := NAN
	if airborne:
		var ttl := sim.time_to_land()
		var landing_s := sim.s + speed * ttl
		# Without a planned landing, look from where the ball would come down
		# if the phone were held level (the spin keeps carrying it).
		var start := _landing.y
		if is_nan(start):
			var k := tuning.rolling_resistance
			var flow := sim.spin_speed()
			var drift := flow * ttl + (sim.lateral_speed - flow) * (1.0 - exp(-k * ttl)) / k
			start = sim.angle + drift / level.tunnel_radius
		target = _best_angle(start, landing_s - 0.5, landing_s + speed * 0.3, true)
		if is_nan(target) and not is_nan(_landing.y):
			target = _landing.y
	elif _plan.has("landing_angle"):
		var aim: float = _plan["landing_angle"]
		var route_end := minf(gap.x, sim.s + speed * ROUTE_SECONDS)
		target = _clamp_to_floor(sim.angle, aim, sim.s + 0.5, route_end)
	if is_nan(target):
		for seconds in [2.0, 1.3, 0.9, 0.6, 0.35]:
			# Only lanes we can roll to: a long window can see floor past
			# the next jump, and the way there may be all holes.
			var reach_s := minf(gap.x, sim.s + speed * ROUTE_SECONDS)
			target = _best_angle(sim.angle, sim.s + 0.5, sim.s + speed * seconds, false, sim.s + 0.5, reach_s)
			if not is_nan(target):
				break
	return sim.angle if is_nan(target) else target


## `aim`, or as far towards it from `current` as the floor over [s0, s1]
## lets the ball roll (keeping clear of the edge).
func _clamp_to_floor(current: float, aim: float, s0: float, s1: float) -> float:
	var start := _bin(current)
	var side := 1 if TunnelMath.angle_difference(aim, current) >= 0.0 else -1
	var wanted := int(round(absf(TunnelMath.angle_difference(aim, current)) / TAU * ANGLE_BINS))
	var reach := 0
	if s1 > s0:
		for k in range(1, wanted + 1):
			if _window_blocked(s0, s1, start + side * k):
				break
			reach = k
	else:
		reach = wanted
	var inset := int(ceil(1.1 / level.tunnel_radius / (TAU / ANGLE_BINS)))
	var allowed := wanted if reach >= wanted else maxi(reach - inset, 0)
	return TunnelMath.wrap_angle_positive(current + side * allowed * TAU / ANGLE_BINS)


# --- The floor map ---------------------------------------------------------------

## Bins of cell `cell` where the floor is safe to roll on (both words).
func _row(cell: int) -> PackedInt64Array:
	if _rows.has(cell):
		return _rows[cell]
	var s0 := cell * CELL
	var words := PackedInt64Array([0, 0])
	var window := level.holes_window(s0, s0 + CELL)
	if window.is_empty():
		words[0] = WORD_MASK
		words[1] = WORD_MASK
	else:
		for b in ANGLE_BINS:
			var angle := b * TAU / ANGLE_BINS
			if level.floor_distance_in(window, 0, s0 + CELL * 0.25, angle) > SAFE \
					and level.floor_distance_in(window, 0, s0 + CELL * 0.75, angle) > SAFE:
				words[b / WORD] |= 1 << (b % WORD)
	_rows[cell] = words
	return words


func _cell(s: float) -> int:
	return int(floor(s / CELL))


func _bin(angle: float) -> int:
	return posmod(int(round(angle / TAU * ANGLE_BINS)), ANGLE_BINS)


static func _has(words: PackedInt64Array, bin: int) -> bool:
	var b := posmod(bin, ANGLE_BINS)
	return (words[b / WORD] >> (b % WORD)) & 1 == 1


static func _empty(lo: int, hi: int) -> bool:
	return lo == 0 and hi == 0


## A row with no safe floor anywhere: it can only be jumped.
func _is_jump_row(cell: int) -> bool:
	var row := _row(cell)
	return _empty(row[0], row[1])


## Is angle bin `bin` blocked anywhere in [s0, s1]? Rows with no floor at
## all are ignored: those are jumped, not steered around.
func _window_blocked(s0: float, s1: float, bin: int) -> bool:
	# The window bends with the floor: where the holes wind round (a
	# corkscrew, a funnel turning with the spin), a lane through them does too.
	var turned := 0.0
	for cell in range(_cell(s0), _cell(s1) + 1):
		var row := _row(cell)
		if not _empty(row[0], row[1]) and not _has(row, bin + int(round(turned))):
			return true
		turned += _turn(cell)
	return false


## How many bins the holes in a cell wind round over its length (their
## mean twist; rings and cells without holes do not turn).
func _turn(cell: int) -> float:
	if _turns.has(cell):
		return _turns[cell]
	var s := (cell + 0.5) * CELL
	var total := 0.0
	var count := 0
	for hole in level.holes_between(s - 1.0, s + 1.0):
		if hole.angle_width >= TAU - 0.01 or hole.s_start > s or hole.s_start + hole.length < s:
			continue
		total += hole.twist
		count += 1
	var bins := 0.0 if count == 0 else total / count * CELL / (TAU / ANGLE_BINS)
	_turns[cell] = bins
	return bins


## Where the floor the ball can still roll to runs out, looking `horizon`
## metres ahead from (s, angle), and where any floor starts again after
## that: Vector2(dead end, floor again), or INF if it never runs out.
func _dead_end(s: float, angle: float, speed: float, horizon: float) -> Vector2:
	var c := _cell(s)
	var bin := _bin(angle)
	var lo := 0
	var hi := 0
	for k in [-1, 0, 1]:
		var b := posmod(bin + k, ANGLE_BINS)
		if b < WORD:
			lo |= 1 << b
		else:
			hi |= 1 << (b - WORD)
	var row := _row(c)
	if not _empty(lo & row[0], hi & row[1]):
		lo &= row[0]
		hi &= row[1]
	var bin_width := TAU / ANGLE_BINS * level.tunnel_radius
	var per_cell := ROLL_LATERAL * CELL / maxf(speed, 1.0) / bin_width
	var spread := 0.0
	# The spin carries the ball round as it rolls, so where it can reach
	# drifts with the current (holes that turn with the spin are as easy
	# to roll between as straight ones are without it).
	var drift := 0.0
	var last := _cell(s + horizon)
	while c < last:
		c += 1
		spread += per_cell
		while spread >= 1.0:
			var grown := _dilate(lo, hi)
			lo = grown[0]
			hi = grown[1]
			spread -= 1.0
		drift += level.spin_speed_at(c * CELL) * CELL / maxf(speed, 1.0) / bin_width
		while absf(drift) >= 1.0:
			var turned := _rotate(lo, hi, 1 if drift > 0.0 else -1)
			lo = turned[0]
			hi = turned[1]
			drift -= signf(drift)
		row = _row(c)
		lo &= row[0]
		hi &= row[1]
		if _empty(lo, hi):
			var resume := c
			while resume < last + 80 and _is_jump_row(resume):
				resume += 1
			return Vector2(c * CELL, resume * CELL)
	return Vector2(INF, INF)


## Turns a set of bins one bin round the tunnel (+1: towards bigger angles).
static func _rotate(lo: int, hi: int, direction: int) -> Array[int]:
	if direction > 0:
		return [((lo << 1) & WORD_MASK) | ((hi >> (WORD - 1)) & 1), ((hi << 1) & WORD_MASK) | ((lo >> (WORD - 1)) & 1)]
	return [(lo >> 1) | ((hi & 1) << (WORD - 1)), (hi >> 1) | ((lo & 1) << (WORD - 1))]


## Grows a set of bins by one on each side (round the tunnel).
static func _dilate(lo: int, hi: int) -> Array[int]:
	var up_lo := ((lo << 1) & WORD_MASK) | ((hi >> (WORD - 1)) & 1)
	var up_hi := ((hi << 1) & WORD_MASK) | ((lo >> (WORD - 1)) & 1)
	var down_lo := (lo >> 1) | ((hi & 1) << (WORD - 1))
	var down_hi := (hi >> 1) | ((lo & 1) << (WORD - 1))
	return [lo | up_lo | down_lo, hi | up_hi | down_hi]


## Safe floor over a whole landing: from just before touchdown to a
## little after it (the ball must stay on it while it settles).
func _landing_row(cell: int) -> PackedInt64Array:
	if _landing_rows.has(cell):
		return _landing_rows[cell]
	var a := _row(cell - 1)
	var b := _row(cell)
	var c := _row(cell + 1)
	var words := PackedInt64Array([a[0] & b[0] & c[0], a[1] & b[1] & c[1]])
	_landing_rows[cell] = words
	return words


# --- Jump planning --------------------------------------------------------------

## The best jump over the dead end `gap`: {takeoff_s, strength, landing_s,
## landing_angle, score}, or {} if no jump lands anywhere.
func _plan_jump(sim: BallSimulation, gap: Vector2) -> Dictionary:
	var speed := sim.forward_speed
	var latest := gap.x - 0.1
	var spacing := maxf(speed / STEP_RATE * 2.0, 0.25)
	var reach := speed * 2.0 * sqrt(2.0 * tuning.max_jump_height / tuning.gravity) + 1.0
	if gap.y - sim.s > reach + spacing * TAKEOFF_SAMPLES:
		return {}
	var series := _is_series(gap, speed)
	var options := []
	for k in TAKEOFF_SAMPLES:
		var s_t := sim.s + k * spacing
		if s_t > latest and k > 0:
			break
		# Where the ball will be around the tunnel when it takes off from s_t
		# (the spin and its sideways speed keep carrying it meanwhile).
		var lead_time := (s_t - sim.s) / speed
		var angle_t := sim.angle + sim.lateral_speed * lead_time / level.tunnel_radius
		for strength in COARSE_STRENGTHS:
			var option := _score_jump(sim, s_t, angle_t, sim.lateral_speed, strength, gap, series, false)
			if option.is_empty():
				continue
			# Prefer taking off close to the edge, like a player, not early.
			option["score"] -= 0.04 * maxf(gap.x - s_t - 1.0, 0.0)
			option["takeoff_s"] = s_t
			option["angle_t"] = angle_t
			options.append(option)
	if options.is_empty():
		return {}
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	# Look one jump further: a landing that leaves no way on is a trap.
	var best: Dictionary = options[0]
	for option in options.slice(0, 6):
		if _continues(option["landing_s"], option["landing_angle"]):
			best = option
			break
	# Refine the swipe size around the best coarse one.
	for delta in [-0.1, 0.1]:
		var strength: float = clampf(best["strength"] + delta, 0.0, 1.0)
		var option := _score_jump(sim, best["takeoff_s"], best["angle_t"], sim.lateral_speed, strength, gap, series, false)
		if not option.is_empty():
			option["score"] -= 0.04 * maxf(gap.x - best["takeoff_s"] - 1.0, 0.0)
			if option["score"] > best["score"] and _continues(option["landing_s"], option["landing_angle"]):
				option["takeoff_s"] = best["takeoff_s"]
				option["angle_t"] = best["angle_t"]
				best = option
	return best


## After landing at (s, angle): is there a way on? True if the floor
## reachable by rolling lasts over a second, or some floor after its end is
## within reach of a full jump (steering all the way, carried by the spin).
func _continues(s: float, angle: float) -> bool:
	var v := _speed_at(s)
	var gap := _dead_end(s, angle, v, v * 1.2)
	if gap.x == INF:
		return true
	var air := 2.0 * sqrt(2.0 * tuning.max_jump_height / tuning.gravity)
	var k := tuning.rolling_resistance
	var t := maxf(gap.x - s, 0.0) / v + air
	var reach := tuning.steering_acceleration * tuning.air_control / k * (t - (1.0 - exp(-k * t)) / k) * 0.8
	var centre := _bin(angle + level.spin_speed_at(s) * t / level.tunnel_radius)
	var half := int(reach / level.tunnel_radius / (TAU / ANGLE_BINS))
	if half * 2 + 1 >= ANGLE_BINS:
		return true
	var lo := 0
	var hi := 0
	for d in range(-half, half + 1):
		var b := posmod(centre + d, ANGLE_BINS)
		if b < WORD:
			lo |= 1 << b
		else:
			hi |= 1 << (b - WORD)
	for c in range(_cell(gap.y), _cell(gap.x + v * air) + 1):
		var row := _row(c)
		if not _empty(row[0] & lo, row[1] & hi):
			return true
	return false


## Rings evenly spaced for the maximum jump ("echo runs"): the floor after
## this dead end is short and runs out again.
func _is_series(gap: Vector2, speed: float) -> bool:
	var strip_end := gap.y
	while strip_end < gap.y + speed * 0.5 and not _is_jump_row(_cell(strip_end)):
		strip_end += CELL
	return strip_end < gap.y + speed * 0.5


## How good a jump of `strength` taken off at (s_t, angle_t) is: where it
## lands, how much floor is around that landing, and how far the ball has
## to steer in the air to get there. {} if it cannot land on floor.
func _score_jump(sim: BallSimulation, s_t: float, angle_t: float, lateral: float, strength: float,
		gap: Vector2, series: bool, echo: bool) -> Dictionary:
	var height := minf(sim.jump_height_for_strength(strength), 2.0 * level.tunnel_radius - 2.0 * tuning.ball_radius - 0.3)
	var air := 2.0 * sqrt(2.0 * height / tuning.gravity)
	var v := _speed_at(s_t + _speed_at(s_t) * air * 0.5)
	var s_l := s_t + v * air
	if s_l < gap.y + 0.3:
		return {}
	var k := tuning.rolling_resistance
	var flow := level.spin_speed_at(s_t)
	# A bounce throws the sideways speed away: the ball leaves at most
	# smash_redirect_speed sideways, the way the phone is tilted.
	var start_lateral := 0.0 if echo else lateral
	var decay := 1.0 - exp(-k * air)
	var drift := flow * air + (start_lateral - flow) * decay / k
	# How far sideways the air control can add, after reacting.
	var steer_time := maxf(air - steering_delay * 0.5, 0.0)
	# (The spin is already in the drift: the dynamics are linear.)
	var a := tuning.steering_acceleration * tuning.air_control
	var reach := a / k * (steer_time - (1.0 - exp(-k * steer_time)) / k) * 0.8
	if echo:
		reach += tuning.smash_redirect_speed * decay / k
	var centre := angle_t + drift / level.tunnel_radius
	var reach_bins := int(floor(reach / level.tunnel_radius / (TAU / ANGLE_BINS)))
	var landing := _landing_row(_cell(s_l))
	var centre_bin := _bin(centre)
	var best := {}
	for offset in range(0, reach_bins + 1):
		for side in ([1] if offset == 0 else [1, -1]):
			var bin: int = centre_bin + side * offset
			if not _has(landing, bin):
				continue
			# Land with room to spare either side: a little early or late
			# (or a swipe a little off in size) must still come down on floor.
			var room_s := clampf(v * 0.15, 2.0, 5.0)
			var width := _lateral_room(landing, bin, 1.0)
			var along := _along_room(s_l, bin, room_s)
			if along < 0.5 or width < 0.25:
				continue
			var score := 2.0 * minf(along / room_s, 1.0) + minf(width / 1.0, 1.0)
			score -= 0.8 * float(offset) / maxf(reach_bins, 1)
			# A full swipe is the one size a person repeats exactly: use it
			# when it lands well (and always for evenly spaced rings: echoes).
			if strength >= 1.0:
				score += 0.6 if series else 0.4
			if best.is_empty() or score > best["score"]:
				best = {"strength": strength, "landing_s": s_l, "landing_angle": TunnelMath.wrap_angle_positive(bin * TAU / ANGLE_BINS), "score": score}
		# The nearest good lane wins ties: stop widening once one is found
		# and the next offsets can only score lower.
		if not best.is_empty() and best["score"] > 3.2:
			break
	return best


## Metres of safe floor beside bin `bin` (the smaller side), in a row,
## counted up to `cap`.
func _lateral_room(words: PackedInt64Array, bin: int, cap: float) -> float:
	var bin_width := TAU / ANGLE_BINS * level.tunnel_radius
	var limit := int(ceil(cap / bin_width))
	var room := INF
	for side in [1, -1]:
		var n := 0
		while n < limit and _has(words, bin + side * (n + 1)):
			n += 1
		room = minf(room, n * bin_width)
	return room


## Metres of safe floor before and after s at `bin` (the smaller side),
## counted up to `cap`.
func _along_room(s: float, bin: int, cap: float) -> float:
	var c := _cell(s)
	var limit := int(ceil(cap / CELL))
	var back := 0
	while back < limit and _has(_row(c - back - 1), bin):
		back += 1
	var ahead := 0
	while ahead < limit and _has(_row(c + ahead + 1), bin):
		ahead += 1
	return minf((back + 0.5) * CELL, (ahead + 0.5) * CELL)


## Just before touchdown: if the floor after the landing runs out again
## soon, smash (swipe down) when the bounce lands well, or swipe a better
## size (which fires on landing and re-shapes the jump).
func _decide_landing_action(sim: BallSimulation, speed: float, frame: InputFrame) -> void:
	var landing_s := sim.s + speed * sim.time_to_land()
	var gap := _dead_end(landing_s, sim.angle, speed, speed * 0.6)
	if gap.x == INF or gap.x - landing_s > speed * 0.45:
		return
	var series := _is_series(gap, speed)
	var echo := {}
	if sim.last_jump_height > 0.0:
		var strength := pow(clampf(inverse_lerp(tuning.min_jump_height, tuning.max_jump_height, sim.last_jump_height), 0.0, 1.0), 1.0 / tuning.jump_strength_exponent)
		echo = _score_jump(sim, landing_s, sim.angle, 0.0, strength, gap, series, true)
	var best := {}
	for strength in STRENGTHS:
		var option := _score_jump(sim, landing_s, sim.angle, sim.lateral_speed, strength, gap, series, false)
		if not option.is_empty() and (best.is_empty() or option["score"] > best["score"]):
			best = option
	var tap: bool = not echo.is_empty() and (best.is_empty() or echo["score"] >= best["score"] - 0.35)
	if not tap and best.is_empty():
		return
	var chosen: Dictionary = echo if tap else best
	_landing = Vector2(chosen["landing_s"], chosen["landing_angle"])
	if _tap_offset < -0.05 and timing_jitter > 0.0:
		# Late: after touchdown (the smash still counts up to its grace time).
		_late_tap = -_tap_offset - 0.05
		_late_tap_strength = -1.0 if tap else _swipe(best["strength"])
		return
	if tap:
		frame.smash = true
	else:
		frame.jump_strength = _swipe(best["strength"])


# --- Steering helpers (unchanged in spirit) --------------------------------------

## Angle to aim for: the nearest stretch of floor that stays solid over
## [s0, s1], searching outwards from `current`. Aims well inside that
## stretch (its middle if it is narrow), not at its edge.
##
## With a route window [route_s0, route_s1], the way there must be floor
## too (every angle in between, over that window): stretches past a hole are
## skipped, or with `approach`, still chosen but only gone towards as far as
## the floor allows (lining up for a landing: finish the move in the air).
func _best_angle(current: float, s0: float, s1: float, middle: bool = false, route_s0: float = 0.0, route_s1: float = -1.0, approach: bool = false) -> float:
	var start := _bin(current)
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


## Forward speed at s, smash speed-ups included.
func _speed_at(s: float) -> float:
	return level.speed_at(s) * _boost
