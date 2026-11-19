class_name TunnelMesher
extends RefCounted
## Builds the tunnel's geometry for one stretch ("chunk") of a level: the
## floor with every hole really cut out of it, and the shell's cut faces
## welded to every edge of those holes.
##
## The shape comes from LevelData.floor_distance(), the very function the
## simulation falls by, so the floor you see is the floor you roll on (to a
## few millimetres). Nothing is cut per pixel and nothing is ray-marched:
## every edge is a triangle edge, which the GPU's MSAA smooths, and a cut
## face cannot come loose from its floor edge because the two share their
## vertices exactly.
##
## How: the unrolled wall is a grid of COLUMNS around the tunnel and rows of
## FINE metres along it. Cells beyond the outline's reach of any edge
## (INK_REACH; checked on a coarse grid of BAND rows, using how fast the
## distance field can change) become long plain quads, flat in edge
## distance; cells nearer an edge are cut by marching squares, which puts
## a vertex where the field crosses zero on each grid edge. Every crossing
## is computed once per grid edge from the same two values, so neighbouring
## cells and neighbouring chunks meet exactly, without cracks or overlaps.
## Each contour segment is extruded outwards through the shell into a cut
## face. The floor's vertices carry the distance to the edge (UV.x), from
## which tunnel_floor.gdshader draws the black outline.
##
## No T-junctions: a long plain quad's sides pick up every vertex that a
## neighbouring cell put on the same grid line, so no vertex ever sits in
## the middle of another triangle's edge (where rounding on the GPU would
## open pinholes of void).
##
## Pure data in, arrays out: no nodes, safe to run on a worker thread.

## Grid columns around the tunnel. 192 keeps facets and edges smooth on a
## phone screen (the tube's facets are 0.3 mm off a true circle).
const COLUMNS := 192
## Fine row length along the tunnel. A power of two, so every row lands on
## an exactly representable distance and chunks share their boundary rows
## bit for bit.
const FINE := 0.125
## Fine rows per coarse band (BAND = 1 m).
const SUB_ROWS := 8
const BAND := FINE * SUB_ROWS
## The floor's black outline: this many metres of floor along every edge.
const OUTLINE_WIDTH := 0.25
## tunnel_floor.gdshader keeps the outline at least a pixel and a half wide
## far away, but never wider than this.
const OUTLINE_MAX_WIDTH := OUTLINE_WIDTH * 1.6
## The farthest from an edge that any ink can reach: the widest band plus
## its soft inner side (at most half its width more). Cells that may
## contain any floor this close to an edge are always refined, so there
## the interpolated edge distance is the true one. Long plain strips only
## cover floor further away than this: interpolating along them can be
## wildly off (a strip from one hole's corner to the next carries a small
## distance at both ends), but never down into the ink. Refining only up
## to OUTLINE_WIDTH is what drew thin stray lines between hole corners.
const INK_REACH := OUTLINE_MAX_WIDTH * 1.5
## Upper bound of |gradient| of floor_distance(). Each hole is a rounded
## box in skewed coordinates (at most sqrt(2)); the smooth union never
## exceeds the larger of its inputs. Used to prove a cell has no edge in it.
const LIPSCHITZ := 1.42
## The edge distance every vertex of a plain strip carries, instead of its
## own. Every strip lies beyond INK_REACH (its vertices are at least
## INK_REACH + fine_reach, so at least INK_REACH + 0.089, from an edge),
## where the value has no use, and a constant makes every strip perfectly
## flat. That matters twice. fwidth() reads a slope as "far away" and
## widens the outline (strips once carried distances up to 8 m, with
## steep fake slopes next to INF). And with MSAA a pixel that a sliver of
## a strip only grazes is shaded at the pixel's centre, outside the
## triangle, with the edge distance extrapolated: on a slope that dips into
## the ink and leaves a faint dotted line along the strip. On a flat strip
## it cannot. Cut cells carry their exact distances (always finite there).
const PLAIN_DISTANCE := INK_REACH + 0.05

## A built chunk, ready to become an ArrayMesh (see to_mesh()).
class Geometry:
	var floor_vertices := PackedVector3Array()
	var floor_uvs := PackedVector2Array()
	var floor_indices := PackedInt32Array()
	var wall_vertices := PackedVector3Array()
	var wall_uvs := PackedVector2Array()
	var wall_indices := PackedInt32Array()
	## Distance-field evaluations it took (for performance tests).
	var evaluations := 0

	func triangle_count() -> int:
		return (floor_indices.size() + wall_indices.size()) / 3


