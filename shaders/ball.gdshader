// The ball: polished dark metal. It is lit by the lamp that travels with it
// and mirrors the two things worth mirroring in a dark tunnel: the glow at
// the far end and the pool of light on the floor beneath it. Two hairline
// seams at right angles make rolling readable in every direction.
// All look parameters come from a BallSkin resource.
shader_type spatial;
render_mode unshaded;

uniform vec3 base_color : source_color = vec3(0.09);
uniform vec3 seam_color : source_color = vec3(0.55);
uniform float seam_width = 0.014;
uniform float glossiness = 140.0;
uniform float specular = 1.1;
uniform float reflectivity = 0.55;
uniform vec3 reflection_tint : source_color = vec3(1.0);

// Scene inputs (world space), set every frame by WorldView.
uniform vec3 lamp_position = vec3(0.0, 2.0, 0.0);
uniform vec3 lamp_color : source_color = vec3(1.0);
uniform vec3 up_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 glow_color : source_color = vec3(0.5, 0.6, 1.0);
uniform vec3 floor_color : source_color = vec3(0.1);

uniform vec3 flash_color : source_color = vec3(1.0);
uniform float flash = 0.0;
uniform float fade = 0.0;
uniform vec3 fade_color : source_color = vec3(0.0);

varying vec3 local_pos;
varying vec3 world_pos;

// What the ball sees in direction `dir` (world space).
vec3 environment(vec3 dir) {
	float ahead = max(dot(dir, vec3(0.0, 0.0, -1.0)), 0.0);
	vec3 env = glow_color * (pow(ahead, 10.0) * 1.6 + pow(ahead, 2.0) * 0.12);
	float below = max(-dot(dir, up_direction), 0.0);
	env += floor_color * pow(below, 1.2) * 1.4;
	// The tunnel wall all around: a dim, even band that outlines the silhouette.
	env += floor_color * 0.25 * (1.0 - abs(dot(dir, vec3(0.0, 0.0, -1.0))));
	return env;
}

void vertex() {
	local_pos = normalize(VERTEX);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float seam = min(abs(local_pos.z), abs(local_pos.x));
	float line = 1.0 - smoothstep(seam_width * 0.5, seam_width, seam);

	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
	vec3 l = normalize(lamp_position - world_pos);
	vec3 h = normalize(l + v);

	float diffuse = max(dot(n, l), 0.0);
	float spec = pow(max(dot(n, h), 0.0), glossiness) * specular;
	float fresnel = 0.04 + 0.96 * pow(1.0 - max(dot(n, v), 0.0), 5.0);
	vec3 reflected = environment(reflect(-v, n)) * reflection_tint;

	// Two specular lobes: a tight glint plus a broad satin sheen.
	float sheen = pow(max(dot(n, h), 0.0), glossiness * 0.08) * specular * 0.22;

	vec3 albedo = mix(base_color, seam_color, line);
	vec3 color = albedo * (0.25 + diffuse * 1.6) * lamp_color;
	color += reflected * mix(reflectivity * 0.6, 1.0, fresnel) * (1.0 - line * 0.5);
	color += (spec + sheen) * lamp_color;
	color = mix(color, flash_color * 1.4, flash * (0.35 + 0.65 * fresnel));
	ALBEDO = mix(color, fade_color, fade);
}
