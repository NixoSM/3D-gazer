class_name LevelValidator
extends RefCounted
## Playability checks for a level: "can a skilled player get through?"
##
## LevelSerializer.validate() checks the file is well-formed; this checks the
## *design*. It is deliberately conservative and cheap, so the future level
## editor can run it live while someone drags holes around.
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


static func check(level: LevelData, tuning: BallTuning) -> PackedStringArray:
	var problems := PackedStringArray()
	var needed_bins := int(ceil(_ball_arc(level, tuning) / (TAU / ANGLE_BINS)))
	var blocked_start := -1.0
	var last_blocked_end := -INF
	var s := 0.0
	while s <= level.length:
		var blocked := _max_free_run(level, s) < needed_bins
		if blocked and blocked_start < 0.0:
			blocked_start = s
			if s - last_blocked_end < MIN_LANDING:
				problems.append("only %.1f m of ground before the gap at %.0f m" % [s - last_blocked_end, s])
		elif not blocked and blocked_start >= 0.0:
			var stretch := s - blocked_start
			var jumpable := max_jump_distance(level, tuning, blocked_start) * JUMP_SAFETY
			if stretch > jumpable:
				problems.append("gap at %.0f m is %.1f m long (max %.1f m)" % [blocked_start, stretch, jumpable])
			last_blocked_end = s
			blocked_start = -1.0
		s += SAMPLE_STEP
	return problems


## Horizontal distance covered by the highest jump at distance s.
static func max_jump_distance(level: LevelData, tuning: BallTuning, s: float) -> float:
	var ceiling := 2.0 * level.tunnel_radius - 2.0 * tuning.ball_radius - 0.3
	var height := minf(tuning.max_jump_height, ceiling)
	var air_time := 2.0 * sqrt(2.0 * height / tuning.gravity)
	return level.speed_at(s) * air_time


static func _ball_arc(level: LevelData, tuning: BallTuning) -> float:
	# The ball needs its own width plus the forgiveness the simulation grants.
	return (tuning.ball_radius * 2.0 - tuning.hole_forgiveness * 2.0 + 0.2) / level.tunnel_radius


static func _max_free_run(level: LevelData, s: float) -> int:
	var free := PackedByteArray()
	free.resize(ANGLE_BINS)
	var any_blocked := false
	for i in ANGLE_BINS:
		var angle := (i + 0.5) * TAU / ANGLE_BINS
		var is_free := level.hole_at(s, angle) == null
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
