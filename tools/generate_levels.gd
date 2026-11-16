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

	# 1. Blue hour to sunrise: the gentle one.
	var dawn := LevelGenerator.Spec.new()
	dawn.id = "01_dawn"
	dawn.display_name = "Dawn"
	dawn.seed = 1107
	dawn.base_speed = 10.5
	dawn.difficulty = 0.35
	dawn.pattern_weights = {"gate": 4.0, "ring": 2.0, "echo_run": 1.2, "bridge": 0.6}
	dawn.palette = [
		_stop(0.00, "#5b6489", "#0d1024", "#f3c98f"),
		_stop(0.35, "#9a6f93", "#1d1230", "#ffd9a6"),
		_stop(0.70, "#e5937a", "#331a2c", "#fff0d4"),
		_stop(1.00, "#f5e5ca", "#26355f", "#e0603f"),
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
		_stop(0.00, "#d9ece6", "#16324a", "#e8833a"),
		_stop(0.30, "#86c3b9", "#0f2d3a", "#f5a04e"),
		_stop(0.65, "#2f7f85", "#061b24", "#ffc27a"),
		_stop(1.00, "#163f52", "#02080d", "#ffe1a8"),
	]
	specs.append(tide)

	# 3. A kiln cooling: fast and tight.
	var ember := LevelGenerator.Spec.new()
	ember.id = "03_ember"
	ember.display_name = "Ember"
	ember.seed = 3391
	ember.base_speed = 12.5
	ember.difficulty = 0.85
	ember.palette = [
		_stop(0.00, "#3a3233", "#0b0808", "#ffb347"),
		_stop(0.35, "#83302b", "#160505", "#ffd27a"),
		_stop(0.70, "#d98a35", "#251004", "#fff1c9"),
		_stop(1.00, "#eee4d0", "#3b2b22", "#83302b"),
	]
	specs.append(ember)
	return specs
