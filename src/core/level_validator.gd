class_name LevelValidator
extends RefCounted
## Playability checks for a level: "can a skilled player get through?"
##
## LevelSerializer.validate() checks the file is well-formed; this checks the
## *design*. It is deliberately conservative and cheap, so the level editor
## can run it after every edit (in the background).
##
## Method: slice the tunnel every SAMPLE_STEP metres. A slice is "blocked" if
## no free arc around the circumference is wide enough for the ball. Every
## blocked stretch must be short enough to jump at the local speed, and
## must be followed by enough ground to land on.

const SAMPLE_STEP := 0.25
const ANGLE_BINS := 120
## Share of the theoretical max jump distance we allow a blocked stretch to use.
const JUMP_SAFETY := 0.8
const MIN_LANDING := 1.4


## A stretch where no arc of floor is wide enough for the ball: it must be jumped.
class Gap:
	var s_start: float
	var s_end: float
	## Longest stretch that is safely jumpable here (m).
	var jumpable: float
	## Floor before this gap since the previous one (m).
	var run_up: float

	func length() -> float:
		return s_end - s_start

	func too_long() -> bool:
		return length() > jumpable

	func too_close() -> bool:
		return run_up < MIN_LANDING


class Report:
	var gaps: Array[Gap] = []
	## Widest free arc (m along the wall) of every slice, SAMPLE_STEP apart.
	var free_width := PackedFloat32Array()

	func problems() -> PackedStringArray:
		var lines := PackedStringArray()
		for gap in gaps:
			if gap.too_close():
				lines.append("only %.1f m of ground before the gap at %.0f m" % [gap.run_up, gap.s_start])
			if gap.too_long():
				lines.append("gap at %.0f m is %.1f m long (max %.1f m)" % [gap.s_start, gap.length(), gap.jumpable])
		return lines


static func check(level: LevelData, tuning: BallTuning) -> PackedStringArray:
	return scan(level, tuning).problems()


## Slices the whole level. `cancelled` is polled now and then; return true
## from it to give up early (the editor restarts the scan after each edit).
static func scan(level: LevelData, tuning: BallTuning, cancelled: Callable = Callable()) -> Report:
	var report := Report.new()
	var bin_width := TAU / ANGLE_BINS * level.tunnel_radius
	var needed_bins := int(ceil(_ball_arc(level, tuning) / (TAU / ANGLE_BINS)))
	var blocked_start := -1.0
	var last_blocked_end := -INF
	var s := 0.0
	var slice := 0
	while s <= level.length:
		if cancelled.is_valid() and slice % 64 == 0 and cancelled.call():
			return report
		var free_run := _max_free_run(level, s)
		report.free_width.append(free_run * bin_width)
		var blocked := free_run < needed_bins
		if blocked and blocked_start < 0.0:
			blocked_start = s
		elif not blocked and blocked_start >= 0.0:
			var gap := Gap.new()
			gap.s_start = blocked_start
			gap.s_end = s
			gap.jumpable = max_jump_distance(level, tuning, blocked_start) * JUMP_SAFETY
			gap.run_up = blocked_start - last_blocked_end
			report.gaps.append(gap)
			last_blocked_end = s
			blocked_start = -1.0
		s += SAMPLE_STEP
		slice += 1
	if blocked_start >= 0.0:
		# Open up to the finish line: the run is complete before the ball drops.
		var last := Gap.new()
		last.s_start = blocked_start
		last.s_end = level.length
		last.jumpable = INF
		last.run_up = blocked_start - last_blocked_end
		report.gaps.append(last)
	return report


## Horizontal distance covered by the highest jump at distance s.
static func max_jump_distance(level: LevelData, tuning: BallTuning, s: float) -> float:
	return level.speed_at(s) * air_time(level, tuning, tuning.max_jump_height)


## Seconds in the air for a jump of `height` (capped below the ceiling).
static func air_time(level: LevelData, tuning: BallTuning, height: float) -> float:
	var ceiling := 2.0 * level.tunnel_radius - 2.0 * tuning.ball_radius - 0.3
	return 2.0 * sqrt(2.0 * minf(height, ceiling) / tuning.gravity)


static func _ball_arc(level: LevelData, tuning: BallTuning) -> float:
	# The ball needs its own width plus the forgiveness the simulation grants.
	return (tuning.ball_radius * 2.0 - tuning.hole_forgiveness * 2.0 + 0.2) / level.tunnel_radius


static func _max_free_run(level: LevelData, s: float) -> int:
	# Holes blend (smooth union) up to BLEND/4 beyond their outlines; with no
	# hole within a metre the slice is certainly all floor.
	if level.holes_between(s - 1.0, s + 1.0).is_empty():
		return ANGLE_BINS
	var free := PackedByteArray()
	free.resize(ANGLE_BINS)
	var any_blocked := false
	for i in ANGLE_BINS:
		var angle := (i + 0.5) * TAU / ANGLE_BINS
		var is_free := not level.is_hole(s, angle)
		free[i] = 1 if is_free else 0
		any_blocked = any_blocked or not is_free
	if not any_blocked:
		return ANGLE_BINS
	# Longest circular run of free bins.
	var best := 0
	var run := 0
	for i in ANGLE_BINS * 2:
		if free[i % ANGLE_BINS] == 1:
			run += 1
			best = maxi(best, mini(run, ANGLE_BINS))
		else:
			run = 0
	return best
