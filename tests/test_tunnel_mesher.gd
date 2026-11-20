extends TestCase
## TunnelMesher builds the tunnel the player sees. These tests hold it to
## the level's definition (LevelData.floor_distance, what the ball falls by)
## without looking at any picture:
##   * the floor covers exactly the solid wall, once (no holes in the floor,
##     no floor over a hole, nothing drawn twice);
##   * the floor is watertight: every triangle edge is shared by two
##     triangles except along the holes' edges and the ends of the stretch,
##     including where two chunks meet (no cracks, no T-junctions);
##   * every edge of every hole has a cut face welded to it;
##   * the edge distance the floor shader draws the outline from, and its
##     gradient (how wide the outline is far away), are the true ones
##     wherever ink can reach (no stray black lines);
##   * a chunk stays within its triangle and time budget.

const ANGLE_BUCKETS := 64
const ANGLE_BUCKET := TAU / ANGLE_BUCKETS


## A stretch with every kind of edge: a ring, a gate across the angle seam,
## two holes blending into one across a chunk boundary, a twisted bridge,
## and a narrow sliver of floor between two holes.
func _level() -> LevelData:
	var holes: Array[HoleData] = [
		HoleData.new(3.0, 3.0, 0.0, TAU),
		HoleData.new(9.0, 6.0, deg_to_rad(350.0), deg_to_rad(70.0)),
		HoleData.new(14.0, 8.0, deg_to_rad(120.0), deg_to_rad(40.0)),
		HoleData.new(15.5, 2.5, deg_to_rad(150.0), deg_to_rad(30.0)),
		HoleData.new(22.0, 11.0, deg_to_rad(200.0), deg_to_rad(250.0), deg_to_rad(6.0)),
		HoleData.new(26.0, 4.0, deg_to_rad(20.0), deg_to_rad(60.0)),
		HoleData.new(26.0, 4.0, deg_to_rad(88.0), deg_to_rad(60.0)),
	]
	return make_level(holes)


func _chunks(level: LevelData) -> Array:
	return [TunnelMesher.build(level, 0.0, 18.0), TunnelMesher.build(level, 18.0, 36.0)]


static func _surface(v: Vector3) -> Vector2:
	return Vector2(-v.z, fposmod(atan2(v.x, -v.y), TAU))


func test_floor_covers_exactly_the_solid_wall() -> void:
	var level := _level()
	var triangles: Array[PackedVector2Array] = []
	for geometry: TunnelMesher.Geometry in _chunks(level):
		for i in range(0, geometry.floor_indices.size(), 3):
			var a := _surface(geometry.floor_vertices[geometry.floor_indices[i]])
			var b := _surface(geometry.floor_vertices[geometry.floor_indices[i + 1]])
			var c := _surface(geometry.floor_vertices[geometry.floor_indices[i + 2]])
			# Unwrap around the angle seam so the triangle is one piece.
			b.y = a.y + wrapf(b.y - a.y, -PI, PI)
			c.y = a.y + wrapf(c.y - a.y, -PI, PI)
			assert_true(absf((b - a).cross(c - a)) > 1e-12, "degenerate floor triangle at s %.3f" % a.x)
			triangles.append(PackedVector2Array([a, b, c]))
	# Bucket the triangles on a coarse grid of the unrolled wall.
	var buckets := {}
	for t in triangles.size():
		var tri := triangles[t]
		var lo := Vector2(minf(tri[0].x, minf(tri[1].x, tri[2].x)), minf(tri[0].y, minf(tri[1].y, tri[2].y)))
		var hi := Vector2(maxf(tri[0].x, maxf(tri[1].x, tri[2].x)), maxf(tri[0].y, maxf(tri[1].y, tri[2].y)))
		for bs in range(floori(lo.x / 0.5), floori(hi.x / 0.5) + 1):
			for ba in range(floori(lo.y / ANGLE_BUCKET), floori(hi.y / ANGLE_BUCKET) + 1):
				var key := Vector2i(bs, posmod(ba, ANGLE_BUCKETS))
				if not buckets.has(key):
					buckets[key] = []
				buckets[key].append(t)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var wrong := 0
	var checked := 0
	var first_wrong := ""
	for n in 6000:
		var p := Vector2(rng.randf_range(0.01, 35.99), rng.randf_range(0.0, TAU))
		var d := level.floor_distance(p.x, p.y)
		if absf(d) < 0.02:
			continue  # on an edge: the mesh is a few millimetres off the true curve
		checked += 1
		var cover := 0
		var key := Vector2i(floori(p.x / 0.5), posmod(floori(p.y / ANGLE_BUCKET), ANGLE_BUCKETS))
		for t in buckets.get(key, []):
			var tri := triangles[t]
			for shift in [0.0, TAU, -TAU]:
				if Geometry2D.point_is_inside_triangle(p + Vector2(0.0, shift), tri[0], tri[1], tri[2]):
					cover += 1
		var want := 1 if d > 0.0 else 0
		if cover != want:
			wrong += 1
			if first_wrong.is_empty():
				first_wrong = "s %.3f angle %.1f° d %.3f: covered %d times" % [p.x, rad_to_deg(p.y), d, cover]
	assert_true(checked > 5000)
	assert_eq(wrong, 0, first_wrong)


