class_name LevelGenerator
extends RefCounted
## Builds deterministic levels from an authored *script* of sections.
##
## This is an authoring tool, not part of the runtime: tools/generate_levels.gd
## runs it once and writes JSON into res://levels/. The game then loads those
## files like any other level, so generated and hand-made (or future
## editor-made) levels are indistinguishable.
##
## A level is a list of sections played in order, each naming a pattern, how
## many of it, how intense it is and (optionally) what the ground spin does
## from there on. Randomness (seeded) only varies details inside a pattern,
## so every level has a designed shape: teach, combine, test, release.
##
## The generator keeps track of a "safe path": the angle around the tunnel
## where solid ground is guaranteed. Patterns cut holes around that path and
## then let it wander, at a rate the ball can physically follow, so the route
## spirals around the tunnel and the camera rotation becomes part of the game.

const REFERENCE_SPEED := 12.0
## The shortest hole worth cutting: shorter ones can be skimmed at speed.
const MIN_HOLE := 3.0

## Pattern names, also used in docs/GAME_DESIGN.md.
const PATTERNS := ["gate", "ring", "echo_run", "bridge", "split", "slalom", "corkscrew",
	"funnel", "combo", "pad_run", "rest"]

var _rng := RandomNumberGenerator.new()
var _level: LevelData
var _tuning: BallTuning
var _path_angle: float = 0.0
## How far (radians) from the path the player may be when a pattern starts
## (a split lets them be a quarter-turn away on either side).
var _spread: float = 0.0
## Where the previous pattern ended: the ground before the next one starts.
var _last_end: float = 0.0
var _spin_rate: float = 0.0
## Where the script ran out, if it did (for tuning section lists).
var script_end: float = INF
## How many sections fitted before the outro.
var sections_used: int = 0
## Prints where each section starts and how long it lasts.
var verbose := false


class Spec:
	var id: String
	var display_name: String
	var seed: int = 1
	var duration_seconds: float = 60.0
	var base_speed: float = 11.0
	var speed_ramp: float = 0.2
	var tunnel_radius: float = 4.0
	## Seconds of empty tunnel at the start, to settle in.
	var intro_seconds: float = 3.5
	## The level, in order. Each section is a Dictionary:
	##   p      pattern name (see PATTERNS)
	##   n      how many (gates, rings, bounces, segments…; pattern-specific)
	##   i      intensity 0..1 (gap widths, lengths, spacing)
	##   spin   ground spin (°/s) from this section on; omitted = unchanged
	##   ramp   seconds over which the spin changes (default 0.8, 0 = a snap)
	##   rest   seconds of plain floor after the section (default from i)
	##   secs   for "rest": how long
	var sections: Array[Dictionary] = []
	var palette: Array[PaletteStop] = []


func generate(spec: Spec, tuning: BallTuning) -> LevelData:
	_rng.seed = spec.seed
	_tuning = tuning
	_path_angle = 0.0
	_spread = 0.0
	_last_end = 0.0
	_spin_rate = 0.0
	script_end = INF
	sections_used = 0

	_level = LevelData.new()
	_level.id = spec.id
	_level.display_name = spec.display_name
	_level.base_speed = spec.base_speed
	_level.speed_ramp = spec.speed_ramp
	_level.tunnel_radius = spec.tunnel_radius
	_level.length = roundf(SpeedProfile.length_for_duration(spec.duration_seconds, spec.base_speed, spec.speed_ramp))
	_level.palette = spec.palette
	_level.spin = []

	var s := spec.base_speed * spec.intro_seconds
	var end := _level.length - spec.base_speed * 2.5  # quiet outro: enjoy the colour
	for section in spec.sections:
		if s >= end:
			break
		var intensity: float = section.get("i", 0.5)
		if section.has("spin"):
			_set_spin(s, float(section["spin"]), float(section.get("ramp", 0.8)))
		var section_start := s
		s = _place(section, s, intensity)
		_last_end = s
		sections_used += 1
		if verbose:
			print("    %-10s n=%-2d i=%.2f  %5.1f s  %4.1f s long" % [section.get("p", "gate"), section.get("n", 1), intensity,
				_level.progress_at(section_start) * spec.duration_seconds, (s - section_start) / _level.speed_at(s)])
		var rest: float = section.get("rest", lerpf(1.1, 0.55, intensity))
		s += _level.speed_at(s) * rest
	if s < end:
		script_end = s

	_level.holes = _level.holes.filter(func(h: HoleData) -> bool: return h.s_end() < end + 1.0)
	_level.spin = _level.spin.filter(func(k: SpinKey) -> bool: return k.s <= _level.length)
	_level.sort()
	return _level


func _set_spin(s: float, rate: float, ramp_seconds: float) -> void:
	var ramp := maxf(_level.speed_at(s) * ramp_seconds, 0.5)
	_level.spin.append(SpinKey.new(s, _spin_rate))
	_level.spin.append(SpinKey.new(s + ramp, rate))
	_spin_rate = rate


