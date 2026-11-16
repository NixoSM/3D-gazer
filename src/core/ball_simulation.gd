class_name BallSimulation
extends RefCounted
## The game's rules: a deterministic, engine-node-free model of the ball.
##
## State lives in *tunnel-surface coordinates* (s along the tunnel, angle
## around it, height above the wall), not in 3D. Gravity always points from
## the ball to the wall beneath it, so in this space the tunnel is simply a
## flat strip whose sides are glued together: the curved, rotating 3D view
## is purely a presentation concern (see CameraRig).
##
## Call step() at a fixed rate with an InputFrame; it returns the events that
## happened during that step. No signals, no nodes, no randomness: the same
## inputs always give the same run, which keeps it unit-testable and makes
## replays, ghosts and editor previews possible later.

enum Phase { ROLLING, AIRBORNE, FALLING, FINISHED }

enum EventType {
	JUMPED,        ## Left the ground. data: height, echo, perfect, chain
	LANDED,        ## Touched down safely. data: echo_queued
	CHAIN_BROKEN,  ## Landed and the echo window closed without a tap. data: chain
	FELL,          ## Dropped through a hole.
	FINISHED,      ## Reached the end of the tunnel.
}


class SimEvent:
	var type: EventType
	var s: float
	var angle: float
	var height: float = 0.0
	var echo: bool = false
	var perfect: bool = false
	var chain: int = 0

	func _init(p_type: EventType, p_s: float, p_angle: float) -> void:
		type = p_type
		s = p_s
		angle = p_angle


var level: LevelData
var tuning: BallTuning

# --- State (read freely, write only through the methods below) -------------
var phase: Phase = Phase.ROLLING
## Distance travelled along the tunnel, metres.
var s: float = 0.0
## Position around the circumference, radians in [0, TAU).
var angle: float = 0.0
## Height of the ball's lowest point above the wall, metres (< 0 once falling).
var height: float = 0.0
## Forward speed, m/s.
var forward_speed: float = 0.0
## Sideways speed along the wall, m/s (positive = to the right).
var lateral_speed: float = 0.0
## Speed away from the wall, m/s.
var vertical_speed: float = 0.0
## Seconds since the run started.
var time: float = 0.0
## Height of the last jump: what an echo repeats.
var last_jump_height: float = 0.0
## Consecutive echo jumps.
var echo_chain: int = 0

var _echo_queued: bool = false
var _echo_queued_perfect: bool = false
var _buffered_jump_strength: float = -1.0
var _time_since_landing: float = INF
var _landing_resolved: bool = true


func _init(p_level: LevelData, p_tuning: BallTuning) -> void:
	level = p_level
	tuning = p_tuning
	reset()


func reset(start_angle: float = 0.0) -> void:
	phase = Phase.ROLLING
	s = 0.0
	angle = TunnelMath.wrap_angle_positive(start_angle)
	height = 0.0
	forward_speed = level.speed_at(0.0)
	lateral_speed = 0.0
	vertical_speed = 0.0
	time = 0.0
	last_jump_height = 0.0
	echo_chain = 0
	_echo_queued = false
	_echo_queued_perfect = false
	_buffered_jump_strength = -1.0
	_time_since_landing = INF
	_landing_resolved = true


func progress() -> float:
	return level.progress_at(s)


func is_alive() -> bool:
	return phase != Phase.FALLING


## Seconds until the ball reaches the wall again, assuming no input.
func time_to_land() -> float:
	if phase != Phase.AIRBORNE:
		return 0.0
	var g := tuning.gravity
	return (vertical_speed + sqrt(vertical_speed * vertical_speed + 2.0 * g * maxf(height, 0.0))) / g


## Jump height (m) produced by a swipe of the given strength in [0, 1].
func jump_height_for_strength(strength: float) -> float:
	var shaped := pow(clampf(strength, 0.0, 1.0), tuning.jump_strength_exponent)
	return lerpf(tuning.min_jump_height, tuning.max_jump_height, shaped)


## Advances the simulation by `dt` seconds. Returns what happened.
func step(dt: float, input: InputFrame) -> Array[SimEvent]:
	var events: Array[SimEvent] = []
	time += dt

	_step_forward(dt)
	_step_lateral(dt, input.tilt)

	match phase:
		Phase.ROLLING:
			_step_rolling(dt, input, events)
		Phase.AIRBORNE:
			_step_airborne(dt, input, events)
		Phase.FALLING:
			_step_falling(dt)
		Phase.FINISHED:
			_step_finished(dt)

	if phase in [Phase.ROLLING, Phase.AIRBORNE] and s >= level.length:
		phase = Phase.FINISHED
		events.append(SimEvent.new(EventType.FINISHED, s, angle))
	return events


func _step_forward(dt: float) -> void:
	if phase in [Phase.ROLLING, Phase.AIRBORNE]:
		forward_speed = level.speed_at(s)
	s += forward_speed * dt


