extends TestCase
## The level editor's non-visual parts: undo, the background analysis
## (including resuming from a snapshot after an edit) and pattern stamping.


func _short_level() -> LevelData:
	var holes: Array[HoleData] = [
		HoleData.new(60.0, 8.0, 0.0, deg_to_rad(200.0)),
		HoleData.new(90.0, 3.0, 0.0, TAU),
		HoleData.new(130.0, 10.0, PI, deg_to_rad(220.0)),
		HoleData.new(170.0, 12.0, deg_to_rad(90.0), deg_to_rad(240.0), deg_to_rad(3.0)),
	]
	var level := make_level(holes)
	level.length = 260.0
	level.spin = [SpinKey.new(40.0, 0.0), SpinKey.new(50.0, 20.0)]
	level.sort()
	return level


static func _finish(analysis: LevelAnalysis) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 60000:
		analysis.poll()
		if not analysis.busy:
			analysis.poll()
			return
		OS.delay_msec(10)


func test_undo_and_redo_restore_the_level() -> void:
	var document := LevelDocument.new(_short_level())
	var before := LevelSerializer.to_json(document.level)
	document.begin("Move")
	document.level.holes[0].s_start += 5.0
	document.changed_from(60.0)
	var after := LevelSerializer.to_json(document.level)
	assert_true(document.dirty)
	assert_eq(document.undo(), "Move")
	assert_eq(LevelSerializer.to_json(document.level), before)
	assert_eq(document.redo(), "Move")
	assert_eq(LevelSerializer.to_json(document.level), after)
	assert_false(document.can_redo())


func test_coalesced_edits_share_one_undo_step() -> void:
	var document := LevelDocument.new(_short_level())
	for i in 5:
		document.begin("Change colour", true)
		document.level.palette[0].wall = Color(i / 5.0, 0, 0)
		document.changed_from(INF)
	document.undo()
	assert_false(document.can_undo(), "five quick colour changes are one step")


func test_save_and_reopen(path: String = "user://test_editor_level.json") -> void:
	var document := LevelDocument.new(_short_level())
	assert_eq(document.save(path), OK)
	assert_false(document.dirty)
	var reopened := LevelDocument.open(path)
	assert_true(reopened.ok(), "%s" % [reopened.errors])
	assert_eq(LevelSerializer.to_json(reopened.level), LevelSerializer.to_json(document.level))
	DirAccess.remove_absolute(path)


func test_validator_report_matches_its_messages() -> void:
	var holes: Array[HoleData] = [HoleData.new(100.0, 40.0, 0.0, TAU), HoleData.new(140.9, 3.0, 0.0, TAU)]
	var report := LevelValidator.scan(make_level(holes), make_tuning())
	assert_eq(report.gaps.size(), 2, "two separate blocked stretches")
	assert_true(report.gaps[0].too_long())
	assert_true(report.gaps[1].too_close())
	assert_eq(report.problems().size(), 2)
	assert_near(report.free_width.size(), 600.0 / LevelValidator.SAMPLE_STEP, 2.0)


func test_analysis_resumes_exactly_after_an_edit() -> void:
	var tuning: BallTuning = load("res://resources/ball_tuning.tres")
	var level := _short_level()
	var analysis := LevelAnalysis.new(tuning)
	analysis.request(level, 0.0)
	_finish(analysis)
	assert_true(analysis.report != null, "the gap report arrived")
	for trace in analysis.bots:
		assert_true(trace.outcome != "running", "every bot finished its run")
		assert_true(trace.snapshots.size() >= 5, "snapshots were taken")

	# Move the last hole; the edited analysis resumes from a snapshot.
	level.holes[3].angle_center += 0.6
	level.sort()
	analysis.request(level, 170.0)
	_finish(analysis)

	var fresh := LevelAnalysis.new(tuning)
	fresh.request(level, 0.0)
	_finish(fresh)
	for i in analysis.bots.size():
		var resumed := analysis.bots[i]
		var full := fresh.bots[i]
		assert_eq(resumed.outcome, full.outcome, "bot %d outcome" % i)
		assert_near(resumed.end_s, full.end_s, 0.001, "bot %d end" % i)
		assert_eq(resumed.points.size(), full.points.size(), "bot %d path" % i)
	analysis.shutdown()
	fresh.shutdown()


func test_reach_paths_fan_out_and_follow_the_spin() -> void:
	var level := _short_level()
	var tuning := make_tuning()
	var paths := LevelAnalysis.reach_paths(level, tuning, 100.0, 0.0, 1.0)
	var left := paths[0][paths[0].size() - 1].y
	var drift := paths[1][paths[1].size() - 1].y
	var right := paths[2][paths[2].size() - 1].y
	assert_true(left < drift and drift < right, "left %.2f < drift %.2f < right %.2f" % [left, drift, right])
	assert_true(drift > 0.1, "a right-hand spin carries a hands-off ball to the right")


func test_pattern_stamp_cuts_holes_inside_the_level() -> void:
	var level := make_level()
	var before := level.holes.size()
	var result := LevelGenerator.new().stamp(level, make_tuning(), {"p": "gate", "n": 3, "i": 0.5}, 200.0, 0.0, 7)
	var added: Array = result["holes"]
	assert_eq(level.holes.size(), before + added.size())
	assert_true(added.size() >= 3, "three gates")
	for hole in added:
		assert_true(hole.s_start >= 200.0 and hole.s_end() <= level.length)


## Drives the Spin fields the way a person does (through their signals), on a
## level with no spin and on one with a generator spin that starts at 0 °/s:
## picking a direction must stick, and every field must reach the level.
func test_spin_fields_take_effect_through_the_ui() -> void:
	for spin in [[], [SpinKey.new(0.0, 0.0), SpinKey.new(80.0, 25.0), SpinKey.new(160.0, -30.0)]]:
		var level := _short_level()
		level.spin.assign(spin)
		var document := LevelDocument.new()
		document.replace(level, "")
		var strip := StripView.new()
		var analysis := LevelAnalysis.new(make_tuning())
		var inspector := InspectorPanel.new()
		inspector.setup(document, strip, analysis)
		var direction: OptionButton = inspector._spin_direction
		direction.select(1)
		direction.item_selected.emit(1)
		assert_eq(direction.selected, 1, "Left stays selected")
		assert_true(document.level.spin_at(0.0) < -1.0, "choosing Left alone spins left")
		_type(inspector._spin_rate, 45.0)
		_type(inspector._spin_ramp, 100.0)
		assert_near(document.level.spin_at(0.0), -45.0, 0.01)
		assert_near(document.level.spin_at(document.level.length), -90.0, 0.01)
		direction.select(2)
		direction.item_selected.emit(2)
		assert_near(document.level.spin_at(0.0), 45.0, 0.01, "Right keeps the speed")
		direction.select(0)
		direction.item_selected.emit(0)
		assert_true(document.level.spin.is_empty(), "None removes the spin")
		inspector.free()
		strip.free()
		analysis.shutdown()


## Types a number into a field. (Outside the scene tree, as here, setting
## .value does not emit value_changed, so emit it as the UI would.)
static func _type(box: SpinBox, value: float) -> void:
	box.set_value_no_signal(value)
	box.value_changed.emit(value)
