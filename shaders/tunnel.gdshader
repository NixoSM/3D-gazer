// The tunnel wall: glazed ceramic tiles whose colour follows level progress.
//
// Everything here is computed from the fragment's world position, converted
// to tunnel coordinates (s along the axis, angle around it), so the same
// maths as the simulation drives the look:
//   * colour        = palette sampled at s / level_length (you see upcoming colours ahead)
//   * contact shadow= distance on the cylinder surface to the ball
//   * echo ripples  = rings expanding *over the curved surface*; they wrap
//                     around the tunnel and meet themselves on the far side,
//                     lighting tiles one by one as they pass
//   * best marker   = a thin ring where your best attempt ended
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

const int MAX_RIPPLES = 6;

uniform sampler2D wall_gradient : source_color, filter_linear, repeat_disable;
uniform sampler2D accent_gradient : source_color, filter_linear, repeat_disable;
uniform float level_length = 600.0;
uniform float tunnel_radius = 4.0;
uniform float rim_thickness = 0.45;

// Tiles
uniform float tiles_around = 28.0;
uniform float tile_length = 1.7;
uniform float tile_jitter = 0.08;
uniform float grout_width = 0.035;

// Ball (s, angle, height) and radius, for the contact shadow and floor light.
uniform vec3 ball = vec3(0.0);
uniform float ball_radius = 0.42;

// Echo ripples: xyzw = (s, angle, start_time, strength). strength 0 = unused.
uniform vec4 ripples[MAX_RIPPLES];
uniform float now = 0.0;
uniform float ripple_speed = 15.0;
uniform float ripple_life = 1.4;

uniform float best_s = -1.0;
uniform float fog_distance = 70.0;
uniform vec3 fog_color : source_color = vec3(1.0);
uniform float fade = 0.0;          // 0..1, fades everything to fog_color (fail / transitions)
uniform vec3 fade_color : source_color = vec3(0.0);

varying vec3 world_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float wrap_angle(float a) {
	return mod(a + PI, TAU) - PI;
}

// Distance between two points on the cylinder surface, the short way round.
float surface_distance(float s0, float a0, float s1, float a1) {
	return length(vec2(s1 - s0, tunnel_radius * wrap_angle(a1 - a0)));
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
	bool rim = COLOR.r > 0.5;

	// --- Tiles -------------------------------------------------------------
	// Running bond: every other ring of tiles is offset by half a tile,
	// like laid ceramic rather than a graph-paper grid.
	vec2 tile_uv = vec2(angle / TAU * tiles_around, s / tile_length);
	tile_uv.x += 0.5 * mod(floor(tile_uv.y), 2.0);
	vec2 cell = floor(tile_uv);
	vec2 local = fract(tile_uv);
	float jitter = hash12(cell) - 0.5;
	vec3 color = wall * (1.0 + jitter * tile_jitter);
	vec2 edge = min(local, 1.0 - local) * vec2(TAU * tunnel_radius / tiles_around, tile_length);
	float grout = 1.0 - smoothstep(0.0, grout_width, min(edge.x, edge.y));
	color *= 1.0 - grout * 0.16;
	// A soft glaze highlight in the middle of each tile.
	float glaze = smoothstep(0.55, 0.0, length(local - vec2(0.35, 0.3)));
	color += glaze * 0.05;

	// --- "Up" shading: the wall opposite the ball is the ceiling, so it is dimmer.
	float facing = cos(wrap_angle(angle - ball.y));
	color *= mix(0.62, 1.04, facing * 0.5 + 0.5);

	// --- Rims are the cut edge of the shell: a bright glazed lip where the
	// tile surface ends, then the darker body of the ceramic below it.
	if (rim) {
		float depth = (length(world_pos.xy) - tunnel_radius) / rim_thickness;
		vec3 body = wall * 0.48;
		float lip = 1.0 - smoothstep(0.1, 0.22, depth);
		color = mix(body * mix(1.0, 0.7, depth), accent * 1.15, lip);
	}

	// --- Contact shadow ----------------------------------------------------
	float d_ball = surface_distance(ball.x, ball.y, s, angle);
	float h = max(ball.z, 0.0);
	float shadow_radius = ball_radius * (1.05 + h * 0.35);
	float shadow = (1.0 - smoothstep(0.0, shadow_radius, d_ball)) * mix(0.5, 0.12, clamp(h / 3.0, 0.0, 1.0));
	if (!rim) {
		color *= 1.0 - shadow;
	}

	// --- Echo ripples --------------------------------------------------------
	float cell_angle = (cell.x + 0.5) / tiles_around * TAU;
	float cell_s = (cell.y + 0.5) * tile_length;
	float glow = 0.0;
	for (int i = 0; i < MAX_RIPPLES; i++) {
		vec4 r = ripples[i];
		if (r.w <= 0.0) continue;
		float age = now - r.z;
		if (age < 0.0 || age > ripple_life) continue;
		float life = 1.0 - age / ripple_life;
		float front = age * ripple_speed;
		// Thin smooth wavefront...
		float d = surface_distance(r.x, r.y, s, angle);
		float line = exp(-pow((d - front) / 0.22, 2.0));
		// ...and whole tiles lighting up as it passes over them.
		float dc = surface_distance(r.x, r.y, cell_s, cell_angle);
		float tile_flash = exp(-pow((dc - front) / 1.3, 2.0)) * (0.55 + 0.45 * hash12(cell + 7.0));
		glow += (line * 0.8 + tile_flash * 0.8) * r.w * life * life;
	}
	color = mix(color, accent * 1.25, clamp(glow, 0.0, 1.0));

	// --- Best run marker -----------------------------------------------------
	if (best_s > 0.0) {
		float band = 1.0 - smoothstep(0.04, 0.12, abs(s - best_s));
		float dash = step(0.5, fract(angle / TAU * 24.0));
		color = mix(color, accent, band * (0.5 + 0.5 * dash));
	}

	// --- Finish line ---------------------------------------------------------
	float finish = 1.0 - smoothstep(0.0, 0.6, abs(s - level_length));
	color = mix(color, accent * 1.3, finish);

	// --- Depth fog towards the light at the end of the tunnel -----------------
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float fog = 1.0 - exp(-pow(dist / fog_distance, 1.7));
	color = mix(color, fog_color, fog);
	color = mix(color, fade_color, fade);

	ALBEDO = color;
}
