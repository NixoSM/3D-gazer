extends SceneTree
## Edge-case probes for the smash and the speed-up (not a test: it measures
## and prints, so limits can be read before they are turned into tests).
##
##   godot --headless --script res://tools/stress_smash.gd

const DT := 1.0 / 120.0
const E := BallSimulation.EventType
const P := BallSimulation.Phase

var tuning: BallTuning = load("res://resources/ball_tuning.tres")
var levels: Array[LevelData] = []


func _init() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://levels/manifest.json"))
	for id in manifest.levels:
		levels.append(LevelSerializer.load_file("res://levels/%s.json" % id).level)
	if "--finish" not in OS.get_cmdline_user_args():
		probe_spam()
		probe_cap()
		probe_roll_over_holes()
		probe_dive_onto_edges()
	probe_finish_line()
	probe_camera_dip()
	quit()


func flat_level(speed: float = 20.0) -> LevelData:
	var level := TestCase.make_level()
	level.base_speed = speed
	level.speed_ramp = 0.0
	level.length = 5000.0
	return level


## Smash as fast as possible (every step) and as fast as a thumb can (every
## `period` s): how much of the time is the world frozen, and how fast does
## the ball really travel?
func probe_spam() -> void:
	print("\n== smash spam on a flat 20 m/s level, 6 s after one big jump ==")
	for period in [DT, 0.12, 0.2, 0.35]:
		for holding in [false, true]:
			var sim := BallSimulation.new(flat_level(), tuning)
			sim.step(DT, InputFrame.new(0.0, 1.0))
			var frozen := 0.0
			var next := 0.0
			var hits := 0
			var max_h := 0.0
			var start_s := sim.s
			var t0 := sim.time
			while sim.time - t0 < 6.0:
				var f := InputFrame.new()
				if sim.time - t0 >= next:
					f.smash = true
					next += period
				f.holding = holding
				for e in sim.step(DT, f):
					if e.type == E.SMASH_HIT:
						hits += 1
				if sim.phase == P.FROZEN:
					frozen += DT
				max_h = maxf(max_h, sim.height)
			var travelled := sim.s - start_s
			print("  swipe every %.3f s, finger held=%s: %d smashes, frozen %.0f%% of the time, boost %.2f, avg speed %.1f m/s (level x boost = %.1f), max height %.2f m" % [
				period, holding, hits, frozen / 6.0 * 100.0, sim.speed_boost, travelled / 6.0, 20.0 * sim.speed_boost, max_h])


func probe_cap() -> void:
	print("\n== speed cap ==")
	var sim := BallSimulation.new(flat_level(), tuning)
	sim.step(DT, InputFrame.new(0.0, 0.2))
	var smash := InputFrame.new(0.0, -1.0, true)
	for i in 6000:
		sim.step(DT, smash)
	print("  after %d smashes: boost=%.17f  (max %.2f)  forward=%.4f" % [sim.smash_count, sim.speed_boost, tuning.smash_speed_max, sim.forward_speed])
	var exact := 1.0
	for i in 15:
		exact += tuning.smash_speed_gain
	print("  15 x 0.04 in floats = %.17f" % exact)


## A rolling ball needs time to sink below the far edge's pop limit, so a
## gap crossed fast enough is rolled over without a jump. The faster the
## ball (smashes add up to +60%), the longer the gaps that stop mattering.
func probe_roll_over_holes() -> void:
	print("\n== longest full-ring gap rolled over with no input ==")
	for v in [20.0, 27.0, 34.0, 51.0, 54.4, 81.6]:
		var gap := 0.2
		while _rolls_over(gap + 0.1, v):
			gap += 0.1
		print("  %5.1f m/s: %.1f m (%.3f s of travel)" % [v, gap, gap / v])


func _rolls_over(gap: float, speed: float) -> bool:
	var holes: Array[HoleData] = [HoleData.new(50.0, gap, 0.0, TAU)]
	var level := TestCase.make_level(holes)
	level.base_speed = speed
	level.speed_ramp = 0.0
	var sim := BallSimulation.new(level, tuning)
	sim.place(45.0)
	while sim.s < 50.0 + gap + 3.0 and sim.is_alive():
		sim.step(DT, InputFrame.new())
	return sim.is_alive()


