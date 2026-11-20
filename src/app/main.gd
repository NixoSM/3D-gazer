extends Node
## Application flow: menu -> run -> (fail -> quick retry | finish -> results).
##
## Main wires the pieces together and owns the app state machine; it holds
## no gameplay rules (BallSimulation) and draws nothing itself (WorldView, UI).

enum State { MENU, PLAYING, PAUSED, RETRYING, RESULTS }

const MANIFEST := "res://levels/manifest.json"
## Pause between falling and the screen fading, so the fall is readable.
const FAIL_HOLD := 0.45
const FADE_TIME := 0.3

@onready var session: GameSession = $GameSession
@onready var world: WorldView = $World
@onready var input_router: InputRouter = $InputRouter
@onready var hud: Hud = $UI/Hud
@onready var menu: MenuScreen = $UI/Menu
@onready var pause_screen: PauseScreen = $UI/Pause
@onready var results: ResultsScreen = $UI/Results

var state := State.MENU
var levels: Array[LevelData] = []
var level_index := 0
## Next level hint to show in this run (index into LevelData.hints), or -1
## when hints are off (the level has been finished before).
var _next_hint := -1


func _ready() -> void:
	_load_levels()
	session.run_failed.connect(_on_run_failed)
	session.run_completed.connect(_on_run_completed)
	hud.pause_pressed.connect(_pause)
	menu.level_chosen.connect(_play_level)
	pause_screen.resume_pressed.connect(_resume)
	pause_screen.restart_pressed.connect(func() -> void: _resume(); _retry(true))
	pause_screen.quit_pressed.connect(_show_menu)
	pause_screen.set_level_pressed.connect(input_router.set_level_here)
	pause_screen.reset_level_pressed.connect(input_router.reset_level)
	results.next_pressed.connect(func() -> void: _play_level(level_index + 1))
	results.replay_pressed.connect(func() -> void: _play_level(level_index))
	results.menu_pressed.connect(_show_menu)
	_select_level(_first_unfinished_level())
	_show_menu()
	_apply_command_line()


## Developer switches, passed after `--` on the command line:
##   --autoplay        the Autopilot plays (great with --write-movie)
##   --level=N         start level N (1-based) immediately
func _apply_command_line() -> void:
	var autoplay := false
	var start_level := -1
	for arg in OS.get_cmdline_user_args():
		if arg == "--autoplay":
			autoplay = true
		elif arg.begins_with("--level="):
			start_level = int(arg.get_slice("=", 1)) - 1
	if autoplay:
		session.autopilot = Autopilot.new(levels[level_index], session.tuning)
		if start_level < 0:
			start_level = level_index
	if start_level >= 0:
		_play_level.call_deferred(start_level)


func _process(delta: float) -> void:
	if state == State.MENU:
		session.attract(delta)
	elif state == State.PLAYING and session.simulation.is_alive():
		hud.set_spin(session.simulation.spin_rate())
		_show_hints()


## Shows each level hint as the ball reaches it, until the level is done once.
func _show_hints() -> void:
	var hints := session.level.hints
	while _next_hint >= 0 and _next_hint < hints.size() and session.view_s >= hints[_next_hint].s:
		hud.hint(hints[_next_hint].text)
		_next_hint += 1


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		if state == State.PLAYING:
			_pause()
		elif state == State.PAUSED:
			_resume()


func _notification(what: int) -> void:
	# iOS: pause when the app is backgrounded or a call/notification takes focus.
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		if state == State.PLAYING:
			_pause()


# --- Levels ------------------------------------------------------------------

func _load_levels() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if typeof(manifest) != TYPE_DICTIONARY:
		push_error("Missing or invalid %s" % MANIFEST)
		return
	for id in manifest.get("levels", []):
		var result := LevelSerializer.load_file("res://levels/%s.json" % id)
		if result.ok():
			levels.append(result.level)
		else:
			push_error("\n".join(result.errors))


