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
## Holes are cut through a shell TunnelMath.WALL_THICKNESS thick. When the
## ground goes from under the ball it really drops, and the four walls of
## the cut are solid: a ball that drops near the far edge slams into it and
## bounces back instead of passing through, and a ball that lands on an edge
## can be popped back out. The run is lost once the ball's centre sinks
## below the lip or it hits a wall side-on.
##
## Ground spin (LevelData.spin) carries everything inside the tunnel
## sideways; each echo jump flips its direction.
##
## An echo starts with a hit-stop (Phase.FROZEN): the ball holds still on
## the floor for tuning.echo_freeze_time, then jumps. A swipe during the
## freeze replaces the echo's height, so a player can reshape the rhythm;
## while a finger is still down the freeze waits for it, up to
## tuning.echo_freeze_max.
##
## Call step() at a fixed rate with an InputFrame; it returns the events that
## happened during that step. No signals, no nodes, no randomness: the same
## inputs always give the same run, which keeps it unit-testable and makes
## replays, ghosts and editor previews possible later.

enum Phase { ROLLING, AIRBORNE, FALLING, FINISHED, FROZEN }

enum EventType {
	JUMPED,        ## Left the ground. data: height, echo, perfect, chain, spin_flipped
	LANDED,        ## Touched down safely. data: echo_queued
	CHAIN_BROKEN,  ## Landed and the echo window closed without a tap. data: chain
	FELL,          ## Lost into a hole.
	FINISHED,      ## Reached the end of the tunnel.
	BUMPED,        ## Hit the wall of a hole. data: height = impact speed (m/s)
	ECHO_HIT,      ## An echo tap connected; the hit-stop starts. data: perfect, chain (the coming one)
}

## Below this spin rate (°/s) an echo does not flip the spin.
const SPIN_FLIP_THRESHOLD := 0.5
## The run is lost once the ball's centre is this far below the lip of a hole.
const LOST_DEPTH := 0.02
## A wall contact whose normal points less "up" than this is a crash, not a pop.
const POP_NORMAL := 0.5


class SimEvent:
	var type: EventType
	var s: float
	var angle: float
	var height: float = 0.0
	var echo: bool = false
	var perfect: bool = false
	var chain: int = 0
	var spin_flipped: bool = false

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
## Height of the ball's lowest point above the wall, metres (< 0 once dropping).
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
## +1 or -1: multiplies the level's spin. Every echo jump flips it.
var spin_direction: float = 1.0

var _echo_queued: bool = false
var _echo_queued_perfect: bool = false
var _buffered_jump_strength: float = -1.0
var _time_since_landing: float = INF
var _landing_resolved: bool = true
## Seconds since the ground went from under a rolling ball (INF = it did not).
var _time_unsupported: float = INF
## The hole the ball was lost into: its walls still bound the fall.
var _fall_hole: HoleData
var _freeze_left: float = 0.0
var _freeze_elapsed: float = 0.0
var _freeze_perfect: bool = false


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
	spin_direction = 1.0
	_echo_queued = false
	_echo_queued_perfect = false
	_buffered_jump_strength = -1.0
	_time_since_landing = INF
	_landing_resolved = true
	_time_unsupported = INF
	_fall_hole = null
	_freeze_left = 0.0
	_freeze_elapsed = 0.0
	_freeze_perfect = false


func progress() -> float:
	return level.progress_at(s)


func is_alive() -> bool:
	return phase != Phase.FALLING


## Still running: alive and not past the finish.
func is_playing() -> bool:
	return phase in [Phase.ROLLING, Phase.AIRBORNE, Phase.FROZEN]


## Sideways drift (m/s) the ground spin imposes here, with the echo flips applied.
func spin_speed() -> float:
	return level.spin_speed_at(s) * spin_direction


