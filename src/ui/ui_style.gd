class_name UiStyle
extends RefCounted
## Typography and widgets shared by every screen.
##
## Chunky and loud, like an old Flash game: one rounded heavy face
## (Lilita One) for everything, white with a thick dark outline so it reads
## on any colour. No panels or boxes.

const FONT := preload("res://assets/fonts/LilitaOne-Regular.woff2")
const OUTLINE := Color("0b0910")

const INK := Color("ffffff")
## Text that is not available yet (locked levels).
const LOCKED := Color("a9a3b5")
const SHADOW := Color("0b0910")


## Big headline text. `tracking` adds letter spacing (in pixels).
static func display(text: String, size: int, tracking: int = 0, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _font(tracking))
	label.add_theme_font_size_override("font_size", size)
	_finish(label, color, size)
	return label


## Small uppercase label.
static func caption(text: String, size: int = 22, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_override("font", _font(int(size * 0.08)))
	label.add_theme_font_size_override("font_size", size)
	_finish(label, color, size)
	return label


## A borderless text button: big for primary actions, small caps otherwise.
static func button(text: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text if primary else text.to_upper()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var size := 64 if primary else 30
	b.add_theme_font_override("font", _font(0 if primary else 2))
	b.add_theme_font_size_override("font_size", size)
	for state in ["font_color", "font_hover_color", "font_focus_color"]:
		b.add_theme_color_override(state, INK)
	b.add_theme_color_override("font_pressed_color", Color("fff36b"))
	b.add_theme_color_override("font_disabled_color", LOCKED)
	b.add_theme_color_override("font_outline_color", OUTLINE)
	b.add_theme_constant_override("outline_size", int(size * 0.22))
	b.custom_minimum_size = Vector2(0, 88)  # >= 44 pt touch target at 2x
	return b


static func _font(tracking: int) -> Font:
	if tracking == 0:
		return FONT
	var font := FontVariation.new()
	font.base_font = FONT
	font.spacing_glyph = tracking
	return font


static func _finish(label: Label, color: Color, size: int) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", OUTLINE)
	label.add_theme_constant_override("outline_size", maxi(int(size * 0.2), 6))
	label.add_theme_color_override("font_shadow_color", SHADOW)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", maxi(int(size * 0.06), 3))
	label.add_theme_constant_override("shadow_outline_size", maxi(int(size * 0.2), 6))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
