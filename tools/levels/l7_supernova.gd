extends RefCounted
## 7 · Supernova. Maniacal. A star's life in one minute, no brakes.
##
## Six acts, each faster than the last (34 m/s rising to over 50) and with
## the spin winding up from 50 to 160 °/s, always the same way, so the
## world turns faster and faster round the ball:
##
##   Ignition    a countdown of hops and a launch.
##   Corona      flares (chevrons) bursting open, a ribbon that lashes about
##               and a field of sunspots in no pattern you can predict;
##               the walls flicker through three colours in bands.
##   Solar wind  the tunnel blows apart: bounce from debris to debris, ride
##               a ribbon in the gusts, pick a way through the rubble.
##   Red giant   the star swells and pulses: the floor squeezes and opens,
##               a long prominence stands still while the spin pulls you
##               off it, a heartbeat of bounces, and convection cells boil
##               up in slanting lanes.
##   Collapse    the floor falls into a spiral: threads that break, threads
##               that turn against the spin faster than the ball can roll
##               (bounce them), then a dotted corkscrew core.
##   Supernova   everything at once at full speed, then one last leap into
##               white.
##
## Nothing is fair on first sight; everything is fair on the tenth. The test
## bot finishes it with perfect reactions.
##
## At these spins players end up anywhere round the tunnel (some ride the
## current, some fight it), so whenever a pattern needs the ball in one
## lane a funnel gathers it first, from wherever it is: either from the
## edges of a loose road that has kept up with the current, or opening from
## just behind the ball after a free stretch. Funnel walls close more slowly
## than a ball can cross, so nobody meets one from behind.
##
## (Photosensitivity: the colour bands pass at under 2.5 a second and swap
## between colours of similar brightness; the void colour only ever fades.)


var rng := RandomNumberGenerator.new()
## When each act really starts (s of the clock), for the colour script.
var acts := {}


