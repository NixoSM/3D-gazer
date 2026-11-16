extends TestCase

const E := BallSimulation.EventType


func test_tilt_accelerates_and_ball_coasts_after_release() -> void:
	var sim := BallSimulation.new(make_level(), make_tuning())
	run(sim, 0.5, InputFrame.new(1.0))
	var speed_after_tilt := sim.lateral_speed
	assert_true(speed_after_tilt > 1.0, "tilting right builds rightward speed")
	run(sim, 1.0 / 120.0, InputFrame.new(0.0))
	assert_true(sim.lateral_speed > speed_after_tilt * 0.95, "neutral does not stop the ball instantly")
	run(sim, 3.0, InputFrame.new(0.0))
	assert_true(absf(sim.lateral_speed) < speed_after_tilt * 0.1, "rolling resistance eventually stops it")


func test_tilt_left_moves_angle_down() -> void:
	var sim := BallSimulation.new(make_level(), make_tuning())
	run(sim, 0.5, InputFrame.new(-1.0))
	assert_true(TunnelMath.angle_difference(sim.angle, 0.0) < -0.05)


func test_bigger_swipe_jumps_higher() -> void:
	var tuning := make_tuning()
	var small := BallSimulation.new(make_level(), tuning)
	var big := BallSimulation.new(make_level(), tuning)
	small.step(1.0 / 120.0, InputFrame.new(0.0, 0.2))
	big.step(1.0 / 120.0, InputFrame.new(0.0, 1.0))
	assert_true(big.last_jump_height > small.last_jump_height + 1.0)
	assert_near(big.last_jump_height, tuning.max_jump_height, 0.001)


func test_jump_reaches_requested_height() -> void:
	var sim := BallSimulation.new(make_level(), make_tuning())
	sim.step(1.0 / 240.0, InputFrame.new(0.0, 1.0))
	var peak := 0.0
	while sim.phase == BallSimulation.Phase.AIRBORNE:
		sim.step(1.0 / 240.0, InputFrame.new())
		peak = maxf(peak, sim.height)
	assert_near(peak, sim.last_jump_height, 0.08)


func test_tap_just_before_landing_echoes_same_jump() -> void:
	var sim := BallSimulation.new(make_level(), make_tuning())
	sim.step(1.0 / 120.0, InputFrame.new(0.0, 0.6))
	var height := sim.last_jump_height
	while sim.time_to_land() > 0.04:
		sim.step(1.0 / 120.0, InputFrame.new())
	var events := sim.step(1.0 / 120.0, InputFrame.new(0.0, -1.0, true))
	events.append_array(run(sim, 0.3))
	var echoes := events.filter(func(e: BallSimulation.SimEvent) -> bool: return e.type == E.JUMPED and e.echo)
	assert_eq(echoes.size(), 1, "one echo jump")
	assert_true(echoes[0].perfect, "tap 40 ms before touchdown is perfect")
	assert_near(sim.last_jump_height, height, 0.0001, "echo repeats the same height")
	assert_eq(sim.echo_chain, 1)


func test_tap_just_after_landing_still_echoes() -> void:
	var sim := BallSimulation.new(make_level(), make_tuning())
	sim.step(1.0 / 120.0, InputFrame.new(0.0, 0.3))
	while sim.phase == BallSimulation.Phase.AIRBORNE:
		sim.step(1.0 / 120.0, InputFrame.new())
	run(sim, 0.05)
	var events := sim.step(1.0 / 120.0, InputFrame.new(0.0, -1.0, true))
	assert_eq(count(events, E.ECHO_HIT), 1)
	events.append_array(run(sim, 0.3))
	assert_eq(count(events, E.JUMPED), 1)


func test_late_tap_does_nothing_and_breaks_chain() -> void:
	var sim := BallSimulation.new(make_level(), make_tuning())
	sim.step(1.0 / 120.0, InputFrame.new(0.0, 0.3))
	while sim.phase == BallSimulation.Phase.AIRBORNE:
		sim.step(1.0 / 120.0, InputFrame.new())
	run(sim, 0.4)
	var events := sim.step(1.0 / 120.0, InputFrame.new(0.0, -1.0, true))
	assert_eq(count(events, E.JUMPED), 0)
	assert_eq(sim.echo_chain, 0)