## Lateral motion is a ball on a tilted plane: tilt gives acceleration, not
## velocity, so the ball keeps drifting after the phone returns to neutral.
func _step_lateral(dt: float, tilt: float) -> void:
	var authority := 0.0
	match phase:
		Phase.ROLLING:
			authority = 1.0
		Phase.AIRBORNE:
			authority = tuning.air_control
	var slope := clampf(tilt, -1.0, 1.0) * tuning.max_tilt_radians()
	var acceleration := tuning.rolling_factor * tuning.gravity * sin(slope) * authority
	lateral_speed += acceleration * dt
	lateral_speed *= exp(-tuning.rolling_resistance * dt)
	lateral_speed = clampf(lateral_speed, -tuning.max_lateral_speed, tuning.max_lateral_speed)
	angle = TunnelMath.wrap_angle_positive(angle + lateral_speed * dt / level.tunnel_radius)


func _step_rolling(dt: float, input: InputFrame, events: Array[SimEvent]) -> void:
	var in_grace := not _landing_resolved and _time_since_landing <= tuning.echo_grace_time
	if input.tap and in_grace and last_jump_height > 0.0:
		_landing_resolved = true
		_jump(last_jump_height, true, _time_since_landing <= tuning.perfect_window, events)
		return
	if input.has_jump():
		_landing_resolved = true
		echo_chain = 0
		_jump(jump_height_for_strength(input.jump_strength), false, false, events)
		return

	_time_since_landing += dt
	if not _landing_resolved and _time_since_landing > tuning.echo_grace_time:
		_landing_resolved = true
		if echo_chain > 0:
			var broken := SimEvent.new(EventType.CHAIN_BROKEN, s, angle)
			broken.chain = echo_chain
			events.append(broken)
		echo_chain = 0

	if _over_hole():
		_start_falling(events)


func _step_airborne(dt: float, input: InputFrame, events: Array[SimEvent]) -> void:
	var landing_in := time_to_land()
	if input.tap and last_jump_height > 0.0 and not _echo_queued and landing_in <= tuning.echo_buffer_time:
		_echo_queued = true
		_echo_queued_perfect = landing_in <= tuning.perfect_window
	if input.has_jump() and landing_in <= tuning.jump_buffer_time:
		_buffered_jump_strength = input.jump_strength

	vertical_speed -= tuning.gravity * dt
	height += vertical_speed * dt
	if height > 0.0:
		return

	# Touchdown.
	height = 0.0
	vertical_speed = 0.0
	if _over_hole():
		_start_falling(events)
		return

	var landed := SimEvent.new(EventType.LANDED, s, angle)
	landed.echo = _echo_queued
	landed.chain = echo_chain
	events.append(landed)

	if _echo_queued:
		var perfect := _echo_queued_perfect
		_echo_queued = false
		_jump(last_jump_height, true, perfect, events)
	elif _buffered_jump_strength >= 0.0:
		var strength := _buffered_jump_strength
		_buffered_jump_strength = -1.0
		echo_chain = 0
		_jump(jump_height_for_strength(strength), false, false, events)
	else:
		phase = Phase.ROLLING
		_time_since_landing = 0.0
		_landing_resolved = false


func _step_falling(dt: float) -> void:
	# Beyond the wall the ball keeps falling "down", i.e. out of the tunnel.
	vertical_speed -= tuning.gravity * dt
	height += vertical_speed * dt


func _step_finished(_dt: float) -> void:
	if height > 0.0 or vertical_speed > 0.0:
		vertical_speed -= tuning.gravity * _dt
		height = maxf(height + vertical_speed * _dt, 0.0)
		if height == 0.0:
			vertical_speed = 0.0


func _jump(jump_height: float, echo: bool, perfect: bool, events: Array[SimEvent]) -> void:
	# Never let a jump hit the ceiling: the far wall is 2R away.
	var ceiling := 2.0 * level.tunnel_radius - 2.0 * tuning.ball_radius - 0.3
	jump_height = minf(jump_height, ceiling)
	last_jump_height = jump_height
	if echo:
		echo_chain += 1
	phase = Phase.AIRBORNE
	vertical_speed = sqrt(2.0 * tuning.gravity * jump_height)
	_buffered_jump_strength = -1.0
	var jumped := SimEvent.new(EventType.JUMPED, s, angle)
	jumped.height = jump_height
	jumped.echo = echo
	jumped.perfect = perfect
	jumped.chain = echo_chain
	events.append(jumped)


func _over_hole() -> bool:
	var margin := tuning.hole_forgiveness
	return level.hole_at(s, angle, margin, margin) != null


func _start_falling(events: Array[SimEvent]) -> void:
	phase = Phase.FALLING
	vertical_speed = minf(vertical_speed, 0.0) - 2.0
	echo_chain = 0
	events.append(SimEvent.new(EventType.FELL, s, angle))
