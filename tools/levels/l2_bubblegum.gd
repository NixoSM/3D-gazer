extends RefCounted
## 2 · Bubblegum. A clear step up, and a tour of shapes.
##
## Everything from Lemonade, a little faster and always turning, arranged
## into patterns worth looking at: polka dots to weave through, a zigzag
## ribbon, floating hoops to bounce along, a half-turn corkscrew, chevrons
## that split the way in two, and hop-leap-hop rhythms. Each shape gets one
## gentle showing and one sharper one later.
##
## Colour: bubblegum pink, lavender, sky blue, and back to hot pink.


func build(tuning: BallTuning) -> LevelData:
	var b := LevelBuilder.new("02_bubblegum", "Bubblegum", 23.0, 0.2, 60.0, [], tuning)

	b.stop(0.00, "#ff9ad5", "#12305e", "#ffffff")
	b.stop(0.35, "#d6a2ff", "#1b1f66", "#fff36b")
	b.stop(0.68, "#8fd8ff", "#2a1260", "#ffffff")
	b.stop(1.00, "#ff6fb5", "#1a0b4a", "#fff36b")

	b.spin(3.6, 15.0, 1.5)

	# --- Warm up, then a zigzag ribbon ------------------------------------------------
	b.gate(3.0, 0.32, 60.0, 125.0)
	b.gate(3.85, 0.32, -30.0, 125.0)
	b.gate(4.7, 0.32, 50.0, 125.0)
	var t := b.zigzag(5.6, 4, 0.6, 50.0, 115.0, 55.0)

	# --- Polka dots: weave between the rows --------------------------------------------
	t = b.dots(t + 0.6, 6, 5, 38.0, 0.11, 0.5, 14.0)

	# --- Floating hoops: one swipe, then echo -----------------------------------------
	t = b.echo_run(t + 0.8, 4, 0.26)

	# --- Jump and steer into the gap, twice ---------------------------------------------
	b.ring(t + 0.6, 0.3)
	b.gate(t + 1.6, 0.4, 75.0, 110.0)
	b.ring(t + 2.5, 0.3)
	b.gate(t + 3.5, 0.4, -20.0, 110.0)
	t += 4.4

	# --- A half-turn corkscrew with the spin, then a fork --------------------------------
	b.gate(t, 2.4, -20.0, 120.0, 75.0)
	var after := -20.0 + 75.0 * 2.4
	t += 2.4
	# The fork: a wedge of void splits the floor; both sides go on.
	b.hole(t + 0.1, 0.8, after, 70.0)
	t += 1.2

	# --- Chevrons: round either side -----------------------------------------------------
	t = b.chevron(t + 0.3, 0.9, after + 90.0, 40.0, 50.0)
	t = b.chevron(t + 0.25, 0.9, after, 40.0, 50.0)
	t = b.chevron(t + 0.25, 0.9, after + 90.0, 40.0, 50.0)

	# --- Hop, leap, hop, leap -----------------------------------------------------------------
	t += 0.7
	t = _hop_leap(b, t)
	t = _hop_leap(b, t + 0.4)

	# --- The current picks up: aimed bounces --------------------------------------------------
	b.spin(t + 0.2, 22.0, 1.5)
	t = b.pad_run(t + 0.9, [0.0, 25.0, 55.0, 85.0, 110.0], 110.0, 0.32)

	# --- A faster zigzag, denser dots -----------------------------------------------------------
	t = b.zigzag(t + 0.7, 6, 0.5, 110.0, 105.0, 65.0)
	t = b.dots(t + 0.6, 7, 6, 32.0, 0.1, 0.42, 110.0 - 30.0)

	# --- Bounces left and right, harder spin --------------------------------------------------
	b.spin(t + 0.3, 28.0, 1.5)
	t = b.pad_run(t + 0.9, [140.0, 80.0, 140.0, 80.0], 140.0, 0.32)

	# --- Corkscrew against the spin, then with it ------------------------------------------------
	t += 0.5
	b.gate(t, 1.8, 110.0, 125.0, -60.0)
	b.gate(t + 1.8, 1.8, 110.0 - 60.0 * 1.8, 125.0, 60.0)
	t += 3.6

	# --- Finale: chevron, fork, and three last echoes -------------------------------------------
	t = b.chevron(t + 0.3, 0.9, 200.0, 40.0, 55.0)
	b.hole(t + 0.35, 0.8, 110.0, 80.0)
	t = b.echo_run(t + 1.5, 3, 0.3)
	return b.finish()


## A hop over a short ring onto an island, then a leap over a long one:
## a full swipe at the first would fly past the island into the second.
static func _hop_leap(b: LevelBuilder, t: float) -> float:
	b.ring(t, 0.12)
	b.ring(t + 0.12 + 0.5, 0.55)
	return t + 0.12 + 0.5 + 0.55