func _first_unfinished_level() -> int:
	for i in levels.size():
		if not Progress.is_completed(levels[i].id):
			return i
	return 0


func _is_unlocked(index: int) -> bool:
	return index == 0 or Progress.is_completed(levels[index - 1].id)


func _select_level(index: int) -> void:
	level_index = clampi(index, 0, levels.size() - 1)
	session.load_level(levels[level_index])
	world.set_level(levels[level_index], session.tuning)
	world.tunnel.set_best_marker(_best_marker_s())


func _best_marker_s() -> float:
	var level := levels[level_index]
	var best := Progress.best_progress(level.id)
	return best * level.length if best > 0.02 and best < 1.0 else -1.0


# --- States ------------------------------------------------------------------

func _show_menu() -> void:
	get_tree().paused = false
	state = State.MENU
	session.stop_run()
	session.reset_run()
	world.reset_view()
	world.fade = 0.0
	var entries := []
	for i in levels.size():
		entries.append({
			"level": levels[i],
			"palette": LevelPalette.new(levels[i].palette),
			"unlocked": _is_unlocked(i),
			"best": Progress.best_progress(levels[i].id),
			"completed": Progress.is_completed(levels[i].id),
			"best_chain": Progress.best_chain(levels[i].id),
		})
	ScreenLayout.unlock()
	menu.populate(entries)
	menu.visible = true
	hud.visible = false
	pause_screen.visible = false
	results.visible = false


func _play_level(index: int) -> void:
	if index >= levels.size():
		_show_menu()
		return
	if index != level_index or session.level != levels[index]:
		_select_level(index)
	menu.visible = false
	results.visible = false
	hud.visible = true
	_begin_run()


func _begin_run() -> void:
	session.reset_run()
	world.reset_view()
	world.tunnel.set_best_marker(_best_marker_s())
	state = State.PLAYING
	ScreenLayout.lock_for_play()
	session.start_run()
	hud.clear_spin()
	hud.clear_hint()
	_next_hint = -1 if Progress.is_completed(levels[level_index].id) else 0
	var best := Progress.best_progress(levels[level_index].id)
	var toast := levels[level_index].display_name
	if session.attempt > 1:
		toast = "attempt %d · best %d%%" % [session.attempt, int(best * 100.0)]
	hud.toast(toast)


func _pause() -> void:
	state = State.PAUSED
	get_tree().paused = true
	pause_screen.visible = true
	ScreenLayout.unlock()


func _resume() -> void:
	get_tree().paused = false
	pause_screen.visible = false
	state = State.PLAYING
	ScreenLayout.lock_for_play()


## Fade out, reset, fade in, go. `immediate` skips the hold after a fall.
func _retry(immediate: bool = false) -> void:
	state = State.RETRYING
	var tween := create_tween()
	if immediate:
		session.stop_run()
	else:
		tween.tween_interval(FAIL_HOLD)
	tween.tween_property(world, "fade", 1.0, FADE_TIME)
	tween.tween_callback(session.stop_run)
	tween.tween_callback(_begin_run)
	tween.tween_property(world, "fade", 0.0, FADE_TIME)


# --- Session events ------------------------------------------------------------

func _on_run_failed(progress: float) -> void:
	var level := levels[level_index]
	var improved := Progress.record_attempt(level.id, progress, false, session.longest_chain)
	hud.toast("%d%%%s" % [int(progress * 100.0), " · new best" if improved else ""], 0.8)
	# The session keeps stepping during the hold, so the ball visibly drops away.
	_retry()


func _on_run_completed() -> void:
	var level := levels[level_index]
	Progress.record_attempt(level.id, 1.0, true, session.longest_chain)
	state = State.RESULTS
	var tween := create_tween()
	tween.tween_interval(1.8)
	tween.tween_callback(func() -> void:
		results.present(level.display_name, session.attempt, session.longest_chain, level_index + 1 < levels.size())
		results.visible = true
		hud.visible = false
		ScreenLayout.unlock())
