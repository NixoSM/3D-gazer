extends SceneTree
## Every permutation of "smash onto the edge of a hole" (2026-11-21).
##
##   godot --headless --script res://tools/stress_edges.gd [-- --verbose]
##
## For each edge kind (near and far end of a hole, its side, a rounded
## corner, a twisted side, a full ring, a narrow bridge between two holes),
## the dive is aimed so the ball reaches floor level at a signed offset from
## the edge (negative = centre over the void), at several speeds, smash
## heights, tilts and spins, and at several sub-step phases. Each run is
## classified, and the table shows what a player would see for each offset.

const DT := 1.0 / 120.0
const E := BallSimulation.EventType
const P := BallSimulation.Phase
const R := 4.0

var tuning: BallTuning = load("res://resources/ball_tuning.tres")
var verbose := false


func _init() -> void:
	verbose = "--verbose" in OS.get_cmdline_user_args()
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--edge="):
			only = a.get_slice("=", 1)
	var totals := {}
	for edge in ["near", "far", "side", "corner", "twisted_side", "ring_far", "bridge_0.6", "bridge_1.0"]:
		if only != "" and edge != only:
			continue
		_sweep(edge, totals)
	print("\nall edges: ", totals)
	quit()


## The level and the target point for an edge kind and offset (m, + = floor).
func _setup(edge: String, offset: float) -> Dictionary:
	var holes: Array[HoleData] = []
	var target := Vector2.ZERO  # (s, angle)
	match edge:
		"near":
			holes.append(HoleData.new(100.0, 6.0, 0.0, 1.2))
			target = Vector2(100.0 - offset, 0.0)
		"far":
			holes.append(HoleData.new(100.0, 6.0, 0.0, 1.2))
			target = Vector2(106.0 + offset, 0.0)
		"side":
			holes.append(HoleData.new(100.0, 6.0, 0.0, 1.2))
			target = Vector2(103.0, 0.6 + offset / R)
		"corner":
			holes.append(HoleData.new(100.0, 6.0, 0.0, 1.2))
			# Along the diagonal out of the rounded corner at (100, 0.6).
			var c := HoleData.CORNER_RADIUS
			var centre := Vector2(100.0 + c, 0.6 * R - c)
			var out := centre + Vector2(-1.0, 1.0).normalized() * (c + offset)
			target = Vector2(out.x, out.y / R)
		"twisted_side":
			holes.append(HoleData.new(100.0, 8.0, 0.0, 1.2, 0.08))
			var s := 104.0
			var h := holes[0]
			var slope := h.twist * R
			var slant := 1.0 / sqrt(1.0 + slope * slope)
			target = Vector2(s, h.center_at(s) + 0.6 + offset / R / slant)
		"ring_far":
			holes.append(HoleData.new(100.0, 4.0, 0.0, TAU))
			target = Vector2(104.0 + offset, 0.0)
		"bridge_0.6", "bridge_1.0":
			# Two holes side by side with a strip of floor between them,
			# running along the tunnel: the ball smashes across the strip.
			var width := float(edge.get_slice("_", 1))
			var half := width * 0.5 / R
			holes.append(HoleData.new(100.0, 8.0, -half - 0.5, 1.0))
			holes.append(HoleData.new(100.0, 8.0, half + 0.5, 1.0))
			# offset = distance of the centre from the strip's edge, inwards +.
			target = Vector2(104.0, -half + offset / R)
	var level := TestCase.make_level(holes)
	level.speed_ramp = 0.0
	level.tunnel_radius = R
	return {"level": level, "target": target}


