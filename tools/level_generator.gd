class_name LevelGenerator
extends RefCounted
## Builds hand-tunable, deterministic levels out of reusable *patterns*.
##
## This is an authoring tool, not part of the runtime: tools/generate_levels.gd
## runs it once and writes JSON into res://levels/. The game then loads those
## files like any other level, so generated and hand-made (or future
## editor-made) levels are indistinguishable.
##
## The generator keeps track of a "safe path": the angle around the tunnel
## where solid ground is guaranteed. Patterns cut holes around that path and
## then let it wander, at a rate the ball can physically follow, so the route
## spirals around the tunnel and the camera rotation becomes part of the game.

const REFERENCE_SPEED := 12.0

## Pattern names, also used in docs/GAME_DESIGN.md.
const PATTERNS := ["gate", "ring", "echo_run", "bridge", "split"]

var _rng := RandomNumberGenerator.new()
var _level: LevelData
var _tuning: BallTuning
var _difficulty: float
var _path_angle: float = 0.0
## How far (radians) from the path the player may be when a pattern starts
## (a split lets them be a quarter-turn away on either side).
var _spread: float = 0.0
## Where the previous pattern ended: the ground before the next one starts.
var _last_end: float = 0.0


class Spec:
	var id: String
	var display_name: String
	var seed: int = 1
	var duration_seconds: float = 60.0
	var base_speed: float = 11.0
	var speed_ramp: float = 0.2
	var tunnel_radius: float = 4.0
	## 0 = gentle, 1 = demanding.
	var difficulty: float = 0.5
	## Pattern weights at full intensity; missing patterns are not used.
	var pattern_weights: Dictionary = {"gate": 3.0, "ring": 2.0, "echo_run": 1.5, "bridge": 1.5, "split": 1.0}
	var palette: Array[PaletteStop] = []


func generate(spec: Spec, tuning: BallTuning) -> LevelData:
	_rng.seed = spec.seed
	_tuning = tuning
	_difficulty = clampf(spec.difficulty, 0.0, 1.0)
	_path_angle = 0.0
	_spread = 0.0
	_last_end = 0.0

	_level = LevelData.new()
	_level.id = spec.id
	_level.display_name = spec.display_name
	_level.base_speed = spec.base_speed
	_level.speed_ramp = spec.speed_ramp
	_level.tunnel_radius = spec.tunnel_radius
	_level.length = roundf(SpeedProfile.length_for_duration(spec.duration_seconds, spec.base_speed, spec.speed_ramp))
	_level.palette = spec.palette

	var s := spec.base_speed * 3.5          # quiet intro: learn the tilt
	var end := _level.length - spec.base_speed * 2.5  # quiet outro: enjoy the colour
	var since_breather := 0.0
	while s < end:
		var intensity := _intensity_at(s)
		var pattern := _pick_pattern(spec.pattern_weights, intensity)
		var start := s
		s = _place(pattern, s, intensity)
		_last_end = s
		since_breather += (s - start) / _level.speed_at(s)
		# Solid ground between patterns, shorter as the level heats up.
		s += _level.speed_at(s) * lerpf(1.15, 0.5, intensity)
		if since_breather > lerpf(9.0, 14.0, _difficulty):
			s += _level.speed_at(s) * 1.6
			since_breather = 0.0

	_level.holes = _level.holes.filter(func(h: HoleData) -> bool: return h.s_end() < end + 1.0)
	_level.sort()
	return _level


## Difficulty felt at distance s: rises across the level, eased at the start.
func _intensity_at(s: float) -> float:
	var progress := _level.progress_at(s)
	return clampf(_difficulty * (0.45 + 0.55 * smoothstep(0.0, 0.85, progress)), 0.0, 1.0)


func _pick_pattern(weights: Dictionary, intensity: float) -> String:
	var adjusted := {}
	var total := 0.0
	for pattern in weights:
		var w: float = weights[pattern]
		# Complex patterns fade in with intensity; gates are always available.
		if pattern in ["echo_run", "bridge", "split"]:
			w *= smoothstep(0.15, 0.55, intensity)
		adjusted[pattern] = w
		total += w
	var roll := _rng.randf() * total
	for pattern in adjusted:
		roll -= adjusted[pattern]
		if roll <= 0.0:
			return pattern
	return "gate"


func _place(pattern: String, s: float, intensity: float) -> float:
	match pattern:
		"ring":
			return _place_ring(s, intensity)
		"echo_run":
			return _place_echo_run(s, intensity)
		"bridge":
			return _place_bridge(s, intensity)
		"split":
			return _place_split(s, intensity)
		_:
			return _place_gate(s, intensity)


