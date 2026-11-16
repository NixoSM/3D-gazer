class_name StripView
extends Control
## The editor's main canvas: the tunnel unrolled flat, with everything the
## analysis knows drawn on top.
##
##   | ruler | strip (the wall: s up, angle across) | spin lane | bots |
##
## The strip is the simulation's own coordinate system: `s` metres along
## the tunnel runs up the screen (the way the ball travels), the angle runs
## across with the floor (0°) in the middle and the player's right to the
## right, wrapping at the sides. Holes are drawn by a shader that evaluates
## the game's own hole field, so what you see is exactly what the ball meets.
##
## On top: a time grid, the analysis bots' paths (solid on the ground,
## dotted in the air, a cross where they fall), the jump checks of every
## stretch that must be jumped, and under the mouse the "reach cone" (where
## a rolling ball can steer to from there) and the jump landings.

signal hovered(s: float, angle: float)
## Double-click: play from this point.
signal play_requested(s: float, angle: float)
signal selection_changed
signal status(text: String)
## Scrolled or zoomed.
signal view_changed

enum Tool { SELECT, HOLE, RING }

const RULER_W := 84.0
const SPIN_W := 92.0
const BOT_W := 40.0
const HANDLE := 9.0
const SNAP_S := 0.25
const SNAP_ANGLE := deg_to_rad(2.5)
const MIN_LENGTH := 0.5
const MIN_WIDTH := deg_to_rad(4.0)
const MAX_TWIST := deg_to_rad(30.0)
const STRIP_SHADER := preload("res://shaders/editor_strip.gdshader")

var document: LevelDocument
var analysis: LevelAnalysis
var tuning: BallTuning
var tool := Tool.SELECT:
	set(value):
		tool = value
		_cancel_drag()
		queue_redraw_all()
var snap := true
var selection: Array[HoleData] = []
## Distance at the bottom edge of the strip (m).
var s_bottom := -4.0
## Vertical zoom (pixels per metre along the tunnel).
var px_per_m := 7.0
## Angle shown in the middle of the strip. 0 = the floor at the start.
var angle_middle := 0.0
var show_reach := true
## Turn the strip so the route the bots take stays in the middle, the way
## the game's camera keeps the ball at the bottom of the screen.
var follow_route := true
var show_bots: Array[bool] = [true, true, true]
## Where the ball is during a playtest (s, angle); x = NAN when not playing.
var live_ball := Vector2(NAN, 0.0)
var live_trail := PackedVector2Array()
## Where the player fell in playtests since the last edit (s, angle).
var player_falls := PackedVector2Array()
## Length of the last ring placed, reused by a plain click with the ring tool.
var ring_length := 4.0

var _strip: ColorRect
var _overlay: Control
var _strip_rect := Rect2()
var _spin_rect := Rect2()
var _bots_rect := Rect2()
var _mouse := Vector2(-1.0, -1.0)
var _mouse_inside := false
var _drag := {}
var _palette: LevelPalette
var _void_texture := GradientTexture1D.new()
var _font: Font
var _labels: Array = []


func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = EditorTheme.FONT
	_strip = ColorRect.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = STRIP_SHADER
	_strip.material = material
	add_child(_strip)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.clip_contents = true
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	resized.connect(_layout)
	mouse_exited.connect(func() -> void:
		_mouse_inside = false
		queue_redraw_all())
	_layout()


func level() -> LevelData:
	return document.level


func strip_material() -> ShaderMaterial:
	return _strip.material as ShaderMaterial


## Call after the level (or the document) changed.
func level_changed() -> void:
	var lv := level()
	selection = selection.filter(func(h: HoleData) -> bool: return h in lv.holes)
	_palette = LevelPalette.new(lv.palette)
	_void_texture.gradient = _palette.void_color
	_void_texture.width = 256
	var material := _strip.material as ShaderMaterial
	material.set_shader_parameter("hole_data", TunnelView.hole_texture(lv))
	material.set_shader_parameter("wall_gradient", _palette.wall_texture)
	material.set_shader_parameter("void_gradient", _void_texture)
	material.set_shader_parameter("level_length", lv.length)
	material.set_shader_parameter("tunnel_radius", lv.tunnel_radius)
	_update_view_uniforms()
	queue_redraw_all()


func queue_redraw_all() -> void:
	queue_redraw()
	if _overlay:
		_overlay.queue_redraw()


# --- View --------------------------------------------------------------------

func visible_metres() -> float:
	return size.y / px_per_m


func s_top() -> float:
	return s_bottom + visible_metres()


## Scrolls so that distance s sits a third of the way up.
func center_on(s: float) -> void:
	s_bottom = s - visible_metres() * 0.33
	_clamp_view()


## A comfortable default zoom: about six seconds of tunnel on screen.
func reset_zoom() -> void:
	px_per_m = clampf(size.y / (level().base_speed * 6.0), 0.5, 60.0)
	_clamp_view()


func _clamp_view() -> void:
	var lv := level()
	s_bottom = clampf(s_bottom, -visible_metres() * 0.5, lv.length - visible_metres() * 0.5)
	angle_middle = TunnelMath.wrap_angle(angle_middle)
	_update_view_uniforms()
	queue_redraw_all()
	view_changed.emit()


func _layout() -> void:
	var strip_w := maxf(size.x - RULER_W - SPIN_W - BOT_W, 80.0)
	_strip_rect = Rect2(RULER_W, 0.0, strip_w, size.y)
	_spin_rect = Rect2(RULER_W + strip_w, 0.0, SPIN_W, size.y)
	_bots_rect = Rect2(RULER_W + strip_w + SPIN_W, 0.0, BOT_W, size.y)
	if _strip:
		_strip.position = _strip_rect.position
		_strip.size = _strip_rect.size
		_overlay.position = _strip_rect.position
		_overlay.size = _strip_rect.size
		_update_view_uniforms()


func _update_view_uniforms() -> void:
	if document == null or _strip == null:
		return
	var lv := level()
	var material := _strip.material as ShaderMaterial
	material.set_shader_parameter("s_bottom", s_bottom)
	material.set_shader_parameter("s_top", s_top())
	material.set_shader_parameter("angle_middle", angle_middle)
	var first := lv.first_hole_index_near(s_bottom - 4.0)
	var last := first
	while last < lv.holes.size() and lv.holes[last].s_start <= s_top() + 4.0:
		last += 1
	material.set_shader_parameter("hole_first", first)
	material.set_shader_parameter("hole_count", last - first)


