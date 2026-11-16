// The ball, drawn like a cartoon: flat colours, one hard shadow step, a
// solid white shine spot and (via a second "outline" mesh) a thick black
// outline. A wide stripe around it, like a striped pool ball, makes the
// rolling readable at a glance. All colours come from a BallSkin.
shader_type spatial;
render_mode unshaded;

uniform vec3 body_color : source_color = vec3(1.0);
uniform vec3 stripe_color : source_color = vec3(1.0, 0.2, 0.35);
uniform float stripe_width = 0.42;      // half-height of the stripe, 0..1 of the radius
uniform vec3 line_color : source_color = vec3(0.04, 0.03, 0.06);
uniform float shade_amount = 0.28;      // darkness of the shadow side
uniform float shine_size = 0.18;

uniform vec3 flash_color : source_color = vec3(1.0);
uniform float flash = 0.0;
uniform float fade = 0.0;
uniform vec3 fade_color : source_color = vec3(0.0);

varying vec3 local_pos;

float inside(float value, float threshold) {
	float w = max(fwidth(value), 0.0001);
	return 1.0 - smoothstep(threshold - w, threshold + w, value);
}

void vertex() {
	local_pos = normalize(VERTEX);
}

void fragment() {
	// Stripe: a band around the local X axis, with black edge lines.
	float band = abs(local_pos.x);
	vec3 albedo = body_color;
	albedo = mix(albedo, line_color, inside(abs(band - stripe_width), 0.035));
	albedo = mix(albedo, stripe_color, inside(band, stripe_width - 0.03));

	// One hard light step, light from the upper left in view space.
	vec3 light_dir = normalize(vec3(-0.45, 0.75, 0.5));
	float lambert = dot(NORMAL, light_dir);
	vec3 color = albedo * mix(1.0 - shade_amount, 1.0, 1.0 - inside(lambert, 0.0));

	// Solid shine spot.
	float shine = length(NORMAL.xy - vec2(-0.38, 0.45));
	color = mix(color, vec3(1.0), inside(shine, shine_size) * step(0.0, NORMAL.z));

	color = mix(color, flash_color, flash * 0.75);
	ALBEDO = mix(color, fade_color, fade);
}