var _level: LevelData
var _window: Array[HoleData]
var _s0: float
var _rows: int
var _radius: float
var _outer: float
var _sin := PackedFloat64Array()
var _cos := PackedFloat64Array()
## Distance at every grid node (row-major: row * COLUMNS + column), NAN until evaluated.
var _d := PackedFloat64Array()
## 1 where a floor vertex sits on grid node (row, column), same layout as _d.
var _marks := PackedByteArray()
## Plain floor runs, three ints each: column, first row, end row.
var _runs := PackedInt32Array()
var _geometry: Geometry


## Builds [s0, s1). s0 and s1 must be whole multiples of BAND.
static func build(level: LevelData, s0: float, s1: float, shell_thickness: float = TunnelMath.WALL_THICKNESS) -> Geometry:
	var mesher := TunnelMesher.new()
	return mesher._build(level, s0, s1, shell_thickness)


static func to_mesh(geometry: Geometry, floor_material: Material, wall_material: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if not geometry.floor_indices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = geometry.floor_vertices
		arrays[Mesh.ARRAY_TEX_UV] = geometry.floor_uvs
		arrays[Mesh.ARRAY_INDEX] = geometry.floor_indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, floor_material)
	if not geometry.wall_indices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = geometry.wall_vertices
		arrays[Mesh.ARRAY_TEX_UV] = geometry.wall_uvs
		arrays[Mesh.ARRAY_INDEX] = geometry.wall_indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, wall_material)
	return mesh


## Angle of grid column `column` (radians).
static func column_angle(column: int) -> float:
	return TAU * float(column) / COLUMNS


func _build(level: LevelData, s0: float, s1: float, shell_thickness: float) -> Geometry:
	_level = level
	_s0 = s0
	_rows = int(round((s1 - s0) / FINE))
	assert(_rows % SUB_ROWS == 0, "chunks must be whole bands")
	_radius = level.tunnel_radius
	_outer = level.tunnel_radius + shell_thickness
	_window = level.holes_window(s0, s1)
	_geometry = Geometry.new()
	_sin.resize(COLUMNS)
	_cos.resize(COLUMNS)
	for k in COLUMNS:
		var a := column_angle(k)
		_sin[k] = sin(a)
		_cos[k] = cos(a)
	_d.resize((_rows + 1) * COLUMNS)
	_d.fill(NAN)
	_marks.resize((_rows + 1) * COLUMNS)
	_marks.fill(0)
	_runs.clear()

	var band_count := _rows / SUB_ROWS
	# Coarse cells: half the diagonal, and what the field must exceed at all
	# four corners for the whole cell to be plain floor (outline included) or
	# plain void.
	var column_width := TAU * _radius / COLUMNS
	var coarse_reach := LIPSCHITZ * 0.5 * sqrt(BAND * BAND + column_width * column_width)
	var fine_reach := LIPSCHITZ * 0.5 * sqrt(FINE * FINE + column_width * column_width)
	var coarse_floor := INK_REACH + coarse_reach
	var coarse_void := -coarse_reach
	var fine_floor := INK_REACH + fine_reach

	for k in COLUMNS:
		var k2 := (k + 1) % COLUMNS
		var run_start := -1  # first row of a run of plain floor in this column
		for band in band_count:
			var r0 := band * SUB_ROWS
			var r1 := r0 + SUB_ROWS
			var a := _node(r0, k)
			var b := _node(r0, k2)
			var c := _node(r1, k)
			var e := _node(r1, k2)
			var low := minf(minf(a, b), minf(c, e))
			var high := maxf(maxf(a, b), maxf(c, e))
			if low > coarse_floor:
				if run_start < 0:
					run_start = r0
				continue
			if high < coarse_void:
				run_start = _flush(run_start, r0, k, k2)
				continue
			for row in range(r0, r1):
				a = _node(row, k)
				b = _node(row, k2)
				c = _node(row + 1, k)
				e = _node(row + 1, k2)
				low = minf(minf(a, b), minf(c, e))
				if low > fine_floor:
					if run_start < 0:
						run_start = row
					continue
				run_start = _flush(run_start, row, k, k2)
				if maxf(maxf(a, b), maxf(c, e)) < 0.0:
					continue
				_march(row, k, k2, a, b, e, c)
		_flush(run_start, _rows, k, k2)
	for i in range(0, _runs.size(), 3):
		_emit_run(_runs[i], _runs[i + 1], _runs[i + 2])
	return _geometry


## Distance at grid node (row, column), evaluated once.
func _node(row: int, column: int) -> float:
	var i := row * COLUMNS + column
	var d := _d[i]
	if is_nan(d):
		d = _level.floor_distance_in(_window, 0, _row_s(row), column_angle(column))
		_d[i] = d
		_geometry.evaluations += 1
	return d


