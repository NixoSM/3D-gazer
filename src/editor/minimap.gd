class_name Minimap
extends Control
## The whole level at a glance, beside the strip: every hole, where each
## analysis bot falls, every problem, and the part the strip is showing.
## Click or drag to jump there.

signal jump_to(s: float)

var strip: StripView
var analysis: LevelAnalysis

var _rect: ColorRect
var _overlay: Control


func _ready() -> void:
	custom_minimum_size = Vector2(56, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = StripView.STRIP_SHADER
	_rect.material = material
	add_child(_rect)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	resized.connect(func() -> void:
		_rect.position = Vector2(4, 4)
		_rect.size = size - Vector2(8, 8)
		_overlay.size = size)


## Call after the level changed (the strip has already rebuilt its textures).
func level_changed() -> void:
	var level := strip.level()
	var strip_material := strip.strip_material()
	var material := _rect.material as ShaderMaterial
	for parameter in ["hole_data", "wall_gradient", "void_gradient", "level_length", "tunnel_radius"]:
		material.set_shader_parameter(parameter, strip_material.get_shader_parameter(parameter))
	material.set_shader_parameter("s_bottom", 0.0)
	material.set_shader_parameter("s_top", level.length)
	material.set_shader_parameter("angle_middle", 0.0)
	material.set_shader_parameter("hole_first", 0)
	material.set_shader_parameter("hole_count", level.holes.size())
	material.set_shader_parameter("outline_width", 0.0)
	_overlay.queue_redraw()


func refresh() -> void:
	_overlay.queue_redraw()


func _s_to_y(s: float) -> float:
	return _rect.position.y + _rect.size.y * (1.0 - s / strip.level().length)


func _gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouse
	if mouse == null:
		return
	var drag := mouse is InputEventMouseMotion and (mouse.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	var click := mouse is InputEventMouseButton and (mouse as InputEventMouseButton).pressed and (mouse as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	if drag or click:
		var fraction := 1.0 - (mouse.position.y - _rect.position.y) / _rect.size.y
		jump_to.emit(clampf(fraction, 0.0, 1.0) * strip.level().length)
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), EditorTheme.INK)


func _draw_overlay() -> void:
	if strip == null:
		return
	var level := strip.level()
	var left: float = _rect.position.x
	var right: float = _rect.position.x + _rect.size.x
	if analysis and analysis.report:
		for gap in analysis.report.gaps:
			if gap.too_long() or gap.too_close():
				var y := _s_to_y(gap.s_start)
				_overlay.draw_rect(Rect2(left - 4, y - 3, size.x, 6), EditorTheme.BAD)
	if analysis:
		for i in analysis.bots.size():
			var trace := analysis.bots[i]
			var y := _s_to_y(trace.end_s)
			var x: float = left + (right - left) * (i + 0.5) / analysis.bots.size()
			var color: Color = EditorTheme.BOT_COLORS[i]
			if trace.outcome == "fell":
				_overlay.draw_line(Vector2(x - 6, y - 6), Vector2(x + 6, y + 6), EditorTheme.INK, 6.0)
				_overlay.draw_line(Vector2(x - 6, y + 6), Vector2(x + 6, y - 6), EditorTheme.INK, 6.0)
				_overlay.draw_line(Vector2(x - 6, y - 6), Vector2(x + 6, y + 6), color, 3.0)
				_overlay.draw_line(Vector2(x - 6, y + 6), Vector2(x + 6, y - 6), color, 3.0)
			elif trace.outcome == "running":
				_overlay.draw_rect(Rect2(x - 4, y - 2, 8, 4), color)
	for fall in strip.player_falls:
		var y := _s_to_y(fall.x)
		_overlay.draw_rect(Rect2(left, y - 1.5, right - left, 3), Color.WHITE)
	# The part the strip shows.
	var top := _s_to_y(clampf(strip.s_top(), 0.0, level.length))
	var bottom := _s_to_y(clampf(strip.s_bottom, 0.0, level.length))
	var view := Rect2(1, top, size.x - 2, maxf(bottom - top, 4.0))
	_overlay.draw_rect(view, Color(EditorTheme.ACTIVE, 0.25))
	_overlay.draw_rect(view, EditorTheme.ACTIVE, false, 3.0)
