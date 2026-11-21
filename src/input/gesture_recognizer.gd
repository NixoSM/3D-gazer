class_name GestureRecognizer
extends RefCounted
## Turns raw touches into the game's two gestures: *swipe up* and *swipe down*.
##
## * A swipe up fires on release with a strength proportional to its length,
##   or early as soon as it reaches full length, so long swipes feel instant.
## * A swipe down (the smash) has no size: it fires the moment the finger has
##   travelled SMASH_SWIPE downwards, mid-drag, never waiting for the lift.
##   The smash is about timing, and every frame of lag would blunt it.
## Distances are fractions of the screen height, so any device size works.

## Swipes shorter than this (fraction of screen height) are ignored.
const MIN_SWIPE := 0.035
## A swipe this long is a full-strength jump.
const FULL_SWIPE := 0.28
## Swipes must be mostly vertical: |dx| <= dy * this.
const MAX_SLANT := 1.1
## A downward drag this long (fraction of screen height) is a smash.
const SMASH_SWIPE := 0.03

## True once per swipe down.
var smashed := false
## Strength of a completed swipe in [0, 1], or -1.
var swipe_strength := -1.0

var _active_index := -1
var _start := Vector2.ZERO
var _fired := false


## Feed every touch event here. Returns true if the event was used.
func handle(event: InputEvent, screen_height: float) -> bool:
	if event is InputEventScreenTouch:
		if event.pressed and _active_index == -1:
			_active_index = event.index
			_start = event.position
			_fired = false
			return true
		if not event.pressed and event.index == _active_index:
			if not _fired:
				_try_smash(event.position, screen_height)
			if not _fired:
				_try_swipe(event.position, screen_height, false)
			_active_index = -1
			return true
	elif event is InputEventScreenDrag and event.index == _active_index and not _fired:
		_try_smash(event.position, screen_height)
		if not _fired:
			_try_swipe(event.position, screen_height, true)
		return true
	return false


## A finger is down and has not produced a swipe yet.
func is_holding() -> bool:
	return _active_index != -1 and not _fired


## Forgets everything, the finger being tracked included. For moments when
## touch events stop arriving (input off after a fall, the game paused, the
## app in the background): the lift of that finger would never be seen, and
## the stale finger would swallow the next touch and keep "holding" on.
func reset() -> void:
	consume()
	_active_index = -1
	_fired = false


## Clears the one-shot gestures once they have been handed to the simulation.
func consume() -> void:
	smashed = false
	swipe_strength = -1.0


func _try_swipe(position: Vector2, screen_height: float, only_if_full: bool) -> void:
	var up := (_start.y - position.y) / screen_height
	var side := absf(position.x - _start.x) / screen_height
	if up < MIN_SWIPE or side > up * MAX_SLANT:
		return
	var strength := clampf((up - MIN_SWIPE) / (FULL_SWIPE - MIN_SWIPE), 0.0, 1.0)
	if only_if_full and strength < 1.0:
		return
	swipe_strength = strength
	_fired = true


func _try_smash(position: Vector2, screen_height: float) -> void:
	var down := (position.y - _start.y) / screen_height
	var side := absf(position.x - _start.x) / screen_height
	if down < SMASH_SWIPE or side > down * MAX_SLANT:
		return
	smashed = true
	_fired = true