func _row_s(row: int) -> float:
	return _s0 + row * FINE


## Records the plain floor of column k from row `from` to row `to` (built
## once every cell is done, see _emit_run). Returns -1 (no run open any more).
func _flush(from: int, to: int, k: int, k2: int) -> int:
	if from < 0 or to <= from:
		return -1
	_runs.append_array([k, from, to])
	_mark(from, k)
	_mark(from, k2)
	_mark(to, k)
	_mark(to, k2)
	return -1


func _mark(row: int, column: int) -> void:
	_marks[row * COLUMNS + column] = 1


## A run of plain floor: one long strip between grid lines k and k + 1,
## zipped together from every vertex either line has within the run.
func _emit_run(k: int, from: int, to: int) -> void:
	var k2 := (k + 1) % COLUMNS
	var left := _line_rows(k, from, to)
	var right := _line_rows(k2, from, to)
	var base := _geometry.floor_vertices.size()
	for row in left:
		_floor_vertex_node(row, k)
	var right_base := base + left.size()
	for row in right:
		_floor_vertex_node(row, k2)
	var i := 0
	var j := 0
	var last_i := left.size() - 1
	var last_j := right.size() - 1
	while i < last_i or j < last_j:
		if j == last_j or (i < last_i and left[i + 1] <= right[j + 1]):
			_geometry.floor_indices.append_array([base + i, right_base + j, base + i + 1])
			i += 1
		else:
			_geometry.floor_indices.append_array([base + i, right_base + j, right_base + j + 1])
			j += 1


## Rows from `from` to `to` (both included) at which grid line `column` has a vertex.
func _line_rows(column: int, from: int, to: int) -> PackedInt32Array:
	var rows := PackedInt32Array([from])
	for row in range(from + 1, to):
		if _marks[row * COLUMNS + column]:
			rows.append(row)
	rows.append(to)
	return rows


func _floor_vertex_node(row: int, column: int) -> void:
	_geometry.floor_vertices.append(_point_on_column(_row_s(row), column, _radius))
	_geometry.floor_uvs.append(Vector2(PLAIN_DISTANCE, 0.0))


func _point_on_column(s: float, column: int, r: float) -> Vector3:
	return Vector3(r * _sin[column], -r * _cos[column], -s)


# --- Marching squares ------------------------------------------------------------
#
# The cell's corners, walked round its edge:
#   p0 = (row, k)   p1 = (row, k2)   p2 = (row + 1, k2)   p3 = (row + 1, k)
# A point is a crossing (where the field is 0) or a corner; each carries its
# surface position (s, angle) so walls can be extruded from it.

## A point of a cell polygon: surface position and distance-field value.
class Point:
	var s: float
	var column: int    # >= 0: lies on this grid column (exact table position)
	var angle: float   # used when column < 0
	var d: float
	var crossing: bool

	func _init(p_s: float, p_column: int, p_angle: float, p_d: float, p_crossing: bool) -> void:
		s = p_s
		column = p_column
		angle = p_angle
		d = p_d
		crossing = p_crossing


func _march(row: int, k: int, k2: int, d0: float, d1: float, d2: float, d3: float) -> void:
	var corners: Array[Point] = [
		Point.new(_row_s(row), k, 0.0, d0, false),
		Point.new(_row_s(row), k2, 0.0, d1, false),
		Point.new(_row_s(row + 1), k2, 0.0, d2, false),
		Point.new(_row_s(row + 1), k, 0.0, d3, false),
	]
	var crossings: Array[Point] = [
		_crossing_on_row(row, k, k2, d0, d1),      # edge p0-p1
		_crossing_on_column(row, k2, d1, d2),      # edge p1-p2
		_crossing_on_row(row + 1, k, k2, d3, d2),  # edge p2-p3 (computed k -> k2)
		_crossing_on_column(row, k, d0, d3),       # edge p3-p0 (computed row -> row + 1)
	]
	var solid := [d0 >= 0.0, d1 >= 0.0, d2 >= 0.0, d3 >= 0.0]
	if solid[0]:
		_mark(row, k)
	if solid[1]:
		_mark(row, k2)
	if solid[2]:
		_mark(row + 1, k2)
	if solid[3]:
		_mark(row + 1, k)

	# Walk the edge of the cell: floor corners, and a crossing wherever the
	# sign changes.
	var polygon: Array[Point] = []
	for i in 4:
		if solid[i]:
			polygon.append(corners[i])
		if solid[i] != solid[(i + 1) % 4]:
			polygon.append(crossings[i])

	var saddle: bool = solid[0] == solid[2] and solid[1] == solid[3] and solid[0] != solid[1]
	if saddle and (d0 + d1 + d2 + d3) * 0.25 < 0.0:
		# Two separate pieces of floor: split at the crossings.
		var pieces: Array = []
		var current: Array[Point] = []
		# Rotate so the walk starts right after a crossing pair boundary.
		var start := 0
		while not (polygon[start].crossing and polygon[(start + polygon.size() - 1) % polygon.size()].crossing):
			start += 1
		for i in polygon.size():
			var p := polygon[(start + i) % polygon.size()]
			current.append(p)
			if p.crossing and current.size() > 1:
				pieces.append(current)
				current = []
		for piece in pieces:
			_emit_piece(piece)
	else:
		_emit_piece(polygon)