## Call every frame: eases the view round to the route (or the live ball).
func update_follow(delta: float) -> void:
	if not follow_route or not _drag.is_empty() or analysis == null:
		return
	var target := NAN
	if not is_nan(live_ball.x):
		target = live_ball.y
	else:
		var s := s_bottom + visible_metres() * 0.45
		for i in [1, 0, 2]:
			target = analysis.bots[i].angle_at(s)
			if not is_nan(target):
				break
	if is_nan(target):
		return
	var step := TunnelMath.angle_difference(target, angle_middle) * (1.0 - exp(-6.0 * delta))
	if absf(step) < 0.0005:
		return
	angle_middle = TunnelMath.wrap_angle(angle_middle + step)
	_update_view_uniforms()
	queue_redraw_all()


# --- Coordinates (all in this control's space) ---------------------------------

func s_to_y(s: float) -> float:
	return size.y - (s - s_bottom) * px_per_m


func y_to_s(y: float) -> float:
	return s_bottom + (size.y - y) / px_per_m


## Angle relative to the middle of the strip, in (-PI, PI].
func relative_angle(angle: float) -> float:
	return TunnelMath.wrap_angle(angle - angle_middle)


func angle_to_x(angle: float) -> float:
	return _strip_rect.position.x + (relative_angle(angle) / TAU + 0.5) * _strip_rect.size.x


## Like angle_to_x, but without wrapping: `relative` may run past ±PI.
func relative_to_x(relative: float) -> float:
	return _strip_rect.position.x + (relative / TAU + 0.5) * _strip_rect.size.x


func x_to_angle(x: float) -> float:
	return angle_middle + ((x - _strip_rect.position.x) / _strip_rect.size.x - 0.5) * TAU


func to_screen(s: float, angle: float) -> Vector2:
	return Vector2(angle_to_x(angle), s_to_y(s))


func _snap_s(s: float, force: bool = false) -> float:
	return snappedf(s, SNAP_S) if (snap or force) and not Input.is_key_pressed(KEY_ALT) else s


func _snap_angle(angle: float) -> float:
	return snappedf(angle, SNAP_ANGLE) if snap and not Input.is_key_pressed(KEY_ALT) else angle


# --- Hit testing -------------------------------------------------------------

## The hole under a screen point (its own outline, ignoring blends), or null.
func hole_at_point(point: Vector2) -> HoleData:
	if not _strip_rect.has_point(point):
		return null
	var s := y_to_s(point.y)
	var angle := x_to_angle(point.x)
	var lv := level()
	var best: HoleData = null
	var best_area := INF
	for hole in lv.holes_between(s - 0.01, s + 0.01):
		if hole.signed_distance(s, angle, lv.tunnel_radius) < 0.0:
			var area := hole.length * hole.angle_width
			if area < best_area:
				best_area = area
				best = hole
	return best


## Handle positions of a hole: bottom, top, left, right, twist.
func _handles(hole: HoleData) -> Dictionary:
	var mid := hole.s_start + hole.length * 0.5
	var handles := {
		"bottom": to_screen(hole.s_start, hole.center_at(hole.s_start)),
		"top": to_screen(hole.s_end(), hole.center_at(hole.s_end())),
	}
	if not hole.is_ring():
		handles["left"] = to_screen(mid, hole.center_at(mid) - hole.angle_width * 0.5)
		handles["right"] = to_screen(mid, hole.center_at(mid) + hole.angle_width * 0.5)
		handles["twist"] = handles["top"] + Vector2(0.0, -24.0)
	return handles


func _handle_at(point: Vector2) -> String:
	if selection.size() != 1:
		return ""
	var handles := _handles(selection[0])
	for name in ["twist", "left", "right", "bottom", "top"]:
		if handles.has(name) and (handles[name] as Vector2).distance_to(point) <= HANDLE + 3.0:
			return name
	return ""


func _spin_key_at(point: Vector2) -> int:
	var lv := level()
	for i in lv.spin.size():
		var key := lv.spin[i]
		if Vector2(_rate_to_x(key.rate), s_to_y(key.s)).distance_to(point) <= HANDLE + 2.0:
			return i
	return -1


func _spin_range() -> float:
	var top := 60.0
	for key in level().spin:
		top = maxf(top, ceilf((absf(key.rate) + 5.0) / 30.0) * 30.0)
	return top


func _rate_to_x(rate: float) -> float:
	return _spin_rect.position.x + 10.0 + (rate / _spin_range() * 0.5 + 0.5) * (_spin_rect.size.x - 20.0)


func _x_to_rate(x: float) -> float:
	return ((x - _spin_rect.position.x - 10.0) / (_spin_rect.size.x - 20.0) - 0.5) * 2.0 * _spin_range()


# --- Input -------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
		_mouse_inside = true
		if not _drag.is_empty():
			_drag_to(event.position)
		elif _strip_rect.has_point(event.position):
			hovered.emit(y_to_s(event.position.y), x_to_angle(event.position.x))
		_update_cursor_shape()
		queue_redraw_all()
	elif event is InputEventMouseButton:
		_mouse_button(event)


func _mouse_button(event: InputEventMouseButton) -> void:
	var command := event.is_command_or_control_pressed()
	if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var direction := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
		if command:
			var anchor := y_to_s(event.position.y)
			px_per_m = clampf(px_per_m * (1.15 if direction > 0.0 else 1.0 / 1.15), 0.5, 60.0)
			s_bottom = anchor - (size.y - event.position.y) / px_per_m
		elif event.shift_pressed:
			angle_middle += direction * deg_to_rad(15.0)
			follow_route = false
			view_changed.emit()
		else:
			s_bottom += direction * visible_metres() * 0.08
		_clamp_view()
		accept_event()
		return
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			_drag = {"mode": "pan", "from": event.position, "s_bottom": s_bottom, "angle": angle_middle}
		else:
			_drag = {}
		accept_event()
		return
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_right_click(event.position)
		accept_event()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	grab_focus()
	if not event.pressed:
		_finish_drag(event.position)
		return
	if event.double_click and _strip_rect.has_point(event.position):
		_cancel_drag()
		play_requested.emit(maxf(y_to_s(event.position.y), 0.0), x_to_angle(event.position.x))
		return
	if _spin_rect.has_point(event.position):
		_press_spin(event.position)
	elif _strip_rect.has_point(event.position):
		_press_strip(event.position, event.shift_pressed, command)


