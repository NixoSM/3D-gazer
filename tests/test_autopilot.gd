extends TestCase
## Proves every bundled level can actually be finished with real inputs, and
## that each stays within its difficulty: a bot that steers with a reaction
## delay still finishes each level (the delay it is allowed is set per
## level below, the first level forgiving far more).

## Reaction delay (s) each bundled level must be finished with. Levels not
## listed (a new one from the editor) must manage the old rule, 0.2 s.
## Each is at or under the level's measured reaction budget (the longest
## delay the bot finishes with, see tools/rate_levels.gd and GAME_DESIGN.md);
## the sweep cannot tell the two easiest apart (both pass every delay to
## about 0.5 s), the human-like profiles can. Supernova is meant to be
## beyond human reactions on first sight: only the perfect bot has to
## finish it.
const REACTION := {
	"01_lemonade": 0.35,
	"02_bubblegum": 0.3,
	"03_hot_sauce": 0.15,
	"04_moon_bounce": 0.25,
	"05_mixtape": 0.15,
	"06_screwball": 0.1,
	"07_supernova": 0.0,
}


func test_bot_finishes_every_bundled_level() -> void:
	for id in _level_ids():
		_assert_finishes(id, 0.0)


func test_bot_with_human_reaction_time_finishes_every_level() -> void:
	for id in _level_ids():
		var delay: float = REACTION.get(id, 0.2)
		if delay > 0.0:
			_assert_finishes(id, delay)


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


## Rings with the floor after them in other lanes than before them, at
## 30 m/s (from a level made in the editor): the bot must not cut across a
## hole to line up early, and must jump high enough to switch lanes in the
## air. It used to fall at 225 m even with no reaction delay.
func test_bot_switches_lanes_over_rings_at_speed() -> void:
	var rows := [
		[45.25, 15.25, 0.0, 360.0], [69.75, 10.25, 92.5, 65.0], [70.25, 10.75, 270.0, 60.0],
		[90.75, 15.75, 0.0, 360.0], [115.5, 11.25, 0.0, 60.0], [116.0, 10.25, 180.0, 60.0],
		[136.25, 15.25, 0.0, 360.0], [161.75, 9.0, 268.8, 57.5], [161.75, 9.0, 91.3, 57.5],
		[182.25, 15.5, 0.0, 360.0], [192.5, 37.75, 358.8, 57.5], [195.25, 34.5, 180.0, 60.0],
		[227.75, 16.0, 0.0, 360.0], [236.75, 41.25, 90.0, 60.0], [239.25, 38.0, 270.0, 60.0],
		[275.0, 15.5, 0.0, 360.0], [289.0, 11.75, 1.3, 62.5], [289.5, 10.5, 180.0, 60.0],
	]
	var holes: Array[HoleData] = []
	for row in rows:
		holes.append(HoleData.new(row[0], row[1], deg_to_rad(row[2]), deg_to_rad(row[3])))
	var level := make_level(holes)
	level.length = 330.0
	level.base_speed = 30.0
	for delay in [0.0, 0.2]:
		var tuning := make_tuning()
		var sim := BallSimulation.new(level, tuning)
		var bot := Autopilot.new(level, tuning)
		bot.steering_delay = delay
		while sim.is_playing() and sim.time < 60.0:
			sim.step(1.0 / 120.0, bot.decide(sim))
		assert_eq(sim.phase, BallSimulation.Phase.FINISHED, "reaction %.2f s: fell at %.0f m" % [delay, sim.s])
