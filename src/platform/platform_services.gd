extends Node
## The only place that talks to platform-specific APIs. Autoloaded as `Platform`.
##
## Game code asks for *intentions* ("a strong haptic tick") and this node maps
## them to whatever the device offers. Porting to Android, or adding a native
## iOS plugin for richer Core Haptics patterns, only touches this file.

enum Haptic { LIGHT, MEDIUM, HEAVY, SUCCESS }

## Duration (ms) and amplitude (0..1) for each haptic intention.
const HAPTIC_PATTERNS := {
	Haptic.LIGHT: [12, 0.35],
	Haptic.MEDIUM: [22, 0.6],
	Haptic.HEAVY: [40, 1.0],
	Haptic.SUCCESS: [80, 0.8],
}


func _ready() -> void:
	# A tilt game is played without touching the screen for long stretches.
	DisplayServer.screen_set_keep_on(true)


func is_handheld() -> bool:
	return OS.has_feature("mobile")


func haptic(kind: Haptic) -> void:
	if not Settings.haptics_enabled or not is_handheld():
		return
	var pattern: Array = HAPTIC_PATTERNS[kind]
	Input.vibrate_handheld(pattern[0], pattern[1])
