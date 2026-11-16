// The cut faces of the tunnel's shell: what gives the holes their thickness.
//
// Drawn on a second tube, the shell's *outer* surface (tunnel radius plus
// the shell thickness), behind the inner one. Seen through a hole, a pixel
// of this tube is either void (there is no shell under it either) or the
// side of the cut: the view ray crossed the inner surface inside a hole and
// left the shell where it is solid, so it must have hit a cut face on the
// way. Both tests use the holes' distance field, so the faces follow the
// rounded, blended, twisted outlines exactly, with no geometry to build.
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

#include "res://shaders/holes.gdshaderinc"

uniform sampler2D wall_gradient : source_color, filter_linear, repeat_disable;
uniform float level_length = 600.0;
uniform float shell_thickness = 0.45;
uniform float face_shade = 0.62;      // cut faces are the wall colour, this much darker
// Face texture: 0 plain, 1 blocks (the floor tiles' seams run down the
// faces, so every tile is a block), 2 layers (strata, like a cut cake),
// 3 blocks and layers.
uniform int face_style = 1;
uniform float band_length = 3.0;
uniform vec3 outline_color : source_color = vec3(0.04, 0.03, 0.06);
uniform float fog_distance = 95.0;
uniform vec3 fog_color : source_color = vec3(0.1);
uniform float fade = 0.0;
uniform vec3 fade_color : source_color = vec3(0.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 camera = CAMERA_POSITION_WORLD;
	vec3 ray = world_pos - camera;
	// Where the ray crossed the inner surface (the camera is inside the tube).
	float a = dot(ray.xy, ray.xy);
	float b = dot(camera.xy, ray.xy);
	float c = dot(camera.xy, camera.xy) - tunnel_radius * tunnel_radius;
	float t = (-b + sqrt(max(b * b - a * c, 0.0))) / max(a, 0.000001);
	// March through the shell from the inner crossing (open: the floor
	// would hide the pixel otherwise) to this pixel on the outer surface.
	// The first solid sample means the ray met a cut face; a ray that stays
	// open all the way is void. Marching (rather than testing only this
	// pixel) keeps short platforms solid when the ray leaves the shell
	// beyond them, into the next hole.
	vec3 inner = camera + ray * t;
	if (floor_distance(-inner.z, atan(inner.x, -inner.y)) >= 0.0) {
		discard;  // the floor is in front of this pixel anyway
	}
	const int STEPS = 10;
	float lo = t;
	float hi = -1.0;
	for (int i = 1; i <= STEPS; i++) {
		float k = mix(t, 1.0, float(i) / float(STEPS));
		vec3 p = camera + ray * k;
		if (floor_distance(-p.z, atan(p.x, -p.y)) >= 0.0) {
			hi = k;
			break;
		}
		lo = k;
	}
	if (hi < 0.0) {
		discard;  // open all the way through: void
	}
	// Refine where the ray meets the face.
	for (int i = 0; i < 6; i++) {
		float mid = (lo + hi) * 0.5;
		vec3 p = camera + ray * mid;
		if (floor_distance(-p.z, atan(p.x, -p.y)) < 0.0) {
			lo = mid;
		} else {
			hi = mid;
		}
	}
	vec3 hit = camera + ray * hi;
	float s = -hit.z;
	float hit_angle = atan(hit.x, -hit.y);
	float depth = clamp((length(hit.xy) - tunnel_radius) / shell_thickness, 0.0, 1.0);
	float fade_far = 1.0 - smoothstep(28.0, 60.0, length(hit - camera));

	float progress = clamp(s / level_length, 0.0, 1.0);
	vec3 wall = texture(wall_gradient, vec2(progress, 0.5)).rgb;
	vec3 color = wall * face_shade;

	if (face_style == 2 || face_style == 3) {
		// Layers: a lighter top course, a darker body, a band between.
		float layer = depth < 0.34 ? 1.0 : 0.0;
		color = mix(wall * (face_shade - 0.08), wall * (face_shade + 0.12), layer);
		float band = abs(depth - 0.34);
		float w = max(fwidth(depth), 0.0001);
		color = mix(color, wall * (face_shade - 0.22), (1.0 - smoothstep(0.035 - w, 0.035 + w, band)) * fade_far);
	}
	if (face_style == 1 || face_style == 3) {
		// Blocks: the floor tiles' seams carry on down the face.
		vec2 tile;
		float v = wrap_angle(hit_angle) * tunnel_radius + PI * tunnel_radius;
		float seam = tile_box(s, v, band_length, tile);
		float w = max(fwidth(seam), 0.0001);
		float in_seam = 1.0 - smoothstep(-w, w, seam);
		color = mix(color, wall * (face_shade - 0.25), in_seam * fade_far);
		// Alternate blocks, like the tiles above.
		color *= 1.0 - mod(tile.x + tile.y, 2.0) * 0.05 * fade_far;
	}
	// A black line where the face ends at the back of the shell.
	float dw = max(fwidth(depth), 0.0001);
	float line = max(0.07, dw * 2.0);
	color = mix(color, outline_color, smoothstep(1.0 - line - dw, 1.0 - line + dw, depth));

	float ahead = s + camera.z;
	color = mix(color, fog_color, smoothstep(fog_distance * 0.3, fog_distance, ahead));
	color = mix(color, fade_color, fade);
	ALBEDO = color;
}
