class_name EditorTheme
extends RefCounted
## The level editor's look: the game's Flash-era style turned into a tool.
## Flat warm paper panels, thick black borders, chunky offset shadows, one
## loud yellow for "active" and the game's own font. Built in code like the
## game's UI (UiStyle), so there is no .tres to keep in sync.

const FONT := preload("res://assets/fonts/LilitaOne-Regular.woff2")

const INK := Color("0b0910")
const PAPER := Color("fff4dc")
const PAPER_DARK := Color("f4dfb4")
const FIELD := Color("ffffff")
const ACTIVE := Color("ffd23f")
const HOT := Color("ff4f79")
const MUTED := Color("6b6275")
const GOOD := Color("2ec27e")
const WARN := Color("ff9f1c")
const BAD := Color("e8283c")

## One colour per analysis bot, from quickest reflexes to slowest.
const BOT_COLORS := [Color("00b4d8"), Color("7b2ff7"), Color("ff4f79")]

const FONT_SIZE := 17
const BORDER := 3


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font = FONT
	theme.default_font_size = FONT_SIZE

	for type in ["Label", "Button", "MenuButton", "OptionButton", "CheckBox", "CheckButton", "LineEdit", "SpinBox", "PopupMenu", "TooltipLabel", "ItemList"]:
		theme.set_color("font_color", type, INK)
	theme.set_color("font_hover_color", "Button", INK)
	theme.set_color("font_pressed_color", "Button", INK)
	theme.set_color("font_focus_color", "Button", INK)
	theme.set_color("font_hover_pressed_color", "Button", INK)
	theme.set_color("font_disabled_color", "Button", MUTED)
	theme.set_color("font_hover_color", "PopupMenu", INK)
	theme.set_color("font_selected_color", "LineEdit", INK)
	theme.set_color("selection_color", "LineEdit", ACTIVE)
	theme.set_color("caret_color", "LineEdit", INK)

	var normal := box(FIELD)
	var hover := box(Color("fffbef"))
	var pressed := box(ACTIVE, 0)
	pressed.content_margin_top += 2
	var disabled := box(PAPER_DARK, 0)
	for type in ["Button", "MenuButton", "OptionButton"]:
		theme.set_stylebox("normal", type, normal)
		theme.set_stylebox("hover", type, hover)
		theme.set_stylebox("pressed", type, pressed)
		theme.set_stylebox("hover_pressed", type, pressed)
		theme.set_stylebox("disabled", type, disabled)
		theme.set_stylebox("focus", type, StyleBoxEmpty.new())

	var field := box(FIELD, 0)
	field.border_width_left = 2
	field.border_width_right = 2
	field.border_width_top = 2
	field.border_width_bottom = 2
	field.content_margin_left = 8
	theme.set_stylebox("normal", "LineEdit", field)
	var focus := field.duplicate() as StyleBoxFlat
	focus.border_color = HOT
	theme.set_stylebox("focus", "LineEdit", focus)
	theme.set_stylebox("read_only", "LineEdit", box(PAPER_DARK, 0))

	var popup := box(PAPER, 5)
	popup.content_margin_left = 6
	popup.content_margin_right = 6
	theme.set_stylebox("panel", "PopupMenu", popup)
	theme.set_stylebox("hover", "PopupMenu", box(ACTIVE, 0, 0))
	theme.set_stylebox("panel", "PopupPanel", popup)
	theme.set_stylebox("panel", "TooltipPanel", box(PAPER, 3))
	theme.set_stylebox("panel", "PanelContainer", panel(PAPER))
	theme.set_stylebox("panel", "AcceptDialog", panel(PAPER))
	theme.set_stylebox("embedded_border", "Window", panel(PAPER))

	theme.set_constant("separation", "HBoxContainer", 8)
	theme.set_constant("separation", "VBoxContainer", 8)
	theme.set_constant("h_separation", "GridContainer", 8)
	theme.set_constant("v_separation", "GridContainer", 6)
	theme.set_constant("separation", "HSplitContainer", 10)
	return theme


## A chunky box: flat fill, black border, rounded corners, hard shadow.
static func box(fill: Color, shadow: int = 3, border: int = BORDER) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = INK
	style.border_width_left = border
	style.border_width_right = border
	style.border_width_top = border
	style.border_width_bottom = border
	style.set_corner_radius_all(7)
	style.shadow_color = INK
	style.shadow_size = 0
	style.shadow_offset = Vector2(0, shadow)
	if shadow > 0:
		style.shadow_size = 1
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style


static func panel(fill: Color) -> StyleBoxFlat:
	var style := box(fill, 0)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


## A section heading inside a panel.
static func heading(text: String, size: int = 22) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", INK)
	return label


static func note(text: String, color: Color = MUTED) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	return label
