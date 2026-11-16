extends Node
## Player preferences, persisted to user://settings.cfg. Autoloaded as `Settings`.

signal changed

const PATH := "user://settings.cfg"

var haptics_enabled: bool = true:
	set(value):
		haptics_enabled = value
		_save()
var sound_enabled: bool = true:
	set(value):
		sound_enabled = value
		_save()
## Flip if tilting right steers left on a particular device.
var invert_tilt: bool = false:
	set(value):
		invert_tilt = value
		_save()
## Multiplier on phone tilt before it reaches the simulation.
var tilt_sensitivity: float = 1.0:
	set(value):
		tilt_sensitivity = clampf(value, 0.4, 2.5)
		_save()

## The phone roll (degrees) the player wants treated as level. 0 = straight.
var tilt_zero_degrees: float = 0.0:
	set(value):
		tilt_zero_degrees = clampf(value, -35.0, 35.0)
		_save()

var _loading := false


func _ready() -> void:
	_load()


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	_loading = true
	haptics_enabled = config.get_value("feedback", "haptics", true)
	sound_enabled = config.get_value("feedback", "sound", true)
	invert_tilt = config.get_value("controls", "invert_tilt", false)
	tilt_sensitivity = config.get_value("controls", "tilt_sensitivity", 1.0)
	tilt_zero_degrees = config.get_value("controls", "tilt_zero_degrees", 0.0)
	_loading = false


func _save() -> void:
	if _loading:
		return
	var config := ConfigFile.new()
	config.set_value("feedback", "haptics", haptics_enabled)
	config.set_value("feedback", "sound", sound_enabled)
	config.set_value("controls", "invert_tilt", invert_tilt)
	config.set_value("controls", "tilt_sensitivity", tilt_sensitivity)
	config.set_value("controls", "tilt_zero_degrees", tilt_zero_degrees)
	config.save(PATH)
	changed.emit()