func test_early_tap_mid_air_is_ignored() -> void:
	var sim := BallSimulation.new(make_level(), make_tuning())
	sim.step(1.0 / 120.0, InputFrame.new(0.0, 1.0))
	sim.step(1.0 / 120.0, InputFrame.new(0.0, -1.0, true))
	var events := run(sim, 1.5)
	assert_eq(count(events, E.JUMPED), 0, "tapping right after take-off must not queue an echo")


func test_rolling_into_a_hole_falls() -> void:
	var holes: Array[HoleData] = [HoleData.new(20.0, 6.0, 0.0, deg_to_rad(90.0))]
	var sim := BallSimulation.new(make_level(holes), make_tuning())
	var events := run(sim, 3.0)
	assert_eq(count(events, E.FELL), 1)
	assert_false(sim.is_alive())


func test_steering_around_a_hole_survives() -> void:
	var holes: Array[HoleData] = [HoleData.new(30.0, 6.0, 0.0, deg_to_rad(90.0))]
	var sim := BallSimulation.new(make_level(holes), make_tuning())
	var events := run(sim, 1.2, InputFrame.new(1.0))
	events.append_array(run(sim, 3.0, InputFrame.new(0.0)))
	assert_eq(count(events, E.FELL), 0)


func test_jumping_over_a_ring_survives() -> void:
	var holes: Array[HoleData] = [HoleData.new(22.0, 4.0, 0.0, TAU)]
	var sim := BallSimulation.new(make_level(holes), make_tuning())
	run(sim, 1.9)
	var events := sim.step(1.0 / 120.0, InputFrame.new(0.0, 0.7))
	events.append_array(run(sim, 3.0))
	assert_eq(count(events, E.FELL), 0)
	assert_eq(count(events, E.LANDED), 1)


func test_simulation_is_deterministic() -> void:
	var a := BallSimulation.new(make_level(), make_tuning())
	var b := BallSimulation.new(make_level(), make_tuning())
	for i in 600:
		var input := InputFrame.new(sin(i * 0.05), 0.5 if i % 97 == 0 else -1.0, i % 41 == 0)
		a.step(1.0 / 120.0, input)
		b.step(1.0 / 120.0, input)
	assert_eq(a.s, b.s)
	assert_eq(a.angle, b.angle)
	assert_eq(a.height, b.height)


static func spin_level(rate: float, holes: Array[HoleData] = []) -> LevelData:
	var level := make_level(holes)
	level.spin = [SpinKey.new(0.0, rate)]
	return level


func test_spin_carries_the_ball_sideways() -> void:
	var sim := BallSimulation.new(spin_level(30.0), make_tuning())
	run(sim, 4.0)
	var turned := rad_to_deg(TunnelMath.angle_difference(sim.angle, 0.0))
	# Starts at rest and relaxes to 30°/s (time constant 1 / rolling_resistance).
	assert_true(turned > 60.0 and turned < 120.0, "4 s of 30°/s spin turned %.0f°" % turned)
	assert_near(sim.spin_rate(), 30.0, 0.001)


func test_counter_tilt_holds_against_spin() -> void:
	var tuning := make_tuning()
	var sim := BallSimulation.new(spin_level(30.0), tuning)
	# Tilt that exactly cancels the drift: a = flow * resistance.
	var flow := deg_to_rad(30.0) * 4.0
	var tilt := -flow * tuning.rolling_resistance / tuning.steering_acceleration
	run(sim, 4.0, InputFrame.new(tilt))
	assert_true(absf(sim.lateral_speed) < 0.05, "balanced: lateral speed %.3f" % sim.lateral_speed)


