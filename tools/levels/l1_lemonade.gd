extends RefCounted
## 1 · Lemonade. The first level anyone plays.
##
## Not hard, but it uses everything: every idea gets one clean, isolated
## introduction, one repeat, and then is combined with what came before, so
## by the finish the player has leaned, jumped big and small, steered in the
## air, echoed, aimed an echo, and leaned against a turning tunnel. Short
## hints name each idea the moment the layout asks for it (only until the
## level is beaten once).
##
## Colour: lemonade yellow, through lime and mint, to pink lemonade.


func build(tuning: BallTuning) -> LevelData:
	var b := LevelBuilder.new("01_lemonade", "Lemonade", 20.0, 0.2, 58.0, [], tuning)

	b.stop(0.00, "#ffe066", "#2b2d8f", "#ffffff")
	b.stop(0.30, "#d4f26a", "#1f3590", "#fff6a8")
	b.stop(0.58, "#7cebc0", "#262070", "#ffffff")
	b.stop(0.82, "#ffa3c8", "#3a1670", "#fff36b")
	b.stop(1.00, "#ff7aa8", "#2a0f5c", "#ffffff")

	# --- Lean (3 - 10 s) ------------------------------------------------------------
	b.hint(0.9, "tilt to roll")
	b.gate(3.0, 0.35, 95.0, 150.0)          # the first gap is off to the right
	b.gate(4.5, 0.35, -15.0, 150.0)         # then back left
	b.gate(6.0, 0.35, 80.0, 140.0)
	# A gentle slalom: the open side swaps on a steady beat.
	for i in 4:
		b.gate(7.3 + i * 0.85, 0.3, -30.0 if i % 2 == 0 else 50.0, 120.0)

	# --- Jump (10 - 20 s) -------------------------------------------------------------
	b.hint(10.2, "swipe up to jump")
	b.ring(11.4, 0.15)                      # any jump clears it
	b.ring(12.8, 0.25)
	b.hint(13.7, "longer swipe, longer jump")
	b.ring(14.6, 0.5)                       # needs a real swipe
	b.ring(16.2, 0.62)                      # needs a big one
	# Hop, then leap: a big jump here would fly past the island into the
	# long hole after it, so the first one has to be small.
	b.hint(17.6, "short swipe for a hop")
	b.ring(18.6, 0.12)
	b.ring(18.6 + 0.12 + 0.55, 0.6)

	# --- Steer in the air (21 - 26 s) -----------------------------------------------
	b.hint(21.0, "steer in the air")
	b.ring(21.9, 0.32)
	b.gate(22.95, 0.4, 70.0, 115.0)         # the way on is off to the side
	b.ring(24.5, 0.32)
	b.gate(25.55, 0.4, -40.0, 115.0)

	# --- Echo (27 - 37 s) --------------------------------------------------------------
	b.hint(26.8, "tap as you land to echo")
	var t := _echo_run(b, 27.8, 3, 0.36)
	t = _echo_run(b, t + 1.0, 5, 0.34)
	# Pads: the floor between rings is only an island, a little further
	# round each time. Tilt during the echo to aim the bounce.
	b.hint(t + 0.3, "tilt as you echo to aim")
	t = _pad_run(b, t + 1.2, [-40.0, -15.0, 15.0, 40.0], 120.0, 0.34)

	# --- The tunnel turns (37 - 47 s) ------------------------------------------------
	var spin_at := t + 0.6
	b.hint(spin_at - 0.3, "the tunnel turns: lean")
	b.spin(spin_at, 12.0, 1.5)
	# A wide winding bridge that turns with the spin (ride it), then one
	# that turns against it (lean into it).
	b.gate(spin_at + 1.2, 2.2, 40.0, 130.0, 14.0)
	b.gate(spin_at + 1.2 + 2.2, 2.2, 40.0 + 14.0 * 2.2, 130.0, -14.0)
	t = spin_at + 1.2 + 4.4 + 0.6
	for i in 3:
		b.gate(t + i * 0.9, 0.32, [-10.0, 75.0, -5.0][i], 125.0)
	t += 3 * 0.9 + 0.2

	# --- Everything once (47 - 56 s) --------------------------------------------------
	b.spin(t, 16.0, 1.0)
	b.ring(t + 0.4, 0.3)                    # jump, steer in the air...
	b.gate(t + 1.4, 0.4, 70.0, 115.0)       # ...into the gap
	t = _pad_run(b, t + 2.4, [70.0, 45.0, 20.0], 120.0, 0.34)   # echo and aim
	b.ring(t + 0.5, 0.12)                   # hop...
	b.ring(t + 0.5 + 0.12 + 0.55, 0.6)      # ...then leap
	t += 0.5 + 0.12 + 0.55 + 0.6 + 0.9
	b.gate(t, 0.4, 60.0, 120.0)
	b.ring(t + 1.2, 0.5)                    # one last big jump to the finish
	return b.finish()


## `count` rings spaced for the biggest jump: one full swipe, then echoes.
## `strip` is the floor between rings, in seconds. Returns when it ends.
static func _echo_run(b: LevelBuilder, t: float, count: int, strip: float) -> float:
	var period := b.max_air()
	for i in count:
		b.ring(t + strip * 0.5 + i * period, period - strip)
	return t + count * period


## Like _echo_run, but each landing is an island of floor centred at the
## next angle in `angles` (degrees), `width` degrees wide.
static func _pad_run(b: LevelBuilder, t: float, angles: Array, width: float, strip: float) -> float:
	var period := b.max_air()
	var start := t + strip * 0.5
	for i in angles.size():
		var land := start + (i + 1) * period - strip
		b.ring(start + i * period, period - strip)
		if i < angles.size() - 1:
			b.gate(land, strip, angles[i + 1], width)
	return start + angles.size() * period - strip * 0.5