func _right_click(point: Vector2) -> void:
	if _spin_rect.has_point(point):
		var key := _spin_key_at(point)
		if key >= 0:
			document.begin("Delete spin key")
			var s := level().spin[key].s
			level().spin.remove_at(key)
			document.changed_from(s)
			status.emit("Spin key removed.")
		return
	var hole := hole_at_point(point)
	if hole:
		if not hole in selection:
			selection = [hole]
		delete_selection()


func _press_spin(point: Vector2) -> void:
	var key := _spin_key_at(point)
	var lv := level()
	if key < 0:
		document.begin("Add spin key")
		var new_key := SpinKey.new(clampf(_snap_s(y_to_s(point.y), true), 0.0, lv.length), snappedf(_x_to_rate(point.x), 5.0))
		lv.spin.append(new_key)
		document.changed_from(new_key.s)
		_drag = {"mode": "spin", "key": new_key, "begun": true}
		status.emit("Spin key added. Drag to adjust, right-click to remove.")
	else:
		_drag = {"mode": "spin", "key": lv.spin[key], "begun": false}


func _press_strip(point: Vector2, shift: bool, command: bool) -> void:
	var s := y_to_s(point.y)
	var angle := x_to_angle(point.x)
	match tool:
		Tool.HOLE:
			_drag = {"mode": "draw", "s": _snap_s(s), "angle": _snap_angle(angle), "from": point}
		Tool.RING:
			_drag = {"mode": "ring", "s": _snap_s(s), "from": point}
		Tool.SELECT:
			var handle := _handle_at(point)
			if not handle.is_empty():
				_start_handle_drag(handle, point)
				return
			var hole := hole_at_point(point)
			if hole == null:
				if not shift:
					selection = []
					selection_changed.emit()
				_drag = {"mode": "box", "from": point, "add": shift}
				return
			if shift:
				if hole in selection:
					selection.erase(hole)
				else:
					selection.append(hole)
				selection_changed.emit()
				return
			if not hole in selection:
				selection = [hole]
				selection_changed.emit()
			_start_move(point, command)


func _start_move(point: Vector2, duplicate: bool) -> void:
	var originals := []
	for hole in selection:
		originals.append(Vector2(hole.s_start, hole.angle_center))
	_drag = {"mode": "move", "from": point, "s": y_to_s(point.y), "angle": x_to_angle(point.x),
		"originals": originals, "begun": false, "duplicate": duplicate}


func _start_handle_drag(handle: String, point: Vector2) -> void:
	var hole := selection[0]
	_drag = {"mode": handle, "from": point, "begun": false, "hole": hole,
		"s_start": hole.s_start, "length": hole.length, "center": hole.angle_center,
		"width": hole.angle_width, "twist": hole.twist}


func _begin_once(label: String) -> void:
	if not _drag.get("begun", false):
		document.begin(label)
		_drag["begun"] = true
		if _drag.get("duplicate", false):
			# Ctrl/Cmd-drag: leave copies behind and move the originals' twins.
			var copies: Array[HoleData] = []
			for hole in selection:
				var copy := HoleData.new(hole.s_start, hole.length, hole.angle_center, hole.angle_width, hole.twist)
				level().holes.append(copy)
				copies.append(copy)
			selection = copies
			selection_changed.emit()


func _drag_to(point: Vector2) -> void:
	var lv := level()
	var s := y_to_s(point.y)
	var angle := x_to_angle(point.x)
	match _drag["mode"]:
		"pan":
			var from: Vector2 = _drag["from"]
			s_bottom = _drag["s_bottom"] + (point.y - from.y) / px_per_m
			angle_middle = _drag["angle"] - (point.x - from.x) / _strip_rect.size.x * TAU
			if absf(point.x - from.x) > 4.0:
				follow_route = false
			_clamp_view()
		"spin":
			if not _drag["begun"]:
				document.begin("Move spin key")
				_drag["begun"] = true
			var key: SpinKey = _drag["key"]
			var old_s := key.s
			key.s = clampf(_snap_s(s, true), 0.0, lv.length)
			key.rate = clampf(snappedf(_x_to_rate(point.x), 1.0 if Input.is_key_pressed(KEY_ALT) else 5.0), -180.0, 180.0)
			document.changed_from(minf(old_s, key.s) - 30.0)
			status.emit("Spin %+.0f °/s at %.1f m" % [key.rate, key.s])
		"move":
			var from: Vector2 = _drag["from"]
			if not _drag["begun"] and from.distance_to(point) < 4.0:
				return
			_begin_once("Duplicate holes" if _drag["duplicate"] else "Move holes")
			var ds := _snap_s(s - float(_drag["s"]))
			var da := _snap_angle(TunnelMath.angle_difference(angle, _drag["angle"]))
			var originals: Array = _drag["originals"]
			var lowest := INF
			for i in selection.size():
				var hole := selection[i]
				var original: Vector2 = originals[i]
				lowest = minf(lowest, minf(hole.s_start, original.x + ds))
				hole.s_start = clampf(original.x + ds, 0.0, lv.length - hole.length)
				hole.angle_center = TunnelMath.wrap_angle_positive(original.y + da)
			document.changed_from(lowest)
			status.emit("Moved %+.2f m, %+.1f°" % [ds, rad_to_deg(da)])
		"bottom", "top", "left", "right", "twist":
			_drag_handle(point, s, angle)
		_:
			pass
	queue_redraw_all()


