extends TestCase
## Limit cases of the smash, the speed-up and the input around them, found by
## tools/stress_smash.gd and tools/stress_flow.gd (2026-11-21).

const E := BallSimulation.EventType
const P := BallSimulation.Phase
const DT := 1.0 / 120.0


static func smash() -> InputFrame:
	return InputFrame.new(0.0, -1.0, true)


func flat(speed: float = 20.0, length: float = 600.0) -> LevelData:
	var level := make_level()
	level.base_speed = speed
	level.speed_ramp = 0.0
	level.length = length
	return level


## A smash that lands on the finish line ends the run there: no hit-stop
## past the line padding the finish time.
func test_smash_landing_on_the_finish_line_finishes_at_once() -> void:
	var tuning := make_tuning()
	for tenth in range(0, 40):
		var level := flat(20.0, 100.0)
		var sim := BallSimulation.new(level, tuning)
		sim.place(level.length - 0.6 - tenth * 0.05)
		sim.step(DT, InputFrame.new(0.0, 0.0))
		sim.step(DT, InputFrame.new())
		sim.step(DT, InputFrame.new())
		var frozen_past_line := 0
		for i in 120:
			sim.step(DT, smash() if i == 0 else InputFrame.new())
			if sim.s >= level.length and sim.phase == P.FROZEN:
				frozen_past_line += 1
		assert_eq(frozen_past_line, 0, "start %.2f m before the line" % (0.6 + tenth * 0.05))
		assert_eq(sim.phase, P.FINISHED)


## A dive that clips the edge of a hole and pops off it has had its impact:
## the next landing must not be a hit-stop and a speed-up.
func test_a_dive_that_pops_off_an_edge_is_not_a_smash_on_the_next_landing() -> void:
	var tuning := make_tuning()
	var holes: Array[HoleData] = [HoleData.new(100.0, 6.0, 0.0, 1.2)]
	var level := make_level(holes)
	level.speed_ramp = 0.0
	var pops := 0
	for speed in [10.0, 30.0, 80.0]:
		level.base_speed = speed
		for lateral in range(-30, 31, 2):
			for k in range(0, 60, 2):
				var sim := BallSimulation.new(level, tuning)
				var landing_s: float = 97.0 + k * 0.2
				sim.place(landing_s - speed * 0.12, lateral * 0.025)
				sim.step(DT, InputFrame.new(0.0, 1.0))
				while sim.vertical_speed > 0.0:
					sim.step(DT, InputFrame.new())
					sim.s = landing_s - speed * 0.12
				sim.step(DT, smash())
				var popped := false
				for i in 240:
					var events := sim.step(DT, InputFrame.new())
					if sim.phase == P.AIRBORNE and sim.vertical_speed > 0.0 and sim.smash_chain == 0:
						popped = true
					for e in events:
						if e.type == E.SMASH_HIT and popped:
							pops += 1
					if not sim.is_playing():
						break
	assert_eq(pops, 0, "smash hits counted on the landing after a pop")


## Rolling off an edge, popping off the far side and landing is not the
## landing of a jump: a swipe down then must not bounce (to the height of
## a jump made long before) nor speed the ball up.
func test_no_late_smash_after_a_landing_that_was_not_a_jump() -> void:
	var tuning := make_tuning()
	var holes: Array[HoleData] = [HoleData.new(60.0, 1.2, 0.0, TAU)]
	var sim := BallSimulation.new(flat(20.0), tuning)
	sim.level.holes = holes
	sim.level.sort()
	# An earlier jump, long landed.
	sim.place(20.0)
	sim.step(DT, InputFrame.new(0.0, 1.0))
	run(sim, 1.2)
	assert_eq(sim.phase, P.ROLLING)
	# Roll into the short gap: the ball dips and pops out on the far side.
	var landed := false
	var events := []
	while sim.s < 70.0 and sim.is_alive():
		var step_events := sim.step(DT, InputFrame.new())
		for e in step_events:
			if e.type == E.LANDED:
				landed = true
		if landed:
			events.append_array(sim.step(DT, smash()))
			break
	assert_true(sim.is_alive(), "the ball rolls over a 1.2 m gap at 20 m/s")
	assert_true(landed, "and lands after dipping into it")
	assert_eq(count(events, E.SMASH_HIT), 0, "no smash without a jump")
	assert_eq(sim.speed_boost, 1.0)