func test_floor_is_watertight_across_cells_and_chunks() -> void:
	var level := _level()
	var keys := {}
	var vertices: Array[Vector3] = []
	var edges := {}
	for geometry: TunnelMesher.Geometry in _chunks(level):
		for i in range(0, geometry.floor_indices.size(), 3):
			var corner := []
			for j in 3:
				var v := geometry.floor_vertices[geometry.floor_indices[i + j]]
				var key := Vector3i(roundi(v.x * 1e5), roundi(v.y * 1e5), roundi(v.z * 1e5))
				if not keys.has(key):
					keys[key] = vertices.size()
					vertices.append(v)
				corner.append(keys[key])
			if corner[0] == corner[1] or corner[1] == corner[2] or corner[0] == corner[2]:
				continue  # degenerate: covers nothing
			for j in 3:
				var a: int = corner[j]
				var b: int = corner[(j + 1) % 3]
				var edge := Vector2i(mini(a, b), maxi(a, b))
				edges[edge] = edges.get(edge, 0) + 1
	var loose := 0
	var example := ""
	for edge: Vector2i in edges:
		var uses: int = edges[edge]
		var a := _surface(vertices[edge.x])
		var b := _surface(vertices[edge.y])
		var at_ends := (absf(a.x) < 1e-4 and absf(b.x) < 1e-4) or (absf(a.x - 36.0) < 1e-4 and absf(b.x - 36.0) < 1e-4)
		if uses > 2:
			loose += 1
			example = "edge used %d times at s %.3f" % [uses, a.x]
		elif uses == 1 and not at_ends:
			# Only the holes' edges may be open, and they lie on the contour.
			var da := absf(level.floor_distance(a.x, a.y))
			var db := absf(level.floor_distance(b.x, b.y))
			if da > 0.01 or db > 0.01:
				loose += 1
				example = "open edge from s %.3f %.1f° to s %.3f %.1f° (d %.3f, %.3f)" % [a.x, rad_to_deg(a.y), b.x, rad_to_deg(b.y), da, db]
	assert_eq(loose, 0, example)


func test_every_hole_edge_has_a_cut_face() -> void:
	var level := _level()
	for geometry: TunnelMesher.Geometry in _chunks(level):
		# Open floor edges (used by one triangle, not at the chunk's ends)...
		var edges := {}
		for i in range(0, geometry.floor_indices.size(), 3):
			for j in 3:
				var a := _key(geometry.floor_vertices[geometry.floor_indices[i + j]])
				var b := _key(geometry.floor_vertices[geometry.floor_indices[i + (j + 1) % 3]])
				if a == b:
					continue
				var edge := [a, b] if str(a) < str(b) else [b, a]
				edges[edge] = edges.get(edge, 0) + 1
		# ...must each be the top of a cut face.
		var tops := {}
		for i in range(0, geometry.wall_vertices.size(), 4):
			var a := _key(geometry.wall_vertices[i])
			var b := _key(geometry.wall_vertices[i + 1])
			tops[[a, b] if str(a) < str(b) else [b, a]] = true
			# The face goes straight out through the shell, the full thickness.
			var out := geometry.wall_vertices[i + 3]
			var top := geometry.wall_vertices[i]
			assert_near(Vector2(out.x, out.y).length() - Vector2(top.x, top.y).length(), TunnelMath.WALL_THICKNESS, 1e-4)
			assert_near(out.z, top.z, 1e-5)
		var missing := 0
		var example := ""
		for edge in edges:
			if edges[edge] != 1:
				continue
			var s_a: float = -float(edge[0].z) / 1e5
			var s_b: float = -float(edge[1].z) / 1e5
			var chunk_end := func(s: float) -> bool: return fmod(s + 1e-4, 18.0) < 2e-4
			if chunk_end.call(s_a) and chunk_end.call(s_b):
				continue
			if not tops.has(edge):
				missing += 1
				example = "first at s %.3f, %.1f°" % [s_a, rad_to_deg(atan2(edge[0].x, -edge[0].y))]
		assert_eq(missing, 0, "hole edges without a cut face, " + example)
		assert_true(not tops.is_empty())


