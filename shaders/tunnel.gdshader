// The tunnel wall, drawn like an old Flash game: flat bright colours, hard
// two-tone shading, thick black outlines. No textures, no realistic lighting.
//
// Everything is computed from the fragment's world position, converted to
// tunnel coordinates (s along the axis, angle around it), so the same maths
// as the simulation drives the look:
//   * colour        = palette sampled at s / level_length (you see upcoming colours ahead)
//   * bands         = alternating light/dark rings that sell the speed; faster
//                     levels get shorter bands, so they flicker past faster
//   * contact shadow= a hard-edged blob under the ball
//   * echo ripples  = bold outlined rings expanding *over the curved surface*;
//                     they wrap around the tunnel and meet on the far side
//   * best marker   = a black-and-white dashed ring where your best attempt ended
//   * finish line   = a chequered band
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

const int MAX_RIPPLES = 6;

uniform sampler2D wall_gradient : source_color, filter_linear, repeat_disable;
uniform sampler2D accent_gradient : source_color, filter_linear, repeat_disable;
uniform float level_length = 600.0;
uniform float tunnel_radius = 4.0;
uniform vec3 outline_color : source_color = vec3(0.04, 0.03, 0.06);

// Look
uniform float band_length = 3.0;       // metres per light/dark ring (shorter on faster levels)
uniform float band_contrast = 0.16;    // how much darker the dark rings are
uniform float stripe_count = 6.0;      // thin lane lines around the tunnel (0 = none)
uniform float shade_dark = 0.72;       // brightness of the "ceiling" half

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
}

void fragment() {
	float s = -world_pos.z;
	float angle = atan(world_pos.x, -world_pos.y);
	float progress = clamp(s / level_length, 0.0, 1.0);
	vec3 wall = texture(wall_gradient, vec2(progress, 0.5)).rgb;
	vec3 accent = texture(accent_gradient, vec2(progress, 0.5)).rgb;
	float arc = wrap_angle(angle - ball.y) * tunnel_radius;

	// --- Flat colour with alternating bands ------------------------------------
	// Bands fade out in the distance, where they would shimmer (aliasing).
	float band = mod(floor(s / band_length), 2.0);
	float band_fade = 1.0 - smoothstep(25.0, 55.0, length(world_pos - CAMERA_POSITION_WORLD));
	vec3 color = wall * (1.0 - band * band_contrast * band_fade);

	// Thin lane lines along the tunnel. Like the bands they fade with distance:
	// far away they are thinner than a pixel and would break up into dashes.
	if (stripe_count > 0.0) {
		float lane = abs(fract(angle / TAU * stripe_count) - 0.5) * TAU * tunnel_radius / stripe_count;
		float lane_fade = 1.0 - smoothstep(30.0, 70.0, length(world_pos - CAMERA_POSITION_WORLD));
		color = mix(color, wall * 0.55, inside(abs(lane - TAU * tunnel_radius / stripe_count * 0.5), 0.04) * lane_fade);
	}

	// --- Hard two-tone shading: the half of the tunnel above the ball is darker,
	// with a black-ish terminator line, like a cel-shaded cartoon.
	float facing = cos(wrap_angle(angle - ball.y));
	float lit = 1.0 - inside(facing, -0.15);
	color *= mix(shade_dark, 1.0, lit);

	// --- Contact shadow: a hard-edged blob ------------------------------------------
	float h = max(ball.z, 0.0);
	float d_ball = length(vec2((s - ball.x) * 0.85, arc));
	float shadow_radius = ball_radius * mix(1.0, 0.55, clamp(h / 3.5, 0.0, 1.0));
	color = mix(color, color * 0.55, inside(d_ball, shadow_radius));

	// --- Echo ripples: a bold accent ring with black edges ---------------------
	for (int i = 0; i < MAX_RIPPLES; i++) {
		vec4 r = ripples[i];
		if (r.w <= 0.0) continue;
		float age = now - r.z;
		if (age < 0.0 || age > ripple_life) continue;
		float life = 1.0 - age / ripple_life;
		float front = age * ripple_speed;
		float dist = abs(surface_distance(r.x, r.y, s, angle) - front);
		float core = 0.09 + 0.16 * life * min(r.w, 1.5);
		color = mix(color, outline_color, inside(dist, core + 0.07));
		color = mix(color, accent, inside(dist, core));
	}

	// --- Best run marker: dashed black/white ring --------------------------------
	if (best_s > 0.0) {
		float d = abs(s - best_s);
		float dash = step(0.5, fract(angle / TAU * 32.0));
		color = mix(color, outline_color, inside(d, 0.16));
		color = mix(color, mix(vec3(1.0), accent, dash), inside(d, 0.1));
	}

	// --- Finish line: chequered band ------------------------------------------------
	float to_finish = s - level_length;
	if (to_finish > -1.5 && to_finish < 1.5) {
		float check = mod(floor(angle / TAU * 24.0) + floor((to_finish + 1.5) / 0.75), 2.0);
		color = mix(vec3(1.0), outline_color, check);
	}

	// --- Hole rims and outline strips are solid black --------------------------------
	if (COLOR.r > 0.5 || COLOR.g > 0.5) {
		color = outline_color;
	}

	// --- Distance fades into the void colour ------------------------------------------
	// Measured along the tunnel and stepped once per band, so each band is one
	// flat tone and the steps coincide with band edges: no extra lines, and
	// nothing cutting across holes. Far away (where the bands are thinner
	// than a few pixels) it becomes a smooth fade to avoid shimmer.
	float ahead = s + CAMERA_POSITION_WORLD.z;
	float band_mid = (floor(s / band_length) + 0.5) * band_length + CAMERA_POSITION_WORLD.z;
	float fog_smooth = smoothstep(fog_distance * 0.3, fog_distance, ahead);
	float fog_stepped = smoothstep(fog_distance * 0.3, fog_distance, band_mid);
	float fog = mix(fog_stepped, fog_smooth, smoothstep(45.0, 70.0, ahead));
	color = mix(color, fog_color, fog);
	color = mix(color, fade_color, fade);

	ALBEDO = color;
}