## Crossing on the row edge between columns k and k2 (always computed in
## that order, so the cells above and below get the same point).
func _crossing_on_row(row: int, k: int, k2: int, dk: float, dk2: float) -> Point:
	if (dk >= 0.0) == (dk2 >= 0.0):
		return null
	var t := _snap(dk / (dk - dk2))
	if t == 0.0:
		return Point.new(_row_s(row), k, 0.0, 0.0, true)
	if t == 1.0:
		return Point.new(_row_s(row), k2, 0.0, 0.0, true)
	var angle := (float(k) + t) * TAU / COLUMNS
	return Point.new(_row_s(row), -1, angle, 0.0, true)


## Crossing on column `column` between `row` and `row + 1` (always in that order).
func _crossing_on_column(row: int, column: int, d_low: float, d_high: float) -> Point:
	if (d_low >= 0.0) == (d_high >= 0.0):
		return null
	var t := _snap(d_low / (d_low - d_high))
	if t == 1.0:
		return Point.new(_row_s(row + 1), column, 0.0, 0.0, true)
	return Point.new(_row_s(row) + t * FINE, column, 0.0, 0.0, true)


## An edge that passes within a hair of a grid node crosses exactly at the
## node, so the crossing and the corner are the same vertex, bit for bit
## (and the sliver triangle between them is dropped as degenerate).
static func _snap(t: float) -> float:
	if t < 1e-5:
		return 0.0
	if t > 1.0 - 1e-5:
		return 1.0
	return t


## One convex piece of floor: a triangle fan, plus a cut face on every
## stretch of contour (two crossings in a row).
func _emit_piece(piece: Array) -> void:
	var count := piece.size()
	if count < 3:
		return
	var base := _geometry.floor_vertices.size()
	for p: Point in piece:
		_geometry.floor_vertices.append(_position(p, _radius))
		_geometry.floor_uvs.append(Vector2(p.d, 0.0))
	# Where an edge runs exactly through a grid node, a crossing lands on a
	# corner: skip the triangles that collapse to a line or a point.
	var v := _geometry.floor_vertices
	for i in range(1, count - 1):
		var p0 := v[base]
		var p1 := v[base + i]
		var p2 := v[base + i + 1]
		if (p1 - p0).cross(p2 - p0).length_squared() > 1e-22:
			_geometry.floor_indices.append_array([base, base + i, base + i + 1])
	for i in count:
		var a: Point = piece[i]
		var b: Point = piece[(i + 1) % count]
		if a.crossing and b.crossing:
			_emit_wall(a, b)


func _emit_wall(a: Point, b: Point) -> void:
	var top_a := _position(a, _radius)
	var top_b := _position(b, _radius)
	if top_a.is_equal_approx(top_b):
		return
	# UV: x = depth through the shell (0 at the floor, 1 at the back),
	# y = 1 when the face runs along the tunnel, 0 when it runs around it.
	var along := absf(top_a.z - top_b.z) > top_a.distance_to(top_b) * 0.7071
	var axis := 1.0 if along else 0.0
	var base := _geometry.wall_vertices.size()
	_geometry.wall_vertices.append(top_a)
	_geometry.wall_vertices.append(top_b)
	_geometry.wall_vertices.append(_position(b, _outer))
	_geometry.wall_vertices.append(_position(a, _outer))
	_geometry.wall_uvs.append(Vector2(0.0, axis))
	_geometry.wall_uvs.append(Vector2(0.0, axis))
	_geometry.wall_uvs.append(Vector2(1.0, axis))
	_geometry.wall_uvs.append(Vector2(1.0, axis))
	_geometry.wall_indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


func _position(p: Point, r: float) -> Vector3:
	if p.column >= 0:
		return _point_on_column(p.s, p.column, r)
	return Vector3(r * sin(p.angle), -r * cos(p.angle), -p.s)
