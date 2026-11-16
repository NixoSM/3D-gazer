class_name PauseScreen
extends Control
## Pause overlay with the few settings worth having on a phone.

signal resume_pressed
signal restart_pressed
signal quit_pressed

var _haptics: Button
var _sound: Button
var _invert: Button
var _sensitivity: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var safe := SafeArea.new()
	add_child(safe)
	var layout := VBoxContainer.new()
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 8)
	safe.add_child(layout)

	layout.add_child(UiStyle.serif("Paused", 120))
	var resume := UiStyle.button("Resume", true)
	resume.pressed.connect(resume_pressed.emit)
	layout.add_child(resume)
	var restart := UiStyle.button("restart level")
	restart.pressed.connect(restart_pressed.emit)
	layout.add_child(restart)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 40)
	layout.add_child(gap)

	_haptics = UiStyle.button("")
	_haptics.pressed.connect(func() -> void: Settings.haptics_enabled = not Settings.haptics_enabled; _refresh())
	layout.add_child(_haptics)
	_sound = UiStyle.button("")
	_sound.pressed.connect(func() -> void: Settings.sound_enabled = not Settings.sound_enabled; _refresh())
	layout.add_child(_sound)
	_invert = UiStyle.button("")
	_invert.pressed.connect(func() -> void: Settings.invert_tilt = not Settings.invert_tilt; _refresh())
	layout.add_child(_invert)

	var sensitivity_row := HBoxContainer.new()
	sensitivity_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var less := UiStyle.button("−")
	less.custom_minimum_size = Vector2(96, 88)
	less.pressed.connect(func() -> void: Settings.tilt_sensitivity -= 0.1; _refresh())
	var more := UiStyle.button("+")
	more.custom_minimum_size = Vector2(96, 88)
	more.pressed.connect(func() -> void: Settings.tilt_sensitivity += 0.1; _refresh())
	_sensitivity = UiStyle.caption("", 24)
	_sensitivity.custom_minimum_size = Vector2(330, 0)
	sensitivity_row.add_child(less)
	sensitivity_row.add_child(_sensitivity)
	sensitivity_row.add_child(more)
	layout.add_child(sensitivity_row)

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 40)
	layout.add_child(gap2)
	var quit := UiStyle.button("back to levels")
	quit.pressed.connect(quit_pressed.emit)
	layout.add_child(quit)
	_refresh()


func _refresh() -> void:
	_haptics.text = "HAPTICS  %s" % ("ON" if Settings.haptics_enabled else "OFF")
	_sound.text = "SOUND  %s" % ("ON" if Settings.sound_enabled else "OFF")
	_invert.text = "TILT  %s" % ("INVERTED" if Settings.invert_tilt else "NORMAL")
	_sensitivity.text = "SENSITIVITY %.1f" % Settings.tilt_sensitivity
