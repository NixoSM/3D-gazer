extends Node
## Checks the baked hole field (TunnelView._bake_field) against the
## simulation's own LevelData.floor_distance, texel by texel on a sample.
##
##   xvfb-run godot --rendering-driver opengl3 res://tools/field_check.tscn

func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var worst_all := 0.0
	for index in main.levels.size():
		main._play_level.call_deferred(index)
		var image: Image = await main.world.tunnel.field_baked
		main.session.stop_run()
		var level: LevelData = main.session.level
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var worst := 0.0
		var near_edge := 0.0
		for i in 20000:
			var px := rng.randi_range(0, image.get_width() - 1)
			var py := rng.randi_range(0, image.get_height() - 1)
			var strip := py / TunnelView.FIELD_STRIP_ROWS
			var s := strip * TunnelView.FIELD_STRIP - TunnelView.FIELD_GUARD + (px + 0.5) / TunnelView.FIELD_TEXELS
			var angle := (py - strip * TunnelView.FIELD_STRIP_ROWS + 0.5 - 2.0) / 256.0 * TAU
			var expected := clampf(level.floor_distance(s, TunnelMath.wrap_angle_positive(angle)), -2.0, 2.0)
			var got := (image.get_pixel(px, py).r - 0.5) * 4.0
			worst = maxf(worst, absf(got - expected))
			if absf(expected) < 0.5:
				near_edge = maxf(near_edge, absf(got - expected))
		print("%s  %dx%d  worst error %.4f m, within 0.5 m of an edge %.4f m" % [level.id, image.get_width(), image.get_height(), worst, near_edge])
		worst_all = maxf(worst_all, near_edge)
	get_tree().quit(0 if worst_all < 0.01 else 1)
