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

	# Palettes: `wall` tints the dark shell (keep it dark and desaturated),
	# `void` is the colour seen through holes and carries the level's mood,
	# `accent` lights hole lips, ripples and the lamp.

	# 1. Night into sunrise: the gentle one.
	var dawn := LevelGenerator.Spec.new()
	dawn.id = "01_dawn"
	dawn.display_name = "Dawn"
	dawn.seed = 1107
	dawn.base_speed = 13.65  # 10.5 m/s + 30%
	dawn.difficulty = 0.35
	dawn.pattern_weights = {"gate": 4.0, "ring": 2.0, "echo_run": 1.2, "bridge": 0.6}
	dawn.palette = [
		_stop(0.00, "#383b47", "#141a3d", "#9fb0ff"),
		_stop(0.35, "#3d3747", "#2a1746", "#c8a6ff"),
		_stop(0.70, "#463a3c", "#5a1f2c", "#ff9a85"),
		_stop(1.00, "#4a4038", "#8a4a1c", "#ffc58a"),
	]
	specs.append(dawn)

	# 2. Down through the sea: rhythm and bridges.
	var tide := LevelGenerator.Spec.new()
	tide.id = "02_tide"
	tide.display_name = "Tide"
	tide.seed = 2214
	tide.base_speed = 11.5
	tide.difficulty = 0.6
	tide.palette = [
		_stop(0.00, "#34403f", "#0b3a3d", "#7ff0e0"),
		_stop(0.30, "#333e44", "#0b2c45", "#7fd0ff"),
		_stop(0.65, "#30364a", "#101d4a", "#8fa0ff"),
		_stop(1.00, "#2b2d3a", "#05081c", "#c9d2ff"),
	]
	specs.append(tide)

	# 3. Through the kiln and out into ash: fast and tight.
	var ember := LevelGenerator.Spec.new()
	ember.id = "03_ember"
	ember.display_name = "Ember"
	ember.seed = 3391
	ember.base_speed = 12.5
	ember.difficulty = 0.85
	ember.palette = [
		_stop(0.00, "#3b3634", "#3a0f08", "#ff8a4c"),
		_stop(0.35, "#41363a", "#5c1209", "#ff6a3d"),
		_stop(0.70, "#423a33", "#6e3305", "#ffb54a"),
		_stop(1.00, "#45423c", "#1a1714", "#f2e9da"),
	]
	specs.append(ember)
	return specs