## Dive onto every offset near a hole edge: does the ball ever end up inside
## the wall, frozen over the void, or with a NaN?
func probe_dive_onto_edges() -> void:
	print("\n== smash dives onto a hole's edges (far, near, side) ==")
	var holes: Array[HoleData] = [HoleData.new(100.0, 6.0, 0.0, 1.2)]
	var level := TestCase.make_level(holes)
	level.speed_ramp = 0.0
	var problems := {}
	var outcomes := {}
	for speed in [10.0, 30.0, 80.0]:
		level.base_speed = speed
		for lateral in range(-30, 31):
			for dive_s_index in range(0, 60):
				var sim := BallSimulation.new(level, tuning)
				var landing_s: float = 97.0 + dive_s_index * 0.2
				var a: float = lateral * 0.025
				# Start in the air above a spot so the dive lands at landing_s.
				sim.place(landing_s - speed * 0.12, a)
				sim.step(DT, InputFrame.new(0.0, 1.0))
				while sim.vertical_speed > 0.0:
					sim.step(DT, InputFrame.new())
					sim.s = landing_s - speed * 0.12
				sim.step(DT, InputFrame.new(0.0, -1.0, true))
				var steps := 0
				var popped_still_smashing := false
				var last_phase := sim.phase
				while steps < 240 and sim.phase != P.FALLING:
					var events := sim.step(DT, InputFrame.new())
					steps += 1
					if is_nan(sim.height) or is_nan(sim.s):
						problems["nan"] = problems.get("nan", 0) + 1
						break
					if sim.phase == P.ROLLING and sim.height < -0.001:
						problems["rolling below the floor"] = problems.get("rolling below the floor", 0) + 1
					if sim.phase == P.FROZEN and level.is_hole(sim.s, sim.angle, tuning.hole_forgiveness):
						problems["frozen over the void"] = problems.get("frozen over the void", 0) + 1
					if sim.smash_stage == 2 and sim.vertical_speed > 0.0:
						popped_still_smashing = true
					for e in events:
						if e.type == E.SMASH_HIT and popped_still_smashing:
							problems["pop off an edge, then counted as a smash on the next landing"] = problems.get("pop off an edge, then counted as a smash on the next landing", 0) + 1
					if sim.phase == P.AIRBORNE and sim.smash_chain >= 1 and sim.smash_stage == 0 and sim.vertical_speed < 0.0:
						break
				var key := "fell" if sim.phase == P.FALLING else "survived"
				outcomes[key] = outcomes.get(key, 0) + 1
	print("  outcomes: ", outcomes)
	print("  problems: ", problems if not problems.is_empty() else "none")


## Smash so the impact lands on or past the finish line.
func probe_finish_line() -> void:
	print("\n== smash across the finish line (20 m/s, length 100) ==")
	var level := flat_level(20.0)
	level.length = 100.0
	for tenth in range(0, 30, 2):
		var d: float = tenth * 0.1
		var sim := BallSimulation.new(level, tuning)
		sim.place(level.length - d)
		sim.step(DT, InputFrame.new(0.0, 0.0))
		sim.step(DT, InputFrame.new())
		sim.step(DT, InputFrame.new())
		var hit_s := -1.0
		var finish_t := -1.0
		var finish_phase := ""
		var frozen_after := 0
		for i in 120:
			var pre := sim.phase
			var f := InputFrame.new(0.0, -1.0, i == 0)
			for e in sim.step(DT, f):
				if e.type == E.SMASH_HIT:
					hit_s = e.s
				if e.type == E.FINISHED:
					finish_t = sim.time
					finish_phase = P.keys()[pre]
			if sim.s >= level.length and sim.phase == P.FROZEN:
				frozen_after += 1
		print("  start %.1f m before the line: hit at s=%.2f, finished t=%.3f (phase before %s), steps frozen past the line %d, boost %.2f" % [d, hit_s, finish_t, finish_phase, frozen_after, sim.speed_boost])


## CameraRig's dip spring, fed one kick per smash at spam rate, at 60, 30 fps
## and with one long frame (a hitch) in the middle.
func probe_camera_dip() -> void:
	print("\n== camera dip spring (CameraRig) under repeated smashes; camera_height is 1.75 m ==")
	for fps in [120.0, 60.0, 30.0]:
		for hitch in [0.0, 0.15, 0.3]:
			var dip := 0.0
			var vel := 0.0
			var worst := 0.0
			var t := 0.0
			var next_kick := 0.0
			var hitched := false
			while t < 3.0:
				var delta: float = 1.0 / fps
				if not hitched and t > 1.0 and hitch > 0.0:
					delta = hitch
					hitched = true
				if t >= next_kick:
					vel += 7.0  # dip(2.5 + power * 4.5) at full power
					next_kick += 0.16
				var next := CameraRig.step_dip(dip, vel, delta)
				dip = next.x
				vel = next.y
				worst = maxf(worst, absf(dip))
				t += delta
			print("  %3.0f fps, one %.2f s frame: max |dip| %.2f m" % [fps, hitch, worst])
