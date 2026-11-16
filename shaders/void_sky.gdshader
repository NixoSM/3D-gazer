// What lies outside the tunnel: seen through every hole and at its far end.
// A deep void colour, a glow straight ahead (the "light at the end" that the
// tunnel fog fades into) and slow, sparse motes so holes read as depth.
shader_type sky;

uniform vec3 void_color : source_color = vec3(0.02, 0.02, 0.05);
uniform vec3 glow_color : source_color = vec3(1.0, 0.9, 0.8);
uniform vec3 mote_color : source_color = vec3(1.0, 0.8, 0.6);
uniform float glow_power = 18.0;
uniform float fade = 0.0;
uniform vec3 fade_color : source_color = vec3(0.0);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float ahead = max(dot(dir, vec3(0.0, 0.0, -1.0)), 0.0);
	vec3 color = mix(void_color, glow_color, pow(ahead, glow_power));

	// Motes on a coarse direction grid, twinkling slowly.
	vec3 grid = dir * 38.0;
	vec3 cell = floor(grid);
	float pick = hash13(cell);
	if (pick > 0.965) {
		vec3 center = cell + 0.5 + (vec3(hash13(cell + 1.0), hash13(cell + 2.0), hash13(cell + 3.0)) - 0.5) * 0.6;
		float d = length(grid - center);
		float twinkle = 0.55 + 0.45 * sin(TIME * (0.6 + pick * 2.0) + pick * 40.0);
		color += mote_color * smoothstep(0.22, 0.0, d) * twinkle * 0.8;
	}
	COLOR = mix(color, fade_color, fade);
}
