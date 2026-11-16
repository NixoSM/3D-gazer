class_name TunnelMeshBuilder
extends RefCounted
## Builds the mesh for one stretch ("chunk") of tunnel: a plain tube.
##
## Holes are not cut into the mesh. The tunnel shader cuts them per pixel
## from the same distance field the simulation uses (LevelData.floor_distance),
## which is what gives them rounded corners, smooth diagonal edges and
## seamless joins between holes that touch; geometry made of grid cells
## could only ever approximate that with steps.
##
## Rows that lie entirely inside a full ring hole are left out (nothing of
## them would survive the shader), and each chunk overlaps its neighbours by
## SKIRT metres so the seam between them never shows.

const ANGULAR_SEGMENTS := 120
const ROW_LENGTH := 1.5
const SKIRT := 0.3


static func build_chunk(level: LevelData, chunk_start: float, chunk_end: float) -> ArrayMesh:
	# Chunks before s = 0 exist too: the camera starts behind the ball and
	# must not see the open end of the tube.
	var s0 := chunk_start - SKIRT
	var s1 := chunk_end + SKIRT
	var radius := level.tunnel_radius
	var rings := _ring_spans(level, s0, s1)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var rows := int(ceil((s1 - s0) / ROW_LENGTH))
	for i in rows:
		var sa := s0 + (s1 - s0) * i / rows
		var sb := s0 + (s1 - s0) * (i + 1) / rows
		if _inside_ring(rings, sa, sb):
			continue
		var base := vertices.size()
		for k in ANGULAR_SEGMENTS + 1:
			var a := TAU * k / ANGULAR_SEGMENTS
			vertices.append(TunnelMath.point(sa, a, radius))
			vertices.append(TunnelMath.point(sb, a, radius))
			normals.append(TunnelMath.inward(a))
			normals.append(TunnelMath.inward(a))
		for k in ANGULAR_SEGMENTS:
			var v := base + k * 2
			indices.append_array([v, v + 1, v + 3, v, v + 3, v + 2])

	var mesh := ArrayMesh.new()
	if indices.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# The shader cuts holes from the vertices' world positions; the bounds
	# are the tube's either way.
	return mesh


## Stretches [start, end] of the chunk that are open all the way round,
## shrunk by the blend distance so the rounded/blended rim stays drawn.
static func _ring_spans(level: LevelData, s0: float, s1: float) -> Array[Vector2]:
	var spans: Array[Vector2] = []
	var margin := LevelData.BLEND + HoleData.CORNER_RADIUS
	for hole in level.holes_between(s0, s1):
		if hole.is_ring() and hole.length > 2.0 * margin:
			spans.append(Vector2(hole.s_start + margin, hole.s_end() - margin))
	return spans


static func _inside_ring(spans: Array[Vector2], sa: float, sb: float) -> bool:
	for span in spans:
		if sa >= span.x and sb <= span.y:
			return true
	return false


## Index range [first, first + count) of the level's holes that can affect
## the shader anywhere in this chunk (see tunnel.gdshader floor_distance()).
static func hole_range(level: LevelData, chunk_start: float, chunk_end: float) -> Vector2i:
	var reach := LevelData.BLEND + HoleData.CORNER_RADIUS + 1.0
	var s0 := chunk_start - SKIRT - reach
	var s1 := chunk_end + SKIRT + reach
	var first := level.first_hole_index_near(s0)
	var last := first
	while last < level.holes.size() and level.holes[last].s_start <= s1:
		last += 1
	return Vector2i(first, last - first)
