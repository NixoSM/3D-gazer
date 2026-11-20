extends RefCounted
## 6 · Screwball. The hard gimmick: you ride the thread of a screw.
##
## Every floor in this level is a helix. It starts as rifling, grooves cut
## into the tunnel that turn with the spin (let go and the current keeps you
## between them). Then the tunnel falls away and only the threads are left:
## bands of floor winding round the void, which you ride, steer along when
## they turn faster than the current, and lean against when they turn the
## other way. Then the thread is stripped (hop the breaks), and then the
## screw turns faster than any ball can roll: stay on it and you slide off,
## so you bounce, and every full jump comes down one thread further round.
## The finish is a nut of four threads spinning round you.
##
## Nothing here asks for a pixel-perfect landing: the threads are wide. It
## asks you to read which way the floor is moving under you, and to time
## the jumps to the turning of the screw.
##
## Colour: steel blue, brass, copper, and a red-hot finish.


func build(tuning: BallTuning) -> LevelData:
	var b := LevelBuilder.new("06_screwball", "Screwball", 28.0, 0.15, 60.0, [], tuning)

	b.stop(0.00, "#8fdcff", "#1b1446", "#ffffff")
	b.stop(0.30, "#ffd23a", "#2a1040", "#ffffff")
	b.stop(0.62, "#ff9a3c", "#16103a", "#fff36b")
	b.stop(0.86, "#ff4f6d", "#120a30", "#ffe14a")
	b.stop(1.00, "#ff2d55", "#0c0626", "#ffe14a")

	# --- Rifling: grooves that turn with the spin (2.5 - 9 s) --------------------------
	b.spin(1.5, 30.0, 1.0)
	var t := 2.6
	var at := 60.0
	# Twist per segment (°/s) and groove width: with the current, then a
	# little faster than it, then slower (the grooves come at you). Widths
	# change only where the twist does, so the grooves have no steps.
	var segments := [[30.0, 48.0], [30.0, 48.0], [30.0, 48.0], [60.0, 62.0], [60.0, 62.0], [0.0, 62.0], [0.0, 62.0], [30.0, 62.0]]
	for segment in segments:
		for k in 3:
			b.hole(t, 0.8, at + 120.0 * k, segment[1], segment[0])
		at += segment[0] * 0.8
		t += 0.8
	# The lands between the grooves were centred at at + 60.

	# --- Thread: only the screw is left (9.5 - 18 s) ------------------------------------
	t += 0.4
	var start := t
	var islands := [[t, t + 0.5, 0.0, 360.0]]
	t += 0.5
	var lane := at + 60.0
	# Three threads; each leg [seconds, twist °/s]: ride it, steer along,
	# lean against, ride.
	lane = _threads(islands, t, [[1.6, 30.0], [1.8, 95.0], [1.8, -15.0], [1.4, 30.0]], lane, 3, 76.0)
	t += 1.6 + 1.8 + 1.8 + 1.4

	# --- Stripped: the same threads break, hop the breaks (17 - 27 s) ------------------
	# Each piece [seconds, twist]: with the current, then outrunning it,
	# then against it.
	b.spin(t, 40.0, 1.0)
	var legs := []
	for twist in [40.0, 40.0, 40.0, 100.0, 100.0, 100.0, -20.0, -20.0, -20.0]:
		legs.append([0.72, twist])
	t = _stripped(islands, t, legs, 0.42, lane, 3, 76.0)
	lane = _end_angle(legs, 0.42, lane)
	islands.append([t + 0.42, t + 1.0, 0.0, 360.0])
	b.void_with(start, t + 1.0, islands)
	t += 1.0
	lane += 40.0 * 0.6

	# --- The screw turns under you: bounce (28.5 - 40 s) -------------------------------
	# Three threads turning against the current so fast (one thread
	# spacing per full jump) that the ball cannot stay on one: jump, and
	# the next thread comes round under you; echo and it happens again.
	b.spin(t, 50.0, 1.0)
	start = t
	islands = [[t, t + 0.5, 0.0, 360.0]]
	t += 0.5
	lane += 50.0 * 0.5
	var pitch_rate := 120.0 / b.max_air()
	lane = _threads(islands, t, [[1.0, 50.0 - pitch_rate * 0.5], [4.2, 50.0 - pitch_rate]], lane, 3, 68.0)
	t += 5.2
	islands.append([t, t + 0.55, 0.0, 360.0])
	# Then with the current: the threads run away from you.
	t += 0.55
	lane += 50.0 * 0.55
	lane = _threads(islands, t, [[4.0, 50.0 + pitch_rate]], lane, 3, 68.0)
	t += 4.0
	islands.append([t, t + 0.6, 0.0, 360.0])
	b.void_with(start, t + 0.6, islands)
	t += 0.6
	lane += 60.0 * 0.6

	# --- Left hand, right hand: a zigzag thread (40 - 50 s) ----------------------------
	b.spin(t, 60.0, 1.0)
	start = t
	islands = [[t, t + 0.4, 0.0, 360.0]]
	t += 0.4
	legs = []
	for i in 6:
		legs.append([0.75, 150.0 if i % 2 == 0 else -30.0])
	lane = _threads(islands, t, legs, lane + 60.0 * 0.4, 3, 72.0)
	t += 6 * 0.75
	# A stripped zigzag: the same, in pieces.
	legs = []
	for i in 6:
		legs.append([0.6, 150.0 if i % 2 == 0 else -30.0])
	t = _stripped(islands, t, legs, 0.38, lane, 3, 72.0)
	lane = _end_angle(legs, 0.38, lane)
	islands.append([t + 0.38, t + 0.9, 0.0, 360.0])
	b.void_with(start, t + 0.9, islands)
	t += 0.9
	lane += 70.0 * 0.5

	# --- The nut: four threads spinning round you (50 - 59 s) --------------------------
	b.spin(t, 70.0, 1.0)
	start = t
	islands = [[t, t + 0.4, 0.0, 360.0]]
	t += 0.4
	var nut_rate := 90.0 / b.max_air()
	lane = _threads(islands, t, [[1.2, 70.0], [3.6, 70.0 + nut_rate]], lane + 70.0 * 0.4, 4, 60.0)
	t += 4.8
	legs = []
	for i in 4:
		legs.append([0.55, 70.0 - nut_rate if i % 2 == 0 else 70.0])
	t = _stripped(islands, t, legs, 0.36, lane, 4, 60.0)
	islands.append([t + 0.36, t + 1.2, 0.0, 360.0])
	b.void_with(start, t + 1.2, islands)
	t += 1.2
	b.ring(t + 0.4, 0.45)
	return b.finish()


