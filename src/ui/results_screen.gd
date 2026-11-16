class_name ResultsScreen
extends Control
## Shown when a level is completed.

signal next_pressed
signal replay_pressed
signal menu_pressed

var _title: Label
var _stats: Label
var _next: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(MenuScreen._scrim())
	var safe := SafeArea.new()
	add_child(safe)
	var layout := VBoxContainer.new()
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 10)
	safe.add_child(layout)

	_title = UiStyle.display("", 132)
	layout.add_child(_title)
	layout.add_child(UiStyle.caption("complete", 24))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 40)
	layout.add_child(gap)
	_stats = UiStyle.caption("", 24)
	_stats.modulate.a = 0.85
	layout.add_child(_stats)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 80)
	layout.add_child(gap2)

	_next = UiStyle.button("Next", true)
	_next.pressed.connect(next_pressed.emit)
	layout.add_child(_next)
	var replay := UiStyle.button("again")
	replay.pressed.connect(replay_pressed.emit)
	layout.add_child(replay)
	var menu := UiStyle.button("levels")
	menu.pressed.connect(menu_pressed.emit)
	layout.add_child(menu)


func present(level_name: String, attempts: int, longest_chain: int, has_next: bool) -> void:
	_title.text = level_name
	_stats.text = "attempts %d\nlongest echo ×%d" % [attempts, longest_chain]
	_next.visible = has_next
