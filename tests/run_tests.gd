extends SceneTree
## Headless test runner.
##
##   godot --headless --script res://tests/run_tests.gd
##
## Runs every `test_*` method of every tests/test_*.gd file. Exit code 0 means
## all tests passed, so it can gate CI.


func _init() -> void:
	var total := 0
	var failed := 0
	var dir := DirAccess.open("res://tests/")
	var files := Array(dir.get_files()).filter(func(f: String) -> bool: return f.begins_with("test_") and f.ends_with(".gd"))
	files.sort()
	for file in files:
		var script: GDScript = load("res://tests/" + file)
		if script == null or not script.can_instantiate():
			failed += 1
			total += 1
			printerr("  FAIL  %s does not compile" % file)
			continue
		for method in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			var instance: TestCase = script.new()
			instance._current = "%s::%s" % [file.get_basename(), name]
			instance.call(name)
			total += 1
			if instance.failures.is_empty():
				print("  ok    ", instance._current)
			else:
				failed += 1
				for failure in instance.failures:
					printerr("  FAIL  ", failure)
	print("\n%d tests, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)
