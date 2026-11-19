class_name LevelBuilder
extends RefCounted
## Helpers for writing levels by hand, in code (tools/author_levels.gd).
##
## Everything is placed on a clock: times are seconds from the start of the
## level, turned into distances by the level's own speed (its ramp and any
## speed surges), so a pattern lands on the beat it was written for even
## after the speeds change. Angles are degrees: 0 is where the ball starts,
## positive is to the player's right. Durations along the tunnel are
## seconds of travel; twists are degrees per second of travel (the band
## turns that fast while the ball rides it).
##
## The result is plain level data: holes, spin keys, speed keys, hints and a
## palette, exactly what the level editor opens and saves.

var level := LevelData.new()
var tuning: BallTuning


## A level lasting about `seconds`, starting at `base_speed` m/s and ending
## `ramp` faster, with speed surges `surges` ([[time s, factor, seconds to
## reach it], ...] in order; factors multiply the base profile).
func _init(id: String, name: String, base_speed: float, ramp: float, seconds: float, surges: Array = [], p_tuning: BallTuning = null) -> void:
	tuning = p_tuning if p_tuning else load("res://resources/ball_tuning.tres")
	level.id = id
	level.display_name = name
	level.base_speed = base_speed
	level.speed_ramp = ramp
	level.tunnel_radius = 4.0
	# The surges are placed by time, and their places depend on the length
	# (the ramp is spread over it): find the length that lasts `seconds`.
	var low := seconds * base_speed * 0.5
	var high := seconds * base_speed * 3.0
	for i in 40:
		var mid := (low + high) * 0.5
		_place_surges(mid, surges)
		if level.duration() < seconds:
			low = mid
		else:
			high = mid
	_place_surges(roundf((low + high) * 0.5), surges)


func _place_surges(length: float, surges: Array) -> void:
	level.length = length
	level.speed_keys = []
	var factor := 1.0
	for surge in surges:
		var s0 := level.s_at_time(float(surge[0]))
		var ramp_m := maxf(level.speed_at(s0) * float(surge[2]), 0.5)
		level.speed_keys.append(SpeedKey.new(s0, factor))
		level.speed_keys.append(SpeedKey.new(s0 + ramp_m, float(surge[1])))
		factor = float(surge[1])
		level.sort()


# --- Clock -------------------------------------------------------------------------

## Distance (m) reached at time t.
func s(t: float) -> float:
	return level.s_at_time(t)


## Forward speed (m/s) at time t.
func v(t: float) -> float:
	return level.speed_at(s(t))


## Seconds in the air for a jump of `height` metres.
func air_time(height: float) -> float:
	return 2.0 * sqrt(2.0 * height / tuning.gravity)


## Seconds in the air for the biggest jump (a full swipe).
func max_air() -> float:
	return air_time(tuning.max_jump_height)


## Seconds in the air for the smallest jump (the shortest swipe).
func min_air() -> float:
	return air_time(tuning.min_jump_height)


## Degrees the spin carries the ball round during an echo of `air` seconds
## (default: a full jump) with the phone held level. An echo throws the
## sideways speed away, so the ball only picks the spin's drift up again
## in the air: much less than spin × air time.
func echo_drift(spin_rate: float, air: float = -1.0) -> float:
	if air < 0.0:
		air = max_air()
	var k := tuning.rolling_resistance
	return spin_rate * (air - (1.0 - exp(-k * air)) / k)


## Degrees the spin carries a ball that is not steered, from time t0 to t1
## (it rolls along with the floor). With the angle a pattern last pinned the
## ball to, this says where a player who lets go will be.
func free_drift(t0: float, t1: float) -> float:
	var total := 0.0
	var t := t0
	while t < t1:
		var dt := minf(0.02, t1 - t)
		total += level.spin_at(s(t + dt * 0.5)) * dt
		t += dt
	return total


# --- Holes -------------------------------------------------------------------------

