extends RefCounted
## 5 · Mixtape. Mastery: every technique, cut together like a tape.
##
## Five tracks, each its own colour and each a notch faster than the last
## (the speed steps up at every splice, the spin keeps winding up): a
## lean-and-weave track, a jump-size track, an echo track, a floating track
## and a B-side that throws it all back at you. Between tracks the tape is
## spliced: one ring to jump and the colour cuts hard to the next label.
## The moves are the ones the earlier levels teach, but now in combination
## and against the clock: jumping into a side door against the spin, an
## echo run at half height, an echo reshaped into a leap, a floating ribbon
## that turns faster than the current.


const STRIP := 0.27


func build(tuning: BallTuning) -> LevelData:
	# Each track a little faster: the splices are where the speed steps up.
	var surges := [[12.0, 1.04, 0.4], [24.0, 1.08, 0.4], [36.0, 1.12, 0.4], [48.0, 1.16, 0.4]]
	var b := LevelBuilder.new("05_mixtape", "Mixtape", 28.0, 0.1, 60.0, surges, tuning)

	# Five tape labels, cut hard at the splices.
	var labels := [
		["#ff9a3c", "#0f3550", "#fff36b"],      # 1 tangerine on deep teal
		["#5ad1ff", "#3a0a5c", "#ffffff"],      # 2 electric blue on purple
		["#b6f03c", "#3d0f45", "#ff6fb5"],      # 3 lime on plum
		["#b99cff", "#070a2a", "#7dfcff"],      # 4 ultraviolet in the dark
		["#ff4fa3", "#1a0640", "#ffe14a"],      # 5 hot pink, B-side
	]
	var cuts := [0.0, 12.0, 24.0, 36.0, 48.0, 61.0]
	var titles := ["track 1: lean", "track 2: jump around", "track 3: echo chamber", "track 4: ultraviolet", "b-side"]
	for i in labels.size():
		var label: Array = labels[i]
		b.stop(b.at(cuts[i]) if i > 0 else 0.0, label[0], label[1], label[2])
		b.stop(b.at(cuts[i + 1] - 0.25) if i < labels.size() - 1 else 1.0, label[0], label[1], label[2])
		b.hint(cuts[i] + (0.6 if i == 0 else 0.15), titles[i])

	var lane := 0.0

	# === Track 1 · Lean (0 - 12 s) =====================================================
	b.spin(1.5, 32.0, 1.5)
	# A fast slalom.
	var t := 3.0
	var doors := [40.0, -30.0, 50.0, -20.0, 60.0, -10.0]
	for i in doors.size():
		b.gate(t + i * 0.5, 0.24, lane + doors[i], 100.0)
	t += doors.size() * 0.5 + 0.2
	lane -= 10.0
	# Scratch: a road that wiggles like a needle on a record.
	t = b.zigzag(t, 8, 0.22, lane, 92.0, 140.0)
	# Weave through the dots.
	t = b.dots(t + 0.4, 5, 6, 34.0, 0.1, 0.34, lane + 30.0)
	# Round the chevrons (clear of the splice: the ring needs a run-up).
	t = b.chevron(t + 0.25, 0.55, lane + 180.0, 36.0, 60.0)
	t = b.chevron(t + 0.1, 0.55, lane, 36.0, 60.0)
	if t > 11.3:
		push_warning("Mixtape: track 1 runs into the splice (%.2f s)" % t)
	# Splice.
	b.ring(11.55, 0.35)

	# === Track 2 · Jump around (12 - 24 s) ==============================================
	b.spin(12.0, 38.0, 1.0)
	# Stairs: each ring longer than the last, each landing short, so each
	# jump must be a size bigger (a full swipe early flies past the step).
	t = 12.7
	for d in [0.18, 0.32, 0.46, 0.6]:
		b.ring(t, d)
		t += d + 0.34
	# Side doors: jump, and steer through a gap in the next gate, the
	# first with the spin, the second back against it.
	t += 0.4
	b.ring(t, 0.3)
	b.gate(t + 0.95, 0.4, lane + 100.0, 90.0)
	t += 0.95 + 0.4 + 0.35
	b.ring(t, 0.3)
	b.gate(t + 0.95, 0.4, lane + 75.0, 90.0)
	t += 0.95 + 0.4 + 0.45
	lane += 75.0 + 30.0
	# Morse: hop, leap, hop, hop, leap.
	for beat in ["H", "L", "H", "H", "L"]:
		var d := 0.12 if beat == "H" else 0.58
		b.ring(t, d)
		t += d + 0.45
	# Splice.
	b.ring(23.55, 0.35)

	# === Track 3 · Echo chamber (24 - 36 s) =============================================
	b.spin(24.0, 44.0, 1.0)
	t = b.echo_run(24.35, 3, STRIP)
	# Aimed echoes: a funnel lines everyone up, then the pads swing either
	# side of where the current carries each echo.
	t = b.funnel(t + 0.05, 0.4, 0.0, 360.0, 110.0, 44.0)
	lane = 44.0 * 0.4
	var drift := b.echo_drift(44.0)
	var pads := []
	for i in 5:
		pads.append(lane + drift * i + [0.0, 30.0, -15.0, 35.0, -10.0][i])
	t = b.pad_run(t, pads, 80.0, STRIP)
	lane = pads[4] + drift * 0.5
	# Half-height echoes: a full swipe here lands in a ring; find the
	# middle size, then let the echo repeat it...
	var half := b.air_time(1.7)
	t += 0.45
	var start := t + STRIP * 0.5
	for i in 4:
		b.ring(start + i * half, half - STRIP)
	t = start + 4 * half - STRIP
	# ...and the drop: reshape the last echo into a leap (the splice).
	b.ring(t + STRIP, 0.6)
	t += STRIP + 0.6
	lane += 44.0 * (t - 31.0)

	# === Track 4 · Ultraviolet: floating (36 - 48 s) =====================================
	b.spin(36.0, 50.0, 1.0)
	t += 0.35
	start = t
	var islands := [[t, t + 0.5, lane, 140.0]]
	t += 0.5
	# A ribbon that turns faster than the current, in pieces.
	var twist := 80.0
	for i in 7:
		var piece := t + 0.22 + i * 0.62
		islands.append([piece, piece + 0.4, lane + twist * (piece - t), 70.0, twist])
	t += 0.22 + 7 * 0.62
	lane += twist * (t - 0.22 - 36.9)
	# A turntable: moonlets stepping round with the spin, then two lines of
	# moonlets half a turn apart that close in on each other (an eighth of
	# a turn per hop, either line) and meet in one.
	for i in 5:
		islands.append([t + 0.3 + i * 0.78, t + 0.68 + i * 0.78, lane + 70.0 * (i + 1), 82.0])
	t += 0.68 + 4 * 0.78
	lane += 70.0 * 5
	var lines := [[0.0, 180.0], [45.0, 135.0], [90.0]]
	for i in lines.size():
		var row := t + 0.35 + i * 0.8
		for offset in lines[i]:
			islands.append([row, row + 0.42, lane + 40.0 * (i + 1) + float(offset), 70.0 if lines[i].size() > 1 else 90.0])
	t += 0.35 + 2 * 0.8 + 0.42
	islands.append([t + 0.3, t + 0.9, lane + 160.0 + 90.0, 180.0])
	b.void_with(start, t + 0.9, islands)
	t += 0.9
	lane += 160.0 + 90.0
	# Splice.
	b.ring(maxf(t + 0.3, 47.55), 0.35)
	t = maxf(t + 0.3, 47.55) + 0.35

	# === Track 5 · B-side (48 - 60 s) ===================================================
	b.spin(48.0, 56.0, 1.0)
	t = maxf(t + 0.35, 48.3)
	# Rewind: track 1's slalom, faster, leaning the other way.
	doors = [-20.0, 45.0, -25.0, 50.0]
	for i in doors.size():
		b.gate(t + i * 0.44, 0.22, lane + 20.0 * i + doors[i], 95.0)
	t += doors.size() * 0.44 + 0.15
	lane += 20.0 * doors.size()
	# Equaliser: the floor band squeezes and opens on the beat.
	var bars := [150.0, 105.0, 75.0, 120.0, 70.0]
	for i in bars.size():
		b.gate(t + i * 0.3, 0.3, lane + 18.0 * i, bars[i])
	t += bars.size() * 0.3
	lane += 18.0 * bars.size()
	# A corkscrew against the spin, dotted.
	b.gate(t + 0.3, 1.3, lane, 115.0, -55.0)
	b.dots(t + 0.6, 2, 3, 26.0, 0.09, 0.42, lane - 25.0, -23.0)
	t += 0.3 + 1.3
	lane -= 55.0 * 1.3
	# Hop, leap, side door.
	b.ring(t + 0.35, 0.12)
	b.ring(t + 0.35 + 0.12 + 0.45, 0.58)
	b.gate(t + 0.35 + 0.12 + 0.45 + 0.58 + 0.42, 0.4, lane + 85.0, 100.0)
	t += 0.35 + 0.12 + 0.45 + 0.58 + 0.42 + 0.4
	lane += 85.0
	# Last call: aimed echoes to the finish.
	drift = b.echo_drift(56.0)
	pads = []
	for i in 3:
		pads.append(lane + drift * (i + 1) + [0.0, -20.0, 25.0][i])
	t = b.pad_run(t + 0.3, pads, 85.0, STRIP)
	if t > 59.6:
		push_warning("Mixtape: the B-side runs past the finish (%.2f s)" % t)
	return b.finish()
