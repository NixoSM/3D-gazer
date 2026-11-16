class_name Hud
extends Control
## In-run overlay: the echo chain counter, a toast between attempts, and the
## pause button. Deliberately sparse: progress is shown by the tunnel colour.

signal pause_pressed

var _chain: Label
var _perfect: Label
var _toast: Label
var _chain_tween: Tween
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

	_toast = UiStyle.caption("", 22)
	_toast.modulate.a = 0.0
	layout.add_child(_toast)

	var chain_gap := Control.new()
	chain_gap.custom_minimum_size = Vector2(0, 150)
	chain_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(chain_gap)
	_chain = UiStyle.display("", 132)
	_chain.modulate.a = 0.0
	layout.add_child(_chain)
	_perfect = UiStyle.caption("perfect", 22)
	_perfect.modulate.a = 0.0
	layout.add_child(_perfect)


func show_chain(chain: int, perfect: bool, color: Color) -> void:
	if chain < 2:
		return
	_chain.text = "×%d" % chain
	_chain.add_theme_color_override("font_color", color)
	_chain.pivot_offset = _chain.size * 0.5
	if _chain_tween:
		_chain_tween.kill()
	_chain.modulate.a = 1.0
	_chain.scale = Vector2.ONE * 1.25
	_perfect.modulate.a = 1.0 if perfect else 0.0
	_chain_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_chain_tween.tween_property(_chain, "scale", Vector2.ONE, 0.22)
	_chain_tween.tween_interval(0.9)
	_chain_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_chain_tween.tween_property(_chain, "modulate:a", 0.0, 0.5)
	_chain_tween.parallel().tween_property(_perfect, "modulate:a", 0.0, 0.3)


func hide_chain() -> void:
	if _chain_tween:
		_chain_tween.kill()
	_chain_tween = create_tween()
	_chain_tween.tween_property(_chain, "modulate:a", 0.0, 0.2)
	_chain_tween.parallel().tween_property(_perfect, "modulate:a", 0.0, 0.2)


func toast(text: String, seconds: float = 1.6) -> void:
	_toast.text = text.to_upper()
	if _toast_tween:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)
