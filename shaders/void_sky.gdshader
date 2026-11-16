// What lies outside the tunnel, seen through every hole: the level's colour,
// deepest at the sides and glowing straight ahead, where the tunnel's
// darkness narrows to a point of light. A few slow motes give holes depth.
shader_type sky;

uniform vec3 void_color : source_color = vec3(0.05, 0.06, 0.12);
uniform vec3 glow_color : source_color = vec3(0.6, 0.7, 1.0);
uniform vec3 mote_color : source_color = vec3(1.0);
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
	vec3 color = mix(void_color, glow_color, pow(ahead, 3.0) * 0.55);
	color += glow_color * pow(ahead, 120.0) * 1.5;

	vec3 grid = dir * 46.0;
	vec3 cell = floor(grid);
	float pick = hash13(cell);
	if (pick > 0.975) {
		vec3 center = cell + 0.5 + (vec3(hash13(cell + 1.0), hash13(cell + 2.0), hash13(cell + 3.0)) - 0.5) * 0.6;
		float d = length(grid - center);
		float twinkle = 0.5 + 0.5 * sin(TIME * (0.5 + pick * 1.5) + pick * 40.0);
		color += mote_color * smoothstep(0.12, 0.0, d) * twinkle * 0.6;
	}
	COLOR = mix(color, fade_color, fade);
}