## Appends `starts` threads (bands of floor `width`° wide, evenly spaced
## round the tunnel) to `islands`, from time t, one leg after another:
## each leg [seconds, twist °/s]. The first thread starts at `at`. Returns
## where the first thread ends.
static func _threads(islands: Array, t: float, legs: Array, at: float, starts: int, width: float) -> float:
	for leg in legs:
		var seconds := float(leg[0])
		var twist := float(leg[1])
		for k in starts:
			islands.append([t, t + seconds, at + 360.0 / starts * k, width, twist])
		at += twist * seconds
		t += seconds
	return at


## Like _threads, with a break of `gap` seconds of void after every leg
## (the thread keeps its line across the break). Returns the end time.
static func _stripped(islands: Array, t: float, legs: Array, gap: float, at: float, starts: int, width: float) -> float:
	for i in legs.size():
		var seconds := float(legs[i][0])
		var twist := float(legs[i][1])
		for k in starts:
			islands.append([t, t + seconds, at + 360.0 / starts * k, width, twist])
		at += twist * (seconds + gap)
		t += seconds + (gap if i < legs.size() - 1 else 0.0)
	return t


## Where the first thread ends after _stripped(legs, gap, at).
static func _end_angle(legs: Array, gap: float, at: float) -> float:
	for i in legs.size():
		at += float(legs[i][1]) * (float(legs[i][0]) + (gap if i < legs.size() - 1 else 0.0))
	return at
