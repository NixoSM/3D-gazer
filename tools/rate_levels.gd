extends SceneTree
## Rates how hard levels are, with the Autopilot.
##
##   godot --headless --script res://tools/rate_levels.gd -- [ids|all] [--sweep] [--players N] [--profile name] [--dir res://levels/]
##
## --sweep (the default) plays each level with a sweep of reaction delays and
## prints how far each bot gets. The longest delay it still finishes with
## (and every shorter one) is the level's "reaction budget": higher is more
## forgiving. Ember, the hardest of the old levels, measures 0.20 s.
##
## --players N plays each level N times as each human-like profile below
## (a reaction delay plus a wobbling hand, swipes a little early or late and
## a little off in size; a different seed each run) and prints how many
## runs finished and the median distance reached. Roughly: success rate p
## means about 1/p attempts for a player of that kind, once they know the
## level. --profile limits it to one profile (to spread work over processes).

const DELAYS := [0.0, 0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45, 0.5]

## name: [reaction delay s, tilt wobble, timing jitter s, swipe size jitter]
## Two kinds of person: "steady" reacts in a quarter second and is a little
## imprecise; "shaky" is slower, wobblier and less exact with swipes.
## (Ember, the hardest of the old levels, with this bot: 37% steady, 12%
## shaky. The seven levels' numbers are in docs/GAME_DESIGN.md.)
const PROFILES := {
	"steady": [0.25, 0.20, 0.06, 0.15],
	"shaky": [0.30, 0.30, 0.08, 0.20],
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dir := "res://levels/"
	if "--dir" in args:
		dir = args[args.find("--dir") + 1]
	var ids: Array = []
	if args.size() > 0 and not args[0].begins_with("--") and args[0] != "all":
		ids = Array(args[0].split(","))
	else:
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir + "manifest.json"))
		ids = manifest["levels"]
	var players := 0
	if "--players" in args:
		players = int(args[args.find("--players") + 1])
	var only := ""
	if "--profile" in args:
		only = args[args.find("--profile") + 1]
	var tuning: BallTuning = load("res://resources/ball_tuning.tres")
	for id in ids:
		var level := LevelSerializer.load_file(dir + "%s.json" % id).level
		if players > 0:
			for name in PROFILES:
				if only.is_empty() or only == name:
					_rate_players(level, tuning, name, players)
		else:
			_sweep(level, tuning)
	quit(0)


static func _sweep(level: LevelData, tuning: BallTuning) -> void:
	var line := "%-14s %5.1f m/s  %4.0f m  %3d holes |" % [level.id, level.base_speed, level.length, level.holes.size()]
	var budget := -1.0
	var all_ok := true
	for delay in DELAYS:
		var bot := Autopilot.new(level, tuning)
		bot.steering_delay = delay
		var result := play(level, tuning, bot)
		if result.x >= 1.0:
			line += " %4.2f:ok " % delay
			if all_ok:
				budget = delay
		else:
			all_ok = false
			line += " %4.2f:%3d%%" % [delay, int(result.x * 100.0)]
	print(line, "  | budget %.2f s" % budget)


static func _rate_players(level: LevelData, tuning: BallTuning, name: String, runs: int) -> void:
	var profile: Array = PROFILES[name]
	var finished := 0
	var reached: Array[float] = []
	var falls: Array[int] = []
	for seed in runs:
		var bot := Autopilot.new(level, tuning)
		bot.steering_delay = profile[0]
		bot.tilt_noise = profile[1]
		bot.timing_jitter = profile[2]
		bot.strength_jitter = profile[3]
		bot.noise_seed = 1000 + seed * 7919
		var result := play(level, tuning, bot)
		if result.x >= 1.0:
			finished += 1
		else:
			falls.append(int(result.y))
		reached.append(result.x)
	reached.sort()
	falls.sort()
	print("%-14s %-7s %2d/%2d finished (%3d%%)  median %3d%%  falls at %s" % [level.id, name, finished, runs,
		int(100.0 * finished / runs), int(reached[reached.size() / 2] * 100.0), falls])


## Plays to the end or a fall: (progress, or 1 if finished; distance reached).
static func play(level: LevelData, tuning: BallTuning, bot: Autopilot) -> Vector2:
	var sim := BallSimulation.new(level, tuning)
	while sim.is_playing() and sim.time < 300.0:
		sim.step(1.0 / 120.0, bot.decide(sim))
	return Vector2(1.0 if sim.phase == BallSimulation.Phase.FINISHED else sim.progress(), sim.s)
