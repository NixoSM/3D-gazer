extends TestCase


func test_round_trip_preserves_level() -> void:
	var holes: Array[HoleData] = [HoleData.new(40.0, 5.0, deg_to_rad(90.0), deg_to_rad(60.0)), HoleData.new(10.0, 2.0, 0.0, TAU)]
	var level := make_level(holes)
	var parsed := LevelSerializer.from_json(LevelSerializer.to_json(level))
	assert_true(parsed.ok(), "round trip errors: %s" % [parsed.errors])
	assert_eq(parsed.level.holes.size(), 2)
	assert_near(parsed.level.holes[0].s_start, 10.0, 0.001, "holes are sorted by s")
	assert_near(parsed.level.holes[1].angle_center, deg_to_rad(90.0), 0.002)
	assert_near(parsed.level.holes[1].angle_width, deg_to_rad(60.0), 0.002)
	assert_eq(LevelSerializer.to_json(parsed.level), LevelSerializer.to_json(level))


func test_rejects_unknown_format_version() -> void:
	var result := LevelSerializer.from_json('{"format_version": 99}')
	assert_false(result.ok())


func test_reports_holes_outside_tunnel() -> void:
	var holes: Array[HoleData] = [HoleData.new(598.0, 5.0, 0.0, 1.0)]
	var errors := LevelSerializer.validate(make_level(holes))
	assert_eq(errors.size(), 1)


func test_hole_contains_wraps_around_seam() -> void:
	var hole := HoleData.new(0.0, 10.0, deg_to_rad(350.0), deg_to_rad(40.0))
	assert_true(hole.contains(5.0, deg_to_rad(5.0), 4.0), "5° is inside a hole centred on 350° ± 20°")
	assert_true(hole.contains(5.0, deg_to_rad(340.0), 4.0))
	assert_false(hole.contains(5.0, deg_to_rad(15.0), 4.0))
	assert_eq(hole.angle_ranges().size(), 2, "seam-crossing hole splits into two ranges")


func test_hole_lookup_finds_long_hole_started_earlier() -> void:
	var holes: Array[HoleData] = [HoleData.new(10.0, 50.0, 0.0, 1.0), HoleData.new(20.0, 1.0, PI, 1.0), HoleData.new(30.0, 1.0, PI, 1.0)]
	var level := make_level(holes)
	assert_true(level.hole_at(45.0, 0.0) != null, "s=45 is inside the long first hole")
	assert_eq(level.holes_between(40.0, 41.0).size(), 1)


func test_bundled_levels_load_and_are_playable() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://levels/manifest.json"))
	assert_true(manifest["levels"].size() >= 1)
	for id in manifest["levels"]:
		var result := LevelSerializer.load_file("res://levels/%s.json" % id)
		assert_true(result.ok(), "%s: %s" % [id, result.errors])
		if result.ok():
			assert_near(result.level.duration(), 60.0, 5.0, "%s should last about a minute" % id)
			var problems := LevelValidator.check(result.level, load("res://resources/ball_tuning.tres"))
			assert_true(problems.is_empty(), "%s: %s" % [id, problems])


func test_validator_flags_unjumpable_ring() -> void:
	var holes: Array[HoleData] = [HoleData.new(100.0, 40.0, 0.0, TAU)]
	assert_false(LevelValidator.check(make_level(holes), make_tuning()).is_empty())