func _drag_handle(point: Vector2, s: float, angle: float) -> void:
	var from: Vector2 = _drag["from"]
	if not _drag["begun"] and from.distance_to(point) < 3.0:
		return
	_begin_once("Resize hole")
	var lv := level()
	var hole: HoleData = _drag["hole"]
	var start: float = _drag["s_start"]
	var length: float = _drag["length"]
	var center: float = _drag["center"]
	var width: float = _drag["width"]
	var twist: float = _drag["twist"]
	match _drag["mode"]:
		"bottom":
			var new_start := clampf(_snap_s(s), 0.0, start + length - MIN_LENGTH)
			hole.s_start = new_start
			hole.length = start + length - new_start
			# Keep the slanted band where it was: move its reference centre along.
			hole.angle_center = TunnelMath.wrap_angle_positive(center + twist * (new_start - start))
		"top":
			hole.length = clampf(_snap_s(s) - start, MIN_LENGTH, lv.length - start)
		"left", "right":
			var mid_center := center + twist * length * 0.5
			var edge := TunnelMath.angle_difference(_snap_angle(angle), mid_center)
			var left := -width * 0.5
			var right := width * 0.5
			if _drag["mode"] == "right":
				right = clampf(edge if edge > left else edge + TAU, left + MIN_WIDTH, left + TAU)
			else:
				left = clampf(edge if edge < right else edge - TAU, right - TAU, right - MIN_WIDTH)
			hole.angle_width = minf(right - left, TAU)
			var new_mid := mid_center + (left + right) * 0.5
			hole.angle_center = TunnelMath.wrap_angle_positive(new_mid - twist * length * 0.5)
		"twist":
			var offset := TunnelMath.angle_difference(angle, center)
			var new_twist := clampf(offset / length, -MAX_TWIST, MAX_TWIST)
			if snap and not Input.is_key_pressed(KEY_ALT):
				new_twist = snappedf(new_twist, deg_to_rad(0.5))
			hole.twist = new_twist
	document.changed_from(minf(start, hole.s_start))
	status.emit(describe_hole(hole))


func _finish_drag(point: Vector2) -> void:
	if _drag.is_empty():
		return
	var lv := level()
	match _drag["mode"]:
		"draw":
			var s0: float = _drag["s"]
			var s1 := _snap_s(y_to_s(point.y))
			var a0: float = _drag["angle"]
			# Unwrapped: dragging across the seam keeps going the same way.
			var da := _snap_angle((point.x - (_drag["from"] as Vector2).x) / _strip_rect.size.x * TAU)
			var span := clampf(absf(da), 0.0, TAU)
			if absf(s1 - s0) >= MIN_LENGTH and span >= MIN_WIDTH:
				var start := clampf(minf(s0, s1), 0.0, lv.length - MIN_LENGTH)
				var length := minf(absf(s1 - s0), lv.length - start)
				document.begin("Add hole")
				var hole := HoleData.new(start, length, a0 + da * 0.5, span)
				lv.holes.append(hole)
				document.changed_from(start)
				selection = [hole]
				selection_changed.emit()
				status.emit("Added " + describe_hole(hole))
			else:
				status.emit("Drag a rectangle to draw a hole.")
		"ring":
			var s0: float = _drag["s"]
			var s1 := _snap_s(y_to_s(point.y))
			var length := absf(s1 - s0)
			if length < MIN_LENGTH:
				length = ring_length
			else:
				ring_length = length
			var start := clampf(minf(s0, s1), 0.0, lv.length - length)
			document.begin("Add ring")
			var ring := HoleData.new(start, length, 0.0, TAU)
			lv.holes.append(ring)
			document.changed_from(start)
			selection = [ring]
			selection_changed.emit()
			status.emit("Added " + describe_hole(ring))
		"box":
			var rect := Rect2(_drag["from"], Vector2.ZERO).expand(point)
			var add: bool = _drag["add"]
			if not add:
				selection = []
			for hole in lv.holes_between(y_to_s(rect.end.y), y_to_s(rect.position.y)):
				var mid := hole.s_start + hole.length * 0.5
				if rect.has_point(to_screen(mid, hole.center_at(mid))) and not hole in selection:
					selection.append(hole)
			selection_changed.emit()
		_:
			if _drag.get("begun", false):
				selection_changed.emit()
	_drag = {}
	queue_redraw_all()


func _cancel_drag() -> void:
	_drag = {}


func _update_cursor_shape() -> void:
	if _spin_rect.has_point(_mouse):
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _spin_key_at(_mouse) >= 0 else Control.CURSOR_CROSS
		return
	if not _strip_rect.has_point(_mouse):
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		return
	if tool != Tool.SELECT:
		mouse_default_cursor_shape = Control.CURSOR_CROSS
		return
	match _handle_at(_mouse):
		"bottom", "top":
			mouse_default_cursor_shape = Control.CURSOR_VSIZE
		"left", "right":
			mouse_default_cursor_shape = Control.CURSOR_HSIZE
		"twist":
			mouse_default_cursor_shape = Control.CURSOR_DRAG
		_:
			mouse_default_cursor_shape = Control.CURSOR_MOVE if hole_at_point(_mouse) else Control.CURSOR_ARROW


# --- Edits called by the editor (keyboard shortcuts, inspector) --------------

func delete_selection() -> void:
	if selection.is_empty():
		return
	document.begin("Delete holes")
	var lowest := INF
	for hole in selection:
		lowest = minf(lowest, hole.s_start)
		level().holes.erase(hole)
	var count := selection.size()
	selection = []
	document.changed_from(lowest)
	selection_changed.emit()
	status.emit("Deleted %d hole%s." % [count, "" if count == 1 else "s"])


## Copies the selection to just after itself: the quickest way to build a
## run of repeated obstacles. `gap` metres of floor between copies.
func repeat_selection(gap: float = -1.0) -> void:
	if selection.is_empty():
		return
	var lv := level()
	var first := INF
	var last := -INF
	for hole in selection:
		first = minf(first, hole.s_start)
		last = maxf(last, hole.s_end())
	if gap < 0.0:
		gap = maxf(lv.speed_at(last) * 0.6, 4.0)
	var shift := last - first + gap
	if last + shift > lv.length:
		status.emit("No room for another copy before the finish.")
		return
	document.begin("Repeat holes")
	var copies: Array[HoleData] = []
	for hole in selection:
		var copy := HoleData.new(hole.s_start + shift, hole.length, hole.angle_center, hole.angle_width, hole.twist)
		lv.holes.append(copy)
		copies.append(copy)
	selection = copies
	document.changed_from(first + shift)
	selection_changed.emit()
	status.emit("Repeated %d hole%s %.1f m further on (%.2f s of floor between)." % [copies.size(), "" if copies.size() == 1 else "s", shift, gap / lv.speed_at(last)])


