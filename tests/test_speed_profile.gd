extends TestCase


func test_speed_reaches_twenty_percent_more_at_the_end() -> void:
	assert_near(SpeedProfile.speed_at(0.0, 700.0, 10.0, 0.2), 10.0, 0.0001)
	assert_near(SpeedProfile.speed_at(700.0, 700.0, 10.0, 0.2), 12.0, 0.0001)
	assert_near(SpeedProfile.speed_at(350.0, 700.0, 10.0, 0.2), 11.0, 0.0001)


func test_length_for_duration_inverts_duration() -> void:
	var length := SpeedProfile.length_for_duration(60.0, 11.0, 0.2)
	assert_near(SpeedProfile.duration(length, 11.0, 0.2), 60.0, 0.001)


func test_simulated_run_matches_analytic_duration() -> void:
	var level := make_level()
	var sim := BallSimulation.new(level, make_tuning())
	var dt := 1.0 / 120.0
	while sim.phase != BallSimulation.Phase.FINISHED:
		sim.step(dt, InputFrame.new())
	assert_near(sim.time, level.duration(), 0.05)


func test_time_at_matches_duration_and_simulation() -> void:
	var level := make_level()
	assert_near(level.time_at(0.0), 0.0, 0.0001)
	assert_near(level.time_at(level.length), level.duration(), 0.0001)
	var sim := BallSimulation.new(level, make_tuning())
	while sim.s < 250.0:
		sim.step(1.0 / 120.0, InputFrame.new())
	assert_near(level.time_at(sim.s), sim.time, 0.02)
