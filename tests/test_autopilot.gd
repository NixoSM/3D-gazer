extends TestCase
## Proves every bundled level can actually be finished with real inputs, and
## that the difficulty curve holds: a bot that steers with a human reaction
## delay still finishes everything, and the first level forgives far more.


func test_bot_finishes_every_bundled_level() -> void:
	for id in _level_ids():
		_assert_finishes(id, 0.0)


func test_bot_with_human_reaction_time_finishes_every_level() -> void:
	for id in _level_ids():
		_assert_finishes(id, 0.2)


func test_first_level_forgives_slow_reactions() -> void:
	_assert_finishes(_level_ids()[0], 0.35)


func _level_ids() -> Array:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://levels/manifest.json"))
	return manifest["levels"]


func _assert_finishes(id: String, steering_delay: float) -> void:
	var tuning: BallTuning = load("res://resources/ball_tuning.tres")
	var level := LevelSerializer.load_file("res://levels/%s.json" % id).level
	var sim := BallSimulation.new(level, tuning)
	var bot := Autopilot.new(level, tuning)
	bot.steering_delay = steering_delay
	var dt := 1.0 / 120.0
	while sim.is_playing() and sim.time < 120.0:
		sim.step(dt, bot.decide(sim))
	assert_eq(sim.phase, BallSimulation.Phase.FINISHED,
		"%s (reaction %.2f s): bot fell at %.0f m (%.0f%%), angle %.0f°" % [id, steering_delay, sim.s, sim.progress() * 100.0, rad_to_deg(sim.angle)])
