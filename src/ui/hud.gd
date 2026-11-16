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


func toast(text: String, seconds: float = 1.6) -> void:
	_toast.text = text.to_upper()
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)