func test_echo_never_changes_the_spin() -> void:
	var sim := BallSimulation.new(spin_level(20.0), make_tuning())
	sim.step(1.0 / 120.0, InputFrame.new(0.0, 0.6))
	while sim.time_to_land() > 0.04:
		sim.step(1.0 / 120.0, InputFrame.new())
	var events: Array = sim.step(1.0 / 120.0, InputFrame.new(0.0, -1.0, true))
	events.append_array(run(sim, 0.3))
	var echoes := events.filter(func(e: BallSimulation.SimEvent) -> bool: return e.type == E.JUMPED and e.echo)
	assert_eq(echoes.size(), 1)
	assert_near(sim.spin_rate(), 20.0, 0.001)


## An echo throws away sideways momentum: the tilt held during the
## hit-stop decides where the ball goes, at once.
func test_echo_takes_off_in_the_direction_of_the_tilt() -> void:
	var tuning := make_tuning()
	var sim := BallSimulation.new(make_level(), tuning)
	# Build up speed to the right, then jump.
	run(sim, 1.0, InputFrame.new(1.0))
	sim.step(1.0 / 120.0, InputFrame.new(1.0, 0.6))
	while sim.time_to_land() > 0.04:
		sim.step(1.0 / 120.0, InputFrame.new(1.0))
	assert_true(sim.lateral_speed > 5.0, "moving right fast (%.1f m/s)" % sim.lateral_speed)
	sim.step(1.0 / 120.0, InputFrame.new(1.0, -1.0, true))
	while sim.phase != BallSimulation.Phase.FROZEN:
		sim.step(1.0 / 120.0, InputFrame.new(1.0))
	# During the freeze the player tilts left.
	while sim.phase == BallSimulation.Phase.FROZEN:
		sim.step(1.0 / 120.0, InputFrame.new(-1.0))
	assert_true(sim.lateral_speed < 0.0, "the ball now heads left (%.2f m/s)" % sim.lateral_speed)
	assert_near(sim.lateral_speed, -tuning.echo_redirect_speed, 0.5)


## The fall must never put the ball inside the shell around a hole, however
## it reaches the far edge (the "clipping" bug).
func test_falling_ball_never_passes_through_the_walls_of_the_cut() -> void:
	var tuning := make_tuning()
	for hole_length in [2.6, 3.2, 4.5, 8.0]:
		for jump in [-1.0, 0.25, 0.5]:
			var hole := HoleData.new(20.0, hole_length, 0.0, TAU)
			var holes: Array[HoleData] = [hole]
			var sim := BallSimulation.new(make_level(holes), tuning)
			# Optionally jump so the ball comes down at different spots.
			while sim.s < 20.0 - 6.0 * maxf(jump, 0.0):
				sim.step(1.0 / 120.0, InputFrame.new())
			if jump > 0.0:
				sim.step(1.0 / 120.0, InputFrame.new(0.0, jump))
			var worst := 0.0
			for i in 360:
				sim.step(1.0 / 120.0, InputFrame.new())
				worst = maxf(worst, _penetration(sim, hole, tuning))
			assert_true(worst < 0.002, "hole %.1f m, jump %.2f: ball %.3f m inside the wall" % [hole_length, jump, worst])


func test_ball_that_drops_into_a_short_hole_hits_the_far_wall_and_bounces_back() -> void:
	var holes: Array[HoleData] = [HoleData.new(20.0, 2.6, 0.0, TAU)]
	var sim := BallSimulation.new(make_level(holes), make_tuning())
	var events := run(sim, 2.6)
	assert_eq(count(events, E.FELL), 1)
	assert_true(count(events, E.BUMPED) >= 1, "the far wall was hit")
	assert_true(sim.s < 22.6, "the ball stayed behind the far wall (s = %.2f)" % sim.s)


func test_late_swipe_after_leaving_the_edge_still_jumps() -> void:
	var holes: Array[HoleData] = [HoleData.new(20.0, 4.0, 0.0, TAU)]
	var tuning := make_tuning()
	var sim := BallSimulation.new(make_level(holes), tuning)
	while sim.phase == BallSimulation.Phase.ROLLING:
		sim.step(1.0 / 120.0, InputFrame.new())
	sim.step(1.0 / 120.0, InputFrame.new())
	sim.step(1.0 / 120.0, InputFrame.new())
	var events := sim.step(1.0 / 120.0, InputFrame.new(0.0, 0.8))
	assert_eq(count(events, E.JUMPED), 1, "coyote time accepts the jump")
	assert_eq(count(run(sim, 2.0), E.FELL), 0)


