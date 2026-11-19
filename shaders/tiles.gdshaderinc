// The floor's rounded tiles (a running bond), shared by the floor and the
// cut faces so the tile seams carry on down the faces ("blocks").
//
// u runs along the tunnel, v around it (metres). Returns the signed
// distance to the tile's edge (< 0 in a seam) and which tile it is
// (x = row, y = column).

const float TILES_AROUND = 10.0;
const float TILE_SEAM = 0.09;
const float TILE_CORNER = 0.35;

uniform float tunnel_radius = 4.0;
// Tile length along the tunnel is band_length * 1.3 (shorter on fast levels).
uniform float band_length = 3.0;

float tile_v_size() {
	return TAU * tunnel_radius / TILES_AROUND;
}

float tile_u_size() {
	return band_length * 1.3;
}

float tile_box(float u, float v, out vec2 tile) {
	float tile_v = tile_v_size();
	float tile_u = tile_u_size();
	float row = floor(u / tile_u);
	float shifted = v + mod(row, 2.0) * tile_v * 0.5;
	tile = vec2(row, floor(shifted / tile_v));
	vec2 cell = vec2(mod(u, tile_u) - tile_u * 0.5, mod(shifted, tile_v) - tile_v * 0.5);
	vec2 q = abs(cell) - vec2(tile_u, tile_v) * 0.5 + TILE_SEAM + TILE_CORNER;
	return -(length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - TILE_CORNER);
}

// Distance (m) to the nearest seam that runs around the tunnel (between
// tile rows) and to the nearest seam that runs along it (between columns).
vec2 seam_distances(float u, float v) {
	float tile_v = tile_v_size();
	float tile_u = tile_u_size();
	float row = floor(u / tile_u);
	float cu = mod(u, tile_u);
	float shifted = v + mod(row, 2.0) * tile_v * 0.5;
	float cv = mod(shifted, tile_v);
	return vec2(min(cu, tile_u - cu), min(cv, tile_v - cv));
}

// Wall position around the tunnel as a distance (m), continuous across the
// top of the tunnel (TILES_AROUND is even, so tile columns line up there).
float wall_v(float angle) {
	return (mod(angle + PI, TAU)) * tunnel_radius;
}

// Material IDs for the pixel test (tools/visual_audit): flat primaries that
// survive sRGB conversion unchanged.
const vec3 ID_VOID = vec3(0.0, 0.0, 1.0);
const vec3 ID_FLOOR = vec3(0.0, 1.0, 0.0);
const vec3 ID_OUTLINE = vec3(1.0, 0.0, 0.0);
const vec3 ID_WALL = vec3(1.0, 1.0, 0.0);
const vec3 ID_BACKLINE = vec3(1.0, 0.0, 1.0);
const vec3 ID_BALL = vec3(1.0, 1.0, 1.0);