func _sweep(edge: String, totals: Dictionary) -> void:
	print("\n== %s ==" % edge)
	var offsets := []
	for i in range(-16, 17):
		offsets.append(i * 0.05)
	var rows := []
	var by_d := {}
	var pop_peaks := []
	var flips := 0
	var configs := 0
	for offset in offsets:
		var counts := {}
		for speed in [20.0, 40.0, 80.0]:
			for strength in [0.0, 0.5, 1.0]:
				for tilt in [0.0, 1.0, -1.0]:
					for spin in [0.0, 60.0]:
						var seen := {}
						for phase in 4:
							var setup := _setup(edge, offset)
							var level: LevelData = setup.level
							level.base_speed = speed
							if spin > 0.0:
								var keys: Array[SpinKey] = [SpinKey.new(0.0, spin)]
								level.spin = keys
							var result := _dive(level, setup.target, strength, tilt, phase)
							var bin := clampi(int(round(result.d / 0.05)), -16, 16)
							if not by_d.has(bin):
								by_d[bin] = {}
							by_d[bin][result.kind] = by_d[bin].get(result.kind, 0) + 1
							if result.kind.begins_with("pop"):
								pop_peaks.append(result.pop)
							totals[result.kind] = totals.get(result.kind, 0) + 1
							seen[result.kind] = true
							if false:
								print("    o=%+.2f v=%.0f str=%.1f tilt=%+.0f spin=%.0f phase=%d: %s" % [offset, speed, strength, tilt, spin, phase, result.detail])
						configs += 1
						if seen.size() > 1:
							flips += 1
							if verbose:
								print("    flip o=%+.2f v=%.0f str=%.1f tilt=%+.0f spin=%.0f: %s" % [offset, speed, strength, tilt, spin, seen.keys()])
	var bins := by_d.keys()
	bins.sort()
	print("  floor distance of the ball's centre where it reaches floor level (- = over the void):")
	for b in bins:
		print("  %+.2f m  %s" % [b * 0.05, _fmt(by_d[b])])
	if not pop_peaks.is_empty():
		pop_peaks.sort()
		print("  pops: %d, height median %.2f m, max %.2f m" % [pop_peaks.size(), pop_peaks[pop_peaks.size() / 2], pop_peaks[-1]])
	print("  configs whose outcome changes with the sub-step phase alone: %d of %d" % [flips, configs])


func _fmt(counts: Dictionary) -> String:
	var keys := counts.keys()
	keys.sort()
	var parts := []
	for k in keys:
		parts.append("%s %d" % [k, counts[k]])
	return ", ".join(parts)


## Jumps, smashes at the top, and aims the dive so the ball reaches floor
## level over `target`. Returns {kind, detail}.
func _dive(level: LevelData, target: Vector2, strength: float, tilt: float, phase: int) -> Dictionary:
	var aim := _dive_offset(level, strength, tilt, phase)
	var sim := BallSimulation.new(level, tuning)
	sim.place(20.0)
	sim.step(DT, InputFrame.new(tilt, strength))
	while sim.vertical_speed > 0.0:
		sim.step(DT, InputFrame.new(tilt))
	for i in phase:
		sim.step(DT, InputFrame.new(tilt))
	var dived := false
	var events := sim.step(DT, InputFrame.new(tilt, -1.0, true))
	for i in 20:
		for e in events:
			if e.type == E.SMASH_DIVED:
				dived = true
		if dived:
			break
		events = sim.step(DT, InputFrame.new(tilt))
	sim.s = target.x - aim.x
	sim.angle = TunnelMath.wrap_angle_positive(target.y - aim.y)
	var contact := false
	var popped := false
	var pop_peak := 0.0
	var smashed := false
	var smashed_over_void := false
	var max_jump := 0.0
	var prev_s := sim.s
	var prev_a := sim.angle
	var max_teleport := 0.0
	var shove_step := -1
	var shove_phase := ""
	var landed_after_pop := ""
	var d_at_floor := INF
	var fell_and_rose := false
	for i in 300:
		var f := InputFrame.new(tilt)
		var v_s := sim.forward_speed
		var v_l := sim.lateral_speed
		var phase_before := sim.phase
		var evs := sim.step(DT, f)
		# Movement beyond what the speeds explain: the collision pushed it.
		var push := Vector2(sim.s - prev_s - v_s * DT, TunnelMath.angle_difference(prev_a, sim.angle) * R - v_l * DT).length()
		if sim.phase != P.FROZEN and phase_before != P.FROZEN and push > max_teleport:
			max_teleport = push
			shove_step = i
			shove_phase = "%s->%s" % [P.keys()[phase_before], P.keys()[sim.phase]]
		if d_at_floor == INF and (sim.height <= 0.0 or sim.phase != P.AIRBORNE):
			d_at_floor = level.floor_distance(sim.s, sim.angle)
		prev_s = sim.s
		prev_a = sim.angle
		for e in evs:
			if e.type == E.SMASH_HIT:
				smashed = true
				smashed_over_void = level.is_hole(e.s, e.angle, 0.0)
			if e.type == E.BUMPED:
				contact = true
		if not smashed and sim.phase == P.AIRBORNE and sim.vertical_speed > 0.0 and not popped and i > 0:
			popped = true
		if popped and not smashed:
			pop_peak = maxf(pop_peak, sim.height)
		if not sim.is_alive():
			# Watch it drop: does it hop back up out of the hole?
			var low := sim.height
			var rise := 0.0
			for j in 60:
				sim.step(DT, InputFrame.new())
				low = minf(low, sim.height)
				rise = maxf(rise, sim.height - low)
			if rise > 0.15:
				fell_and_rose = true
			break
		if smashed and sim.phase == P.AIRBORNE and sim.smash_chain >= 1 and sim.vertical_speed < 0.0:
			break
		if popped and sim.phase == P.ROLLING:
			landed_after_pop = "lands"
			break
	var kind := ""
	if smashed:
		kind = "smash" + ("_over_void" if smashed_over_void else "")
		if not sim.is_alive():
			kind += "_then_fell"
	elif popped:
		kind = "pop_then_" + ("fell" if not sim.is_alive() else ("lands" if landed_after_pop != "" else "airborne"))
	elif not sim.is_alive():
		kind = "fell"
	else:
		kind = "other"
	if fell_and_rose:
		kind += "+hops_out"
	if max_teleport > 0.15:
		kind += "+shove"
		if verbose:
			print("    shove %.2f at step %d phase %s, d=%.2f kind=%s" % [max_teleport, shove_step, shove_phase, d_at_floor, kind])
	return {"kind": kind, "d": d_at_floor, "pop": pop_peak, "detail": "pop %.2f m high, shove %.2f m, lateral %.1f m/s, s %.2f" % [pop_peak, max_teleport, sim.lateral_speed, sim.s]}


