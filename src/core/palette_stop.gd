class_name PaletteStop
extends RefCounted
## One stop of a level's colour journey.
##
## The tunnel colour is a function of *progress* (s / level length), so a
## player can read how far they are from the colour around them, and see the
## next colour approaching in the distance.

## Progress in [0, 1] at which this stop applies.
var at: float
## Colour of the tunnel's inner wall.
var wall: Color
## Colour of the void seen through the holes (and the far end of the tunnel).
var void_color: Color
## Accent used for hole rims, landing ripples and the "best run" marker.
var accent: Color


func _init(p_at: float = 0.0, p_wall: Color = Color.WHITE, p_void: Color = Color.BLACK, p_accent: Color = Color.WHITE) -> void:
	at = p_at
	wall = p_wall
	void_color = p_void
	accent = p_accent
