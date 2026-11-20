class_name LevelHint
extends RefCounted
## A short prompt shown on screen when the ball reaches a point of the level
## ("swipe up to jump" just before the first ring). Levels teach by their
## layout first; hints only name what the layout is asking for. They show
## until the player has finished the level once.

## Distance along the tunnel (metres) where the hint appears.
var s: float
## What it says. Keep it to a few words: it is read at speed.
var text: String


func _init(p_s: float = 0.0, p_text: String = "") -> void:
	s = p_s
	text = p_text
