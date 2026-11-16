// The ball: matte bone-white ceramic with two thin ink seams at right angles,
// so both forward rolling and sideways drift are readable at a glance.
// Lit by hand (unshaded) to match the tunnel, with a rim tinted by the
// tunnel colour so the ball sits *inside* the scene.
shader_type spatial;
render_mode unshaded;

uniform vec3 body_color : source_color = vec3(0.95, 0.93, 0.89);
uniform vec3 ink_color : source_color = vec3(0.12, 0.11, 0.14);
uniform vec3 environment_color : source_color = vec3(0.8, 0.6, 0.5);
uniform vec3 flash_color : source_color = vec3(1.0, 0.8, 0.5);
uniform float flash = 0.0;
uniform float seam_width = 0.045;
uniform float fade = 0.0;
uniform vec3 fade_color : source_color = vec3(0.0);

varying vec3 local_pos;

void vertex() {
	local_pos = normalize(VERTEX);
}

void fragment() {
	// Seams: great circles in the local XY and YZ planes.
	float seam = min(abs(local_pos.z), abs(local_pos.x));
	float ink = 1.0 - smoothstep(seam_width * 0.6, seam_width, seam);
	vec3 albedo = mix(body_color, ink_color, ink * 0.9);

	// Key light from above-behind the camera, wrapped for a soft ceramic look.
	vec3 light_dir = normalize(vec3(-0.35, 0.85, 0.45));
	float wrap = clamp((dot(NORMAL, light_dir) + 0.35) / 1.35, 0.0, 1.0);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float spec = pow(max(dot(reflect(-light_dir, NORMAL), VIEW), 0.0), 40.0);

	vec3 color = albedo * mix(0.42, 1.06, wrap);
	color = mix(color, environment_color, fresnel * 0.55);
	color += spec * 0.18;
	color = mix(color, flash_color, flash * (0.5 + 0.5 * fresnel));
	ALBEDO = mix(color, fade_color, fade);
}