## How far (radians) the safe path may drift over `distance` metres of tunnel,
## keeping lateral speed well below what tilt can deliver.
func _max_drift(distance: float, intensity: float) -> float:
	var comfortable_lateral := lerpf(2.5, 5.0, intensity)  # m/s
	var seconds := distance / _level.speed_at(0.0)
	return comfortable_lateral * seconds / _level.tunnel_radius


func _drift_path(distance: float, intensity: float) -> void:
	var limit := _max_drift(distance, intensity)
	_path_angle = TunnelMath.wrap_angle_positive(_path_angle + _rng.randf_range(-limit, limit))


## Moves a pattern start later if the player needs more ground to steer
## from anywhere they might be to an angle `change` radians from the path.
## Assumes a comfortable sideways acceleration well under the tilt maximum.
func _ensure_lead(s: float, change: float) -> float:
	var arc := (absf(change) + _spread) * _level.tunnel_radius
	var comfortable_acceleration := 5.5  # m/s², about 40% of full tilt
	var seconds := 2.0 * sqrt(arc / comfortable_acceleration) + 0.25
	var needed := _last_end + _level.speed_at(s) * seconds
	return maxf(s, needed)


func _speed_scale(s: float) -> float:
	return _level.speed_at(s) / REFERENCE_SPEED


func _add_hole(s: float, length: float, center: float, width: float) -> void:
	_level.holes.append(HoleData.new(s, length, center, minf(width, TAU)))


## A wide hole with one gap: steer into the gap.
func _place_gate(s: float, intensity: float) -> float:
	var previous := _path_angle
	_drift_path(_level.speed_at(s) * 1.0, intensity)
	s = _ensure_lead(s, TunnelMath.angle_difference(_path_angle, previous))
	_spread = 0.0
	var gap := deg_to_rad(lerpf(170.0, 72.0, intensity) + _rng.randf_range(-12.0, 12.0))
	var length := lerpf(4.0, 8.0, _rng.randf()) * _speed_scale(s)
	_add_hole(s, length, _path_angle + PI, TAU - gap)
	return s + length


## A full ring: the only way through is up.
func _place_ring(s: float, intensity: float) -> float:
	var length := lerpf(2.6, 5.4, intensity * _rng.randf_range(0.7, 1.0)) * _speed_scale(s)
	_add_hole(s, length, 0.0, TAU)
	return s + length


## Evenly spaced rings matched to one jump: swipe once, then tap on each
## landing to echo through the whole run. The signature pattern.
## The spacing is tuned to the *highest* jump on purpose: any long swipe
## produces exactly that height (strength clamps at 1), so a player can
## reproduce it reliably, while a mid-size jump would be guesswork.
func _place_echo_run(s: float, intensity: float) -> float:
	var count := 3 + int(round(intensity * 3.0 * _rng.randf_range(0.6, 1.0)))
	var echo_height := _tuning.max_jump_height
	var air_time := 2.0 * sqrt(2.0 * echo_height / _tuning.gravity)
	for i in count:
		var period := _level.speed_at(s) * air_time
		var landing := lerpf(4.4, 3.2, intensity) * _speed_scale(s)
		var hole_length := period - landing
		# Hole sits in the middle of the jump arc, leaving a landing strip.
		_add_hole(s + landing * 0.5, hole_length, 0.0, TAU)
		s += period
	return s


## A narrow strip of ground that winds around the tunnel.
func _place_bridge(s: float, intensity: float) -> float:
	var segments := 4 + int(round(intensity * 5.0))
	var gap := deg_to_rad(lerpf(110.0, 64.0, intensity))
	var segment_length := 2.4 * _speed_scale(s)
	var direction := 1.0 if _rng.randf() < 0.5 else -1.0
	var turn_per_segment := _max_drift(segment_length, intensity) * _rng.randf_range(0.35, 0.8) * direction
	s = _ensure_lead(s, 0.0)
	_spread = 0.0
	for i in segments:
		_add_hole(s, segment_length, _path_angle + PI, TAU - gap)
		s += segment_length
		_path_angle = TunnelMath.wrap_angle_positive(_path_angle + turn_per_segment)
	return s


## Two gaps on opposite sides, each a quarter-turn from the path: a choice
## between left and right, and both rejoin the path afterwards.
func _place_split(s: float, intensity: float) -> float:
	var previous := _path_angle
	_drift_path(_level.speed_at(s), intensity)
	s = _ensure_lead(s, TunnelMath.angle_difference(_path_angle, previous) + PI * 0.5)
	var gap := deg_to_rad(lerpf(110.0, 70.0, intensity))
	var length := lerpf(5.0, 8.0, _rng.randf()) * _speed_scale(s)
	var blocker := PI - gap
	_add_hole(s, length, _path_angle, blocker)
	_add_hole(s, length, _path_angle + PI, blocker)
	_spread = PI * 0.5
	return s + length