func _place(section: Dictionary, s: float, intensity: float) -> float:
	var n: int = section.get("n", 1)
	match section.get("p", "gate"):
		"rest":
			return s + _level.speed_at(s) * float(section.get("secs", 1.0))
		"ring":
			return _repeat(n, s, intensity, _place_ring, lerpf(1.0, 0.6, intensity))
		"echo_run":
			return _place_echo_run(s, intensity, n, false)
		"pad_run":
			return _place_echo_run(s, intensity, n, true)
		"bridge":
			return _place_bridge(s, intensity, n, false)
		"corkscrew":
			return _place_bridge(s, intensity, n, true)
		"split":
			return _repeat(n, s, intensity, _place_split, lerpf(0.9, 0.55, intensity))
		"slalom":
			return _place_slalom(s, intensity, n)
		"funnel":
			return _place_funnel(s, intensity, n)
		"combo":
			return _repeat(n, s, intensity, _place_combo, lerpf(0.9, 0.5, intensity))
		_:
			return _repeat(n, s, intensity, _place_gate, lerpf(0.85, 0.45, intensity))


## Places `n` copies of a single-shot pattern with `gap_seconds` of floor between them.
func _repeat(n: int, s: float, intensity: float, place: Callable, gap_seconds: float) -> float:
	for k in n:
		s = place.call(s, intensity)
		_last_end = s
		if k < n - 1:
			s += _level.speed_at(s) * gap_seconds
	return s


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
## `slack` is how much of that turn the gap's own width forgives. Assumes a
## sideways acceleration well under the tilt maximum (more of it on intense
## stretches), reduced by what it takes to hold against the spin.
func _ensure_lead(s: float, change: float, intensity: float = 0.3, slack: float = 0.0) -> float:
	var turn := maxf(absf(change) - slack, deg_to_rad(8.0)) + _spread
	var arc := turn * _level.tunnel_radius
	var spin_hold := absf(deg_to_rad(_spin_rate)) * _level.tunnel_radius * _tuning.rolling_resistance
	var comfortable_acceleration := maxf(lerpf(5.5, 8.5, intensity) - spin_hold * 0.5, 3.0)
	var seconds := 2.0 * sqrt(arc / comfortable_acceleration) + 0.2
	var needed := _last_end + _level.speed_at(s) * seconds
	return maxf(s, needed)


func _speed_scale(s: float) -> float:
	return _level.speed_at(s) / REFERENCE_SPEED


func _add_hole(s: float, length: float, center: float, width: float) -> void:
	_level.holes.append(HoleData.new(s, length, center, minf(width, TAU)))


func _degrees(min_degrees: float, max_degrees: float, intensity: float) -> float:
	return deg_to_rad(lerpf(min_degrees, max_degrees, intensity))


## A wide hole with one gap: steer into the gap.
func _place_gate(s: float, intensity: float) -> float:
	var previous := _path_angle
	_drift_path(_level.speed_at(s) * 1.0, intensity)
	var gap := deg_to_rad(lerpf(170.0, 70.0, intensity) + _rng.randf_range(-12.0, 12.0))
	s = _ensure_lead(s, TunnelMath.angle_difference(_path_angle, previous), intensity, gap * 0.3)
	_spread = 0.0
	var length := lerpf(4.0, 8.0, _rng.randf()) * _speed_scale(s)
	_add_hole(s, length, _path_angle + PI, TAU - gap)
	return s + length


## A full ring: the only way through is up.
func _place_ring(s: float, intensity: float) -> float:
	var length := maxf(lerpf(2.6, 5.4, intensity * _rng.randf_range(0.7, 1.0)) * _speed_scale(s), MIN_HOLE)
	_add_hole(s, length, 0.0, TAU)
	_spread = 0.0
	return s + length


## Evenly spaced rings matched to one jump: swipe once, then tap on each
## landing to echo through the whole run. The signature pattern.
## The spacing is tuned to the *highest* jump on purpose: any long swipe
## produces exactly that height (strength clamps at 1), so a player can
## reproduce it reliably, while a mid-size jump would be guesswork.
##
## With `pads`, the landing strips are not full rings of floor but pads
## around the path, which wanders from pad to pad: each echo must also land
## on target, and with spin on, each echo flips the push mid-run.
func _place_echo_run(s: float, intensity: float, count: int, pads: bool) -> float:
	var echo_height := _tuning.max_jump_height
	var air_time := 2.0 * sqrt(2.0 * echo_height / _tuning.gravity)
	if pads:
		s = _ensure_lead(s, 0.0, intensity)
	_spread = 0.0
	var pad_width := _degrees(125.0, 84.0, intensity)
	for i in count:
		var period := _level.speed_at(s) * air_time
		var landing := lerpf(4.4, 3.2, intensity) * _speed_scale(s)
		var hole_length := period - landing
		# Hole sits in the middle of the jump arc, leaving a landing strip.
		_add_hole(s + landing * 0.5, hole_length, 0.0, TAU)
		if pads and i < count - 1:
			# The next landing strip becomes a pad, a little further round.
			var shift := _degrees(8.0, 22.0, intensity) * (1.0 if _rng.randf() < 0.5 else -1.0)
			_path_angle = TunnelMath.wrap_angle_positive(_path_angle + shift)
			_add_hole(s + landing * 0.5 + hole_length, landing, _path_angle + PI, TAU - pad_width)
		s += period
	return s