func test_outline_comes_from_true_edge_distances() -> void:
	# tunnel_floor.gdshader inks the floor where the edge distance it gets
	# (interpolated across each triangle from the vertices) is small. Inside
	# every floor triangle, wherever that interpolated distance or the true
	# one is within ink reach, the two must agree. A long strip from one
	# hole's corner to another's once carried a near-edge distance along its
	# whole length: thin black lines across plain floor.
	var level := _level()
	var checked := 0
	for geometry: TunnelMesher.Geometry in _chunks(level):
		var v := geometry.floor_vertices
		var uv := geometry.floor_uvs
		var idx := geometry.floor_indices
		for i in range(0, idx.size(), 3):
			var p := [v[idx[i]], v[idx[i + 1]], v[idx[i + 2]]]
			var d := [uv[idx[i]].x, uv[idx[i + 1]].x, uv[idx[i + 2]].x]
			for a in 7:
				for b in 7 - a:
					var c := 6 - a - b
					var interpolated: float = (d[0] * a + d[1] * b + d[2] * c) / 6.0
					var q := _surface((p[0] * a + p[1] * b + p[2] * c) / 6.0)
					var truth := level.floor_distance(q.x, q.y)
					if minf(interpolated, truth) > TunnelMesher.INK_REACH:
						continue
					checked += 1
					if absf(interpolated - truth) > 0.01:
						assert_near(interpolated, truth, 0.01, "edge distance off at s %.2f, angle %.1f°" % [q.x, rad_to_deg(q.y)])
						return
	assert_true(checked > 10000, "only %d samples near edges" % checked)
	# Every distance is finite (far from holes the field is INF), and every
	# long triangle (a plain strip) is flat: with MSAA a pixel a sliver only
	# grazes is shaded off the triangle, and a slope would extrapolate there
	# into the ink.
	for geometry: TunnelMesher.Geometry in _chunks(level):
		var v := geometry.floor_vertices
		var uv := geometry.floor_uvs
		var idx := geometry.floor_indices
		for i in range(0, idx.size(), 3):
			var a := idx[i]
			var b := idx[i + 1]
			var c := idx[i + 2]
			for d in [uv[a].x, uv[b].x, uv[c].x]:
				if not (is_finite(d) and d >= 0.0 and d < 2.0):
					assert_true(false, "floor vertex edge distance %f" % d)
					return
			var longest := maxf(v[a].distance_to(v[b]), maxf(v[b].distance_to(v[c]), v[c].distance_to(v[a])))
			if longest > TunnelMesher.BAND and not (uv[a].x == uv[b].x and uv[b].x == uv[c].x):
				assert_true(false, "%.1f m long floor triangle with a sloped edge distance (%.3f, %.3f, %.3f) at s %.2f" % [longest, uv[a].x, uv[b].x, uv[c].x, -v[a].z])
				return


