class_name PauseScreen
extends Control
## Pause overlay with the few settings worth having on a phone.

signal resume_pressed
signal restart_pressed
signal quit_pressed
## "Treat the way I hold the phone now as level."
signal set_level_pressed
signal reset_level_pressed

var _haptics: Button
var _sound: Button
var _invert: Button
var _sensitivity: Label
var _level: Label
var _level_reset: Button


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

	layout.add_child(UiStyle.display("Paused", 96))
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

	# Level is "phone straight" unless the player chooses another angle.
	_level = UiStyle.caption("", 24)
	layout.add_child(_level)
	var level_row := HBoxContainer.new()
	level_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var set_here := UiStyle.button("use this angle")
	set_here.pressed.connect(func() -> void: set_level_pressed.emit(); _refresh())
	_level_reset = UiStyle.button("straight")
	_level_reset.pressed.connect(func() -> void: reset_level_pressed.emit(); _refresh())
	level_row.add_child(set_here)
	level_row.add_child(_level_reset)
	layout.add_child(level_row)

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
	var zero := Settings.tilt_zero_degrees
	_level.text = "LEVEL: PHONE STRAIGHT" if absf(zero) < 0.5 else "LEVEL: PHONE %d° %s" % [roundi(absf(zero)), "RIGHT" if zero > 0.0 else "LEFT"]
	_level_reset.visible = absf(zero) >= 0.5
