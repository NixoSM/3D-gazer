// Shared by the tunnel's inner surface (tunnel.gdshader) and the shell's
// cut faces (tunnel_shell.gdshader): the holes' signed-distance field.
// A line-for-line copy of HoleData.signed_distance and
// LevelData.floor_distance; keep the three in step.

// Keep in step with HoleData.CORNER_RADIUS and LevelData.BLEND.
const float CORNER_RADIUS = 0.6;
const float BLEND = 1.2;
const float REACH = BLEND + CORNER_RADIUS + 1.0;

uniform float tunnel_radius = 4.0;

float wrap_angle(float a) {
	return mod(a + PI, TAU) - PI;
}

#ifdef HOLES_BAKED
// The game's 3D shaders do not evaluate the field: TunnelView bakes it once
// per level into a texture (hole_field_bake.gdshader runs the functions
// below), and a pixel takes one filtered sample. Per-pixel maths over every
// nearby hole, repeated along each ray through the shell, was the game's
// whole GPU cost.
//
// Layout: the level is cut into strips of `x` metres, each baked with `y`
// metres of guard at both ends, at `z` texels per metre; `w` strips are
// stacked down the texture, each FIELD_ROWS rows around the tunnel plus
// FIELD_GUARD_ROWS wrapped rows above and below, so filtering never reads a
// neighbouring strip.
const float FIELD_ROWS = 256.0;
const float FIELD_GUARD_ROWS = 2.0;
// Stored as d / FIELD_RANGE * 0.5 + 0.5.
const float FIELD_RANGE = 2.0;
uniform sampler2D hole_field : filter_linear, repeat_disable;
uniform vec4 field_layout = vec4(480.0, 1.0, 8.0, 1.0);

// > 0 on floor, < 0 over a hole (metres, clamped to the baked range).
float floor_distance(float s, float angle) {
	float strip = clamp(floor(s / field_layout.x), 0.0, field_layout.w - 1.0);
	float width = (field_layout.x + 2.0 * field_layout.y) * field_layout.z;
	float x = clamp((s - strip * field_layout.x + field_layout.y) * field_layout.z, 0.5, width - 0.5);
	float strip_rows = FIELD_ROWS + 2.0 * FIELD_GUARD_ROWS;
	float y = strip * strip_rows + FIELD_GUARD_ROWS + fract(angle / TAU) * FIELD_ROWS;
	float stored = textureLod(hole_field, vec2(x / width, y / (strip_rows * field_layout.w)), 0.0).r;
	return (stored - 0.5) * 2.0 * FIELD_RANGE;
}
#else
// Holes: two RGBA float texels per hole, sorted by start:
//   (s_start, length, angle_center, angle_width), (twist, 0, 0, 0)
uniform sampler2D hole_data : filter_nearest, repeat_disable;
// Which holes can touch this chunk of tube (set per chunk). The level
// editor's 2D strip (canvas_item, no instance uniforms) defines
// HOLES_PLAIN_UNIFORMS and sets them as ordinary uniforms instead.
#ifdef HOLES_PLAIN_UNIFORMS
uniform int hole_first = 0;
uniform int hole_count = 0;
#else
instance uniform int hole_first = 0;
instance uniform int hole_count = 0;
#endif

// HoleData.signed_distance
float hole_distance(vec4 a, float twist, float s, float angle) {
	float half_length = a.y * 0.5;
	float y = abs(s - (a.x + half_length)) - half_length;
	if (a.w >= TAU - 0.0001) {
		return y;
	}
	float slope = twist * tunnel_radius;
	float slant = 1.0 / sqrt(1.0 + slope * slope);
	float half_width = a.w * 0.5 * tunnel_radius;
	float x = (abs(wrap_angle(angle - (a.z + twist * (s - a.x)))) * tunnel_radius - half_width) * slant;
	float corner = min(CORNER_RADIUS, min(half_width * slant, half_length) * 0.9);
	vec2 q = vec2(x, y) + corner;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner;
}

// LevelData.smooth_min
float smooth_min(float a, float b) {
	float h = max(BLEND - abs(a - b), 0.0) / BLEND;
	return min(a, b) - h * h * BLEND * 0.25;
}

// LevelData.floor_distance: > 0 on floor, < 0 over a hole.
float floor_distance(float s, float angle) {
	float d = 1e6;
	for (int i = 0; i < hole_count; i++) {
		int index = (hole_first + i) * 2;
		vec4 a = texelFetch(hole_data, ivec2(index, 0), 0);
		if (a.x > s + REACH || a.x + a.y < s - REACH) {
			continue;
		}
		float twist = texelFetch(hole_data, ivec2(index + 1, 0), 0).x;
		d = smooth_min(d, hole_distance(a, twist, s, angle));
	}
	return d;
}

#endif

// The floor's rounded tiles (a running bond), shared so the cut faces can
// continue the tiles' seams: signed distance to the tile's edge (< 0 in a
// seam), plus which tile it is (x = row, y = column).
float tile_box(float u, float v, float band_length, out vec2 tile) {
	float tiles_around = 10.0;
	float tile_v = TAU * tunnel_radius / tiles_around;
	float tile_u = band_length * 1.3;
	float row = floor(u / tile_u);
	float shifted = v + mod(row, 2.0) * tile_v * 0.5;
	tile = vec2(row, floor(shifted / tile_v));
	vec2 cell = vec2(mod(u, tile_u) - tile_u * 0.5, mod(shifted, tile_v) - tile_v * 0.5);
	vec2 q = abs(cell) - vec2(tile_u, tile_v) * 0.5 + 0.09 + 0.35;
	return -(length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - 0.35);
}