## Mirrors the selection left-right around the floor line (angle -> -angle).
func mirror_selection() -> void:
	if selection.is_empty():
		return
	document.begin("Mirror holes")
	var lowest := INF
	for hole in selection:
		lowest = minf(lowest, hole.s_start)
		hole.angle_center = TunnelMath.wrap_angle_positive(-hole.angle_center)
		hole.twist = -hole.twist
	document.changed_from(lowest)
	selection_changed.emit()


func nudge_selection(ds: float, da: float) -> void:
	if selection.is_empty():
		return
	document.begin("Nudge holes")
	var lowest := INF
	for hole in selection:
		lowest = minf(lowest, hole.s_start + minf(ds, 0.0))
		hole.s_start = clampf(hole.s_start + ds, 0.0, level().length - hole.length)
		hole.angle_center = TunnelMath.wrap_angle_positive(hole.angle_center + da)
	document.changed_from(lowest)
	selection_changed.emit()


func select_all_visible() -> void:
	selection = level().holes_between(s_bottom, s_top())
	selection_changed.emit()
	queue_redraw_all()


static func describe_hole(hole: HoleData) -> String:
	if hole.is_ring():
		return "ring at %.1f m, %.1f m long" % [hole.s_start, hole.length]
	var text := "hole at %.1f m, %.1f m long, %.0f° wide at %.0f°" % [hole.s_start, hole.length,
		rad_to_deg(hole.angle_width), rad_to_deg(TunnelMath.wrap_angle(hole.angle_center))]
	if hole.twist != 0.0:
		text += ", twisting %+.1f °/m" % rad_to_deg(hole.twist)
	return text


# --- Drawing: ruler, spin lane, bot lane ---------------------------------------

func _draw() -> void:
	if document == null:
		return
	var lv := level()
	draw_rect(Rect2(Vector2.ZERO, size), EditorTheme.PAPER)
	_draw_ruler(lv)
	_draw_spin_lane(lv)
	_draw_bot_lane(lv)
	# Thick frame around the strip.
	draw_rect(_strip_rect.grow(1.5), EditorTheme.INK, false, 3.0)


func _draw_ruler(lv: LevelData) -> void:
	var x1 := _strip_rect.position.x - 2.0
	draw_rect(Rect2(0, 0, RULER_W, size.y), EditorTheme.PAPER_DARK)
	# One tick per second of play; a label every second (or less often when
	# zoomed out), and the speed every five seconds.
	var t0 := floorf(lv.time_at(maxf(s_bottom, 0.0)))
	var t1 := ceilf(lv.time_at(clampf(s_top(), 0.0, lv.length)))
	var px_per_second := lv.speed_at(maxf(s_bottom, 0.0)) * px_per_m
	var label_every := 1 if px_per_second > 34.0 else (5 if px_per_second > 7.0 else 10)
	var t := t0
	while t <= t1:
		var s := _s_at_time(lv, t)
		var y := s_to_y(s)
		var major := int(t) % 5 == 0
		draw_line(Vector2(x1 - (16.0 if major else 8.0), y), Vector2(x1, y), EditorTheme.INK, 2.0 if major else 1.0)
		if int(t) % label_every == 0:
			_text(Vector2(8.0, y + 6.0), "%d s" % int(t), 17 if major else 14, EditorTheme.INK)
			if major:
				_text(Vector2(8.0, y + 22.0), "%.0f m" % s, 12, EditorTheme.MUTED)
				_text(Vector2(8.0, y + 36.0), "%.1f m/s" % lv.speed_at(s), 12, EditorTheme.MUTED)
		t += 1.0
	for mark in [[0.0, "START"], [lv.length, "FINISH"]]:
		var y := s_to_y(mark[0])
		if y > -20.0 and y < size.y + 20.0:
			draw_line(Vector2(0, y), Vector2(x1, y), EditorTheme.HOT, 3.0)
			_text(Vector2(8.0, y - 6.0), mark[1], 15, EditorTheme.HOT)


func _s_at_time(lv: LevelData, t: float) -> float:
	# time_at is monotonic: invert it by bisection (cheap, ~30 steps).
	var lo := 0.0
	var hi := lv.length
	if t >= lv.duration():
		return lv.length
	for i in 30:
		var mid := (lo + hi) * 0.5
		if lv.time_at(mid) < t:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


func _draw_spin_lane(lv: LevelData) -> void:
	var rect := _spin_rect
	draw_rect(rect, Color("fff9ec"))
	var zero := _rate_to_x(0.0)
	var range_top := _spin_range()
	for rate in [-range_top, -range_top * 0.5, range_top * 0.5, range_top]:
		draw_line(Vector2(_rate_to_x(rate), 0), Vector2(_rate_to_x(rate), size.y), Color(EditorTheme.INK, 0.08), 1.0)
	draw_line(Vector2(zero, 0), Vector2(zero, size.y), Color(EditorTheme.INK, 0.35), 2.0)
	# Fill between zero and the curve: right-hand spin warm, left-hand cool.
	var step := maxf(2.0 / px_per_m, 0.25)
	var s := maxf(s_bottom, 0.0)
	var curve := PackedVector2Array()
	while s <= minf(s_top(), lv.length) + step:
		var rate := lv.spin_at(minf(s, lv.length))
		var point := Vector2(_rate_to_x(rate), s_to_y(s))
		if not curve.is_empty():
			var previous := curve[curve.size() - 1]
			var color := Color(EditorTheme.HOT, 0.35) if rate > 0.0 else Color(EditorTheme.BOT_COLORS[0], 0.35)
			draw_primitive(PackedVector2Array([Vector2(zero, previous.y), previous, point, Vector2(zero, point.y)]), PackedColorArray([color, color, color, color]), PackedVector2Array())
		curve.append(point)
		s += step
	if curve.size() >= 2:
		draw_polyline(curve, EditorTheme.INK, 3.5, true)
	for key in lv.spin:
		var p := Vector2(_rate_to_x(key.rate), s_to_y(key.s))
		draw_circle(p, HANDLE, EditorTheme.INK)
		draw_circle(p, HANDLE - 3.0, EditorTheme.ACTIVE)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 46)), EditorTheme.PAPER)
	_text(rect.position + Vector2(10, 20), "SPIN", 16, EditorTheme.INK)
	_text(rect.position + Vector2(10, 38), "±%d °/s" % int(range_top), 12, EditorTheme.MUTED)
	if _mouse_inside and rect.has_point(_mouse):
		var hover_s := clampf(y_to_s(_mouse.y), 0.0, lv.length)
		_pill(Vector2(rect.position.x + 6.0, _mouse.y - 12.0), "%+.0f °/s" % lv.spin_at(hover_s), EditorTheme.ACTIVE)


