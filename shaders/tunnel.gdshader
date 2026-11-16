// The tunnel wall: a dark, satin-finished shell lit only by a lamp that
// travels just above the ball. Everything outside that pool of light falls
// away into darkness, so the eye stays on the ball and the holes, which open
// onto the glowing, level-coloured void.
//
// All effects are computed from the fragment's world position, converted to
// tunnel coordinates (s along the axis, angle around it), so the same maths
// as the simulation drives the look:
//   * tint          = palette sampled at s / level_length (subtle on the wall,
//                     strong in the void and the lamp, which carry the progress colour)
//   * contact shadow= distance on the cylinder surface to the ball
//   * echo ripples  = thin rings of light expanding *over the curved surface*;
//                     they wrap around the tunnel and meet on the far side
//   * best marker   = a faint dashed ring where your best attempt ended
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

const int MAX_RIPPLES = 6;

uniform sampler2D wall_gradient : source_color, filter_linear, repeat_disable;
uniform sampler2D accent_gradient : source_color, filter_linear, repeat_disable;
uniform float level_length = 600.0;
uniform float tunnel_radius = 4.0;
uniform float rim_thickness = 0.45;

// Surface
uniform float panel_length = 4.5;      // metres between machined seams
uniform float grain_strength = 0.045;   // brushed grain along the tunnel
uniform float sheen = 0.35;            // satin specular strength

// The lamp that travels with the ball (world space).
uniform vec3 lamp_position = vec3(0.0);
uniform vec3 lamp_color : source_color = vec3(1.0);
uniform float lamp_range = 9.0;
uniform float ambient = 0.34;

// Ball (s, angle, height) and radius, for the contact shadow.
uniform vec3 ball = vec3(0.0);
uniform float ball_radius = 0.42;

// Echo ripples: xyzw = (s, angle, start_time, strength). strength 0 = unused.
uniform vec4 ripples[MAX_RIPPLES];
uniform float now = 0.0;
uniform float ripple_speed = 15.0;
uniform float ripple_life = 1.3;

uniform float best_s = -1.0;
uniform float fog_distance = 70.0;
uniform vec3 fog_color : source_color = vec3(0.0);
uniform float fade = 0.0;          // 0..1, fades everything to fade_color (fail / transitions)
uniform vec3 fade_color : source_color = vec3(0.0);

varying vec3 world_pos;
varying vec3 world_normal;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
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
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float s = -world_pos.z;
	float angle = atan(world_pos.x, -world_pos.y);
	float progress = clamp(s / level_length, 0.0, 1.0);
	vec3 tint = texture(wall_gradient, vec2(progress, 0.5)).rgb;
	vec3 accent = texture(accent_gradient, vec2(progress, 0.5)).rgb;
	bool rim = COLOR.r > 0.5;
	float arc = angle * tunnel_radius;

	// --- Material ------------------------------------------------------------
	// Brushed grain: long streaks along the direction of travel.
	float grain = value_noise(vec2(arc * 38.0, s * 0.9)) * 0.6 + value_noise(vec2(arc * 140.0, s * 3.0)) * 0.4;
	vec3 albedo = tint * (1.0 + (grain - 0.5) * grain_strength * 2.0);

	// Machined seams: a fine dark groove with a hairline highlight on one side.
	float panel = fract(s / panel_length) * panel_length;
	float groove = 1.0 - smoothstep(0.0, 0.025, min(panel, panel_length - panel));
	float bevel = smoothstep(0.025, 0.035, panel) * (1.0 - smoothstep(0.035, 0.06, panel));
	albedo *= 1.0 - groove * 0.6;

	// --- Lighting --------------------------------------------------------------
	vec3 n = normalize(world_normal);
	vec3 view = normalize(CAMERA_POSITION_WORLD - world_pos);
	if (dot(n, view) < 0.0) n = -n;   // rim faces are seen from both sides
	vec3 to_lamp = lamp_position - world_pos;
	float d = length(to_lamp);
	vec3 l = to_lamp / d;
	float attenuation = 1.0 / (1.0 + pow(d / lamp_range, 2.4) * 6.0);
	float diffuse = max(dot(n, l), 0.0) * attenuation;
	vec3 h = normalize(l + view);
	float specular = pow(max(dot(n, h), 0.0), 48.0) * sheen * attenuation;
	// Anisotropic-looking streak: brighten the sheen where the grain is light.
	specular *= 0.6 + grain * 0.8;

	vec3 color = albedo * (ambient + diffuse * 2.4 * lamp_color) + specular * lamp_color;
	color += bevel * lamp_color * attenuation * 0.35;

	// --- Hole edges: the cut shows a thin bright lip, then the dark shell.
	if (rim) {
		float depth = (length(world_pos.xy) - tunnel_radius) / rim_thickness;
		float lip = 1.0 - smoothstep(0.04, 0.12, depth);
		color = mix(albedo * 0.5 * (ambient + diffuse * lamp_color), accent * 1.4, lip);
	}

	// --- Contact shadow ----------------------------------------------------------
	float d_ball = surface_distance(ball.x, ball.y, s, angle);
	float h_ball = max(ball.z, 0.0);
	float shadow_radius = ball_radius * (1.1 + h_ball * 0.45);
	float shadow = (1.0 - smoothstep(0.0, shadow_radius, d_ball)) * mix(0.85, 0.35, clamp(h_ball / 3.0, 0.0, 1.0));
	if (!rim) {
		color *= 1.0 - shadow;
	}

	// --- Echo ripples: a crisp line of light with a soft afterglow ---------------
	float glow = 0.0;
	for (int i = 0; i < MAX_RIPPLES; i++) {
		vec4 r = ripples[i];
		if (r.w <= 0.0) continue;
		float age = now - r.z;
		if (age < 0.0 || age > ripple_life) continue;
		float life = 1.0 - age / ripple_life;
		float front = age * ripple_speed;
		float dist = surface_distance(r.x, r.y, s, angle);
		float line = exp(-pow((dist - front) / 0.07, 2.0));
		float wake = exp(-max(front - dist, 0.0) / 1.2) * step(dist, front) * 0.25;
		glow += (line + wake) * r.w * life * life;
	}
	color += accent * glow * 1.6;

	// --- Best run marker ---------------------------------------------------------
	if (best_s > 0.0) {
		float band = 1.0 - smoothstep(0.015, 0.05, abs(s - best_s));
		float dash = step(0.6, fract(angle / TAU * 36.0));
		color += accent * band * dash * 0.9;
	}

	// --- Finish line ---------------------------------------------------------------
	float finish = 1.0 - smoothstep(0.0, 0.08, abs(s - level_length));
	color += accent * finish * 1.5;

	// --- Distance falls into darkness ------------------------------------------------
	float dist_cam = length(world_pos - CAMERA_POSITION_WORLD);
	float fog = 1.0 - exp(-pow(dist_cam / fog_distance, 1.5));
	color = mix(color, fog_color, fog);
	color = mix(color, fade_color, fade);

	ALBEDO = color;
}
