class_name LevelAnalysis
extends RefCounted
## Everything the editor works out about a level so the designer does not
## have to play it to know: where bots with different reflexes go and fall,
## which stretches must be jumped and whether they can be, and where the
## floor is narrow.
##
## The game's rules are deterministic and node-free (BallSimulation), so the
## editor can simply *play the level* in the background, many times faster
## than real time, with the same Autopilot the tests use. Its
## `steering_delay` (how late it reacts) is the project's difficulty
## measure: a level the 0.35 s bot finishes is relaxed, one only the 0 s
## bot finishes is for experts (see docs/LEVEL_EDITOR.md).
##
## Work runs on threads, on a private copy of the level, and restarts after
## every edit. Restarts are incremental: each bot saves its full state every
## SNAPSHOT_EVERY metres, and an edit at distance s resumes from the last
## snapshot safely before s (the bot looks up to ~60 m ahead, so anything
## earlier cannot have been influenced by the edit). Results stream in, so
## the ghost paths grow up the strip while you watch.

## How late each analysis bot reacts (s). Keep in step with BOT_NAMES.
const BOT_DELAYS: Array[float] = [0.0, 0.2, 0.35]
const BOT_NAMES: PackedStringArray = ["Instant bot (0 s)", "Quick bot (0.2 s)", "Relaxed bot (0.35 s)"]
const SNAPSHOT_EVERY := 20.0
## Resume this far before an edit, at least (the bot's lookahead plus margin).
const RESUME_MARGIN := 90.0
const STEP := 1.0 / 120.0
## Floor narrower than this (m of free arc) is flagged as tight.
const TIGHT_WIDTH := 1.8
## A rolling bot whose centre comes this close to an edge (m) had a near miss.
const NEAR_MISS := 0.45

## Bot event kinds stored in BotTrace.marks (z component).
enum Mark { JUMP, ECHO, NEAR_MISS }


class BotTrace:
	var delay := 0.0
	## (s, angle, 1 if airborne else 0), every ~0.4 m.
	var points := PackedVector3Array()
	## (s, angle, Mark).
	var marks := PackedVector3Array()
	## "running", "finished" or "fell".
	var outcome := "running"
	var end_s := 0.0
	var end_angle := 0.0
	var snapshots: Array[Dictionary] = []

	func copy() -> BotTrace:
		var other := BotTrace.new()
		other.delay = delay
		other.points = points
		other.marks = marks
		other.outcome = outcome
		other.end_s = end_s
		other.end_angle = end_angle
		other.snapshots = snapshots.duplicate()
		return other

	## Where this bot was at distance s (NAN if it never got there).
	func angle_at(s: float) -> float:
		if points.is_empty() or s > points[points.size() - 1].x:
			return NAN
		var lo := 0
		var hi := points.size() - 1
		while lo < hi:
			var mid := (lo + hi) >> 1
			if points[mid].x < s:
				lo = mid + 1
			else:
				hi = mid
		return points[lo].y


var tuning: BallTuning
var bots: Array[BotTrace] = []
var report: LevelValidator.Report = null
## Bumped by every request; workers of an older generation stop.
var generation := 0
## True while any worker is still busy.
var busy := false

var _mutex := Mutex.new()
var _threads: Array[Thread] = []
var _published: Array[BotTrace] = []
var _published_report: LevelValidator.Report = null
var _fresh := false


func _init(p_tuning: BallTuning) -> void:
	tuning = p_tuning
	for delay in BOT_DELAYS:
		var trace := BotTrace.new()
		trace.delay = delay
		bots.append(trace)
		_published.append(trace.copy())


## Starts (re)analysing `level` from distance `from_s` on. Cheap to call
## often; the editor calls it a few times a second while dragging.
func request(level: LevelData, from_s: float) -> void:
	_stop_workers()
	generation += 1
	var data := LevelSerializer.to_dict(level)
	var resume_before := from_s - RESUME_MARGIN
	busy = true
	for i in bots.size():
		var trace := bots[i]
		var snapshot := {}
		while not trace.snapshots.is_empty() and trace.snapshots[trace.snapshots.size() - 1]["s"] > resume_before:
			trace.snapshots.pop_back()
		if not trace.snapshots.is_empty():
			snapshot = trace.snapshots[trace.snapshots.size() - 1]
		var start := BotTrace.new()
		start.delay = trace.delay
		start.snapshots = trace.snapshots.duplicate()
		if not snapshot.is_empty():
			start.points = trace.points.slice(0, snapshot["points"])
			start.marks = trace.marks.slice(0, snapshot["marks"])
		var thread := Thread.new()
		thread.start(_run_bot.bind(data, i, start, snapshot, generation))
		_threads.append(thread)
	var static_thread := Thread.new()
	static_thread.start(_run_report.bind(data, generation))
	_threads.append(static_thread)


## Call every frame. Returns true when new results arrived since last call.
func poll() -> bool:
	_mutex.lock()
	var fresh := _fresh
	_fresh = false
	if fresh:
		for i in bots.size():
			bots[i] = _published[i].copy()
		report = _published_report
	_mutex.unlock()
	if busy:
		var running := false
		for thread in _threads:
			running = running or thread.is_alive()
		if not running:
			_stop_workers()
			busy = false
			fresh = true
	return fresh


func shutdown() -> void:
	generation += 1
	_stop_workers()


func _stop_workers() -> void:
	var current := generation
	generation = current + 1  # tells every running worker to stop
	for thread in _threads:
		thread.wait_to_finish()
	_threads.clear()
	generation = current


