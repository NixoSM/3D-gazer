// The tunnel wall, drawn like an old Flash game: flat bright colours, hard
// two-tone shading, thick black outlines. No textures, no realistic lighting.
//
// The geometry is a plain tube. Holes are cut here, per pixel, from the same
// signed-distance field the simulation uses (LevelData.floor_distance and
// HoleData.signed_distance; keep the three in step): rounded corners, holes
// that touch blend into one opening, slanted (twisted) holes have straight
// diagonal edges. The outline is the band of floor nearest the edge, so it
// only exists where there is floor: nothing floats in the void.
//
// Everything else is computed from the fragment's tunnel coordinates (s
// along the axis, angle around it):
//   * colour        = palette sampled at s / level_length
//   * floor pattern = one of a few flat looks (see `pattern`), fixed to
//                     the wall like the holes
//   * contact shadow= a hard-edged blob under the ball
//   * echo waves    = floor tiles lighting up as a wave spreads from the echo
//   * best marker   = a dashed ring where your best attempt ended
//   * finish line   = a chequered band
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

const int MAX_RIPPLES = 6;

#define HOLES_BAKED
#include "res://shaders/holes.gdshaderinc"

uniform sampler2D wall_gradient : source_color, filter_linear, repeat_disable;
uniform sampler2D accent_gradient : source_color, filter_linear, repeat_disable;
uniform float level_length = 600.0;
uniform vec3 outline_color : source_color = vec3(0.04, 0.03, 0.06);

// Look
uniform int pattern = 1;               // 0 bands, 1 tiles, 2 stripes, 3 diamonds, 4 plain
uniform float band_length = 3.0;       // metres per pattern repeat along the tunnel (shorter on faster levels)
uniform float pattern_contrast = 0.14; // how much darker the dark parts of the pattern are
uniform float shade_dark = 0.72;       // brightness of the "ceiling" half
uniform float outline_width = 0.2;     // metres of black along every edge

// Ball (s, angle, height) and radius, for the contact shadow and shading.
uniform vec3 ball = vec3(0.0);
uniform float ball_radius = 0.42;

// Echo ripples: xyzw = (s, angle, start_time, strength). strength 0 = unused.
uniform vec4 ripples[MAX_RIPPLES];
uniform float now = 0.0;
uniform float ripple_speed = 15.0;
uniform float ripple_life = 1.0;

uniform float best_s = -1.0;
uniform float fog_distance = 95.0;
uniform vec3 fog_color : source_color = vec3(0.1);
uniform float fade = 0.0;          // 0..1, fades everything to fade_color (fail / transitions)
uniform vec3 fade_color : source_color = vec3(0.0);

varying vec3 world_pos;

// Distance between two points on the cylinder surface, the short way round.
float surface_distance(float s0, float a0, float s1, float a1) {
	return length(vec2(s1 - s0, tunnel_radius * wrap_angle(a1 - a0)));
}

// Anti-aliased "inside" test for a value against a threshold: crisp but not jagged.
float inside(float value, float threshold) {
	float w = max(fwidth(value), 0.0001);
	return 1.0 - smoothstep(threshold - w, threshold + w, value);
}