func build(tuning: BallTuning) -> LevelData:
	rng.seed = 7_777
	var surges := [[8.0, 1.1, 0.5], [18.0, 1.2, 0.5], [28.0, 1.3, 0.5], [38.0, 1.4, 0.5], [48.0, 1.5, 0.5]]
	var b := LevelBuilder.new("07_supernova", "Supernova", 34.0, 0.0, 60.0, surges, tuning)
	_pin(0.0, 0.0)

	# === Ignition (0 - 8 s) ==============================================================
	var t := _act(b, "IGNITION", 0.0, 0.0, 50.0)
	# Three, two, one: hops closer and closer, then the launch, on a road
	# that starts to turn with the spin.
	_open_road(1.2)
	b.ring(1.8, 0.2)
	b.ring(2.75, 0.2)
	b.ring(3.5, 0.22)
	b.ring(4.05, 0.62)
	# A slalom that leans with the current.
	t = _funnel(b, 4.95, 110.0)
	for i in 5:
		var at := 0.1 + i * 0.36
		b.gate(t + at, 0.2, _lane + 50.0 * at + (38.0 if i % 2 == 0 else -38.0), 88.0)
	_pin(t + 0.1 + 4 * 0.36 + 0.2, _lane + 50.0 * (0.1 + 4 * 0.36) + 38.0)
	t += 0.1 + 5 * 0.36
	_open_road(t)
	b.ring(t + 0.1, 0.5)
	t += 0.6

	# === Corona (8 - 18 s) ================================================================
	t = _act(b, "CORONA", t, 8.0, 80.0)
	# Flares: chevrons bursting open right in front, left side then right.
	for i in 3:
		t = b.chevron(t + 0.3, 0.5, _here(b, t + 0.3) + (25.0 if i % 2 == 0 else -25.0), 34.0, 95.0) - 0.18
	t += 0.4
	# A ribbon lashing about the current (it swings 40° either side).
	t = _funnel(b, t, 100.0)
	var lane := _lane
	t = _lash(b, t, 8, 0.28, lane, 88.0, 80.0, 140.0)
	_pin(t, lane + 80.0 * 8 * 0.28)
	_open_road(t)
	# Sunspots: rows of round holes of every size, nowhere in particular.
	t += 0.3
	for row in 7:
		var spots := 3 + rng.randi() % 3
		var phase := rng.randf() * 360.0
		for k in spots:
			var size := rng.randf_range(28.0, 52.0)
			b.hole(t + row * 0.3, size / 360.0 * 1.2, phase + 360.0 / spots * k + rng.randf_range(-15.0, 15.0), size)
	t += 7 * 0.3 + 0.1
	# Two quick flares and out.
	t = b.chevron(t, 0.45, _here(b, t) + rng.randf_range(-40.0, 40.0), 34.0, 100.0) + 0.1
	t = b.chevron(t, 0.45, _here(b, t) + rng.randf_range(-40.0, 40.0), 34.0, 100.0)
	b.ring(t + 0.2, 0.45)
	t += 0.65

	# === Solar wind (18 - 28 s) =============================================================
	t = _act(b, "SOLAR WIND", t, 18.0, 100.0)
	# The tunnel blows apart from a plank at the end of a funnel.
	t = _funnel(b, t, 110.0)
	lane = _lane
	var start := t
	var islands := [[t, t + 0.15, lane, 110.0, 100.0]]
	t += 0.15
	lane += 100.0 * 0.15
	# Debris: bounce from rock to rock, the wind carrying each echo round.
	var hop := b.max_air()
	var drift := b.echo_drift(100.0)
	var debris := [0.0, 30.0, -25.0, 30.0, -20.0]
	var centre := lane
	for i in debris.size():
		centre = lane + drift * (i + 1) + debris[i]
		var land := t + hop * (i + 1)
		var last := i == debris.size() - 1
		islands.append([land - (0.25 if i == 0 else 0.17), land + (0.5 if last else 0.17), centre, 100.0 if last else 80.0, 100.0 if last else 0.0])
	t += hop * debris.size() + 0.5
	lane = centre + 100.0 * 0.67
	# Gusts: a floating ribbon that sways either side of the wind.
	for i in 4:
		var twist := 100.0 + (70.0 if i % 2 == 0 else -70.0)
		islands.append([t, t + 0.36, lane, 80.0, twist])
		lane += twist * 0.36
		t += 0.36
	# Rubble: rows of three rocks, a third of a turn apart; any will do, and
	# a hop that lets the wind carry it lands on a rock of the next row.
	var rock := lane + 100.0 * 0.47
	var carry := b.echo_drift(100.0, 0.62)
	for row in 3:
		for k in 3:
			islands.append([t + 0.32 + row * 0.62, t + 0.62 + row * 0.62, rock + 120.0 * k, 72.0])
		rock += carry + rng.randf_range(-12.0, 12.0)
	t += 0.62 + 2 * 0.62
	_pin(t, rock - carry)
	islands.append([t + 0.3, t + 0.75, 0.0, 360.0])
	b.void_with(start, t + 0.75, islands)
	t += 0.75

	# === Red giant (28 - 38 s) ===============================================================
	t = _act(b, "RED GIANT", t, 28.0, 120.0)
	# The swell: a floor band riding the spin that squeezes and opens.
	t = _funnel(b, t, 170.0)
	lane = _lane
	var bars := [170.0, 120.0, 80.0, 62.0, 80.0, 120.0, 80.0, 62.0]
	for i in bars.size():
		b.gate(t + i * 0.26, 0.26, lane + 120.0 * i * 0.26, bars[i], 120.0)
	t += bars.size() * 0.26
	lane += 120.0 * bars.size() * 0.26
	# The prominence: the floor stops turning, a long straight arch, and the
	# spin pulls you off it.
	var arch := lane
	b.gate(t, 1.1, arch, 105.0)
	t += 1.1
	# The heartbeat: half-height bounces, each onto a little gate.
	var beat := 0.62
	var pulse := b.echo_drift(120.0, beat)
	for i in 4:
		b.ring(t + 0.15 + i * beat, beat - 0.32)
		b.gate(t + 0.15 + (i + 1) * beat - 0.32, 0.32, arch + pulse * (i + 1) + (15.0 if i % 2 == 0 else -15.0), 108.0)
	t += 0.15 + 4 * beat
	_pin(t, arch + pulse * 4 - 15.0)
	b.ring(t + 0.15, 0.45)
	t += 0.6
	# Convection cells: rows of holes, each turned a little further, so the
	# four ways through are lanes that slant one way, then the other. Weave.
	var slant := 0.0
	var phase := _here(b, t) + 45.0
	for row in 7:
		slant += 24.0 if row < 4 else -24.0
		for k in 4:
			b.hole(t + row * 0.26, 0.13, phase + 120.0 * row * 0.26 + slant + 90.0 * k, 52.0)
	# Where the four lanes are at the end of the cells.
	lane = phase + 120.0 * 7 * 0.26 + slant - 45.0
	t += 7 * 0.26

	# === Collapse (38 - 48 s) =================================================================
	# The cells' four lanes fall away into four threads riding the spin,
	# breaking as they go.
	t = _act(b, "COLLAPSE", t, t, 140.0) - 0.2
	start = t
	islands = []
	var legs := []
	for i in 4:
		legs.append([0.5, 140.0])
	t = _stripped(islands, t, legs, 0.34, lane, 4, 56.0)
	lane += 140.0 * (4 * 0.5 + 3 * 0.34)
	islands.append([t + 0.34, t + 0.7, 0.0, 360.0])
	t += 0.7
	lane += 140.0 * 0.7
	# Then three threads turning against the spin, one spacing per echo:
	# bounce, and each echo comes down on the next thread round.
	var screw := (b.echo_drift(140.0) - 120.0) / b.max_air()
	for k in 3:
		islands.append([t, t + 2.4, lane + 120.0 * k, 84.0, screw])
	t += 2.4
	# Solid ground for as long as any jump, so whichever thread you came
	# off and however late you jumped, you land on it; then the core closes
	# in from behind, all the way round (no telling which thread a player
	# rode).
	_pin(t, lane + screw * 2.4)
	islands.append([t, t + 0.9, 0.0, 360.0])
	b.void_with(start, t + 0.9, islands)
	t += 0.9
	# The core: a narrow corkscrew with the spin, dotted with holes.
	t = _funnel(b, t, 110.0)
	lane = _lane
	b.gate(t, 1.4, lane, 90.0, 140.0)
	for i in 4:
		b.hole(t + 0.2 + i * 0.32, 0.08, lane + 140.0 * (0.24 + i * 0.32) + (24.0 if i % 2 == 0 else -24.0), 28.0)
	t += 1.4
	_pin(t, lane + 140.0 * 1.4)
	_open_road(t)
	b.ring(t + 0.1, 0.45)
	t += 0.55

	# === Supernova (48 - 60 s) ================================================================
	t = _act(b, "SUPERNOVA", t, 48.0, 160.0)
	# A slalom at full speed.
	t = _funnel(b, t, 110.0)
	lane = _lane
	for i in 6:
		var at := 0.1 + i * 0.3
		b.gate(t + at, 0.17, lane + 160.0 * at + (36.0 if i % 2 == 0 else -36.0), 92.0)
	_pin(t + 0.1 + 5 * 0.3 + 0.17, lane + 160.0 * (0.1 + 5 * 0.3) - 36.0)
	t += 0.1 + 6 * 0.3
	_open_road(t)
	# Hop, leap.
	b.ring(t + 0.15, 0.12)
	b.ring(t + 0.15 + 0.12 + 0.42, 0.55)
	t += 0.15 + 0.12 + 0.42 + 0.55 + 0.3
	# Shock front: rows of holes, then a flare.
	for row in 4:
		phase = rng.randf() * 360.0
		for k in 4:
			b.hole(t + row * 0.27, 0.1, phase + 90.0 * k, 42.0)
	t += 4 * 0.27 + 0.1
	t = b.chevron(t, 0.42, _here(b, t) + rng.randf_range(-30.0, 30.0), 34.0, 110.0) + 0.1
	# Aimed echoes, the wind at its strongest.
	t = _funnel(b, t, 110.0)
	lane = _lane
	# A short run-up in the lane, so whoever jumped the funnel is back in
	# line before the first leap.
	b.gate(t, 0.3, lane, 110.0, 160.0)
	t += 0.3
	lane += 160.0 * 0.3
	drift = b.echo_drift(160.0)
	var pads := []
	for i in 4:
		pads.append(lane + 160.0 * 0.12 + drift * i + [0.0, 25.0, -20.0, 30.0][i])
	t = b.pad_run(t, pads, 96.0, 0.24)
	# The last leap, into white.
	b.ring(t + 0.2, 0.7)
	acts["END"] = t + 0.9
	_paint(b)
	return b.finish()