func _draw_bot_lane(lv: LevelData) -> void:
	var rect := _bots_rect
	draw_rect(rect, EditorTheme.PAPER_DARK)
	if analysis == null:
		return
	var column := (rect.size.x - 8.0) / analysis.bots.size()
	for i in analysis.bots.size():
		var trace := analysis.bots[i]
		var x := rect.position.x + 3.0 + column * i
		var top := s_to_y(trace.end_s)
		var bottom := s_to_y(0.0)
		var color: Color = EditorTheme.BOT_COLORS[i]
		if not show_bots[i]:
			color = Color(color, 0.3)
		draw_rect(Rect2(x + 1.0, top, column - 2.0, bottom - top), color)
		if trace.outcome == "fell":
			_cross(Vector2(x + column * 0.5, top), 6.0, EditorTheme.INK, 3.0)
		elif trace.outcome == "running":
			draw_rect(Rect2(x + 1.0, top - 3.0, column - 2.0, 3.0), EditorTheme.INK)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, 46)), EditorTheme.PAPER)
	_text(rect.position + Vector2(4, 20), "BOTS", 14, EditorTheme.INK)


# --- Drawing: the strip's overlays ---------------------------------------------

func _draw_overlay() -> void:
	if document == null:
		return
	_overlay.draw_set_transform(-_strip_rect.position)
	var lv := level()
	_draw_time_grid(lv)
	_labels.clear()
	if analysis and analysis.report:
		_draw_report(lv, analysis.report)
	if analysis:
		for i in analysis.bots.size():
			if show_bots[i]:
				_draw_bot(analysis.bots[i], EditorTheme.BOT_COLORS[i])
	for label in _labels:
		_pill(label[0], label[1], label[2])
	_draw_selection()
	_draw_drag_preview()
	_draw_live()
	var playing := not is_nan(live_ball.x)
	if not playing and _mouse_inside and _strip_rect.has_point(_mouse) and (_drag.is_empty() or _drag["mode"] == "pan"):
		_draw_cursor(lv)


func _draw_time_grid(lv: LevelData) -> void:
	var t0 := floorf(lv.time_at(maxf(s_bottom, 0.0)))
	var t1 := ceilf(lv.time_at(clampf(s_top(), 0.0, lv.length)))
	var t := t0
	var x0 := _strip_rect.position.x
	var x1 := _strip_rect.end.x
	while t <= t1:
		var y := s_to_y(_s_at_time(lv, t))
		var major := int(t) % 5 == 0
		_line(Vector2(x0, y), Vector2(x1, y), Color(EditorTheme.INK, 0.28 if major else 0.12), 2.0 if major else 1.0)
		t += 1.0
	# The floor line (0°) and the seam (±180°).
	var floor_x := angle_to_x(0.0)
	_dashed(Vector2(floor_x, 0), Vector2(floor_x, size.y), Color(EditorTheme.INK, 0.25), 1.5, 6.0)


func _draw_report(lv: LevelData, report: LevelValidator.Report) -> void:
	var x := _strip_rect.position.x
	for gap in report.gaps:
		if gap.s_end < s_bottom or gap.s_start > s_top():
			continue
		var y0 := s_to_y(gap.s_start)
		var y1 := s_to_y(gap.s_end)
		var color := EditorTheme.GOOD
		var text := "jump %.1f m · %.2f s" % [gap.length(), gap.length() / lv.speed_at(gap.s_start)]
		if gap.too_long():
			color = EditorTheme.BAD
			text = "TOO LONG %.1f m (max %.1f)" % [gap.length(), gap.jumpable]
		elif gap.too_close():
			color = EditorTheme.WARN
			text = "no run-up: %.1f m of floor" % gap.run_up
		elif gap.jumpable < INF and gap.length() > gap.jumpable * 0.8:
			color = EditorTheme.WARN
			text += " · near max"
		# A bracket hugging the left edge; its label is drawn after the bots.
		_overlay.draw_rect(Rect2(x + 2.0, y1, 7.0, y0 - y1), color)
		_overlay.draw_rect(Rect2(x + 2.0, y1, 7.0, y0 - y1), EditorTheme.INK, false, 2.0)
		_labels.append([Vector2(x + 14.0, (y0 + y1) * 0.5 - 11.0), text, color])
	# Narrow floor: stretches where the widest free arc is under TIGHT_WIDTH.
	var count := report.free_width.size()
	if count == 0:
		return
	var first := clampi(int(floor(maxf(s_bottom, 0.0) / LevelValidator.SAMPLE_STEP)), 0, count - 1)
	var last := clampi(int(ceil(s_top() / LevelValidator.SAMPLE_STEP)), 0, count - 1)
	var ball := tuning.ball_radius * 2.0
	var run_start := -1
	var narrowest := INF
	for i in range(first, last + 2):
		var width := report.free_width[i] if i <= last else INF
		var tight := width < LevelAnalysis.TIGHT_WIDTH and width >= ball
		if tight and run_start < 0:
			run_start = i
			narrowest = width
		elif tight:
			narrowest = minf(narrowest, width)
		elif run_start >= 0:
			var y0 := s_to_y(run_start * LevelValidator.SAMPLE_STEP)
			var y1 := s_to_y(i * LevelValidator.SAMPLE_STEP)
			var right := _strip_rect.end.x
			_overlay.draw_rect(Rect2(right - 9.0, y1, 7.0, y0 - y1), EditorTheme.WARN)
			_overlay.draw_rect(Rect2(right - 9.0, y1, 7.0, y0 - y1), EditorTheme.INK, false, 2.0)
			if y0 - y1 > 14.0:
				_labels.append([Vector2(right - 120.0, (y0 + y1) * 0.5 - 11.0), "narrow %.1f m" % narrowest, EditorTheme.WARN])
			run_start = -1


