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

#define HOLES_BAKED
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


// The floor tiles' seams in one direction only (see tile_box() for the
// layout): < 0 in a seam. `across` = the seams around the tunnel (lines
// along it); otherwise the seams across it.
float tile_seam(float u, float v, bool across, out vec2 tile) {
	float tile_v = TAU * tunnel_radius / 10.0;
	float tile_u = band_length * 1.3;
	float row = floor(u / tile_u);
	float shifted = v + mod(row, 2.0) * tile_v * 0.5;
	tile = vec2(row, floor(shifted / tile_v));
	float half_seam = 0.09;
	if (across) {
		return tile_v * 0.5 - abs(mod(shifted, tile_v) - tile_v * 0.5) - half_seam;
	}
	return tile_u * 0.5 - abs(mod(u, tile_u) - tile_u * 0.5) - half_seam;
}

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
	vec3 inner = camera + ray * t;
	float d = floor_distance(-inner.z, atan(inner.x, -inner.y));
	if (d >= 0.0) {
		discard;  // the floor is in front of this pixel anyway
	}
	// Sphere-trace through the shell, from the inner crossing (open: the
	// floor would hide the pixel otherwise) to this pixel on the outer
	// surface. The first solid sample means the ray met a cut face; a ray
	// that stays open all the way is void. Steps are as long as the hole
	// field allows, so a pixel deep inside a hole (most of the screen over
	// open void) is settled in one or two samples instead of a fixed march.
	// `span` is the ray's length measured on the wall, the units of d.
	float span = length(vec2(world_pos.z - inner.z,
		tunnel_radius * wrap_angle(atan(world_pos.x, -world_pos.y) - atan(inner.x, -inner.y))));
	span = max(span, 0.001);
	float lo = t;
	float hi = -1.0;
	float k = t;
	// Far away a face is a few pixels thin: a coarser look is enough there.
	float view_distance = length(world_pos - camera);
	bool near = view_distance < 22.0;
	int steps = near ? 8 : 4;
	int sweep = near ? 8 : 5;
	int refine = 10;  // stops early once within 1 cm (see below)
	bool open_through = false;
	for (int i = 0; i < steps; i++) {
		// The hole is wider than what is left of the ray: open all the way,
		// no need to look (most pixels over open void end here).
		// smooth_min() makes d up to BLEND/4 more negative than the true
		// distance near blended holes, hence the margin.
		if (-d - BLEND * 0.25 > (1.0 - k) / (1.0 - t) * span) {
			open_through = true;
			break;
		}
		float step_m = max((-d - BLEND * 0.25) * 0.8, 0.06);
		k = min(k + step_m / span * (1.0 - t), 1.0);
		vec3 p = camera + ray * k;
		d = floor_distance(-p.z, atan(p.x, -p.y));
		if (d >= 0.0) {
			hi = k;
			break;
		}
		lo = k;
		if (k >= 1.0) {
			break;
		}
	}
	// Out of long steps with ray left (it runs close along an edge): sweep
	// the rest evenly. Never jump to the far end instead: a grazing ray
	// travels metres inside the shell, so its far end can lie in the *next*
	// hole, beyond the platform whose face it hit, and the face would turn
	// see-through.
	if (hi < 0.0 && !open_through && k < 1.0) {
		float from = k;
		for (int i = 1; i <= sweep; i++) {
			k = mix(from, 1.0, float(i) / float(sweep));
			vec3 p = camera + ray * k;
			if (floor_distance(-p.z, atan(p.x, -p.y)) >= 0.0) {
				hi = k;
				break;
			}
			lo = k;
		}
	}
	if (hi < 0.0) {
		discard;  // open all the way through: void
	}
	// Refine where the ray meets the face.
	// Bisect until the bracket is a centimetre on the wall: a step that ran
	// out far from the face needs more halvings than one that landed close
	// (too few showed as moiré on faces seen edge-on).
	for (int i = 0; i < refine; i++) {
		if ((hi - lo) / (1.0 - t) * span < 0.01) {
			break;
		}
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
		// Blocks: the floor tiles' seams carry on down the face. Only the
		// seams that cross the face are drawn: on the end of a ring (a face
		// across the tunnel) the seams around the tunnel, on the side of a
		// gap (a face along it) the seams across. A seam running along the
		// face would cover it, or not, depending on where exactly the ray
		// hit, and smeared into streaks.
		vec2 tile;
		float v = wrap_angle(hit_angle) * tunnel_radius + PI * tunnel_radius;
		const float EPS = 0.03;
		float gs = floor_distance(s + EPS, hit_angle) - floor_distance(s - EPS, hit_angle);
		float ga = floor_distance(s, hit_angle + EPS / tunnel_radius) - floor_distance(s, hit_angle - EPS / tunnel_radius);
		bool across = abs(gs) > abs(ga);  // the face's normal points along the tunnel
		float seam = tile_seam(s, v, across, tile);
		float w = max(fwidth(seam), 0.0001);
		float in_seam = 1.0 - smoothstep(-w, w, seam);
		color = mix(color, wall * (face_shade - 0.25), in_seam * fade_far);
		// Alternate blocks, like the tiles above.
		color *= 1.0 - mod(tile.x + tile.y, 2.0) * 0.05 * fade_far;
	}
	// A black line where the face ends at the back of the shell.
	// fwidth(depth) is huge where the face's outline meets another surface
	// (depth jumps there), so it is capped: uncapped, the line swelled into
	// black spikes at the corners of every face.
	float dw = clamp(fwidth(depth), 0.0001, 0.02);
	float line = 0.07;
	color = mix(color, outline_color, smoothstep(1.0 - line - dw, 1.0 - line + dw, depth));

	float ahead = s + camera.z;
	color = mix(color, fog_color, smoothstep(fog_distance * 0.3, fog_distance, ahead));
	color = mix(color, fade_color, fade);
	ALBEDO = color;
}