## (Δs, Δangle) from the start of the dive to the first step at or below
## floor level, on a level with no holes (the air part does not depend on
## the floor).
var _aim_cache := {}
func _dive_offset(level: LevelData, strength: float, tilt: float, phase: int) -> Vector2:
	var key := "%s/%s/%s/%s/%s" % [level.base_speed, level.spin_at(0.0), strength, tilt, phase]
	if _aim_cache.has(key):
		return _aim_cache[key]
	var flat := TestCase.make_level()
	flat.base_speed = level.base_speed
	flat.speed_ramp = 0.0
	flat.spin = level.spin
	var sim := BallSimulation.new(flat, tuning)
	sim.place(20.0)
	sim.step(DT, InputFrame.new(tilt, strength))
	while sim.vertical_speed > 0.0:
		sim.step(DT, InputFrame.new(tilt))
	for i in phase:
		sim.step(DT, InputFrame.new(tilt))
	var events := sim.step(DT, InputFrame.new(tilt, -1.0, true))
	var dived := false
	for i in 20:
		for e in events:
			if e.type == E.SMASH_DIVED:
				dived = true
		if dived:
			break
		events = sim.step(DT, InputFrame.new(tilt))
	var s0 := sim.s
	var a0 := sim.angle
	# Where exactly the ball crosses floor level (between steps: no holes
	# here, so the step is not sliced; interpolate).
	var prev := Vector3(sim.s, sim.angle, sim.height)
	var vs := sim.vertical_speed
	while sim.phase == P.AIRBORNE:
		prev = Vector3(sim.s, sim.angle, sim.height)
		vs = sim.vertical_speed
		sim.step(DT, InputFrame.new(tilt))
	var fraction := clampf(prev.z / maxf(-(vs - tuning.gravity * DT) * DT, 0.0001), 0.0, 1.0)
	var cross_s := prev.x + sim.forward_speed * DT * fraction
	var cross_a := prev.y + TunnelMath.angle_difference(prev.y, sim.angle) * fraction
	var result := Vector2(cross_s - s0, TunnelMath.angle_difference(a0, cross_a))
	_aim_cache[key] = result
	return result
