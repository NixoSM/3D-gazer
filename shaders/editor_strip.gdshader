// The level editor's unrolled tunnel: the wall laid flat, `s` running up
// the rect and the angle across it (the floor, 0°, in the middle; the
// player's right is to the right). It evaluates the very same hole field
// as the game (holes.gdshaderinc), so rounded corners, blends and twists
// look exactly as they will play.
shader_type canvas_item;

#include "res://shaders/holes.gdshaderinc"

uniform sampler2D wall_gradient : source_color, filter_linear, repeat_disable;
uniform sampler2D void_gradient : source_color, filter_linear, repeat_disable;
uniform float level_length = 600.0;
// Distance at the bottom and top edges of the rect (m).
uniform float s_bottom = 0.0;
uniform float s_top = 100.0;
// Angle at the middle of the rect (radians): lets the view turn the tube.
uniform float angle_middle = 0.0;
uniform vec3 outline_color : source_color = vec3(0.04, 0.03, 0.06);
uniform float outline_width = 0.2;
// Beyond the finish (and before the start) the strip is drawn dimmed.
uniform vec3 outside_color : source_color = vec3(0.2, 0.18, 0.24);

void fragment() {
	float s = mix(s_bottom, s_top, 1.0 - UV.y);
	float angle = angle_middle + (UV.x - 0.5) * TAU;
	float progress = clamp(s / level_length, 0.0, 1.0);
	vec3 wall = texture(wall_gradient, vec2(progress, 0.5)).rgb;
	vec3 void_color = texture(void_gradient, vec2(progress, 0.5)).rgb;

	float d = floor_distance(s, angle);
	float pixel = max(fwidth(min(d, 1.0)), 0.0001);
	vec3 color;
	if (d < 0.0) {
		// Void: the level's own void colour with faint diagonal hatching,
		// so holes read as "nothing here" even when the colours are close.
		float hatch = step(0.5, fract((FRAGCOORD.x + FRAGCOORD.y) / 14.0));
		color = mix(void_color, void_color * 0.75 + vec3(0.06), hatch * 0.5);
	} else {
		// Floor: flat wall colour, a faint lane every 30°, black edge band.
		float lanes = (wrap_angle(angle) + PI) / TAU * 12.0;
		float lane_line = 1.0 - smoothstep(0.0, fwidth(lanes) * 1.5, abs(fract(lanes + 0.5) - 0.5));
		color = wall * (1.0 - lane_line * 0.1);
		float band = max(outline_width, pixel * 2.0);
		float edge = 1.0 - smoothstep(band - pixel, band + pixel, d);
		color = mix(color, outline_color, edge);
	}
	if (s < 0.0 || s > level_length) {
		color = mix(color, outside_color, 0.75);
	}
	COLOR = vec4(color, 1.0);
}
