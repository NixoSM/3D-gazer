// "Inverted hull" outline: a slightly bigger copy of a mesh, showing only its
// back faces in a flat dark colour, so a thick line appears around the shape.
shader_type spatial;
render_mode unshaded, cull_front;

uniform vec3 outline_color : source_color = vec3(0.04, 0.03, 0.06);
uniform float fade = 0.0;
uniform vec3 fade_color : source_color = vec3(0.0);

void fragment() {
	ALBEDO = mix(outline_color, fade_color, fade);
}
