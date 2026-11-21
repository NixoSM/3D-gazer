class_name Hud
extends Control
## In-run overlay: the ground spin chevrons, a toast between attempts, and
## the pause button. Deliberately sparse: progress is shown by the tunnel colour.

signal pause_pressed

var _spin: Label
var _spin_tween: Tween
var _spin_shown := ""
var _toast: Label
var _toast_tween: Tween
var _hint: Label
var _hint_tween: Tween
var _floor_gap: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var safe := SafeArea.new()
	add_child(safe)
	var layout := VBoxContainer.new()
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(layout)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(top)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	var pause := UiStyle.button("pause")
	pause.custom_minimum_size = Vector2(160, 88)
	pause.pressed.connect(pause_pressed.emit)
	top.add_child(pause)

	# Ground spin: which way the tunnel is pushing the ball, and how hard.
	_spin = UiStyle.display("", 64)
	_spin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spin.modulate.a = 0.0
	layout.add_child(_spin)

	_toast = UiStyle.caption("", 26)
	_toast.modulate.a = 0.0
	layout.add_child(_toast)

	# Level hints sit low, under the ball, away from the tunnel ahead.
	var push := Control.new()
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	push.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(push)
	_hint = UiStyle.display("", 46)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.modulate.a = 0.0
	layout.add_child(_hint)
	_floor_gap = Control.new()
	_floor_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(_floor_gap)
	ScreenLayout.changed.connect(_fit)
	_fit(ScreenLayout.landscape)


## In landscape the ball fills the bottom of a short screen and the patterns
## come down the middle, so the hint moves to the empty wall on the left.
func _fit(landscape: bool) -> void:
	_floor_gap.custom_minimum_size = Vector2(0, 150)
	_hint.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if landscape else Control.SIZE_FILL
	_hint.custom_minimum_size = Vector2(400 if landscape else 0, 0)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if landscape else HORIZONTAL_ALIGNMENT_CENTER


## Shows the spin as chevrons pointing the way the ball is being pushed:
## one to three of them by strength.
func set_spin(rate: float) -> void:
	var count := 0
	var magnitude := absf(rate)
	if magnitude >= 1.0:
		count = 1 if magnitude < 20.0 else (2 if magnitude < 40.0 else 3)
	var text := ("»" if rate > 0.0 else "«").repeat(count)
	if text == _spin_shown:
		return
	_spin_shown = text
	if _spin_tween:
		_spin_tween.kill()
	_spin_tween = create_tween()
	if text.is_empty():
		_spin_tween.tween_property(_spin, "modulate:a", 0.0, 0.3)
		return
	_spin.text = text
	_spin.pivot_offset = _spin.size * 0.5
	_spin.scale = Vector2.ONE * 1.2
	_spin.modulate.a = 1.0
	_spin_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_spin_tween.tween_property(_spin, "scale", Vector2.ONE, 0.25)
	_spin_tween.tween_property(_spin, "modulate:a", 0.9, 0.4)


func clear_spin() -> void:
	_spin_shown = ""
	if _spin_tween:
		_spin_tween.kill()
	_spin.modulate.a = 0.0


## A level hint ("swipe up to jump"): pops in, holds, fades.
func hint(text: String, seconds: float = 2.2) -> void:
	_hint.text = text.to_upper()
	if _hint_tween:
		_hint_tween.kill()
	_hint.pivot_offset = _hint.size * 0.5
	_hint.scale = Vector2.ONE * 0.8
	_hint.modulate.a = 1.0
	_hint_tween = create_tween()
	_hint_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hint_tween.tween_property(_hint, "scale", Vector2.ONE, 0.22)
	_hint_tween.tween_interval(seconds)
	_hint_tween.tween_property(_hint, "modulate:a", 0.0, 0.35)


func clear_hint() -> void:
	if _hint_tween:
		_hint_tween.kill()
	_hint.modulate.a = 0.0


func toast(text: String, seconds: float = 1.6) -> void:
	_toast.text = text.to_upper()
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)
