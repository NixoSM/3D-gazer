extends TestCase
## Landscape support: the design canvas and the camera's view angle.

const LayoutScript := preload("res://src/app/screen_layout.gd")


func test_canvas_follows_the_window() -> void:
	assert_eq(LayoutScript.canvas_for(Vector2i(1170, 2532)), Vector2i(720, 1560))
	assert_eq(LayoutScript.canvas_for(Vector2i(2532, 1170)), Vector2i(1560, 720))


func test_portrait_fov_is_unchanged() -> void:
	assert_near(CameraRig.fov_for_aspect(76.0, 0.46, 0.35), 76.0, 0.001)


func test_landscape_fov_stays_out_of_fisheye() -> void:
	var aspect := 2532.0 / 1170.0
	for tall in [64.0, 76.0, 98.0]:
		var vertical := CameraRig.fov_for_aspect(tall, aspect, _squeeze())
		var horizontal := rad_to_deg(2.0 * atan(tan(deg_to_rad(vertical) * 0.5) * aspect))
		assert_true(vertical < tall, "landscape narrows the vertical angle")
		assert_true(horizontal < 128.0, "horizontal %.1f° at %.0f° is a fisheye" % [horizontal, tall])


## Landscape must not shrink what is ahead: the same focal length means the
## landscape's horizontal angle equals portrait's vertical one.
func test_landscape_keeps_portrait_focal_length() -> void:
	var aspect := 2532.0 / 1170.0
	var squeeze: float = _squeeze()
	for tall in [64.0, 76.0, 98.0]:
		var vertical := CameraRig.fov_for_aspect(tall, aspect, squeeze)
		var horizontal := rad_to_deg(2.0 * atan(tan(deg_to_rad(vertical) * 0.5) * aspect))
		assert_near(horizontal, tall, 0.01, "focal length differs at %.0f°" % tall)


func _squeeze() -> float:
	var rig := CameraRig.new()
	var squeeze := rig.landscape_squeeze
	rig.free()
	return squeeze
