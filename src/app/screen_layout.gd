extends Node
## Portrait or landscape, and everything that follows from it. Autoloaded as
## `ScreenLayout`.
##
## * The phone turns freely in menus, pause and results. During a run the
##   app locks to the family it is in (portrait or landscape), because a
##   hard steering tilt can be mistaken for "the player turned the phone",
##   and a mid-run rotation would throw them into a hole. Flipping between
##   the two landscapes stays allowed: it takes a 180° turn nobody makes
##   while steering.
## * The 2D design canvas follows the window: 720 x 1560 tall, 1560 x 720
##   wide. Text and buttons stay the same physical size either way (with one
##   fixed canvas, landscape would shrink everything to under half size).
## * Tilt needs nothing here: Godot already turns the gravity vector into
##   screen coordinates for the current orientation, on iOS and Android.

signal changed(landscape: bool)

## The short and long side of the design canvas.
const SHORT_SIDE := 720
const LONG_SIDE := 1560

var landscape := false


func _ready() -> void:
	get_tree().root.size_changed.connect(_update)
	_update()


## Called when a run starts or resumes.
func lock_for_play() -> void:
	if not OS.has_feature("mobile"):
		return
	DisplayServer.screen_set_orientation(
			DisplayServer.SCREEN_SENSOR_LANDSCAPE if landscape else DisplayServer.SCREEN_SENSOR_PORTRAIT)


## Called in menus, pause and results.
func unlock() -> void:
	if not OS.has_feature("mobile"):
		return
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)


## Pure rule, for tests: the design canvas for a window of this size.
static func canvas_for(window: Vector2i) -> Vector2i:
	return Vector2i(LONG_SIDE, SHORT_SIDE) if window.x > window.y else Vector2i(SHORT_SIDE, LONG_SIDE)


func _update() -> void:
	var window := get_tree().root
	# The level editor runs with stretching off and lays itself out.
	if window.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED:
		return
	var size := window.size
	if size.x <= 0 or size.y <= 0:
		return
	var canvas := canvas_for(size)
	if window.content_scale_size != canvas:
		window.content_scale_size = canvas
	var wide := size.x > size.y
	if wide != landscape:
		landscape = wide
		changed.emit(landscape)
