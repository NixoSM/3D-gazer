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
## shell rather than as flat decals, and a flat strip on the wall along the
## same edge: together they draw the thick cartoon outline around each hole.
## Rim faces are tagged COLOR.r = 1 and outline strips COLOR.g = 1.
##
## Neighbouring chunks have different angle breaks (their holes differ), so
## their edges would not meet exactly: the chords sag differently and leave
## hairline cracks to the void. Each chunk therefore overlaps its neighbours
## by SKIRT metres, which hides the seam completely.

const ANGULAR_SEGMENTS := 120
const ROW_LENGTH := 3.0
const WALL_THICKNESS := TunnelMath.WALL_THICKNESS
const SKIRT := 0.3
## Width (m) of the black outline drawn on the wall around every hole.
const OUTLINE_WIDTH := 0.16
## Outlines float this far off the wall, towards the axis, to avoid z-fighting.
const OUTLINE_LIFT := 0.01

enum Kind { WALL, RIM, OUTLINE }
const EPSILON := 0.0005


static func build_chunk(level: LevelData, chunk_start: float, chunk_end: float) -> ArrayMesh:
	var s0 := maxf(chunk_start - SKIRT, -SKIRT)
	var s1 := chunk_end + SKIRT
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
			# Plus a thick outline strip lying on the wall along that edge.
			var outline_angle := minf(OUTLINE_WIDTH / radius, a1 - a0)
			var outline_s := minf(OUTLINE_WIDTH, sb - sa)
			if left == 0:
				_side_rim(tool, radius, sa, sb, a0)
				_outline(tool, radius, sa, sb, a0, a0 + outline_angle)
			if right == 0:
				_side_rim(tool, radius, sa, sb, a1)
				_outline(tool, radius, sa, sb, a1 - outline_angle, a1)
			if back == 0:
				_end_rim(tool, radius, sa, a0, a1)
				_outline(tool, radius, sa, sa + outline_s, a0, a1)
			if front == 0:
				_end_rim(tool, radius, sb, a0, a1)
				_outline(tool, radius, sb - outline_s, sb, a0, a1)

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


## COLOR.r marks rim faces and COLOR.g outline strips, for the shader.
static func _vertex(tool: SurfaceTool, position: Vector3, normal: Vector3, kind: Kind) -> void:
	tool.set_color(Color(1.0 if kind == Kind.RIM else 0.0, 1.0 if kind == Kind.OUTLINE else 0.0, 0.0))
	tool.set_normal(normal)
	tool.add_vertex(position)


static func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, kind: Kind) -> void:
	_vertex(tool, a, normal, kind)
	_vertex(tool, b, normal, kind)
	_vertex(tool, c, normal, kind)
	_vertex(tool, a, normal, kind)
	_vertex(tool, c, normal, kind)
	_vertex(tool, d, normal, kind)


## Inner surface of the wall, facing the axis.
static func _wall_quad(tool: SurfaceTool, r: float, sa: float, sb: float, a0: float, a1: float) -> void:
	var normal := TunnelMath.inward((a0 + a1) * 0.5)
	_quad(tool,
		TunnelMath.point(sa, a0, r), TunnelMath.point(sb, a0, r),
		TunnelMath.point(sb, a1, r), TunnelMath.point(sa, a1, r),
		normal, Kind.WALL)


## Rim along the tunnel (a hole edge at constant angle). It starts at the
## outline strip's height, not the wall's, so strip and rim share an edge
## and no sliver of wall shows between them at grazing angles.
static func _side_rim(tool: SurfaceTool, r: float, sa: float, sb: float, angle: float) -> void:
	var inner := r - OUTLINE_LIFT
	var outer := r + WALL_THICKNESS
	_quad(tool,
		TunnelMath.point(sa, angle, inner), TunnelMath.point(sa, angle, outer),
		TunnelMath.point(sb, angle, outer), TunnelMath.point(sb, angle, inner),
		TunnelMath.tangent(angle), Kind.RIM)


## Rim across the tunnel (a hole edge at constant s).
static func _end_rim(tool: SurfaceTool, r: float, s: float, a0: float, a1: float) -> void:
	var inner := r - OUTLINE_LIFT
	var outer := r + WALL_THICKNESS
	_quad(tool,
		TunnelMath.point(s, a0, inner), TunnelMath.point(s, a0, outer),
		TunnelMath.point(s, a1, outer), TunnelMath.point(s, a1, inner),
		Vector3(0.0, 0.0, 1.0), Kind.RIM)


## Outline strip on the wall surface, slightly lifted towards the axis.
static func _outline(tool: SurfaceTool, r: float, sa: float, sb: float, a0: float, a1: float) -> void:
	var lifted := r - OUTLINE_LIFT
	_quad(tool,
		TunnelMath.point(sa, a0, lifted), TunnelMath.point(sb, a0, lifted),
		TunnelMath.point(sb, a1, lifted), TunnelMath.point(sa, a1, lifted),
		TunnelMath.inward((a0 + a1) * 0.5), Kind.OUTLINE)
