class_name UiStyle
extends RefCounted
## Typography and widgets shared by every screen.
##
## The look is editorial rather than "gamey": a large italic serif for names
## and numbers, a small spaced-out monospace for labels, no boxes or bevels.
## Text sits directly on the tunnel and takes its colour from the level.

const SERIF := preload("res://assets/fonts/InstrumentSerif-Regular.woff2")
const SERIF_ITALIC := preload("res://assets/fonts/InstrumentSerif-Italic.woff2")
const MONO := preload("res://assets/fonts/GeistMono-Regular.woff2")
const MONO_MEDIUM := preload("res://assets/fonts/GeistMono-Medium.woff2")

const INK := Color("f6efe3")
const SHADOW := Color(0.0, 0.0, 0.0, 0.28)


static func serif(text: String, size: int, italic: bool = true, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", SERIF_ITALIC if italic else SERIF)
	label.add_theme_font_size_override("font_size", size)
	_finish(label, color)
	return label


## Small uppercase label with wide tracking.
static func caption(text: String, size: int = 22, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	var font := FontVariation.new()
	font.base_font = MONO
	font.spacing_glyph = int(size * 0.18)
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	_finish(label, color)
	return label


## A borderless text button. `primary` uses the serif, others the caption style.
static func button(text: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text if primary else text.to_upper()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if primary:
		b.add_theme_font_override("font", SERIF_ITALIC)
		b.add_theme_font_size_override("font_size", 64)
	else:
		var font := FontVariation.new()
		font.base_font = MONO_MEDIUM
		font.spacing_glyph = 5
		b.add_theme_font_override("font", font)
		b.add_theme_font_size_override("font_size", 26)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, INK)
	b.add_theme_color_override("font_pressed_color", INK.darkened(0.25))
	b.custom_minimum_size = Vector2(0, 88)  # >= 44 pt touch target at 2x
	return b


static func _finish(label: Label, color: Color) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", SHADOW)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_constant_override("shadow_outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
