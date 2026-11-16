class_name SpeedLines
extends CanvasLayer
## Full-screen cartoon speed lines over the 3D view (shaders/speed_lines).
## Their strength follows forward speed: none at Dawn's pace, a few on Tide,
## a storm on Ember. Purely visual.

## Below this speed (m/s) there are no lines; at FULL_SPEED they are at full strength.
const START_SPEED := 15.5
const FULL_SPEED := 24.0

var _rect := ColorRect.new()
var _material := ShaderMaterial.new()
var _intensity := 0.0
var _time := 0.0


func _ready() -> void:
	layer = 0
	_material.shader = preload("res://shaders/speed_lines.gdshader")
	_rect.material = _material
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	_material.set_shader_parameter("intensity", 0.0)


## Call every frame with the forward speed (0 when not running). While
## `held` (the echo hit-stop) the lines stop where they are.
func set_speed(speed: float, delta: float, held: bool = false) -> void:
	if not held:
		_time += delta
	_material.set_shader_parameter("clock", _time)
	if held:
		return
	var target := clampf(inverse_lerp(START_SPEED, FULL_SPEED, speed), 0.0, 1.0)
	_intensity = lerpf(_intensity, target, 1.0 - exp(-4.0 * delta))
	_material.set_shader_parameter("intensity", _intensity)
	_rect.visible = _intensity > 0.01