## Spamming the swipe down (every step, finger held or not) never breaks the
## state: no NaN, never under the floor while rolling, the speed-up capped.
func test_smash_spam_keeps_the_state_sane() -> void:
	var tuning := make_tuning()
	for holding in [false, true]:
		var sim := BallSimulation.new(flat(34.0, 5000.0), tuning)
		sim.step(DT, InputFrame.new(0.0, 1.0))
		for i in 2400:
			var f := smash()
			f.holding = holding
			f.tilt = sin(i * 0.05)
			sim.step(DT, f)
			if is_nan(sim.s) or is_nan(sim.height) or is_nan(sim.lateral_speed):
				assert_true(false, "NaN after %d steps" % i)
				return
			if sim.phase == P.ROLLING:
				assert_true(sim.height >= 0.0)
		assert_true(sim.speed_boost <= tuning.smash_speed_max, "boost %.17f" % sim.speed_boost)
		assert_near(sim.forward_speed, 34.0 * tuning.smash_speed_max, 0.0001)


## A finger lifted while input was off (the ball fell, the game was
## paused) is never seen, and a stale finger swallows the next touch.
## InputRouter resets the recognizer whenever input switches on or off and
## on pause (end to end: tools/stress_flow.gd, which needs the autoloads).
func test_a_stale_finger_swallows_the_next_swipe_until_reset() -> void:
	var g := GestureRecognizer.new()
	var h := 1560.0
	g.handle(_touch(0, Vector2(360, 800), true), h)
	g.handle(_drag(0, Vector2(360, 300)), h)
	assert_true(g.swipe_strength >= 0.0, "the first swipe jumps")
	g.consume()
	# The lift is never delivered. Without a reset the next swipe is lost:
	g.handle(_touch(0, Vector2(360, 800), true), h)
	g.handle(_drag(0, Vector2(360, 300)), h)
	assert_eq(g.swipe_strength, -1.0, "(the bug the reset is for)")
	g.reset()
	g.handle(_touch(0, Vector2(360, 800), true), h)
	g.handle(_drag(0, Vector2(360, 300)), h)
	assert_true(g.swipe_strength >= 0.0, "after a reset the next swipe jumps")


func test_reset_forgets_a_held_finger_and_queued_gestures() -> void:
	var g := GestureRecognizer.new()
	g.handle(_touch(0, Vector2(360, 800), true), 1560.0)
	g.smashed = true
	assert_true(g.is_holding())
	g.reset()
	assert_false(g.is_holding(), "no finger keeps the hit-stop open")
	assert_false(g.smashed, "a swipe from before a pause does not fire after it")


## One long frame right after a smash must not fling the camera through the
## floor (camera_height is 1.75 m).
func test_camera_dip_survives_a_long_frame() -> void:
	for hitch in [0.05, 0.15, 0.3, 1.0]:
		var state := Vector2(0.0, 7.0)  # just kicked, the biggest dip
		var worst := 0.0
		state = CameraRig.step_dip(state.x, state.y, 1.0 / 60.0)
		state = CameraRig.step_dip(state.x, state.y, hitch)
		worst = maxf(worst, absf(state.x))
		for i in 120:
			state = CameraRig.step_dip(state.x, state.y, 1.0 / 60.0)
			worst = maxf(worst, absf(state.x))
		assert_true(worst < 0.6, "a %.2f s frame: dip %.2f m" % [hitch, worst])


