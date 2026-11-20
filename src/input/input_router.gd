class_name InputRouter
extends Node
## Collects everything the player does and hands the simulation InputFrames.
##
## The simulation runs at a fixed rate that differs from the frame rate, so
## one-shot gestures (taps, swipes) are delivered to exactly one step and
## then cleared, while tilt is sampled continuously.

var tilt_reader := TiltReader.new()
var gestures := GestureRecognizer.new()
## When false, gestures are ignored (menus, pause).
var enabled := false

var _tilt := 0.0


func _ready() -> void:
	_register_desktop_actions()


func _process(delta: float) -> void:
	_tilt = tilt_reader.read(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	var height := get_viewport().get_visible_rect().size.y
	if gestures.handle(event, height):
		get_viewport().set_input_as_handled()
		return
	# Desktop shortcuts mirror the touch gestures.
	if event.is_action_pressed(&"jump_small"):
		gestures.swipe_strength = 0.45
	elif event.is_action_pressed(&"jump_big"):
		gestures.swipe_strength = 1.0
	elif event.is_action_pressed(&"smash"):
		gestures.smashed = true


func set_level_here() -> float:
	return tilt_reader.set_level_here()


func reset_level() -> void:
	tilt_reader.reset_level()


func current_tilt() -> float:
	return _tilt


## The next InputFrame. One-shot gestures are consumed by this call.
func take_frame() -> InputFrame:
	var frame := InputFrame.new(_tilt, gestures.swipe_strength if enabled else -1.0, gestures.smashed and enabled)
	frame.holding = enabled and gestures.is_holding()
	gestures.consume()
	return frame


## Keys for playing on a computer. Registered in code so they are documented
## next to the touch controls they imitate.
func _register_desktop_actions() -> void:
	var bindings := {
		&"tilt_left": [KEY_A, KEY_LEFT],
		&"tilt_right": [KEY_D, KEY_RIGHT],
		&"jump_small": [KEY_W, KEY_UP],
		&"jump_big": [KEY_SPACE],
		&"smash": [KEY_S, KEY_DOWN, KEY_E, KEY_SHIFT],
		&"pause": [KEY_ESCAPE, KEY_P],
	}
	for action in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode in bindings[action]:
			var key := InputEventKey.new()
			key.physical_keycode = keycode
			InputMap.action_add_event(action, key)