## How far the ball's sphere overlaps the solid shell (any hole shape).
static func _penetration(sim: BallSimulation, _hole: HoleData, tuning: BallTuning) -> float:
	var r := tuning.ball_radius
	var c := sim.height + r
	var thickness := TunnelMath.WALL_THICKNESS
	if c >= r or c < -thickness - r:
		return 0.0
	var worst := 0.0
	# Sample the shell around the ball and measure the deepest overlap.
	for du in range(-6, 7):
		for dv in range(-6, 7):
			var u := du * r / 6.0
			var v := dv * r / 6.0
			var point_s := sim.s + u
			var point_angle := sim.angle + v / sim.level.tunnel_radius
			if sim.level.floor_distance(point_s, point_angle) < 0.0:
				continue
			var z := clampf(c, -thickness, 0.0)
			var d := Vector3(u, v, c - z).length()
			worst = maxf(worst, r - d)
	return worst


func test_echo_freezes_the_ball_then_jumps() -> void:
	var tuning := make_tuning()
	var sim := BallSimulation.new(make_level(), tuning)
	sim.step(1.0 / 120.0, InputFrame.new(0.0, 0.6))
	while sim.time_to_land() > 0.03:
		sim.step(1.0 / 120.0, InputFrame.new())
	var events: Array = sim.step(1.0 / 120.0, InputFrame.new(0.0, -1.0, true))
	events.append_array(run(sim, 0.05))
	assert_eq(count(events, E.ECHO_HIT), 1, "the echo connects on landing")
	assert_eq(sim.phase, BallSimulation.Phase.FROZEN)
	var held := sim.s
	run(sim, tuning.echo_freeze_time * 0.5)
	assert_eq(sim.s, held, "nothing moves during the hit-stop")
	events = run(sim, tuning.echo_freeze_time)
	assert_eq(count(events, E.JUMPED), 1, "then the echo jump fires")
	assert_true(sim.s > held)


func test_swipe_during_the_freeze_sets_the_echo_height() -> void:
	var tuning := make_tuning()
	var sim := BallSimulation.new(make_level(), tuning)
	sim.step(1.0 / 120.0, InputFrame.new(0.0, 0.3))
	var low := sim.last_jump_height
	while sim.time_to_land() > 0.03:
		sim.step(1.0 / 120.0, InputFrame.new())
	sim.step(1.0 / 120.0, InputFrame.new(0.0, -1.0, true))
	run(sim, 0.05)
	assert_eq(sim.phase, BallSimulation.Phase.FROZEN)
	var events := sim.step(1.0 / 120.0, InputFrame.new(0.0, 1.0))
	assert_eq(count(events, E.JUMPED), 1, "the swipe ends the freeze at once")
	assert_true(events[0].echo, "and it still counts as an echo")
	assert_near(sim.last_jump_height, tuning.max_jump_height, 0.001)
	assert_true(sim.last_jump_height > low + 1.0)
	assert_eq(sim.echo_chain, 1)


func test_freeze_waits_for_a_finger_that_is_still_down() -> void:
	var tuning := make_tuning()
	var sim := BallSimulation.new(make_level(), tuning)
	sim.step(1.0 / 120.0, InputFrame.new(0.0, 0.3))
	while sim.time_to_land() > 0.03:
		sim.step(1.0 / 120.0, InputFrame.new())
	sim.step(1.0 / 120.0, InputFrame.new(0.0, -1.0, true))
	run(sim, 0.05)
	var holding := InputFrame.new()
	holding.holding = true
	run(sim, tuning.echo_freeze_time + 0.05, holding)
	assert_eq(sim.phase, BallSimulation.Phase.FROZEN, "still waiting for the swipe")
	run(sim, tuning.echo_freeze_max, holding)
	assert_eq(sim.phase, BallSimulation.Phase.AIRBORNE, "but never longer than the limit")