## Spin here in degrees per second, with the echo flips applied.
func spin_rate() -> float:
	return level.spin_at(s) * spin_direction


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
	if phase == Phase.FROZEN:
		_step_frozen(dt, input, events)
		return events

	_step_forward(dt)
	_step_lateral(dt, input.tilt)

	match phase:
		Phase.ROLLING:
			_step_rolling(dt, input, events)
		Phase.AIRBORNE:
			_step_airborne(dt, input, events)
		Phase.FALLING:
			_step_falling(dt, events)
		Phase.FINISHED:
			_step_finished(dt)

	if phase in [Phase.ROLLING, Phase.AIRBORNE] and s >= level.length:
		phase = Phase.FINISHED
		events.append(SimEvent.new(EventType.FINISHED, s, angle))
	return events


func _step_forward(dt: float) -> void:
	# While alive, forward speed is the level's: the player never controls it.
	# Once lost, the ball is a free body (walls can bounce it back).
	if phase in [Phase.ROLLING, Phase.AIRBORNE]:
		forward_speed = level.speed_at(s)
	s += forward_speed * dt


## Lateral motion is a ball on a tilted plane: tilt gives acceleration, not
## velocity, so the ball keeps drifting after the phone returns to neutral.
## Rolling resistance relaxes the sideways speed towards the spin drift
## (zero without spin), so with the phone level the ball ends up travelling
## with the spinning tunnel.
func _step_lateral(dt: float, tilt: float) -> void:
	if phase == Phase.FALLING:
		angle = TunnelMath.wrap_angle_positive(angle + lateral_speed * dt / level.tunnel_radius)
		return
	var authority := 0.0
	var flow := 0.0
	match phase:
		Phase.ROLLING:
			authority = 1.0
			flow = spin_speed()
		Phase.AIRBORNE:
			authority = tuning.air_control
			# The air inside the tunnel turns with it, so the spin still applies.
			flow = spin_speed()
	var slope := clampf(tilt, -1.0, 1.0) * tuning.max_tilt_radians()
	var acceleration := tuning.rolling_factor * tuning.gravity * sin(slope) * authority
	lateral_speed += acceleration * dt
	lateral_speed = flow + (lateral_speed - flow) * exp(-tuning.rolling_resistance * dt)
	var cap := tuning.max_lateral_speed + absf(flow)
	lateral_speed = clampf(lateral_speed, -cap, cap)
	angle = TunnelMath.wrap_angle_positive(angle + lateral_speed * dt / level.tunnel_radius)


func _step_rolling(dt: float, input: InputFrame, events: Array[SimEvent]) -> void:
	if _ground_actions(input, events):
		return

	_time_since_landing += dt
	if not _landing_resolved and _time_since_landing > tuning.echo_grace_time:
		_landing_resolved = true
		if echo_chain > 0:
			var broken := SimEvent.new(EventType.CHAIN_BROKEN, s, angle)
			broken.chain = echo_chain
			events.append(broken)
		echo_chain = 0

	if _hole_under_ball() != null:
		# The ground is gone: start to drop. Gravity and the cut decide the rest.
		phase = Phase.AIRBORNE
		vertical_speed = 0.0
		_time_unsupported = 0.0


## Jumps and echoes that need the ball to be on (or just off) the ground.
## Returns true if the ball jumped.
func _ground_actions(input: InputFrame, events: Array[SimEvent]) -> bool:
	var in_grace := not _landing_resolved and _time_since_landing <= tuning.echo_grace_time
	if input.tap and in_grace and last_jump_height > 0.0:
		_landing_resolved = true
		_start_echo(_time_since_landing <= tuning.perfect_window, events)
		return true
	if input.has_jump():
		_landing_resolved = true
		echo_chain = 0
		_jump(jump_height_for_strength(input.jump_strength), false, false, events)
		return true
	return false