func _draw_bot(trace: LevelAnalysis.BotTrace, color: Color) -> void:
	var points := trace.points
	if points.is_empty():
		return
	var start := _first_point_index(points, s_bottom - 2.0)
	var previous := Vector2.INF
	var previous_relative := 0.0
	var i := start
	while i < points.size():
		var p := points[i]
		if p.x > s_top() + 2.0:
			break
		var relative := relative_angle(p.y)
		var point := Vector2(relative_to_x(relative), s_to_y(p.x))
		if previous != Vector2.INF and absf(relative - previous_relative) < PI:
			if p.z > 0.5:
				_dashed(previous, point, color, 2.5, 5.0)
			else:
				_line(previous, point, EditorTheme.INK, 6.0)
				_line(previous, point, color, 3.5)
		previous = point
		previous_relative = relative
		i += 1
	for mark in trace.marks:
		if mark.x < s_bottom or mark.x > s_top():
			continue
		var p := to_screen(mark.x, mark.y)
		match int(mark.z):
			LevelAnalysis.Mark.JUMP:
				_overlay.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -8), p + Vector2(6, 3), p + Vector2(-6, 3)]), color)
			LevelAnalysis.Mark.ECHO:
				_overlay.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -7), p + Vector2(6, 0), p + Vector2(0, 7), p + Vector2(-6, 0)]), color)
				_overlay.draw_polyline(PackedVector2Array([p + Vector2(0, -7), p + Vector2(6, 0), p + Vector2(0, 7), p + Vector2(-6, 0), p + Vector2(0, -7)]), EditorTheme.INK, 1.5)
			LevelAnalysis.Mark.NEAR_MISS:
				_overlay.draw_circle(p, 4.0, EditorTheme.WARN)
	if trace.outcome == "fell" and trace.end_s >= s_bottom - 5.0 and trace.end_s <= s_top() + 5.0:
		var p := to_screen(trace.end_s, trace.end_angle)
		_cross(p, 11.0, EditorTheme.INK, 7.0, true)
		_cross(p, 11.0, color, 4.0, true)


func _first_point_index(points: PackedVector3Array, s: float) -> int:
	var lo := 0
	var hi := points.size()
	while lo < hi:
		var mid := (lo + hi) >> 1
		if points[mid].x < s:
			lo = mid + 1
		else:
			hi = mid
	return maxi(lo - 1, 0)


func _draw_selection() -> void:
	for hole in selection:
		if hole.s_end() < s_bottom or hole.s_start > s_top():
			continue
		_draw_hole_outline(hole, EditorTheme.ACTIVE, 3.0)
	if selection.size() == 1 and tool == Tool.SELECT:
		var hole := selection[0]
		var handles := _handles(hole)
		if handles.has("twist"):
			_line(handles["top"], handles["twist"], EditorTheme.INK, 2.0)
		for name in handles:
			var p: Vector2 = handles[name]
			if name == "twist":
				_overlay.draw_circle(p, HANDLE, EditorTheme.INK)
				_overlay.draw_circle(p, HANDLE - 3.0, EditorTheme.HOT)
			else:
				_overlay.draw_rect(Rect2(p - Vector2(HANDLE, HANDLE) * 0.8, Vector2(HANDLE, HANDLE) * 1.6), EditorTheme.INK)
				_overlay.draw_rect(Rect2(p - Vector2(HANDLE, HANDLE) * 0.5, Vector2(HANDLE, HANDLE)), EditorTheme.ACTIVE)


## Outline of a hole's (un-rounded) shape, drawn across the seam if needed.
func _draw_hole_outline(hole: HoleData, color: Color, width: float) -> void:
	var y0 := s_to_y(hole.s_start)
	var y1 := s_to_y(hole.s_end())
	if hole.is_ring():
		var rect := Rect2(_strip_rect.position.x, y1, _strip_rect.size.x, y0 - y1)
		_overlay.draw_rect(rect, EditorTheme.INK, false, width + 3.0)
		_overlay.draw_rect(rect, color, false, width)
		return
	var c0 := relative_angle(hole.angle_center)
	var c1 := c0 + hole.twist * hole.length
	var half := hole.angle_width * 0.5
	for k in [-1, 0, 1]:
		var shift: float = k * TAU
		var poly := PackedVector2Array([
			Vector2(relative_to_x(c0 - half + shift), y0), Vector2(relative_to_x(c0 + half + shift), y0),
			Vector2(relative_to_x(c1 + half + shift), y1), Vector2(relative_to_x(c1 - half + shift), y1)])
		poly.append(poly[0])
		_overlay.draw_polyline(poly, EditorTheme.INK, width + 3.0)
		_overlay.draw_polyline(poly, color, width)


func _draw_drag_preview() -> void:
	if _drag.is_empty():
		return
	match _drag["mode"]:
		"draw":
			var from: Vector2 = _drag["from"]
			var rect := Rect2(from, Vector2.ZERO).expand(_mouse)
			_overlay.draw_rect(rect, Color(EditorTheme.INK, 0.35))
			_overlay.draw_rect(rect, EditorTheme.ACTIVE, false, 3.0)
			var length := absf(y_to_s(_mouse.y) - y_to_s(from.y))
			var width := absf(_mouse.x - from.x) / _strip_rect.size.x * 360.0
			_pill(rect.end + Vector2(8, -10), "%.1f m × %.0f°" % [length, width], EditorTheme.ACTIVE)
		"ring":
			var from: Vector2 = _drag["from"]
			var y0 := from.y
			var y1 := _mouse.y if absf(_mouse.y - from.y) > MIN_LENGTH * px_per_m else from.y - ring_length * px_per_m
			var rect := Rect2(_strip_rect.position.x, minf(y0, y1), _strip_rect.size.x, absf(y1 - y0))
			_overlay.draw_rect(rect, Color(EditorTheme.INK, 0.35))
			_overlay.draw_rect(rect, EditorTheme.ACTIVE, false, 3.0)
			_pill(Vector2(_mouse.x + 10, minf(y0, y1) - 26), "ring %.1f m" % (absf(y1 - y0) / px_per_m), EditorTheme.ACTIVE)
		"box":
			var rect := Rect2(_drag["from"], Vector2.ZERO).expand(_mouse)
			_overlay.draw_rect(rect, Color(EditorTheme.ACTIVE, 0.15))
			_overlay.draw_rect(rect, EditorTheme.INK, false, 2.0)


