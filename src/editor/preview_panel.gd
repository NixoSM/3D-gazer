class_name PreviewPanel
extends PanelContainer
## The game itself, running inside the editor.
##
## When idle it is a camera you scrub with the mouse: hover anywhere on the
## strip and this shows what the ball sees from there, with the real
## renderer. Press play and it *is* the game, from any point of the level,
## either with you at the keyboard or a bot at the wheel. Same GameSession,
## WorldView and EffectsDirector as the phone build, so the feel matches.

signal run_ended(fell: bool, s: float, angle: float)

const HINT_IDLE := "PREVIEW — hover the strip to look from there"
const HINT_PLAY := "A/D tilt · W hop · Space big jump · E echo · Esc stop"

var session: GameSession
var world: WorldView
var tuning: BallTuning
var playing := false
var bot_playing := false

var _viewport: SubViewport
var _hint: Label
var _title: Label
var _start := Vector2.ZERO


func setup(p_tuning: BallTuning, input_router: InputRouter) -> void:
	tuning = p_tuning
	add_theme_stylebox_override("panel", EditorTheme.panel(EditorTheme.INK))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	_title = EditorTheme.heading("PREVIEW", 18)
	_title.add_theme_color_override("font_color", EditorTheme.ACTIVE)
	column.add_child(_title)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.custom_minimum_size = Vector2(270, 420)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.handle_input_locally = false
	container.add_child(_viewport)

	session = GameSession.new()
	session.tuning = tuning
	session.input_router = input_router
	_viewport.add_child(session)
	world = _build_world()
	_viewport.add_child(world)
	var synth := ToneSynth.new()
	var effects := EffectsDirector.new()
	effects.session = session
	effects.world = world
	effects.synth = synth
	effects.add_child(synth)
	_viewport.add_child(effects)
	session.run_failed.connect(_on_failed)
	session.run_completed.connect(_on_completed)

	_hint = EditorTheme.note(HINT_IDLE, Color.WHITE)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_hint)


## The same node tree as scenes/main.tscn's World, built in code.
func _build_world() -> WorldView:
	var view := WorldView.new()
	view.name = "World"
	view.session = session
	var environment := WorldEnvironment.new()
	environment.name = "WorldEnvironment"
	view.add_child(environment)
	var tunnel := TunnelView.new()
	tunnel.name = "Tunnel"
	view.add_child(tunnel)
	var ball := BallView.new()
	ball.name = "Ball"
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ball.add_child(mesh)
	view.add_child(ball)
	var camera := CameraRig.new()
	camera.name = "Camera"
	camera.current = true
	camera.near = 0.1
	camera.far = 260.0
	view.add_child(camera)
	return view


func set_level(level: LevelData) -> void:
	var was_playing := playing
	if was_playing:
		stop()
	session.load_level(level)
	world.set_level(level, tuning)


## Look from (s, angle) without playing.
func show_at(s: float, angle: float) -> void:
	if playing or session.simulation == null:
		return
	session.reset_run(s, angle)
	world.reset_view()


## Plays from (s, angle). bot_delay < 0: you play; otherwise the bot does.
func play(s: float, angle: float, bot_delay: float = -1.0) -> void:
	if session.simulation == null:
		return
	_start = Vector2(s, angle)
	bot_playing = bot_delay >= 0.0
	if bot_playing:
		session.autopilot = Autopilot.new(session.level, tuning)
		session.autopilot.steering_delay = bot_delay
	else:
		session.autopilot = null
	session.reset_run(s, angle)
	world.reset_view()
	world.fade = 0.0
	session.start_run()
	playing = true
	_title.text = ("BOT %.2f s PLAYING" % bot_delay) if bot_playing else "YOU'RE PLAYING"
	_hint.text = "Esc stop" if bot_playing else HINT_PLAY


func restart() -> void:
	play(_start.x, _start.y, session.autopilot.steering_delay if bot_playing else -1.0)


func stop() -> void:
	session.stop_run()
	session.autopilot = null
	playing = false
	bot_playing = false
	world.fade = 0.0
	_title.text = "PREVIEW"
	_hint.text = HINT_IDLE


## The ball's (s, angle) right now, for the strip's live marker.
func ball_position() -> Vector2:
	return Vector2(session.view_s, session.view_angle)


func _on_failed(_progress: float) -> void:
	var sim := session.simulation
	run_ended.emit(true, sim.s, sim.angle)


func _on_completed() -> void:
	var sim := session.simulation
	run_ended.emit(false, sim.s, sim.angle)
