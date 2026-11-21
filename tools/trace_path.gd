extends SceneTree
## Writes a bot's run through a level as CSV (for tools/level_map.py):
##
##   godot --headless --script res://tools/trace_path.gd -- <level.json> <out.csv> [delay] [seed tilt timing strength]
##
## Rows: time, s, angle (degrees), height, phase, event (JUMP, ECHO, FELL...).


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var tuning: BallTuning = load("res://resources/ball_tuning.tres")
	var level := LevelSerializer.load_file(args[0]).level
	var bot := Autopilot.new(level, tuning)
	if args.size() > 2:
		bot.steering_delay = float(args[2])
	if args.size() > 6:
		bot.noise_seed = int(args[3])
		bot.tilt_noise = float(args[4])
		bot.timing_jitter = float(args[5])
		bot.strength_jitter = float(args[6])
	var sim := BallSimulation.new(level, tuning)
	var out := FileAccess.open(args[1], FileAccess.WRITE)
	out.store_line("t,s,angle,height,phase,event")
	var step := 0
	while sim.is_playing() and sim.time < 300.0:
		var events := sim.step(1.0 / 120.0, bot.decide(sim))
		var names := []
		for e in events:
			var name: String = BallSimulation.EventType.keys()[e.type]
			if e.type == BallSimulation.EventType.JUMPED and e.bounce:
				name = "ECHO"
			names.append(name)
		if step % 3 == 0 or not names.is_empty():
			out.store_line("%.3f,%.3f,%.2f,%.3f,%d,%s" % [sim.time, sim.s, rad_to_deg(sim.angle), sim.height, sim.phase, "|".join(names)])
		step += 1
	out.close()
	print("%s: %s at %.0f m" % [level.id, BallSimulation.Phase.keys()[sim.phase], sim.s])
	quit(0)