func _step_airborne(dt: float, input: InputFrame, events: Array[SimEvent]) -> void:
	# Coyote time: just after rolling off an edge, still accept a jump.
	if _time_unsupported < tuning.coyote_time:
		_time_unsupported += dt
		if _ground_actions(input, events):
			return

	var landing_in := time_to_land()
	if input.tap and last_jump_height > 0.0 and not _echo_queued and landing_in <= tuning.echo_buffer_time:
		_echo_queued = true
		_echo_queued_perfect = landing_in <= tuning.perfect_window
	if input.has_jump() and landing_in <= tuning.jump_buffer_time:
		_buffered_jump_strength = input.jump_strength

	vertical_speed -= tuning.gravity * dt
	height += vertical_speed * dt

	var hole := _hole_under_ball()
	if hole != null:
		# No floor under the centre: the ball keeps dropping, and only the
		# walls of the cut can stop it.
		var before := _velocity()
		var contact := _collide_with_cut(hole)
		if contact != Vector3.ZERO and contact.z < POP_NORMAL:
			# Side-on into the wall of the cut: a crash, the run is over.
			_lose(hole, events)
			_report_bump(before, events)
		elif height + tuning.ball_radius < -LOST_DEPTH:
			_lose(hole, events)
		return
	if height > 0.0:
		return

	# Touchdown.
	height = 0.0
	vertical_speed = 0.0
	_time_unsupported = INF

	var landed := SimEvent.new(EventType.LANDED, s, angle)
	landed.echo = _echo_queued
	landed.chain = echo_chain
	events.append(landed)

	if _echo_queued:
		var perfect := _echo_queued_perfect
		_echo_queued = false
		_start_echo(perfect, events)
	elif _buffered_jump_strength >= 0.0:
		var strength := _buffered_jump_strength
		_buffered_jump_strength = -1.0
		echo_chain = 0
		_jump(jump_height_for_strength(strength), false, false, events)
	else:
		phase = Phase.ROLLING
		_time_since_landing = 0.0
		_landing_resolved = false


## The echo's hit-stop: on the floor, nothing moves. A swipe ends it early
## and sets the height; otherwise the last jump is repeated when it ends.
func _start_echo(perfect: bool, events: Array[SimEvent]) -> void:
	phase = Phase.FROZEN
	height = 0.0
	vertical_speed = 0.0
	_freeze_left = tuning.echo_freeze_time
	_freeze_elapsed = 0.0
	_freeze_perfect = perfect
	var hit := SimEvent.new(EventType.ECHO_HIT, s, angle)
	hit.perfect = perfect
	hit.chain = echo_chain + 1
	hit.height = last_jump_height
	events.append(hit)
	if _freeze_left <= 0.0:
		_jump(last_jump_height, true, perfect, events)


func _step_frozen(dt: float, input: InputFrame, events: Array[SimEvent]) -> void:
	_freeze_left -= dt
	_freeze_elapsed += dt
	if input.has_jump():
		_jump(jump_height_for_strength(input.jump_strength), true, _freeze_perfect, events)
		return
	# A finger still down may be the start of a swipe: wait for it, a little.
	var waiting_for_swipe := input.holding and _freeze_elapsed < tuning.echo_freeze_max
	if _freeze_left <= 0.0 and not waiting_for_swipe:
		_jump(last_jump_height, true, _freeze_perfect, events)


func _step_falling(dt: float, events: Array[SimEvent]) -> void:
	# Beyond the wall the ball keeps falling "down", i.e. out of the tunnel,
	# but it cannot pass through the walls of the cut on its way.
	vertical_speed -= tuning.gravity * dt
	height += vertical_speed * dt
	if _fall_hole != null:
		var before := _velocity()
		if _collide_with_cut(_fall_hole) != Vector3.ZERO:
			_report_bump(before, events)


func _velocity() -> Vector3:
	return Vector3(forward_speed, lateral_speed, vertical_speed)


