extends TestCase
## Proves every bundled level can actually be finished with real inputs.


func test_bot_finishes_every_bundled_level() -> void:
	var tuning: BallTuning = load("res://resources/ball_tuning.tres")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://levels/manifest.json"))
	for id in manifest["levels"]:
		var level := LevelSerializer.load_file("res://levels/%s.json" % id).level
		var sim := BallSimulation.new(level, tuning)
		var bot := Autopilot.new(level, tuning)
		var dt := 1.0 / 120.0
		while sim.phase in [BallSimulation.Phase.ROLLING, BallSimulation.Phase.AIRBORNE] and sim.time < 120.0:
			sim.step(dt, bot.decide(sim))
		assert_eq(sim.phase, BallSimulation.Phase.FINISHED,
			"%s: bot fell at %.0f m (%.0f%%), angle %.0f°" % [id, sim.s, sim.progress() * 100.0, rad_to_deg(sim.angle)])
