extends SceneTree
## Prints how much of each bundled level is "just scrolling": stretches
## where no hole starts or is underway for more than IDLE seconds.
##   godot --headless --script res://tools/idle_report.gd

const IDLE := 1.0


func _time(level: LevelData, s: float) -> float:
	var ramp := level.speed_ramp
	if ramp <= 0.0001:
		return s / level.base_speed
	return level.length / (ramp * level.base_speed) * log(1.0 + ramp * s / level.length)


func _init() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://levels/manifest.json"))
	for id in manifest["levels"]:
		var level := LevelSerializer.load_file("res://levels/%s.json" % id).level
		var busy_until := 0.0
		var idle_total := 0.0
		var longest := 0.0
		var stretches := []
		for hole in level.holes:
			var gap := _time(level, hole.s_start) - _time(level, busy_until)
			if gap > IDLE:
				idle_total += gap - IDLE
				stretches.append("%.1fs@%.0fs" % [gap, _time(level, busy_until)])
			longest = maxf(longest, gap)
			busy_until = maxf(busy_until, hole.s_end())
		var duration := level.duration()
		var lengths := []
		for hole in level.holes:
			lengths.append(hole.length)
		lengths.sort()
		print("%s  %.0f s  holes %d  idle beyond %.1f s: %.1f s (%.0f%%)  longest gap %.2f s  stretches>%.1fs %d  median hole %.1f m" % [id, duration,
			level.holes.size(), IDLE, idle_total, 100.0 * idle_total / duration, longest, IDLE, stretches.size(), lengths[lengths.size() / 2]])
		if "--list" in OS.get_cmdline_user_args():
			print("    ", " ".join(stretches))
	quit(0)
