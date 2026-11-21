extends Node
## How far ahead the player can read the floor, in seconds, for the current
## window shape. Compare portrait and landscape:
##
##   xvfb-run -a godot --resolution 585x1266 res://tools/framing_report.tscn
##   xvfb-run -a godot --resolution 1266x585 res://tools/framing_report.tscn [-- --squeeze=0.35]
##
## "Readable" means a FEATURE_METRES stretch of floor on the ball's line (a
## small hole) spans at least READABLE_POINTS on an iPhone screen
## (390 x 844 pt): about when its near and far edges separate into a shape.
## The absolute seconds depend on that choice; the ratio between
## orientations does not. Size on screen falls off with
## distance, so warning time scales with the camera's focal length.

const READABLE_POINTS := 3.0
const FEATURE_METRES := 2.0
## iPhone 14/15/16 screen in points; only the ratio to the render matters.
const SCREEN_POINTS := Vector2(390, 844)


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	_run.call_deferred(main)


func _run(main: Node) -> void:
	for i in 3:
		await get_tree().process_frame
	var camera: CameraRig = main.world.camera
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--squeeze="):
			camera.landscape_squeeze = float(arg.get_slice("=", 1))
	var view := get_viewport().get_visible_rect().size
	var landscape := view.x > view.y
	var screen_h := SCREEN_POINTS.x if landscape else SCREEN_POINTS.y
	print("%s, squeeze %.2f" % ["LANDSCAPE" if landscape else "PORTRAIT", camera.landscape_squeeze])
	print("level          speed  vfov   focal(pt)  readable(m)  warning(s)  ball_y")
	for level: LevelData in main.levels:
		var radius := level.tunnel_radius
		for speed in [level.speed_at(0.0), level.speed_at(level.length * 0.95)]:
			var s := 200.0
			camera.snap(s)
			camera.update_view(1.0 / 60.0, s, 0.0, 0.0, radius, speed, false)
			camera.force_update_transform()
			var focal := (screen_h * 0.5) / tan(deg_to_rad(camera.fov) * 0.5)
			var readable := 0.0
			var d := 1.0
			while d < 400.0:
				var a := camera.unproject_position(TunnelMath.point(s + d, 0.0, radius))
				var b := camera.unproject_position(TunnelMath.point(s + d + FEATURE_METRES, 0.0, radius))
				if absf(a.y - b.y) / view.y * screen_h < READABLE_POINTS:
					break
				readable = d
				d += 0.25
			var ball := camera.unproject_position(TunnelMath.point(s, 0.0, radius - 0.5))
			print("%-14s %5.1f  %5.1f  %8.0f  %10.1f  %9.2f   %.2f" % [level.display_name, speed, camera.fov,
					focal, readable, readable / speed, ball.y / view.y])
	get_tree().quit()