## A hole from time t lasting `dur` seconds of travel, centred at `at`,
## `width` degrees wide, turning `twist` degrees per second of travel.
func hole(t: float, dur: float, at: float, width: float, twist: float = 0.0) -> HoleData:
	var s0 := s(t)
	var length := s(t + dur) - s0
	var per_metre := twist / v(t + dur * 0.5)
	var h := HoleData.new(s0, length, deg_to_rad(at), deg_to_rad(minf(width, 360.0)), deg_to_rad(per_metre))
	level.holes.append(h)
	return h


## Like hole(), in metres: from s0, `length` long.
func hole_m(s0: float, length: float, at: float, width: float, twist_per_metre: float = 0.0) -> HoleData:
	var h := HoleData.new(s0, length, deg_to_rad(at), deg_to_rad(minf(width, 360.0)), deg_to_rad(twist_per_metre))
	level.holes.append(h)
	return h


## A full ring: the only way through is up.
func ring(t: float, dur: float) -> HoleData:
	return hole(t, dur, 0.0, 360.0)


## Everything open except a band of floor centred at `at`, `width` degrees
## wide (a gate with one gap; twisted, a winding bridge).
func gate(t: float, dur: float, at: float, width: float, twist: float = 0.0) -> HoleData:
	return hole(t, dur, at + 180.0, 360.0 - width, twist)


## Void from t0 to t1 except the given islands of floor. Each island is
## [start time, end time, centre°, width°] plus an optional twist (°/s of
## travel; islands side by side must share their twist). Islands are
## clipped to [t0, t1]. The holes are the islands' complement, cut so that
## touching holes blend into one smooth void.
func void_with(t0: float, t1: float, islands: Array) -> void:
	var s0 := s(t0)
	var s1 := s(t1)
	var parts := []
	for island in islands:
		var a := maxf(s(float(island[0])), s0)
		var b := minf(s(float(island[1])), s1)
		if b <= a:
			continue
		var twist := float(island[4]) if island.size() > 4 else 0.0
		var per_metre := twist / v((float(island[0]) + float(island[1])) * 0.5)
		# Centre at a, from the island's own start.
		var centre := float(island[2]) + per_metre * (a - s(float(island[0])))
		parts.append({"a": a, "b": b, "centre": centre, "width": float(island[3]), "twist": per_metre})
	var cuts := [s0, s1]
	for part in parts:
		cuts.append(part["a"])
		cuts.append(part["b"])
	cuts.sort()
	for i in range(cuts.size() - 1):
		var x: float = cuts[i]
		var y: float = cuts[i + 1]
		if y - x < 0.01:
			continue
		var active := parts.filter(func(p: Dictionary) -> bool: return p["a"] <= x + 0.001 and p["b"] >= y - 0.001)
		if active.is_empty():
			hole_m(x, y - x, 0.0, 360.0)
			continue
		var twist: float = active[0]["twist"]
		var spans := []
		for p in active:
			assert(absf(p["twist"] - twist) < 0.0001, "islands side by side must share their twist")
			var c := fposmod(float(p["centre"]) + twist * (x - float(p["a"])), 360.0)
			spans.append([c - p["width"] * 0.5, c + p["width"] * 0.5])
		spans.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
		for k in spans.size():
			var from: float = spans[k][1]
			var to: float = spans[(k + 1) % spans.size()][0]
			if k == spans.size() - 1:
				to += 360.0
			var width := to - from
			if width > 0.5:
				hole_m(x, y - x, (from + to) * 0.5, width, twist)


# --- Patterns ---------------------------------------------------------------------
# Small, reusable shapes. Each returns the time it ends.

## `count` rings spaced for the biggest jump: one full swipe, then echoes.
## `strip` is the floor between rings, in seconds of travel.
func echo_run(t: float, count: int, strip: float) -> float:
	var period := max_air()
	for i in count:
		ring(t + strip * 0.5 + i * period, period - strip)
	return t + count * period