func _report_bump(before: Vector3, events: Array[SimEvent]) -> void:
	var impact := (before - _velocity()).length()
	if impact > 1.0:
		var bump := SimEvent.new(EventType.BUMPED, s, angle)
		bump.height = impact
		events.append(bump)


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
	var flipped := false
	if echo:
		echo_chain += 1
		# The echo turns the tunnel around: spin changes direction.
		if absf(level.spin_at(s)) > SPIN_FLIP_THRESHOLD:
			spin_direction = -spin_direction
			flipped = true
	phase = Phase.AIRBORNE
	vertical_speed = sqrt(2.0 * tuning.gravity * jump_height)
	_buffered_jump_strength = -1.0
	_time_unsupported = INF
	var jumped := SimEvent.new(EventType.JUMPED, s, angle)
	jumped.height = jump_height
	jumped.echo = echo
	jumped.perfect = perfect
	jumped.chain = echo_chain
	jumped.spin_flipped = flipped
	events.append(jumped)


## The hole under the ball's centre, if it is far enough inside to drop.
func _hole_under_ball() -> HoleData:
	var margin := tuning.hole_forgiveness
	return level.hole_at(s, angle, margin, margin)


func _lose(hole: HoleData, events: Array[SimEvent]) -> void:
	phase = Phase.FALLING
	_fall_hole = hole
	echo_chain = 0
	events.append(SimEvent.new(EventType.FELL, s, angle))


## Pushes the ball out of the solid walls around `hole` and bounces it.
##
## Works in the hole's local frame: u along the tunnel (= s), v along the
## wall (arc length from the hole's centre line), c the height of the ball's
## centre above the inner surface. The shell occupies -T <= c <= 0 outside
## the hole's rectangle; each of the four sides is tested only where the
## shell really is solid (an adjacent hole may continue the opening).
## The bounce changes all three speeds; while the ball is alive the next
## step puts the forward speed back to the level's.
## Returns the normal (u, v, c) of the deepest contact, or ZERO.
func _collide_with_cut(hole: HoleData) -> Vector3:
	var radius := tuning.ball_radius
	var r := level.tunnel_radius
	var center := Vector3(s, TunnelMath.angle_difference(angle, hole.angle_center) * r, height + radius)
	if center.z >= radius:
		return Vector3.ZERO
	var velocity := Vector3(forward_speed, lateral_speed, vertical_speed)
	var depth_point := clampf(center.z, -TunnelMath.WALL_THICKNESS, 0.0)
	var half_width := hole.angle_width * 0.5 * r
	var probe := 0.05

	# (closest solid point, fallback normal) for each side that is solid.
	var sides: Array = []
	if level.hole_at(hole.s_start - probe, angle) == null:
		sides.append([Vector3(hole.s_start, center.y, depth_point), Vector3(1, 0, 0)])
	if level.hole_at(hole.s_end() + probe, angle) == null:
		sides.append([Vector3(hole.s_end(), center.y, depth_point), Vector3(-1, 0, 0)])
	if hole.angle_width < TAU - 0.001:
		if level.hole_at(s, hole.angle_center - (half_width + probe) / r) == null:
			sides.append([Vector3(center.x, -half_width, depth_point), Vector3(0, 1, 0)])
		if level.hole_at(s, hole.angle_center + (half_width + probe) / r) == null:
			sides.append([Vector3(center.x, half_width, depth_point), Vector3(0, -1, 0)])

	var deepest := Vector3.ZERO
	var deepest_penetration := 0.0
	for side in sides:
		var point: Vector3 = side[0]
		var offset := center - point
		var distance := offset.length()
		if distance >= radius:
			continue
		var normal: Vector3 = side[1] if distance < 0.00001 else offset / distance
		var penetration := radius - distance
		center += normal * penetration
		var into := velocity.dot(normal)
		if into < 0.0:
			var tangent := velocity - normal * into
			velocity = tangent * 0.9 - normal * into * tuning.wall_restitution
		if penetration > deepest_penetration:
			deepest_penetration = penetration
			deepest = normal

	if deepest == Vector3.ZERO:
		return deepest
	s = center.x
	angle = TunnelMath.wrap_angle_positive(hole.angle_center + center.y / r)
	height = center.z - radius
	forward_speed = velocity.x
	lateral_speed = velocity.y
	vertical_speed = velocity.z
	return deepest