# --- Workers (run on threads: touch only their own copies) -------------------

func _run_bot(data: Dictionary, index: int, trace: BotTrace, snapshot: Dictionary, my_generation: int) -> void:
	var level := LevelSerializer.from_dict(data, "analysis").level
	var sim := BallSimulation.new(level, tuning)
	var bot := Autopilot.new(level, tuning)
	bot.steering_delay = trace.delay
	if not snapshot.is_empty():
		_restore_state(sim, snapshot["sim"])
		_restore_state(bot, snapshot["bot"])
	var next_snapshot := (floorf(sim.s / SNAPSHOT_EVERY) + 1.0) * SNAPSHOT_EVERY
	var last_point_s := -INF
	var last_near_miss_s := -INF
	var was_airborne := false
	var steps := 0
	while sim.is_playing() and sim.time < 600.0:
		if generation != my_generation:
			return
		if sim.s >= next_snapshot:
			trace.snapshots.append({
				"s": sim.s,
				"points": trace.points.size(),
				"marks": trace.marks.size(),
				"sim": _save_state(sim, ["level", "tuning"]),
				"bot": _save_state(bot, ["level", "tuning", "_rows", "_landing_rows", "_rng"]),
			})
			next_snapshot += SNAPSHOT_EVERY
		for event in sim.step(STEP, bot.decide(sim)):
			if event.type == BallSimulation.EventType.JUMPED:
				trace.marks.append(Vector3(event.s, event.angle, Mark.ECHO if event.echo else Mark.JUMP))
		var airborne := sim.phase != BallSimulation.Phase.ROLLING
		if sim.s - last_point_s >= 0.4 or airborne != was_airborne:
			trace.points.append(Vector3(sim.s, sim.angle, 1.0 if airborne else 0.0))
			last_point_s = sim.s
			was_airborne = airborne
		if steps % 6 == 0 and sim.phase == BallSimulation.Phase.ROLLING and sim.s - last_near_miss_s > 3.0:
			if level.floor_distance(sim.s, sim.angle) < NEAR_MISS:
				trace.marks.append(Vector3(sim.s, sim.angle, Mark.NEAR_MISS))
				last_near_miss_s = sim.s
		steps += 1
		if steps % 360 == 0:
			trace.end_s = sim.s
			trace.end_angle = sim.angle
			_publish(index, trace, my_generation)
	trace.end_s = sim.s
	trace.end_angle = sim.angle
	trace.points.append(Vector3(sim.s, sim.angle, 1.0))
	trace.outcome = "finished" if sim.phase == BallSimulation.Phase.FINISHED else "fell"
	_publish(index, trace, my_generation)


func _run_report(data: Dictionary, my_generation: int) -> void:
	var level := LevelSerializer.from_dict(data, "analysis").level
	var result := LevelValidator.scan(level, tuning, func() -> bool: return generation != my_generation)
	if generation != my_generation:
		return
	_mutex.lock()
	_published_report = result
	_fresh = true
	_mutex.unlock()


func _publish(index: int, trace: BotTrace, my_generation: int) -> void:
	_mutex.lock()
	if generation == my_generation:
		_published[index] = trace.copy()
		_fresh = true
	_mutex.unlock()


## Every script variable of a BallSimulation or Autopilot (private ones
## included), so a run can be resumed exactly. Arrays are copied.
static func _save_state(object: Object, skip: Array) -> Dictionary:
	var state := {}
	for property in object.get_property_list():
		if not (property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE) or property["name"] in skip:
			continue
		var value: Variant = object.get(property["name"])
		if value is Array or value is Dictionary:
			value = value.duplicate()
		state[property["name"]] = value
	return state


static func _restore_state(object: Object, state: Dictionary) -> void:
	for key in state:
		var value: Variant = state[key]
		if value is Array or value is Dictionary:
			value = value.duplicate()
		object.set(key, value)


# --- Quick geometry for the cursor overlays (main thread, cheap) -------------

## Where a rolling ball starting at (s, angle) can get to: three paths over
## `seconds`, as (s, unwrapped angle) points: full tilt left, hands off, and
## full tilt right. The ball starts drifting with the spin (as a ball that
## has been rolling for a while does). Mirrors BallSimulation._step_lateral.
static func reach_paths(level: LevelData, tuning: BallTuning, s: float, angle: float, seconds: float) -> Array[PackedVector2Array]:
	var paths: Array[PackedVector2Array] = []
	for tilt in [-1.0, 0.0, 1.0]:
		var path := PackedVector2Array()
		var ps := s
		var pa := angle
		var lateral := level.spin_speed_at(s)
		var t := 0.0
		var dt := 1.0 / 60.0
		path.append(Vector2(ps, pa))
		while t < seconds and ps < level.length:
			var flow := level.spin_speed_at(ps)
			lateral += tuning.tilt_acceleration(tilt) * dt
			lateral = flow + (lateral - flow) * exp(-tuning.rolling_resistance * dt)
			var cap := tuning.max_lateral_speed + absf(flow)
			lateral = clampf(lateral, -cap, cap)
			pa += lateral * dt / level.tunnel_radius
			ps += level.speed_at(ps) * dt
			t += dt
			if int(round(t / dt)) % 3 == 0:
				path.append(Vector2(ps, pa))
		path.append(Vector2(ps, pa))
		paths.append(path)
	return paths


## Distance (m) a jump of `height` metres covers from distance s.
static func jump_length(level: LevelData, tuning: BallTuning, s: float, height: float) -> float:
	return level.speed_at(s) * LevelValidator.air_time(level, tuning, height)