# --- Where the ball is ----------------------------------------------------------------
# Patterns that pin the ball to a lane (a gate, a bridge, a pad) set an
# anchor; between them it drifts with the spin. Funnels are aimed at where
# a player who lets go would be, so nobody starts one at the wrong side.

var _pin_t := 0.0
var _pin_a := 0.0
## Where the last funnel ended (its lane, at its end).
var _lane := 0.0
## Where the open road starts (s of the clock), or -1.
var _road := -1.0
var _road_width := 210.0


func _pin(t: float, angle: float) -> void:
	_pin_t = t
	_pin_a = angle


func _here(b: LevelBuilder, t: float) -> float:
	return _pin_a + b.free_drift(_pin_t, t)


## A funnel aimed at where the ball is, narrowing to `width` and turning
## with the current. If a road is open it runs up to the funnel, and the
## funnel's walls carry on from the road's edges. Without one the funnel
## opens almost all the way round (`mouth`°): its walls start right behind
## the ball, wherever a player may be, and sweep forward. The walls close at
## most CLOSING °/s, slower than a ball can cross, so whoever is inside the
## mouth can always make it to the middle. Pins the ball to its end.
##
## Straight walls can only start so wide (see LevelBuilder.funnel), so a
## wide mouth is built as a chain of funnels, each opening as wide as the
## next one's mouth allows; their walls join edge to edge.
const CLOSING := 80.0

