extends SceneTree
## Bug hunt with bots: plays every level with the Autopilot at several
## reaction delays and checks the simulation's invariants on every step.
## Prints each kind of violation once per level with where it happened.
##
##   godot --headless --script res://tools/invariant_bots.gd

const DT := 1.0 / 120.0
const P := BallSimulation.Phase
const E := BallSimulation.EventType


func _init() -> void:
	var tuning: BallTuning = load("res://resources/ball_tuning.tres")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://levels/manifest.json"))
	var total := 0
	for id in manifest.levels:
		var level: LevelData = LevelSerializer.load_file("res://levels/%s.json" % id).level
		var seen := {}
		var runs := []
		for delay in [0.0, 0.1, 0.2, 0.3]:
			for start_angle in [0.0, 0.7]:
				var sim := BallSimulation.new(level, tuning)
				sim.place(0.0, start_angle)
				var bot := Autopilot.new(level, tuning)
				bot.steering_delay = delay
				var smashes := 0
				var catches := 0
				while sim.is_playing() and sim.time < 150.0:
					var before_phase := sim.phase
					var before_s := sim.s
					var events := sim.step(DT, bot.decide(sim))
					for e in events:
						if e.type == E.SMASH_HIT:
							smashes += 1
							if level.is_hole(e.s, e.angle, tuning.hole_forgiveness):
								_flag(seen, "smash hit over the void", sim, delay)
							if level.floor_distance(e.s, e.angle) < -tuning.hole_forgiveness:
								catches += 1
					_check(seen, sim, tuning, level, delay, before_phase, before_s)
				# Watch the fall too.
				if not sim.is_alive():
					for i in 240:
						sim.step(DT, InputFrame.new())
						_check(seen, sim, tuning, level, delay, P.FALLING, sim.s)
				runs.append("%.1fs/%s: %s %.0f%% smashes %d" % [delay, start_angle, P.keys()[sim.phase], sim.progress() * 100.0, smashes])
		print("%-14s %s" % [id, " | ".join(runs)])
		for k in seen:
			print("    ! %s  (first: %s)" % [k, seen[k]])
		total += seen.size()
	print("\n%d kinds of violation" % total)
	quit()


func _check(seen: Dictionary, sim: BallSimulation, tuning: BallTuning, level: LevelData, delay: float, before_phase: int, before_s: float) -> void:
	if is_nan(sim.s) or is_nan(sim.angle) or is_nan(sim.height) or is_nan(sim.vertical_speed):
		_flag(seen, "NaN", sim, delay)
	if sim.phase == P.ROLLING and sim.height != 0.0:
		_flag(seen, "rolling off the floor (height %.3f)" % sim.height, sim, delay)
	if sim.phase == P.ROLLING and sim.smash_stage != 0:
		_flag(seen, "rolling mid-smash", sim, delay)
	if sim.phase in [P.ROLLING, P.AIRBORNE, P.FROZEN]:
		var cap := tuning.max_lateral_speed + absf(sim.spin_speed()) + 0.01
		if absf(sim.lateral_speed) > cap:
			_flag(seen, "lateral speed over the cap (%.1f m/s)" % sim.lateral_speed, sim, delay)
		var ceiling := 2.0 * level.tunnel_radius - 2.0 * tuning.ball_radius
		if sim.height > ceiling:
			_flag(seen, "through the ceiling", sim, delay)
	if sim.phase == P.FALLING and sim.vertical_speed > BallSimulation.LOST_REBOUND + 0.01:
		_flag(seen, "lost ball rising (%.1f m/s)" % sim.vertical_speed, sim, delay)
	if sim.speed_boost > tuning.smash_speed_max + 1e-9:
		_flag(seen, "speed boost over the cap", sim, delay)
	if sim.phase == P.FROZEN and level.floor_distance(sim.s, sim.angle) < -tuning.hole_forgiveness:
		_flag(seen, "hit-stop with the centre over the void", sim, delay)
	if before_phase != P.FROZEN and sim.phase in [P.ROLLING, P.AIRBORNE] and sim.s < before_s - 0.001:
		_flag(seen, "alive ball moved backwards", sim, delay)
	var pen := _penetration(sim, level, tuning)
	if pen > 0.02:
		_flag(seen, "ball %.2f m inside the wall (%s)" % [pen, P.keys()[sim.phase]], sim, delay)


func _flag(seen: Dictionary, what: String, sim: BallSimulation, delay: float) -> void:
	var key := what.get_slice(" (", 0)
	if not seen.has(key):
		seen[key] = "%s at s %.1f, angle %.0f°, delay %.1f, t %.2f" % [what, sim.s, rad_to_deg(sim.angle), delay, sim.time]


## How deep the ball overlaps the solid shell (0 = not at all).
func _penetration(sim: BallSimulation, level: LevelData, tuning: BallTuning) -> float:
	var r := tuning.ball_radius
	var c := sim.height + r
	var t := TunnelMath.WALL_THICKNESS
	if c >= r or c < -t - r:
		return 0.0
	var d := level.floor_distance(sim.s, sim.angle)
	if d >= 0.0:
		# Over floor: the shell is below c = 0.
		if c >= 0.0:
			return maxf(r - c, 0.0) if c < r and sim.phase != P.FALLING else 0.0
		return r if c > -t else 0.0
	var depth := c - clampf(c, -t, 0.0)
	var dist := Vector2(-d, depth).length()
	return maxf(r - dist, 0.0)
