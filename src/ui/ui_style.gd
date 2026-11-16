class_name UiStyle
extends RefCounted
## Typography and widgets shared by every screen.
##
## Quiet and precise: an extra-light grotesk for names and numbers, a small
## spaced-out monospace for labels, no boxes or bevels. Text sits directly
## on the dark tunnel.

const DISPLAY := preload("res://assets/fonts/Geist-ExtraLight.woff2")
const TEXT := preload("res://assets/fonts/Geist-Regular.woff2")
const MONO := preload("res://assets/fonts/GeistMono-Regular.woff2")
const MONO_MEDIUM := preload("res://assets/fonts/GeistMono-Medium.woff2")

const INK := Color("e9eaee")
const SHADOW := Color(0.0, 0.0, 0.0, 0.35)


## Large, light display text. `tracking` adds letter spacing (in pixels).
static func display(text: String, size: int, tracking: int = 0, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	var font := FontVariation.new()
	font.base_font = DISPLAY
	font.spacing_glyph = tracking
	label.add_theme_font_override("font", font)
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


## A borderless text button. `primary` uses the display face, others the caption style.
static func button(text: String, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text if primary else text.to_upper()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if primary:
		b.add_theme_font_override("font", DISPLAY)
		b.add_theme_font_size_override("font_size", 60)
	else:
		var font := FontVariation.new()
		font.base_font = MONO_MEDIUM
		font.spacing_glyph = 5
		b.add_theme_font_override("font", font)
		b.add_theme_font_size_override("font_size", 26)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, INK)
	b.add_theme_color_override("font_pressed_color", INK.darkened(0.3))
	b.add_theme_color_override("font_disabled_color", INK.darkened(0.6))
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