func _funnel(b: LevelBuilder, t: float, width: float, mouth: float = 350.0) -> float:
	if _road >= 0.0:
		_corridor(b, _road, t, _road_width)
		mouth = _road_width
		_road = -1.0
	var widths := [width]
	while 180.0 + float(widths[-1]) * 0.5 < mouth:
		widths.append(180.0 + float(widths[-1]) * 0.5)
	widths.reverse()
	# widths[0] is the first stage's end (or the only stage's).
	var from := mouth
	var at := _here(b, t)
	for to in widths:
		var dur := maxf(0.04, (from - float(to)) * 0.5 / CLOSING)
		at = _here(b, t)
		var twist := (_here(b, t + dur) - at) / dur
		b.funnel(t, dur, at, from, to, twist)
		t += dur
		at += twist * dur
		from = to
	_lane = at
	_pin(t, _lane)
	return t


## Opens a road (see _corridor) from t, to be closed by the next funnel.
func _open_road(t: float, width: float = 210.0) -> void:
	_road = t
	_road_width = width


## A road `width`° wide from t0 to t1 that keeps up with where a player
## who lets go would be (so it bends as the spin winds up): a loose lane
## for long stretches where nothing else holds the ball to one, so that
## the next funnel can never be met from behind. Cut in pieces that each
## turn at one rate.
func _corridor(b: LevelBuilder, t0: float, t1: float, width: float) -> void:
	var t := t0
	var piece_start := t0
	var piece_rate := NAN
	while t < t1 - 0.0001:
		var dt := minf(0.1, t1 - t)
		# °/m: a piece is straight in metres, and the speed changes too.
		var rate := (_here(b, t + dt) - _here(b, t)) / (b.s(t + dt) - b.s(t))
		if not is_nan(piece_rate) and absf(rate - piece_rate) > 0.01:
			_road_piece(b, piece_start, t, width)
			piece_start = t
		piece_rate = rate
		t += dt
	_road_piece(b, piece_start, t1, width)


func _road_piece(b: LevelBuilder, t0: float, t1: float, width: float) -> void:
	var s0 := b.s(t0)
	var length := b.s(t1) - s0
	var at := _here(b, t0)
	b.hole_m(s0, length, at + 180.0, 360.0 - width, (_here(b, t1) - at) / length)


