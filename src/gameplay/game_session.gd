class_name GameSession
extends Node
## Runs one level: owns the simulation, steps it at a fixed rate, and tells
## the rest of the game what happened through signals.
##
## Presentation nodes never touch BallSimulation directly; they listen to
## these signals and read the interpolated `view_*` values each frame. That
## keeps "what happens" (simulation) and "how it looks" (views, effects)
## independent: you can restyle everything without risking gameplay bugs.

signal sim_event(event: BallSimulation.SimEvent)
signal run_failed(progress: float)
signal run_completed

## Simulation steps per second. 120 keeps input latency low on 120 Hz iPhones.
const STEP_RATE := 120.0
const MAX_STEPS_PER_FRAME := 8

@export var tuning: BallTuning
@export var input_router: InputRouter

## When set, the bot plays instead of the player (demo recordings, tests).
var autopilot: Autopilot
var level: LevelData
var simulation: BallSimulation
var running := false
var attempt := 0
var longest_chain := 0

# Interpolated state for rendering (between the last two simulation steps).
var view_s := 0.0
var view_angle := 0.0
var view_height := 0.0

var _accumulator := 0.0
var _previous := Vector3.ZERO  # (s, angle, height) at the previous step


func load_level(p_level: LevelData) -> void:
	level = p_level
	simulation = BallSimulation.new(level, tuning)
	if autopilot:
		autopilot = Autopilot.new(level, tuning)
	attempt = 0
	reset_run()


## Resets to the start line, or to `start_s` (the level editor plays from
## any point of the level).
func reset_run(start_s: float = 0.0, start_angle: float = 0.0) -> void:
	simulation.place(start_s, start_angle)
	if autopilot:
		# A fresh bot per run (same reflexes), so no stale plan carries over.
		var delay := autopilot.steering_delay
		autopilot = Autopilot.new(level, tuning)
		autopilot.steering_delay = delay
	_accumulator = 0.0
	longest_chain = 0
	_previous = Vector3(simulation.s, simulation.angle, simulation.height)
	_sync_view(1.0)


func start_run() -> void:
	attempt += 1
	running = true
	if input_router:
		input_router.enabled = true


func stop_run() -> void:
	running = false
	if input_router:
		input_router.enabled = false


## Menu backdrop: drifts the ball slowly through the (hole-free) start of the
## level and around the tunnel, without running the rules.
func attract(delta: float) -> void:
	if simulation == null or running:
		return
	_previous = Vector3(simulation.s, simulation.angle, simulation.height)
	simulation.forward_speed = 1.4
	simulation.lateral_speed = 1.6
	simulation.s = fposmod(simulation.s + simulation.forward_speed * delta, level.base_speed * 2.8)
	simulation.angle = TunnelMath.wrap_angle_positive(simulation.angle + simulation.lateral_speed * delta / level.tunnel_radius)
	_sync_view(1.0)


func progress() -> float:
	return simulation.progress() if simulation else 0.0


func _process(delta: float) -> void:
	if simulation == null or not running:
		return
	_accumulator += minf(delta, 0.1)
	var dt := 1.0 / STEP_RATE
	var steps := 0
	while _accumulator >= dt and steps < MAX_STEPS_PER_FRAME:
		_previous = Vector3(simulation.s, simulation.angle, simulation.height)
		var frame: InputFrame
		if autopilot:
			frame = autopilot.decide(simulation)
		elif input_router:
			frame = input_router.take_frame()
		else:
			frame = InputFrame.new()
		for event in simulation.step(dt, frame):
			_handle(event)
		_accumulator -= dt
		steps += 1
	_sync_view(_accumulator / dt)


func _sync_view(alpha: float) -> void:
	view_s = lerpf(_previous.x, simulation.s, alpha)
	view_angle = lerp_angle(_previous.y, simulation.angle, alpha)
	view_height = lerpf(_previous.z, simulation.height, alpha)


func _handle(event: BallSimulation.SimEvent) -> void:
	longest_chain = maxi(longest_chain, simulation.echo_chain)
	sim_event.emit(event)
	match event.type:
		BallSimulation.EventType.FELL:
			if input_router:
				input_router.enabled = false
			run_failed.emit(level.progress_at(event.s))
		BallSimulation.EventType.FINISHED:
			if input_router:
				input_router.enabled = false
			run_completed.emit()
