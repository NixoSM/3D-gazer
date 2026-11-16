class_name TunnelMeshBuilder
extends RefCounted
## Builds the mesh for one stretch ("chunk") of tunnel, with its holes cut out.
##
## The wall is a grid in (s, angle). The grid lines are the regular divisions
## *plus every hole edge*, so each grid cell is either entirely solid or
## entirely open: rectangular holes come out exact, with no shader tricks.
##
## Wherever a solid cell touches an open one we add a "rim" face that goes
## outwards through the wall's thickness, so holes read as cuts in a thick
## shell rather than as flat decals. Rim faces are tagged with
## COLOR.r = 1 so the shader can paint them with the accent colour.

const ANGULAR_SEGMENTS := 72
const ROW_LENGTH := 3.0
const WALL_THICKNESS := 0.45
const EPSILON := 0.0005


static func build_chunk(level: LevelData, s0: float, s1: float) -> ArrayMesh:
	var radius := level.tunnel_radius
	var holes := level.holes_between(s0 - EPSILON, s1 + EPSILON)
	var angles := _angle_breaks(holes)
	var rows := _row_breaks(s0, s1, holes)

	# solid[row][col]: is this cell wall (true) or hole (false)?
	var solid: Array[PackedByteArray] = []
	for i in rows.size() - 1:
		solid.append(_solid_row(level, (rows[i] + rows[i + 1]) * 0.5, angles))
	var before := _solid_row(level, s0 - EPSILON, angles)
	var after := _solid_row(level, s1 + EPSILON, angles)

	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var columns := angles.size() - 1
	for i in rows.size() - 1:
		var sa := rows[i]
		var sb := rows[i + 1]
		for j in columns:
			if solid[i][j] == 0:
				continue
			var a0 := angles[j]
			var a1 := angles[j + 1]
			_wall_quad(tool, radius, sa, sb, a0, a1)
			# Rims towards open neighbours.
			var left := solid[i][(j - 1 + columns) % columns]
			var right := solid[i][(j + 1) % columns]
			var back := solid[i - 1][j] if i > 0 else before[j]
			var front := solid[i + 1][j] if i < rows.size() - 2 else after[j]
			if left == 0:
				_side_rim(tool, radius, sa, sb, a0)
			if right == 0:
				_side_rim(tool, radius, sa, sb, a1)
			if back == 0:
				_end_rim(tool, radius, sa, a0, a1)
			if front == 0:
				_end_rim(tool, radius, sb, a0, a1)

	tool.index()
	return tool.commit()


static func _angle_breaks(holes: Array[HoleData]) -> PackedFloat32Array:
	var breaks := PackedFloat32Array()
	for k in ANGULAR_SEGMENTS + 1:
		breaks.append(TAU * k / ANGULAR_SEGMENTS)
	for hole in holes:
		for r in hole.angle_ranges():
			breaks.append(r.x)
			breaks.append(r.y)
	return _sorted_unique(breaks)


static func _row_breaks(s0: float, s1: float, holes: Array[HoleData]) -> PackedFloat32Array:
	var breaks := PackedFloat32Array()
	var s := s0
	while s < s1:
		breaks.append(s)
		s += ROW_LENGTH
	breaks.append(s1)
	for hole in holes:
		if hole.s_start > s0 and hole.s_start < s1:
			breaks.append(hole.s_start)
		if hole.s_end() > s0 and hole.s_end() < s1:
			breaks.append(hole.s_end())
	return _sorted_unique(breaks)


static func _sorted_unique(values: PackedFloat32Array) -> PackedFloat32Array:
	values.sort()
	var result := PackedFloat32Array()
	for v in values:
		if result.is_empty() or v - result[result.size() - 1] > EPSILON:
			result.append(v)
	return result


static func _solid_row(level: LevelData, s: float, angles: PackedFloat32Array) -> PackedByteArray:
	var row := PackedByteArray()
	row.resize(angles.size() - 1)
	for j in angles.size() - 1:
		var mid := (angles[j] + angles[j + 1]) * 0.5
		row[j] = 0 if level.hole_at(s, mid) != null else 1
	return row


static func _vertex(tool: SurfaceTool, position: Vector3, normal: Vector3, rim: bool) -> void:
	tool.set_color(Color(1.0 if rim else 0.0, 0.0, 0.0))
	tool.set_normal(normal)
	tool.add_vertex(position)


static func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, rim: bool) -> void:
	_vertex(tool, a, normal, rim)
	_vertex(tool, b, normal, rim)
	_vertex(tool, c, normal, rim)
	_vertex(tool, a, normal, rim)
	_vertex(tool, c, normal, rim)
	_vertex(tool, d, normal, rim)


## Inner surface of the wall, facing the axis.
static func _wall_quad(tool: SurfaceTool, r: float, sa: float, sb: float, a0: float, a1: float) -> void:
	var normal := TunnelMath.inward((a0 + a1) * 0.5)
	_quad(tool,
		TunnelMath.point(sa, a0, r), TunnelMath.point(sb, a0, r),
		TunnelMath.point(sb, a1, r), TunnelMath.point(sa, a1, r),
		normal, false)


## Rim along the tunnel (a hole edge at constant angle).
static func _side_rim(tool: SurfaceTool, r: float, sa: float, sb: float, angle: float) -> void:
	var outer := r + WALL_THICKNESS
	_quad(tool,
		TunnelMath.point(sa, angle, r), TunnelMath.point(sa, angle, outer),
		TunnelMath.point(sb, angle, outer), TunnelMath.point(sb, angle, r),
		TunnelMath.tangent(angle), true)


## Rim across the tunnel (a hole edge at constant s).
static func _end_rim(tool: SurfaceTool, r: float, s: float, a0: float, a1: float) -> void:
	var outer := r + WALL_THICKNESS
	_quad(tool,
		TunnelMath.point(s, a0, r), TunnelMath.point(s, a0, outer),
		TunnelMath.point(s, a1, outer), TunnelMath.point(s, a1, r),
		Vector3(0.0, 0.0, 1.0), true)
