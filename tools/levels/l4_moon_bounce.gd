extends RefCounted
## 4 · Moon Bounce. The gimmick level: floating platforms in empty space.
##
## The tunnel crumbles. Tiles go missing, then it breaks into floating
## hoops to bounce along, the hoops break into arcs, and for most of the
## level the ball hops between moonlets hanging in the starry void: along
## a floating highway that forks, round a spiral staircase that turns the
## whole world over, across a field of stepping stones (pick your own way),
## and along a broken ribbon winding through space. At the end the pieces
## drift back together into a tunnel.
##
## Colour: moon-white platforms in a midnight-blue void, warming to gold,
## then ice cyan in a violet night.


func build(tuning: BallTuning) -> LevelData:
	var b := LevelBuilder.new("04_moon_bounce", "Moon Bounce", 25.0, 0.2, 60.0, [], tuning)
	var period := b.max_air()

	b.stop(0.00, "#eef0ff", "#141c5c", "#ffe14a")
	b.stop(0.40, "#ffe28a", "#101a4f", "#ffffff")
	b.stop(0.72, "#9ff3ff", "#24104f", "#ffe14a")
	b.stop(1.00, "#f2f0ff", "#0b0f3a", "#7dfcff")

	# --- Cracks: tiles go missing (3 - 8.5 s) --------------------------------------
	var t := b.dots(3.0, 4, 6, 42.0, 0.16, 0.55, 30.0)
	b.spin(5.0, 15.0, 1.5)
	b.gate(t + 0.5, 0.32, 40.0, 200.0)
	b.gate(t + 1.3, 0.32, -20.0, 150.0)
	b.gate(t + 2.1, 0.32, 45.0, 115.0)
	t += 2.9

	# --- Hoops: the tunnel breaks into rings floating in space (8.5 - 17 s) -----------
	t = b.echo_run(t + 0.3, 4, 0.3)
	# Long, short, short, long, short, long: a rhythm of big and small
	# bounces (the echo repeats the short ones).
	t = _rhythm(b, t + 0.2, [1.0, 0.5, 0.5, 1.0, 0.5, 0.5, 1.0], 0.3)

	# --- Arcs, then a floating highway that forks (17 - 28 s) ---------------------------
	b.spin(t, 25.0, 1.5)
	var start := t + 0.15
	var islands := []
	var angles := [0.0, 45.0, 90.0, 135.0, 180.0, 215.0, 185.0, 225.0]
	var widths := [170.0, 160.0, 150.0, 140.0, 110.0, 100.0, 100.0, 95.0]
	var land := start + period - 0.3
	for i in angles.size():
		islands.append([land + i * period, land + i * period + 0.3, angles[i], widths[i]])
	t = land + (angles.size() - 1) * period + 0.3
	var road := 225.0
	islands.append([t, t + 2.0, road, 70.0, 30.0])
	var fork := road + 30.0 * 2.0
	islands.append([t + 2.0, t + 3.4, fork - 42.0, 46.0, 30.0])
	islands.append([t + 2.0, t + 3.4, fork + 42.0, 46.0, 30.0])
	islands.append([t + 3.4, t + 3.9, 0.0, 360.0])
	b.void_with(start, t + 3.9, islands)
	t += 3.9
	var lane := fork + 30.0 * 1.4

	# --- A spiral staircase that turns the world over (28 - 36 s) ------------------------
	b.spin(t, 30.0, 1.5)
	start = t
	islands = []
	for i in 8:
		islands.append([t + 0.35 + i * 0.9, t + 0.9 + i * 0.9, lane + 45.0 * (i + 1), 90.0])
	t += 0.35 + 7 * 0.9 + 0.55
	lane += 45.0 * 8
	# --- Wider gaps, left and right: aim every jump (36 - 41 s) --------------------------
	# The moonlets swing 20° either side of a line that drifts with the
	# spin, so a jump "left" is half the work of fighting the current.
	for i in 5:
		var at := lane + 30.0 * i + (20.0 if i % 2 == 0 else -20.0)
		islands.append([t + 0.55 + i * 1.0, t + 1.0 + i * 1.0, at, 92.0])
	t += 1.0 + 4 * 1.0
	lane += 30.0 * 4 + 20.0 + 20.0
	# --- Stepping stones: three choices on every row (41 - 47 s) ----------------------------
	for row in 6:
		var turn := lane + 40.0 * row
		for k in 3:
			islands.append([t + 0.55 + row * 0.95, t + 0.95 + row * 0.95, turn + 120.0 * k, 64.0])
	t += 0.95 + 5 * 0.95
	lane += 40.0 * 5
	b.void_with(start, t + 0.3, islands)
	t += 0.3

	# --- Orbit: a broken ribbon winding through space (47 - 53 s) ----------------------------
	b.spin(t, 35.0, 1.5)
	start = t
	islands = [[t, t + 0.5, lane, 120.0]]
	var twist := 45.0
	t += 0.5
	for i in 8:
		var piece := t + i * 0.62
		islands.append([piece, piece + 0.4, lane + twist * (piece - t), 72.0, twist])
	lane += twist * 8 * 0.62
	t += 8 * 0.62
	# --- Reassembly: the pieces grow back into a tunnel (53 - 57 s) ---------------------------
	islands.append([t + 0.25, t + 0.85, lane, 150.0])
	islands.append([t + 1.15, t + 1.75, lane + 30.0, 230.0])
	islands.append([t + 2.05, t + 2.65, lane, 300.0])
	b.void_with(start, t + 2.65, islands)
	t += 2.65
	b.ring(t + 0.6, 0.5)
	return b.finish()


## Rings of void with floating hoops between them, the gaps sized for
## jumps of the given air times (as a share of the biggest jump; small
## ones never shorter than the smallest jump allows).
static func _rhythm(b: LevelBuilder, t: float, beats: Array, strip: float) -> float:
	var start := t + strip * 0.5
	for beat in beats:
		var period: float = b.max_air() if float(beat) >= 1.0 else maxf(b.max_air() * float(beat), b.min_air() + 0.12)
		b.ring(start, period - strip)
		start += period
	return start - strip * 0.5