## A narrow strip of floor that winds around the tunnel. As a corkscrew it
## keeps turning one way, fast enough to need a constant lean.
func _place_bridge(s: float, intensity: float, segments: int, corkscrew: bool) -> float:
	var gap := _degrees(110.0, 64.0, intensity) if not corkscrew else _degrees(125.0, 80.0, intensity)
	# Short segments with small steps, so the edge reads as a smooth curve
	# rather than a staircase. `segments` counts 1.25 m-equivalent lengths.
	segments *= 2
	var segment_length := 0.625 * _speed_scale(s)
	var direction := 1.0 if _rng.randf() < 0.5 else -1.0
	var turn_per_segment := 0.0
	if corkscrew:
		var lateral := lerpf(2.6, 4.4, intensity)  # m/s along the wall
		turn_per_segment = lateral * (segment_length / _level.speed_at(s)) / _level.tunnel_radius * direction
	else:
		turn_per_segment = _max_drift(segment_length, intensity) * _rng.randf_range(0.35, 0.8) * direction
	s = _ensure_lead(s, 0.0, intensity)
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
	var gap := _degrees(110.0, 70.0, intensity)
	s = _ensure_lead(s, absf(TunnelMath.angle_difference(_path_angle, previous)) + PI * 0.5, intensity, gap * 0.4)
	var length := lerpf(5.0, 8.0, _rng.randf()) * _speed_scale(s)
	var blocker := PI - gap
	_add_hole(s, length, _path_angle, blocker)
	_add_hole(s, length, _path_angle + PI, blocker)
	# The next pattern must allow for the player being on either side.
	_spread = PI * 0.25
	return s + length


## Gates whose gaps alternate either side of the path, in a steady beat:
## a rhythm of leaning left, right, left.
func _place_slalom(s: float, intensity: float, count: int) -> float:
	var offset := _degrees(38.0, 52.0, intensity)
	var gap := _degrees(130.0, 88.0, intensity)
	var center := _path_angle
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	_path_angle = TunnelMath.wrap_angle_positive(center + offset * side)
	s = _ensure_lead(s, offset, intensity, gap * 0.3)
	_spread = 0.0
	for i in count:
		var length := lerpf(3.2, 4.4, _rng.randf()) * _speed_scale(s)
		_add_hole(s, length, _path_angle + PI, TAU - gap)
		s += length
		if i < count - 1:
			side = -side
			var previous := _path_angle
			_path_angle = TunnelMath.wrap_angle_positive(center + offset * side)
			_last_end = s
			# Only the part of the swing the two gaps do not overlap must be steered.
			s = _ensure_lead(s + _level.speed_at(s) * 0.12, TunnelMath.angle_difference(_path_angle, previous), intensity, gap * 0.75)
	return s


## Gates back to back whose gap narrows: aim early, then hold the line.
func _place_funnel(s: float, intensity: float, count: int) -> float:
	s = _ensure_lead(s, 0.0, intensity)
	_spread = 0.0
	var wide := _degrees(160.0, 115.0, intensity)
	var narrow := _degrees(95.0, 62.0, intensity)
	for i in count:
		var length := 3.0 * _speed_scale(s)
		var t := float(i) / maxf(count - 1, 1)
		_add_hole(s, length, _path_angle + PI, TAU - lerpf(wide, narrow, t))
		s += length
		_path_angle = TunnelMath.wrap_angle_positive(_path_angle + _max_drift(length, intensity) * 0.3 * _rng.randf_range(-1.0, 1.0))
	return s


## A ring, then a gate right where the ball lands, with its gap off to one
## side: steer in the air to land lined up.
func _place_combo(s: float, intensity: float) -> float:
	s = _ensure_lead(s, 0.0, intensity)
	var ring_length := maxf(lerpf(3.0, 5.0, intensity) * _speed_scale(s), MIN_HOLE)
	_add_hole(s, ring_length, 0.0, TAU)
	s += ring_length
	var turn := _degrees(30.0, 55.0, intensity)
	_path_angle = TunnelMath.wrap_angle_positive(_path_angle + turn * (1.0 if _rng.randf() < 0.5 else -1.0))
	# Room to land, then the gate. Steering starts before the jump (the gap
	# is in plain view) and continues, weaker, in the air; the whole turn
	# must fit between the previous pattern and the gate.
	var gap := _degrees(120.0, 80.0, intensity)
	s += _level.speed_at(s) * lerpf(0.75, 0.5, intensity)
	s = _ensure_lead(s, turn, intensity, gap * 0.3)
	var length := lerpf(4.0, 6.0, _rng.randf()) * _speed_scale(s)
	_add_hole(s, length, _path_angle + PI, TAU - gap)
	_spread = 0.0
	return s + length
