class_name ResultsScreen
extends Control
## Shown when a level is completed.

signal next_pressed
signal replay_pressed
signal menu_pressed

var _title: Label
var _stats: Label
var _next: Button


var _shown := []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	ScreenLayout.changed.connect(func(_landscape: bool) -> void: _build())
	_build()


## Portrait: one column. Landscape: the title on the left, the way on the right.
func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	add_child(MenuScreen._scrim())
	var safe := SafeArea.new()
	add_child(safe)
	var outer: BoxContainer = HBoxContainer.new() if ScreenLayout.landscape else VBoxContainer.new()
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_theme_constant_override("separation", 140 if ScreenLayout.landscape else 80)
	safe.add_child(outer)
	var about := VBoxContainer.new()
	about.alignment = BoxContainer.ALIGNMENT_CENTER
	about.add_theme_constant_override("separation", 10)
	outer.add_child(about)
	var actions := VBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 10)
	outer.add_child(actions)

	_title = UiStyle.display("", 132)
	about.add_child(_title)
	about.add_child(UiStyle.caption("complete", 24))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 40)
	about.add_child(gap)
	_stats = UiStyle.caption("", 24)
	_stats.modulate.a = 0.85
	about.add_child(_stats)

	_next = UiStyle.button("Next", true)
	_next.pressed.connect(next_pressed.emit)
	actions.add_child(_next)
	var replay := UiStyle.button("again")
	replay.pressed.connect(replay_pressed.emit)
	actions.add_child(replay)
	var menu := UiStyle.button("levels")
	menu.pressed.connect(menu_pressed.emit)
	actions.add_child(menu)
	if not _shown.is_empty():
		callv("present", _shown)


func present(level_name: String, attempts: int, longest_chain: int, has_next: bool) -> void:
	_shown = [level_name, attempts, longest_chain, has_next]
	_title.text = level_name
	_stats.text = "attempts %d\nlongest echo ×%d" % [attempts, longest_chain]
	_next.visible = has_next
