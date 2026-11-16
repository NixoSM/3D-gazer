// Cartoon speed lines: thin white streaks shooting out from the vanishing
// point towards the screen edges, like an old Flash game or a manga panel.
// Drawn over the 3D view; `intensity` (0..1) comes from forward speed, so
// they are absent on the easy level and constant on the fastest one.
shader_type canvas_item;

uniform float intensity = 0.0;
uniform vec2 vanishing_point = vec2(0.5, 0.43);
uniform float lanes = 72.0;
uniform float rate = 2.4;            // streaks per second, per lane
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float clock = 0.0;           // seconds; stops during the echo hit-stop

float hash11(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void fragment() {
	vec2 size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 p = (SCREEN_UV - vanishing_point) * vec2(size.x / size.y, 1.0);
	float r = length(p);
	float a = atan(p.y, p.x) / TAU + 0.5;
	float lane = a * lanes;
	float id = floor(lane);
	float h = hash11(id + 1.0);
	// More lanes switch on as intensity rises.
	float active = step(h, intensity * 0.75);
	// Each lane carries one streak that runs outwards and repeats.
	float speed = rate * (0.7 + 0.6 * h);
	float head = mix(0.18, 1.25, fract(clock * speed + h * 13.0));
	float len = 0.10 + 0.22 * hash11(id + 7.0);
	float along = smoothstep(head - len, head - len + 0.02, r) * (1.0 - smoothstep(head - 0.01, head, r));
	// Thin across, tapering towards the tail, anti-aliased with fwidth.
	float across = abs(fract(lane) - 0.5);
	float width = 0.07 * smoothstep(head - len, head, r);
	float w = fwidth(across);
	float line = 1.0 - smoothstep(width - w, width + w, across);
	// Keep the middle of the screen (the ball, the holes ahead) clear.
	float edge = smoothstep(0.28, 0.5, r);
	COLOR = vec4(line_color.rgb, line_color.a * active * along * line * edge * clamp(intensity * 1.4, 0.0, 0.85));
}
