// Bakes the holes' signed-distance field for one level into a texture
// (see HOLES_BAKED in holes.gdshaderinc for the layout). Drawn once per
// level on a ColorRect that fills a SubViewport; TunnelView reads the
// result back into an ordinary texture.
shader_type canvas_item;
render_mode unshaded, blend_disabled;

#define HOLES_PLAIN_UNIFORMS
#include "res://shaders/holes.gdshaderinc"

const float FIELD_ROWS = 256.0;
const float FIELD_GUARD_ROWS = 2.0;
// Distances are stored as d / FIELD_RANGE * 0.5 + 0.5, clamped to 0..1.
const float FIELD_RANGE = 2.0;
uniform vec4 field_layout = vec4(480.0, 1.0, 8.0, 1.0);

void fragment() {
	float width = (field_layout.x + 2.0 * field_layout.y) * field_layout.z;
	float strip_rows = FIELD_ROWS + 2.0 * FIELD_GUARD_ROWS;
	vec2 texel = UV * vec2(width, strip_rows * field_layout.w);
	float strip = floor(texel.y / strip_rows);
	float s = strip * field_layout.x - field_layout.y + texel.x / field_layout.z;
	float angle = (texel.y - strip * strip_rows - FIELD_GUARD_ROWS) / FIELD_ROWS * TAU;
	float d = floor_distance(s, angle);
	COLOR = vec4(vec3(clamp(d / FIELD_RANGE * 0.5 + 0.5, 0.0, 1.0)), 1.0);
}
