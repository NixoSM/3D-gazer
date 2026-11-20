extends RefCounted
## 3 · Hot Sauce. As hard as the hardest of the old levels (Ember).
##
## Ember's speed (27 m/s, ending at 32) and its spin (25 rising to 50 °/s,
## always the same way), with the heat coming in waves: each wave is a
## short burst of patterns at full intensity, then two seconds to breathe.
## Every wave is hotter than the last; the colour goes from jalapeño green
## through habanero orange to ghost-pepper crimson.


func build(tuning: BallTuning) -> LevelData:
	var b := LevelBuilder.new("03_hot_sauce", "Hot Sauce", 27.0, 0.2, 60.0, [], tuning)

	b.stop(0.00, "#8fe33a", "#3a0d2e", "#ffffff")
	b.stop(0.30, "#ffd23a", "#4a0b22", "#ffffff")
	b.stop(0.62, "#ff7a1f", "#2a0a3a", "#fff36b")
	b.stop(0.85, "#ff2d3c", "#1a0630", "#ffe14a")
	b.stop(1.00, "#d6145a", "#10041f", "#ffe14a")

	# --- Wave 1: mild. A quick slalom, jumps into side gaps -------------------------------
	b.spin(2.6, 25.0, 1.0)
	for i in 5:
		b.gate(3.0 + i * 0.6, 0.26, [40.0, -30.0, 45.0, -25.0, 50.0][i], 100.0)
	var t := 3.0 + 5 * 0.6 + 0.2
	b.ring(t, 0.28)
	b.gate(t + 0.95, 0.35, 120.0, 95.0)
	b.ring(t + 1.75, 0.28)
	b.gate(t + 2.7, 0.35, 40.0, 95.0)
	t += 3.3

	# --- Wave 2: salsa. Aimed bounces, then a long corkscrew -----------------------------
	t = b.pad_run(t + 0.5, [40.0, 70.0, 95.0, 70.0, 100.0], 95.0, 0.27)
	b.spin(t, 32.0, 1.0)
	b.gate(t + 0.4, 3.0, 100.0, 105.0, -70.0)          # against the spin: lean in
	t += 3.4
	var lane := 100.0 - 70.0 * 3.0

	# --- Wave 3: chilli flakes and a burning ribbon --------------------------------------------
	t = b.dots(t + 0.5, 6, 6, 30.0, 0.09, 0.38, lane + 30.0)
	t = b.zigzag(t + 0.45, 6, 0.45, lane, 92.0, 75.0)
	t = b.chevron(t + 0.2, 0.8, lane + 180.0, 36.0, 60.0)
	t = b.chevron(t + 0.15, 0.8, lane, 36.0, 60.0)

	# --- Wave 4: habanero. Hop, leap, bounces with the current pulling ----------------------
	b.spin(t + 0.3, 38.0, 1.0)
	t += 0.9
	b.ring(t, 0.1)
	b.ring(t + 0.1 + 0.42, 0.5)
	t += 0.1 + 0.42 + 0.5 + 0.5
	t = b.pad_run(t, [lane + 20.0, lane + 55.0, lane + 20.0, lane + 60.0, lane + 30.0], 90.0, 0.26)
	t = b.dots(t + 0.5, 5, 5, 40.0, 0.1, 0.36, lane + 66.0)

	# --- Wave 5: ghost pepper. Everything, no rest -----------------------------------------------
	b.spin(t + 0.2, 44.0, 1.0)
	b.gate(t + 0.5, 2.4, lane, 100.0, 85.0)            # with the spin, fast
	lane += 85.0 * 2.4
	t += 2.9
	b.ring(t + 0.2, 0.3)
	b.gate(t + 1.15, 0.35, lane + 70.0, 90.0)
	lane += 70.0
	t += 1.8
	b.spin(t, 50.0, 1.0)
	t = b.zigzag(t + 0.2, 4, 0.42, lane, 90.0, -80.0)
	t = b.pad_run(t + 0.4, [lane, lane - 30.0, lane - 60.0, lane - 30.0], 90.0, 0.25)
	for i in 5:
		b.gate(t + 0.5 + i * 0.55, 0.25, lane - 30.0 + (55.0 if i % 2 == 0 else -15.0), 92.0)
	t += 0.5 + 5 * 0.55
	b.ring(t + 0.3, 0.45)
	return b.finish()
