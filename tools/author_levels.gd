extends SceneTree
## Writes the bundled levels (res://levels/) from the hand-made scripts in
## tools/levels/, and the manifest that lists them in play order.
##
##   godot --headless --script res://tools/author_levels.gd [-- --out <dir>] [--only 01_lemonade,...]
##
## Every level is written by hand on a clock (see LevelBuilder): the
## scripts are the source of truth, the JSON files are what the game and the
## level editor read. Re-run after editing a script, then check the level
## with tools/rate_levels.gd and the tests. A level edited in the editor and
## saved under its own id is no longer generated: keep it out of ORDER.

const OUTPUT_DIR := "res://levels/"
const ORDER := [
	"res://tools/levels/l1_lemonade.gd",
	"res://tools/levels/l2_bubblegum.gd",
	"res://tools/levels/l3_hot_sauce.gd",
	"res://tools/levels/l4_moon_bounce.gd",
	"res://tools/levels/l5_mixtape.gd",
	"res://tools/levels/l6_screwball.gd",
	"res://tools/levels/l7_supernova.gd",
]


func _init() -> void:
	var tuning: BallTuning = load("res://resources/ball_tuning.tres")
	var args := OS.get_cmdline_user_args()
	var out_dir := OUTPUT_DIR
	if "--out" in args:
		out_dir = args[args.find("--out") + 1].trim_suffix("/") + "/"
		DirAccess.make_dir_recursive_absolute(out_dir)
	var only: Array = []
	if "--only" in args:
		only = Array(args[args.find("--only") + 1].split(","))
	var ids: Array = []
	for path in ORDER:
		if not ResourceLoader.exists(path):
			continue
		var script: GDScript = load(path)
		var level: LevelData = script.new().build(tuning)
		ids.append(level.id)
		if not only.is_empty() and not only.has(level.id):
			continue
		var errors := LevelSerializer.validate(level)
		var problems := LevelValidator.check(level, tuning)
		var file := out_dir + level.id + ".json"
		var error := LevelSerializer.save_file(level, file)
		if error != OK:
			push_error("Could not write %s (%s)" % [file, error_string(error)])
			quit(1)
			return
		print("%s  %d holes  %d spin keys  %d speed keys  %d hints  %.0f m  %.1f s  %.1f..%.1f m/s%s" % [file, level.holes.size(),
			level.spin.size(), level.speed_keys.size(), level.hints.size(), level.length, level.duration(),
			level.speed_at(0.0), level.speed_at(level.length),
			"" if errors.is_empty() and problems.is_empty() else "  WARN " + "; ".join(errors + problems)])
	var manifest := FileAccess.open(out_dir + "manifest.json", FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"levels": ids}, "  ") + "\n")
	quit(0)
