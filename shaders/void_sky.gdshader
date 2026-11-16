// What lies outside the tunnel, seen through every hole and at the far end:
// a flat, saturated colour with a few cartoon stars.
shader_type sky;

uniform vec3 void_color : source_color = vec3(0.1, 0.05, 0.3);
uniform vec3 star_color : source_color = vec3(1.0);
uniform float fade = 0.0;
uniform vec3 fade_color : source_color = vec3(0.0);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 color = void_color;

	// Sparse plus-shaped stars that blink on and off (no soft glow).
	vec3 grid = dir * 30.0;
	vec3 cell = floor(grid);
	float pick = hash13(cell);
	if (pick > 0.97) {
		vec3 local = grid - cell - 0.5;
		vec3 a = abs(local);
		float size = 0.05 + 0.12 * step(0.5, fract(TIME * (0.3 + pick) + pick * 7.0));
		float plus = step(min(min(a.x + a.y, a.y + a.z), a.x + a.z), 0.06) * step(max(max(a.x, a.y), a.z), size + 0.04);
		color = mix(color, star_color, plus);
	}
	COLOR = mix(color, fade_color, fade);
}
