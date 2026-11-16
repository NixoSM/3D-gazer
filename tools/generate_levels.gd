extends SceneTree
## Regenerates the bundled levels in res://levels/ from their specs.
##
## Usage (from the repository root):
##   godot --headless --script res://tools/generate_levels.gd
##
## Generated files are committed. Re-run after changing LevelGenerator or a
## spec below, then play-test: changing a seed changes the whole layout.

const OUTPUT_DIR := "res://levels/"


func _init() -> void:
	var tuning: BallTuning = load("res://resources/ball_tuning.tres")
	var generator := LevelGenerator.new()
	generator.verbose = "--verbose" in OS.get_cmdline_user_args()
	var manifest := []
	for spec in _specs():
		var level := generator.generate(spec, tuning)
		var path := OUTPUT_DIR + level.id + ".json"
		var error := LevelSerializer.save_file(level, path)
		if error != OK:
			push_error("Could not write %s (%s)" % [path, error_string(error)])
			quit(1)
			return
		var problems := LevelValidator.check(level, tuning)
		var unused := "" if generator.script_end == INF else "  (script ran out at %.0f%%)" % (100.0 * generator.script_end / level.length)
		print("%s  %d holes  %d spin keys  %.0f m  %.1f s  %d/%d sections%s%s" % [path, level.holes.size(), level.spin.size(), level.length,
			level.duration(), generator.sections_used, spec.sections.size(), unused, "" if problems.is_empty() else "  WARN " + "; ".join(problems)])
		manifest.append(level.id)
	var file := FileAccess.open(OUTPUT_DIR + "manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"levels": manifest}, "  ") + "\n")
	quit(0)


static func _stop(at: float, wall: String, void_color: String, accent: String) -> PaletteStop:
	return PaletteStop.new(at, Color(wall), Color(void_color), Color(accent))


func _specs() -> Array[LevelGenerator.Spec]:
	var specs: Array[LevelGenerator.Spec] = []

	# Palettes: `wall` is the tunnel's flat colour and carries the progress,
	# `void` is the background seen through holes (keep it in strong contrast
	# with the wall), `accent` colours echo rings and the best-run marker.
	#
	# Sections: p = pattern, n = count, i = intensity (0..1), spin = ground
	# spin in °/s from there on (ramp = seconds to reach it), rest = seconds
	# of floor after. See LevelGenerator.Spec.

	# 1. Sunrise: learn each idea alone, then a first taste of spin.
	var dawn := LevelGenerator.Spec.new()
	dawn.id = "01_dawn"
	dawn.display_name = "Dawn"
	dawn.seed = 1107
	dawn.base_speed = 13.65
	dawn.sections = [
		{"p": "gate", "n": 3, "i": 0.1},                       # lean into the gap
		{"p": "ring", "n": 2, "i": 0.1, "rest": 1.4},          # swipe to jump
		{"p": "gate", "n": 2, "i": 0.25},
		{"p": "split", "n": 1, "i": 0.25},
		{"p": "echo_run", "n": 3, "i": 0.2, "rest": 1.6},     # tap as you land
		{"p": "gate", "n": 3, "i": 0.3, "spin": 8.0, "ramp": 2.0},  # the tunnel starts to turn
		{"p": "slalom", "n": 4, "i": 0.2},
		{"p": "bridge", "n": 10, "i": 0.25},
		{"p": "rest", "secs": 1.0},
		{"p": "echo_run", "n": 4, "i": 0.3, "spin": 12.0},    # each echo flips the turn
		{"p": "combo", "n": 2, "i": 0.3},
		{"p": "funnel", "n": 4, "i": 0.3},
		{"p": "ring", "n": 2, "i": 0.4},
		{"p": "gate", "n": 3, "i": 0.4},
		{"p": "echo_run", "n": 5, "i": 0.4},
		{"p": "gate", "n": 4, "i": 0.45},
		{"p": "slalom", "n": 4, "i": 0.45},
	]
	dawn.palette = [
		_stop(0.00, "#ffc93c", "#3a1c80", "#ffffff"),
		_stop(0.35, "#ff8f3c", "#33166e", "#fff36b"),
		_stop(0.70, "#ff4f7b", "#26105a", "#fff36b"),
		_stop(1.00, "#c94bff", "#150a3c", "#7dfcff"),
	]
	specs.append(dawn)

	# 2. Into the sea: currents. The spin is always on and the tide turns.
	var tide := LevelGenerator.Spec.new()
	tide.id = "02_tide"
	tide.display_name = "Tide"
	tide.seed = 2214
	tide.base_speed = 17.5
	tide.sections = [
		{"p": "gate", "n": 2, "i": 0.3, "spin": 15.0, "ramp": 1.5},
		{"p": "slalom", "n": 4, "i": 0.35},
		{"p": "ring", "n": 2, "i": 0.4},
		{"p": "gate", "n": 2, "i": 0.4, "spin": -20.0, "ramp": 0.6},  # the tide turns
		{"p": "pad_run", "n": 4, "i": 0.35, "rest": 1.3},             # echoes flip the current mid-air
		{"p": "corkscrew", "n": 12, "i": 0.4},
		{"p": "combo", "n": 2, "i": 0.45},
		{"p": "split", "n": 2, "i": 0.5, "spin": 28.0, "ramp": 0.5},
		{"p": "rest", "secs": 1.0},
		{"p": "funnel", "n": 5, "i": 0.5},
		{"p": "pad_run", "n": 5, "i": 0.5},
		{"p": "slalom", "n": 5, "i": 0.55, "spin": -30.0, "ramp": 0.4},
		{"p": "corkscrew", "n": 14, "i": 0.55},
		{"p": "echo_run", "n": 5, "i": 0.6},
		{"p": "gate", "n": 4, "i": 0.6},
		{"p": "combo", "n": 2, "i": 0.6},
	]
	tide.palette = [
		_stop(0.00, "#5cf2b0", "#0c2a72", "#ffffff"),
		_stop(0.30, "#2fd6ff", "#0b2266", "#fff36b"),
		_stop(0.65, "#3d7bff", "#1a0d4f", "#fff36b"),
		_stop(1.00, "#8a5cff", "#0a0630", "#7dfcff"),
	]
	specs.append(tide)

	# 3. Lava: fast, strong spin that snaps around, narrow lines, few breaks.
	var ember := LevelGenerator.Spec.new()
	ember.id = "03_ember"
	ember.display_name = "Ember"
	ember.seed = 3391
	ember.base_speed = 21.0
	ember.intro_seconds = 2.5
	ember.sections = [
		{"p": "gate", "n": 3, "i": 0.6, "spin": 25.0, "ramp": 1.0},
		{"p": "slalom", "n": 4, "i": 0.65},
		{"p": "combo", "n": 2, "i": 0.65},
		{"p": "pad_run", "n": 5, "i": 0.65, "spin": -32.0, "ramp": 0.3},   # snap reversal
		{"p": "corkscrew", "n": 22, "i": 0.7},
		{"p": "funnel", "n": 6, "i": 0.7},
		{"p": "split", "n": 1, "i": 0.75, "spin": 40.0, "ramp": 0.3},
		{"p": "bridge", "n": 16, "i": 0.75},
		{"p": "combo", "n": 3, "i": 0.8},
		{"p": "pad_run", "n": 6, "i": 0.8, "spin": -45.0, "ramp": 0.25},
		{"p": "ring", "n": 3, "i": 0.85},
		{"p": "corkscrew", "n": 24, "i": 0.85, "spin": 50.0, "ramp": 0.25},
		{"p": "slalom", "n": 4, "i": 0.9},
		{"p": "pad_run", "n": 5, "i": 0.9},
		{"p": "gate", "n": 5, "i": 0.95},
	]
	ember.palette = [
		_stop(0.00, "#ffe14a", "#5a0e2a", "#ffffff"),
		_stop(0.35, "#ffa62b", "#4a0b22", "#ffffff"),
		_stop(0.70, "#ff5a2b", "#1f0a3a", "#fff36b"),
		_stop(1.00, "#ff2e4d", "#120624", "#ffe14a"),
	]
	specs.append(ember)
	return specs