// The floor's own look, before shading. `u` runs along the tunnel, `v`
// around it (metres). Returns how dark (0..1).
float floor_pattern(float u, float v, float distance_fade) {
	float circumference = TAU * tunnel_radius;
	if (pattern == 0) {
		// Alternating rings, plus thin lanes.
		float band = mod(floor(u / band_length), 2.0);
		float lane_width = circumference / 6.0;
		float lane = abs(fract(v / lane_width) - 0.5) * lane_width;
		return band * distance_fade + inside(abs(lane - lane_width * 0.5), 0.04) * distance_fade * 2.5;
	}
	if (pattern == 1) {
		// Big rounded tiles in a running bond, separated by soft seams.
		vec2 tile;
		float box = -tile_box(u, v, band_length, tile);
		float seam = 1.0 - inside(box, 0.0);
		// Alternate tiles a touch lighter, like a hand-painted floor.
		float checker = mod(tile.x + tile.y, 2.0);
		return (seam * 1.6 + checker * 0.45) * distance_fade;
	}
	if (pattern == 2) {
		// Diagonal stripes wound around the tube like a barber's pole.
		float period = 2.8;
		float phase = (u * 0.65 + v) / period;
		float stripe = abs(fract(phase) - 0.5) * period;
		return inside(stripe, period * 0.22) * distance_fade * 1.3;
	}
	if (pattern == 3) {
		// Rounded diamonds (an argyle of panels), alternate ones darker.
		float size = 2.2;
		vec2 p = vec2(u + v, v - u) * 0.70710678 / size;
		vec2 cell = fract(p) - 0.5;
		vec2 q = abs(cell) * size - size * 0.5 + 0.07 + 0.3;
		float box = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - 0.3;
		float seam = 1.0 - inside(box, 0.0);
		float checker = mod(floor(p.x) + floor(p.y), 2.0);
		return (seam * 1.6 + checker * 0.7) * distance_fade;
	}
	return 0.0;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float s = -world_pos.z;
	float angle = atan(world_pos.x, -world_pos.y);

	// --- Cut the holes ------------------------------------------------------------
	float d = floor_distance(s, angle);
	// Screen-space size of the edge band. Measured on d clamped near the
	// edge: far from any hole, d jumps where a hole enters this pixel's
	// search range, and those jumps must not count as "edges".
	float pixel = max(fwidth(min(d, 1.0)), 0.0001);
	if (d < 0.0) {
		discard;
	}

	float progress = clamp(s / level_length, 0.0, 1.0);
	vec3 wall = texture(wall_gradient, vec2(progress, 0.5)).rgb;
	vec3 accent = texture(accent_gradient, vec2(progress, 0.5)).rgb;
	float arc = wrap_angle(angle - ball.y) * tunnel_radius;
	float distance_to_camera = length(world_pos - CAMERA_POSITION_WORLD);

	// --- Flat colour and the floor pattern ---------------------------------------
	// Patterns fade out in the distance, where they would shimmer.
	float pattern_fade = 1.0 - smoothstep(28.0, 60.0, distance_to_camera);
	float v = wrap_angle(angle) * tunnel_radius + PI * tunnel_radius;
	vec3 color = wall * (1.0 - clamp(floor_pattern(s, v, pattern_fade), 0.0, 1.6) * pattern_contrast);

	// --- Hard two-tone shading: the half of the tunnel above the ball is darker,
	// like a cel-shaded cartoon.
	float facing = cos(wrap_angle(angle - ball.y));
	float lit = 1.0 - inside(facing, -0.15);
	color *= mix(shade_dark, 1.0, lit);

	// --- Contact shadow: a hard-edged blob ------------------------------------------
	float h = max(ball.z, 0.0);
	float d_ball = length(vec2((s - ball.x) * 0.85, arc));
	float shadow_radius = ball_radius * mix(1.0, 0.55, clamp(h / 3.5, 0.0, 1.0));
	color = mix(color, color * 0.55, inside(d_ball, shadow_radius));

	// --- Echo waves: whole floor tiles light up as the wave reaches their
	// centre; lit tiles turn the accent colour and their seams turn black.
	vec2 tile;
	float echo_box = tile_box(s, v, band_length, tile);
	float echo_seam = 1.0 - smoothstep(-0.02, 0.02, echo_box);
	float tile_v = TAU * tunnel_radius / 10.0;
	float tile_u = band_length * 1.3;
	float centre_s = (tile.x + 0.5) * tile_u;
	float centre_v = (tile.y + 0.5) * tile_v - mod(tile.x, 2.0) * tile_v * 0.5;
	float centre_angle = (centre_v - PI * tunnel_radius) / tunnel_radius;
	for (int i = 0; i < MAX_RIPPLES; i++) {
		vec4 r = ripples[i];
		if (r.w <= 0.0) continue;
		float age = now - r.z;
		if (age < 0.0 || age > ripple_life) continue;
		float life = 1.0 - age / ripple_life;
		float front = age * ripple_speed;
		float strength = min(r.w, 1.5);
		float tile_distance = surface_distance(r.x, r.y, centre_s, centre_angle);
		float wave = 1.0 - smoothstep(tile_u * 0.35, tile_u * 0.75, abs(tile_distance - front));
		float lit = clamp(wave * (0.4 + 0.6 * life) * strength, 0.0, 1.0);
		color = mix(color, mix(accent, outline_color, echo_seam), lit);
	}

	// --- Best run marker: dashed black/white ring --------------------------------
	if (best_s > 0.0) {
		float db = abs(s - best_s);
		float dash = step(0.5, fract(angle / TAU * 32.0));
		color = mix(color, outline_color, inside(db, 0.16));
		color = mix(color, mix(vec3(1.0), accent, dash), inside(db, 0.1));
	}

	// --- Finish line: chequered band ------------------------------------------------
	float to_finish = s - level_length;
	if (to_finish > -1.5 && to_finish < 1.5) {
		float check = mod(floor(angle / TAU * 24.0) + floor((to_finish + 1.5) / 0.75), 2.0);
		color = mix(vec3(1.0), outline_color, check);
	}

	// --- Edges: the thick black outline ---------------------------------------------
	// A fixed width on the wall. (It used to be widened to at least two
	// pixels, measured with fwidth(d); at grazing angles that measure is
	// several times the true pixel size, and far corners grew black spikes.)
	float soft = min(pixel, outline_width * 0.6);
	color = mix(color, outline_color, 1.0 - smoothstep(outline_width - soft, outline_width + soft, d));

	// --- Distance fades into the void colour, along the tunnel ---------------------
	float ahead = s + CAMERA_POSITION_WORLD.z;
	color = mix(color, fog_color, smoothstep(fog_distance * 0.3, fog_distance, ahead));
	color = mix(color, fade_color, fade);

	ALBEDO = color;
}
