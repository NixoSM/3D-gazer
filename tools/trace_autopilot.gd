extends SceneTree
## Plays a level with the Autopilot and prints what happened: a quick way to
## see *where* and *why* a level is hard after editing or regenerating it.
##
##   godot --headless --script res://tools/trace_autopilot.gd -- 02_tide


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var id: String = args[0] if args.size() > 0 else "01_dawn"
	var tuning: BallTuning = load("res://resources/ball_tuning.tres")
	var level := LevelSerializer.load_file("res://levels/%s.json" % id).level
	var sim := BallSimulation.new(level, tuning)
	var bot := Autopilot.new(level, tuning)
	var log: Array[String] = []
	while sim.phase in [BallSimulation.Phase.ROLLING, BallSimulation.Phase.AIRBORNE] and sim.time < 120.0:
		for e in sim.step(1.0 / 120.0, bot.decide(sim)):
			log.append("%6.2fs  %7.2fm  %-12s angle %5.0f°  height %.2f%s" % [sim.time, e.s,
				BallSimulation.EventType.keys()[e.type], rad_to_deg(e.angle), e.height, "  echo" if e.echo else ""])
	for line in log.slice(maxi(log.size() - 12, 0)):
		print(line)
	print("\nresult: %s at %.0f m (%.0f%%)" % [BallSimulation.Phase.keys()[sim.phase], sim.s, sim.progress() * 100.0])
	print("holes near the end of the run:")
	for hole in level.holes_between(sim.s - 25.0, sim.s + 3.0):
		print("  s %.1f–%.1f  angle %.0f°  width %.0f°" % [hole.s_start, hole.s_end(), rad_to_deg(hole.angle_center), rad_to_deg(hole.angle_width)])
	quit()