func _draw_live() -> void:
	for fall in player_falls:
		if fall.x >= s_bottom - 2.0 and fall.x <= s_top() + 2.0:
			var p := to_screen(fall.x, fall.y)
			_cross(p, 12.0, EditorTheme.INK, 8.0, true)
			_cross(p, 12.0, Color.WHITE, 4.0, true)
	if is_nan(live_ball.x):
		return
	var previous := Vector2.INF
	var previous_relative := 0.0
	for point in live_trail:
		var relative := relative_angle(point.y)
		var p := Vector2(relative_to_x(relative), s_to_y(point.x))
		if previous != Vector2.INF and absf(relative - previous_relative) < PI:
			_line(previous, p, Color.WHITE, 4.0)
		previous = p
		previous_relative = relative
	var ball := to_screen(live_ball.x, live_ball.y)
	_overlay.draw_circle(ball, 9.0, EditorTheme.INK)
	_overlay.draw_circle(ball, 6.0, Color.WHITE)


## Under the mouse: a hairline, the reach cone, jump landings and a readout.
func _draw_cursor(lv: LevelData) -> void:
	var s := y_to_s(_mouse.y)
	var angle := x_to_angle(_mouse.x)
	_line(Vector2(_strip_rect.position.x, _mouse.y), Vector2(_strip_rect.end.x, _mouse.y), Color(EditorTheme.INK, 0.5), 1.0)
	if s < 0.0 or s > lv.length:
		return
	if show_reach and tool == Tool.SELECT and not lv.is_hole(s, angle):
		_draw_reach(lv, s, angle)
	var text := "%.1f m · %.1f s · %+.0f°" % [s, lv.time_at(s), rad_to_deg(TunnelMath.wrap_angle(angle))]
	var spin := lv.spin_at(s)
	if absf(spin) > 0.5:
		text += " · spin %+.0f" % spin
	_pill(_mouse + Vector2(16.0, 14.0), text, Color.WHITE)


func _draw_reach(lv: LevelData, s: float, angle: float) -> void:
	# Where a rolling ball can steer to in the next 1.2 s: the cone between
	# full left and full right tilt, and the hands-off drift down its middle.
	var paths := LevelAnalysis.reach_paths(lv, tuning, s, angle, 1.2)
	var base := relative_angle(angle) - angle
	var left := _path_points(paths[0], base)
	var drift := _path_points(paths[1], base)
	var right := _path_points(paths[2], base)
	var cone := PackedVector2Array(left)
	var reversed := right.duplicate()
	reversed.reverse()
	cone.append_array(reversed)
	if cone.size() >= 3:
		var triangles := Geometry2D.triangulate_polygon(cone)
		if not triangles.is_empty():
			_overlay.draw_colored_polygon(cone, Color(1, 1, 1, 0.35))
	_overlay.draw_polyline(left, EditorTheme.INK, 2.5, true)
	_overlay.draw_polyline(right, EditorTheme.INK, 2.5, true)
	_dashed_polyline(drift, EditorTheme.INK, 2.0)
	# Jump landings: the smallest and the biggest jump from here.
	var x := _mouse.x
	var small := LevelAnalysis.jump_length(lv, tuning, s, tuning.min_jump_height)
	var big := LevelAnalysis.jump_length(lv, tuning, s, tuning.max_jump_height)
	var y_small := s_to_y(s + small)
	var y_big := s_to_y(s + big)
	_overlay.draw_rect(Rect2(x - 4.0, y_big, 8.0, y_small - y_big), Color(EditorTheme.ACTIVE, 0.85))
	_overlay.draw_rect(Rect2(x - 4.0, y_big, 8.0, y_small - y_big), EditorTheme.INK, false, 2.0)
	_dashed(Vector2(x, _mouse.y), Vector2(x, y_small), EditorTheme.INK, 2.0, 4.0)
	_pill(Vector2(x + 10.0, y_big - 11.0), "biggest jump lands %.1f m on" % big, EditorTheme.ACTIVE)
	_pill(Vector2(x + 10.0, y_small - 11.0), "smallest %.1f m" % small, EditorTheme.PAPER)


func _path_points(path: PackedVector2Array, base: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for p in path:
		points.append(Vector2(relative_to_x(p.y + base), s_to_y(p.x)))
	return points


# --- Small drawing helpers (overlay space = this control's space) ------------

func _line(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	_overlay.draw_line(a, b, color, width, true)


func _dashed(a: Vector2, b: Vector2, color: Color, width: float, dash: float) -> void:
	_overlay.draw_dashed_line(a, b, color, width, dash, true, true)


func _dashed_polyline(points: PackedVector2Array, color: Color, width: float) -> void:
	for i in range(0, points.size() - 1, 2):
		_overlay.draw_line(points[i], points[i + 1], color, width, true)


func _cross(p: Vector2, r: float, color: Color, width: float, on_overlay: bool = false) -> void:
	var canvas: CanvasItem = _overlay if on_overlay else self
	canvas.draw_line(p + Vector2(-r, -r), p + Vector2(r, r), color, width, true)
	canvas.draw_line(p + Vector2(-r, r), p + Vector2(r, -r), color, width, true)


func _text(p: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## A rounded label with a black border, readable on any colour.
func _pill(p: Vector2, text: String, fill: Color, on_overlay: bool = true) -> void:
	var canvas: CanvasItem = _overlay if on_overlay else self
	var font_size := 14
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 14.0
	var rect := Rect2(p, Vector2(width, 22.0))
	# Keep it on screen.
	var bounds := _strip_rect if on_overlay else Rect2(Vector2.ZERO, size)
	rect.position.x = clampf(rect.position.x, bounds.position.x + 2.0, maxf(bounds.end.x - width - 2.0, bounds.position.x))
	rect.position.y = clampf(rect.position.y, 2.0, size.y - 24.0)
	var style := EditorTheme.box(fill, 2, 2)
	style.set_corner_radius_all(11)
	canvas.draw_style_box(style, rect)
	canvas.draw_string(_font, rect.position + Vector2(7.0, 16.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, EditorTheme.INK)