## An echo run whose landings are islands of floor (`width`°) centred at
## the next angle of `angles`: each bounce must be aimed. With `hoops`
## (width 360) the landings are floating rings, and anything goes.
func pad_run(t: float, angles: Array, width: float, strip: float, period: float = -1.0) -> float:
	if period < 0.0:
		period = max_air()
	var start := t + strip * 0.5
	for i in angles.size():
		ring(start + i * period, period - strip)
		if i < angles.size() - 1 and width < 360.0:
			gate(start + (i + 1) * period - strip, strip, angles[i + 1], width)
	return start + angles.size() * period - strip * 0.5


## Rows of round holes ("dots") around the tunnel, each row turned half a
## spacing from the last, so the way through weaves between them.
## `per_row` dots per row, each `size`° wide and `dur` s long, rows `gap`
## s apart, the first row's first dot at `phase`°.
func dots(t: float, rows: int, per_row: int, size: float, dur: float, gap: float, phase: float, turn: float = -1.0) -> float:
	var spacing := 360.0 / per_row
	if turn < 0.0:
		turn = spacing * 0.5
	for r in rows:
		for k in per_row:
			hole(t + r * gap, dur, phase + r * turn + k * spacing, size)
	return t + (rows - 1) * gap + dur


## A floor band `width`° wide that zigzags: legs of `leg` s, turning
## `rate`°/s one way, then the other. Starts centred at `at`; returns the
## end time (the band ends where it began when `legs` is even).
func zigzag(t: float, legs: int, leg: float, at: float, width: float, rate: float) -> float:
	var centre := at
	for i in legs:
		var r := rate if i % 2 == 0 else -rate
		gate(t + i * leg, leg, centre, width, r)
		centre += r * leg
	return t + legs * leg


## A V of two holes, its point towards the player at `at`°, arms `arm`°
## wide opening `spread`°/s each way over `dur` s: go round either side.
func chevron(t: float, dur: float, at: float, arm: float, spread: float) -> float:
	hole(t, dur, at, arm, spread)
	hole(t, dur, at, arm, -spread)
	return t + dur


## A floor that narrows like a funnel, from `from_width`° to `to_width`°
## over `dur` s, centred at `at` and turning `twist` °/s (at the spin's
## rate, a player who lets go stays in the middle). Leads anyone on the
## floor before it into one lane. Returns the end time.
##
## Two straight walls close in from either side. They must overlap behind
## the player by as much as each will move, so no floor opens up back there
## as they part; that caps the mouth at 180° + half the end width (wider
## is clamped).
func funnel(t: float, dur: float, at: float, from_width: float, to_width: float, twist: float = 0.0) -> float:
	from_width = minf(from_width, 180.0 + to_width * 0.5)
	var close := (from_width - to_width) * 0.5 / dur
	var side := (360.0 - from_width) * 0.5 + close * dur
	hole(t, dur, at - (from_width + side) * 0.5, side, twist + close)
	hole(t, dur, at + (from_width + side) * 0.5, side, twist - close)
	return t + dur


# --- Spin, hints, colour ---------------------------------------------------------

## The ground spin reaches `rate` °/s at time t, over `ramp` seconds.
func spin(t: float, rate: float, ramp: float = 1.0) -> void:
	var s0 := s(t)
	level.spin.append(SpinKey.new(s0, level.spin_at(s0) if not level.spin.is_empty() else 0.0))
	level.spin.append(SpinKey.new(s(t + ramp), rate))
	level.sort()


func hint(t: float, text: String) -> void:
	level.hints.append(LevelHint.new(s(t), text))


func stop(at: float, wall: String, void_color: String, accent: String) -> void:
	level.palette.append(PaletteStop.new(at, Color(wall), Color(void_color), Color(accent)))


## Progress (0..1) at time t, for palette stops placed on the clock.
func at(t: float) -> float:
	return clampf(s(t) / level.length, 0.0, 1.0)


func finish() -> LevelData:
	level.holes = level.holes.filter(func(h: HoleData) -> bool: return h.s_end() <= level.length - 1.0)
	level.sort()
	return level