## Starts an act at `t` (or its planned time `planned`, if later): title,
## spin. Warns when the act before ran over its slot.
func _act(b: LevelBuilder, title: String, t: float, planned: float, spin: float) -> float:
	if t > planned + 0.5:
		push_warning("Supernova: %s starts at %.2f s, planned %.1f s" % [title, t, planned])
	t = maxf(t, planned)
	acts[title] = t
	b.hint(t + 0.1, title)
	b.spin(t, spin, 0.8)
	return t + 0.2


## A floor band `width`° wide whose centre swings `swing`°/s either side of
## a line drifting `drift`°/s (the spin), `legs` legs of `leg` seconds.
func _lash(b: LevelBuilder, t: float, legs: int, leg: float, at: float, width: float, drift: float, swing: float) -> float:
	var centre := at
	for i in legs:
		var rate := drift + (swing if i % 2 == 0 else -swing)
		b.gate(t + i * leg, leg, centre, width, rate)
		centre += rate * leg
	return t + legs * leg


## Threads of floor (see 6 · Screwball) with a break of `gap` s after each
## leg [seconds, twist]. Returns the end time.
static func _stripped(islands: Array, t: float, legs: Array, gap: float, at: float, starts: int, width: float) -> float:
	for i in legs.size():
		var seconds := float(legs[i][0])
		var twist := float(legs[i][1])
		for k in starts:
			islands.append([t, t + seconds, at + 360.0 / starts * k, width, twist])
		at += twist * (seconds + gap)
		t += seconds + (gap if i < legs.size() - 1 else 0.0)
	return t


## The colour script: each act its own light, the corona flickering through
## bands, the red giant pulsing, and a white-out at the end.
func _paint(b: LevelBuilder) -> void:
	var corona: float = acts["CORONA"]
	var wind: float = acts["SOLAR WIND"]
	var giant: float = acts["RED GIANT"]
	var collapse: float = acts["COLLAPSE"]
	var nova: float = acts["SUPERNOVA"]
	# Ignition: white-hot yellow in deep blue.
	b.stop(0.0, "#fff36b", "#0b1a5c", "#ffffff")
	b.stop(b.at(corona - 0.3), "#ffe14a", "#101a6a", "#ffffff")
	# Corona: bands of cyan, pink and lime, about two a second.
	var colours := ["#5ad1ff", "#ff7ad9", "#b6f03c"]
	var t := corona
	var i := 0
	while t < wind - 0.5:
		var c: String = colours[i % 3]
		b.stop(b.at(t), c, "#1a0a4a", "#ffffff")
		b.stop(b.at(t + 0.36), c, "#1a0a4a", "#ffffff")
		t += 0.44
		i += 1
	# Solar wind: pale gold rocks on violet.
	b.stop(b.at(wind), "#ffd98a", "#2a0f5c", "#fff36b")
	b.stop(b.at(giant - 0.3), "#ffb86b", "#3a0f50", "#fff36b")
	# Red giant: orange-red, the void pulsing slowly (a heartbeat a second).
	t = giant
	i = 0
	while t < collapse - 0.4:
		var deep := i % 2 == 0
		b.stop(b.at(t), "#ff6a3c" if deep else "#ff8a4c", "#3a0718" if deep else "#5a0c24", "#ffe14a")
		t += 0.5
		i += 1
	# Collapse: violet and electric blue, darkening.
	b.stop(b.at(collapse), "#9d7bff", "#100634", "#7dfcff")
	b.stop(b.at(nova - 0.3), "#5ad1ff", "#05021a", "#7dfcff")
	# Supernova: hot magenta to gold, then white.
	b.stop(b.at(nova), "#ff4fa3", "#1a0640", "#ffe14a")
	b.stop(b.at(acts["END"] - 1.6), "#ffd23a", "#3a1a5c", "#ffffff")
	b.stop(minf(b.at(acts["END"]), 0.999), "#ffffff", "#fff6d8", "#ffe14a")
	b.stop(1.0, "#ffffff", "#fff6d8", "#ffe14a")
