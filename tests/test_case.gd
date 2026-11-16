class_name TestCase
extends RefCounted
## Minimal base class for tests: subclass it, add `func test_something()`.
## Kept dependency-free on purpose; swap for GUT/gdUnit4 if the suite grows.

var failures: PackedStringArray = []
var _current := ""


func assert_true(condition: bool, message: String = "expected true") -> void:
	if not condition:
		failures.append("%s: %s" % [_current, message])


func assert_false(condition: bool, message: String = "expected false") -> void:
	assert_true(not condition, message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s %s" % [_current, expected, actual, message])


func assert_near(actual: float, expected: float, tolerance: float, message: String = "") -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s: expected %.4f ± %.4f, got %.4f %s" % [_current, expected, tolerance, actual, message])


## Shared fixtures --------------------------------------------------------------

static func make_level(holes: Array[HoleData] = []) -> LevelData:
	var level := LevelData.new()
	level.id = "test"
	level.display_name = "Test"
	level.length = 600.0
	level.tunnel_radius = 4.0
	level.base_speed = 10.0
	level.speed_ramp = 0.2
	level.palette = [PaletteStop.new(0.0), PaletteStop.new(1.0)]
	level.holes = holes
	level.sort()
	return level


static func make_tuning() -> BallTuning:
	return BallTuning.new()


## Steps a simulation for `seconds` with a constant input, returning all events.
static func run(sim: BallSimulation, seconds: float, input: InputFrame = InputFrame.new()) -> Array:
	var events := []
	var dt := 1.0 / 120.0
	var steps := int(round(seconds / dt))
	for i in steps:
		events.append_array(sim.step(dt, input))
	return events


static func count(events: Array, type: BallSimulation.EventType) -> int:
	return events.filter(func(e: BallSimulation.SimEvent) -> bool: return e.type == type).size()
