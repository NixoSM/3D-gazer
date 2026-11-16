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
		print("%s  %d holes  %.0f m  %.1f s%s" % [path, level.holes.size(), level.length, level.duration(),
			"" if problems.is_empty() else "  WARN " + "; ".join(problems)])
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
	# Speeds are the original 10.5 / 11.5 / 12.5 m/s, all +30%.

	# 1. Sunrise: the gentle one.
	var dawn := LevelGenerator.Spec.new()
	dawn.id = "01_dawn"
	dawn.display_name = "Dawn"
	dawn.seed = 1107
	dawn.base_speed = 13.65
	dawn.difficulty = 0.35
	dawn.pattern_weights = {"gate": 4.0, "ring": 2.0, "echo_run": 1.2, "bridge": 0.6}
	dawn.palette = [
		_stop(0.00, "#ffc93c", "#3a1c80", "#ffffff"),
		_stop(0.35, "#ff8f3c", "#33166e", "#fff36b"),
		_stop(0.70, "#ff4f7b", "#26105a", "#fff36b"),
		_stop(1.00, "#c94bff", "#150a3c", "#7dfcff"),
	]
	specs.append(dawn)

	# 2. Into the sea: rhythm and bridges.
	var tide := LevelGenerator.Spec.new()
	tide.id = "02_tide"
	tide.display_name = "Tide"
	tide.seed = 2214
	tide.base_speed = 14.95
	tide.difficulty = 0.6
	tide.palette = [
		_stop(0.00, "#5cf2b0", "#0c2a72", "#ffffff"),
		_stop(0.30, "#2fd6ff", "#0b2266", "#fff36b"),
		_stop(0.65, "#3d7bff", "#1a0d4f", "#fff36b"),
		_stop(1.00, "#8a5cff", "#0a0630", "#7dfcff"),
	]
	specs.append(tide)

	# 3. Lava: fast and tight.
	var ember := LevelGenerator.Spec.new()
	ember.id = "03_ember"
	ember.display_name = "Ember"
	ember.seed = 3391
	ember.base_speed = 16.25
	ember.difficulty = 0.85
	ember.palette = [
		_stop(0.00, "#ffe14a", "#5a0e2a", "#ffffff"),
		_stop(0.35, "#ffa62b", "#4a0b22", "#ffffff"),
		_stop(0.70, "#ff5a2b", "#1f0a3a", "#fff36b"),
		_stop(1.00, "#ff2e4d", "#120624", "#ffe14a"),
	]
	specs.append(ember)
	return specs
