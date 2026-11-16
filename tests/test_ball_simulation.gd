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
	events.append_array(run(sim, 0.1))
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