static func _touch(index: int, position: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = position
	e.pressed = pressed
	return e


static func _drag(index: int, position: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = position
	return e


# --- Smashing onto the edge of a hole -------------------------------------
# Every permutation is swept by tools/stress_edges.gd; these pin the rule.

## A level with one hole (s 100-106, 1.2 rad wide around angle 0) at `speed`.
func edge_level(speed: float, spin: float = 0.0) -> LevelData:
	var holes: Array[HoleData] = [HoleData.new(100.0, 6.0, 0.0, 1.2)]
	var level := make_level(holes)
	level.speed_ramp = 0.0
	level.base_speed = speed
	if spin != 0.0:
		var keys: Array[SpinKey] = [SpinKey.new(0.0, spin)]
		level.spin = keys
	return level


## A ball mid-dive that will reach floor level over (s, angle), `phase`
## splitting the last step differently.
func diving_at(level: LevelData, s: float, angle: float, phase: float = 0.0) -> BallSimulation:
	var sim := BallSimulation.new(level, make_tuning())
	var drop := 0.6 + phase * 0.33
	var fall_time := drop / 40.0
	sim.place(s - level.base_speed * fall_time, angle)
	sim.phase = P.AIRBORNE
	sim.smash_stage = 2
	sim.last_jump_height = 2.0
	sim._can_smash = true
	sim._smash_from = 2.0
	sim.height = drop
	sim.vertical_speed = -40.0
	return sim


## What became of the dive: "smash" (landed and bounced), "fell", or "pop"
## (bounced up off the edge without a smash: the old pinball).
func dive_outcome(sim: BallSimulation) -> String:
	for i in 120:
		var events := sim.step(DT, InputFrame.new())
		for e in events:
			if e.type == E.SMASH_HIT:
				return "smash"
		if not sim.is_alive():
			return "fell"
		if sim.phase == P.AIRBORNE and sim.vertical_speed > 0.0:
			return "pop"
	return "other"


func test_a_smash_that_overlaps_the_lip_enough_lands_on_it() -> void:
	for speed in [20.0, 80.0]:
		for past in [0.0, 0.1, 0.18]:
			# The side edge sits at angle 0.6 rad; past = centre over the void.
			var sim := diving_at(edge_level(speed), 103.0, 0.6 - past / 4.0)
			assert_eq(dive_outcome(sim), "smash", "%.0f m/s, centre %.2f m past the side edge" % [speed, past])
			assert_true(sim.is_alive())
			assert_false(sim.level.is_hole(sim.s, sim.angle, sim.tuning.hole_forgiveness), "the ball sits on the lip")


func test_a_smash_that_misses_the_lip_drops_in_and_stays_in() -> void:
	for speed in [20.0, 80.0]:
		for past in [0.3, 0.4, 0.6]:
			var sim := diving_at(edge_level(speed), 103.0, 0.6 - past / 4.0)
			assert_eq(dive_outcome(sim), "fell", "%.0f m/s, centre %.2f m past the side edge" % [speed, past])
			var peak := sim.height
			for i in 120:
				sim.step(DT, InputFrame.new())
				peak = maxf(peak, sim.height)
			assert_true(peak < 0.05, "it never hops back up out of the hole (%.2f m)" % peak)


## Racing onto the far edge: short of it by a little at floor level, but
## the forward speed puts the ball on the lip within the catch depth.
func test_a_fast_smash_just_short_of_the_far_edge_is_caught() -> void:
	var sim := diving_at(edge_level(80.0), 106.0 - 0.5, 0.0)
	assert_eq(dive_outcome(sim), "smash")


func test_no_dive_onto_any_edge_pops_or_flings_the_ball() -> void:
	var tuning := make_tuning()
	for speed in [20.0, 40.0, 80.0]:
		for spin in [0.0, 60.0]:
			var level := edge_level(speed, spin)
			var cap := tuning.max_lateral_speed + absf(level.spin_speed_at(0.0)) + 0.01
			for k in range(-20, 21):
				var past := k * 0.04
				for target in [Vector2(103.0, 0.6 - past / 4.0), Vector2(100.0 + past, 0.0), Vector2(106.0 - past, 0.0)]:
					var sim := diving_at(level, target.x, target.y)
					var outcome := dive_outcome(sim)
					assert_true(outcome != "pop", "%.0f m/s spin %.0f at %s: popped off the edge" % [speed, spin, target])
					assert_true(absf(sim.lateral_speed) <= cap, "%.0f m/s at %s: flung sideways at %.1f m/s" % [speed, target, sim.lateral_speed])


## Away from the catch line itself, where the ball comes down decides the
## outcome, not how the last frame happened to be split.
func test_an_edge_smash_does_not_depend_on_frame_timing() -> void:
	var tuning := make_tuning()
	for speed in [20.0, 80.0]:
		for past in [-0.2, -0.1, 0.05, 0.12, 0.3, 0.45, 0.7]:
			var outcomes := {}
			for phase in 8:
				var sim := diving_at(edge_level(speed), 103.0, 0.6 - past / 4.0, phase / 8.0)
				outcomes[dive_outcome(sim)] = true
			assert_eq(outcomes.size(), 1, "%.0f m/s, %.2f m past the edge: %s" % [speed, past, outcomes.keys()])
