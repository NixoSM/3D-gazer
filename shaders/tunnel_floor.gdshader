// The tunnel's floor (its inner surface), drawn like an old Flash game:
// flat bright colours, hard two-tone shading, thick black outlines.
//
// The holes are already cut out of the geometry (TunnelMesher), so this
// shader never discards anything. Each vertex carries its distance to the
// nearest edge (UV.x); the black outline is the floor within
// `outline_width` of an edge, so it only exists where there is floor.
//
// Everything else comes from the fragment's tunnel coordinates (s along the
// axis, angle around it):
//   * colour        = palette sampled at s / level_length
//   * floor pattern = big rounded tiles, fixed to the wall like the holes
//   * contact shadow= a hard-edged blob under the ball
//   * echo waves    = floor tiles lighting up as a wave spreads from the echo
//   * best marker   = a dashed ring where your best attempt ended
//   * finish line   = a chequered band
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

#include "res://shaders/tiles.gdshaderinc"

const int MAX_RIPPLES = 6;

// 1 = draw material IDs instead of colours (tools/visual_audit).
global uniform int gazer_debug_ids;

uniform sampler2D wall_gradient : source_color, filter_linear, repeat_disable;
uniform sampler2D accent_gradient : source_color, filter_linear, repeat_disable;
uniform float level_length = 600.0;
uniform vec3 outline_color : source_color = vec3(0.04, 0.03, 0.06);

// Look
uniform float pattern_contrast = 0.14; // how much darker the dark parts of the pattern are
uniform float shade_dark = 0.72;       // brightness of the "ceiling" half
uniform float outline_width = 0.25;    // metres of black along every edge (TunnelMesher.OUTLINE_WIDTH)
// Like an inked line, the outline stays about the same thickness on screen:
// never thicker than this share of the screen height (close to the camera
// a quarter metre would be a huge black wedge), never thinner than
// outline_min_pixels (far away it would vanish).
uniform float outline_max_screen = 0.011;
uniform float outline_min_pixels = 1.5;

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
varying float edge_distance;

float wrap_angle(float a) {
	return mod(a + PI, TAU) - PI;
}

// Distance between two points on the cylinder surface, the short way round.
float surface_distance(float s0, float a0, float s1, float a1) {
	return length(vec2(s1 - s0, tunnel_radius * wrap_angle(a1 - a0)));
}

// Anti-aliased "inside" test for a value against a threshold: crisp but not jagged.
float inside(float value, float threshold) {
	float w = max(fwidth(value), 0.0001);
	return 1.0 - smoothstep(threshold - w, threshold + w, value);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	edge_distance = UV.x;
}

void fragment() {
	if (gazer_debug_ids == 1) {
		ALBEDO = edge_distance < outline_width ? ID_OUTLINE : ID_FLOOR;
	} else {
		float s = -world_pos.z;
		float angle = atan(world_pos.x, -world_pos.y);
		float v = wall_v(angle);

		float progress = clamp(s / level_length, 0.0, 1.0);
		vec3 wall = texture(wall_gradient, vec2(progress, 0.5)).rgb;
		vec3 accent = texture(accent_gradient, vec2(progress, 0.5)).rgb;
		float arc = wrap_angle(angle - ball.y) * tunnel_radius;
		float distance_to_camera = length(world_pos - CAMERA_POSITION_WORLD);

		// --- Flat colour and the tiles -------------------------------------------------
		// Patterns fade out in the distance, where they would shimmer.
		float pattern_fade = 1.0 - smoothstep(28.0, 60.0, distance_to_camera);
		vec2 tile;
		float box = tile_box(s, v, tile);
		float seam = 1.0 - inside(-box, 0.0);
		// Alternate tiles a touch lighter, like a hand-painted floor.
		float checker = mod(tile.x + tile.y, 2.0);
		float pattern = (seam * 1.6 + checker * 0.45) * pattern_fade;
		vec3 color = wall * (1.0 - clamp(pattern, 0.0, 1.6) * pattern_contrast);

		// --- Hard two-tone shading: the half of the tunnel above the ball is darker.
		float facing = cos(wrap_angle(angle - ball.y));
		float lit = 1.0 - inside(facing, -0.15);
		color *= mix(shade_dark, 1.0, lit);

		// --- Contact shadow: a hard-edged blob ------------------------------------------
		float h = max(ball.z, 0.0);
		float d_ball = length(vec2((s - ball.x) * 0.85, arc));
		float shadow_radius = ball_radius * mix(1.0, 0.55, clamp(h / 3.5, 0.0, 1.0));
		color = mix(color, color * 0.55, inside(d_ball, shadow_radius));

		// --- Echo waves: whole tiles light up as the wave reaches their centre;
		// lit tiles turn the accent colour and their seams turn black.
		float echo_seam = 1.0 - smoothstep(-0.02, 0.02, box);
		float tile_v = tile_v_size();
		float tile_u = tile_u_size();
		float centre_s = (tile.x + 0.5) * tile_u;
		float centre_v = (tile.y + 0.5) * tile_v - mod(tile.x, 2.0) * tile_v * 0.5;
		float centre_angle = centre_v / tunnel_radius - PI;
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
			float glow = clamp(wave * (0.4 + 0.6 * life) * strength, 0.0, 1.0);
			color = mix(color, mix(accent, outline_color, echo_seam), glow);
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

		// --- Edges: the thick black outline ----------------------------------------------
		// edge_distance is interpolated from exact per-vertex values, so its
		// screen-space rate of change (metres per pixel across the edge) is
		// well behaved. The outer side of the band is the triangle edge
		// itself, which MSAA smooths; the inner side is softened by a pixel.
		float per_pixel = max(fwidth(edge_distance), 0.00001);
		float width = min(outline_width, outline_max_screen * VIEWPORT_SIZE.y * per_pixel);
		width = max(width, outline_min_pixels * per_pixel);
		float soft = min(per_pixel, width * 0.5);
		color = mix(color, outline_color, 1.0 - smoothstep(width - soft, width + soft, edge_distance));

		// --- Distance fades into the void colour, along the tunnel ---------------------
		float ahead = s + CAMERA_POSITION_WORLD.z;
		color = mix(color, fog_color, smoothstep(fog_distance * 0.3, fog_distance, ahead));
		ALBEDO = mix(color, fade_color, fade);
	}
}
