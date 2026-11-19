extends SceneTree
## Renders icon.svg (made by tools/make_icon.py) to the PNGs the exports use.
##
##   godot --headless --script res://tools/rasterize_icon.gd
##
## icon_1024.png is the iOS App Store / home screen icon: opaque, square
## (iOS rounds the corners itself).


func _init() -> void:
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	for size in [1024, 180, 120]:
		var image := Image.new()
		var error := image.load_svg_from_string(svg, size / 1024.0)
		if error != OK:
			push_error("icon.svg did not load: %s" % error_string(error))
			quit(1)
			return
		image.convert(Image.FORMAT_RGB8)  # no alpha: the App Store refuses it
		var path := "res://assets/icon/icon_%d.png" % size
		DirAccess.make_dir_recursive_absolute("res://assets/icon")
		image.save_png(path)
		print("wrote ", path)
	quit(0)