func test_outline_width_comes_from_true_gradients() -> void:
	# Far away the outline is as wide as a pixel and a half of edge distance,
	# so the shader needs how fast that distance changes per pixel. It takes
	# the gradient each vertex carries (interpolated), not each triangle's
	# own slope, which jumps between triangles where the field curves: with
	# MSAA that drew faint dotted lines beside the outline. Wherever ink can
	# reach, the interpolated gradient must be the field's.
	var level := _level()
	var step := 1.0 / 256.0
	var checked := 0
	for geometry: TunnelMesher.Geometry in _chunks(level):
		var v := geometry.floor_vertices
		var uv := geometry.floor_uvs
		var slopes := geometry.floor_slopes
		var idx := geometry.floor_indices
		assert_eq(slopes.size(), v.size(), "a gradient for every floor vertex")
		for i in range(0, idx.size(), 3):
			var p := [v[idx[i]], v[idx[i + 1]], v[idx[i + 2]]]
			var d := [uv[idx[i]].x, uv[idx[i + 1]].x, uv[idx[i + 2]].x]
			var g := [slopes[idx[i]], slopes[idx[i + 1]], slopes[idx[i + 2]]]
			for a in 5:
				for b in 5 - a:
					var c := 4 - a - b
					var interpolated: float = (d[0] * a + d[1] * b + d[2] * c) / 4.0
					if interpolated >= TunnelMesher.INK_REACH:
						continue
					var slope: Vector2 = (g[0] * a + g[1] * b + g[2] * c) / 4.0
					var q := _surface((p[0] * a + p[1] * b + p[2] * c) / 4.0)
					var turn := step / level.tunnel_radius
					var truth := Vector2(
						level.floor_distance(q.x + step, q.y) - level.floor_distance(q.x - step, q.y),
						level.floor_distance(q.x, q.y + turn) - level.floor_distance(q.x, q.y - turn)) / (2.0 * step)
					checked += 1
					if slope.distance_to(truth) > 0.1:
						assert_true(false, "gradient (%.2f, %.2f), truly (%.2f, %.2f) at s %.2f, angle %.1f°" % [slope.x, slope.y, truth.x, truth.y, q.x, rad_to_deg(q.y)])
						return
	assert_true(checked > 10000, "only %d samples near edges" % checked)


func test_chunks_stay_within_budget() -> void:
	# Every bundled level, at its busiest: the chunks with the most holes.
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://levels/manifest.json"))
	for id in manifest["levels"]:
		var level := LevelSerializer.load_file("res://levels/%s.json" % id).level
		var busiest := []
		var s := 0.0
		while s < level.length:
			busiest.append([level.holes_between(s, s + TunnelView.CHUNK_LENGTH).size(), s])
			s += TunnelView.CHUNK_LENGTH
		busiest.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		var worst_triangles := 0
		var worst_ms := 0.0
		for entry in busiest.slice(0, 6):
			var start := Time.get_ticks_usec()
			var geometry := TunnelMesher.build(level, entry[1], entry[1] + TunnelView.CHUNK_LENGTH)
			worst_ms = maxf(worst_ms, (Time.get_ticks_usec() - start) / 1000.0)
			worst_triangles = maxi(worst_triangles, geometry.triangle_count())
		# About nine chunks are on screen. Ember, the busiest old level, peaked
		# at 10k a chunk; the new levels pack in far more edges (Screwball's
		# threads run the whole level) and peak near 22k, about 190k on
		# screen at the very busiest: still small for a phone GPU, but
		# keep it from growing further.
		assert_true(worst_triangles < 24000, "%s: worst chunk has %d triangles" % [id, worst_triangles])
		# Built on worker threads ahead of the camera; generous for slow CI machines.
		assert_true(worst_ms < 1000.0, "%s: worst chunk took %.0f ms" % [id, worst_ms])


func test_mesh_matches_physics_where_the_ball_falls() -> void:
	# The ball falls by floor_distance; a floor vertex is never over a hole
	# and a cut face never stands on solid floor.
	var level := _level()
	for geometry: TunnelMesher.Geometry in _chunks(level):
		for i in geometry.floor_vertices.size():
			var p := _surface(geometry.floor_vertices[i])
			assert_true(level.floor_distance(p.x, p.y) > -0.01, "floor vertex over a hole at s %.2f" % p.x)
		for i in range(0, geometry.wall_vertices.size(), 4):
			var p := _surface(geometry.wall_vertices[i])
			assert_near(level.floor_distance(p.x, p.y), 0.0, 0.01, "cut face off the edge at s %.2f" % p.x)


static func _key(v: Vector3) -> Vector3i:
	return Vector3i(roundi(v.x * 1e5), roundi(v.y * 1e5), roundi(v.z * 1e5))
