// The shell's cut faces: what you see of the wall's thickness through a hole.
//
// TunnelMesher extrudes every edge of every hole outwards through the shell,
// so these quads share their top vertices with the floor's edge and can
// never come loose from it. UV.x is the depth through the shell (0 at the
// floor, 1 at the back), UV.y is 1 for a face that runs along the tunnel
// and 0 for one that runs around it (the end of a ring).
//
// The look: the wall colour, darker, with the floor tiles' seams carried on
// down the face so every tile reads as a solid block, and a black line
// where the face ends at the back of the shell.
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

#include "res://shaders/tiles.gdshaderinc"

global uniform int gazer_debug_ids;

uniform sampler2D wall_gradient : source_color, filter_linear, repeat_disable;
uniform float level_length = 600.0;
uniform vec3 outline_color : source_color = vec3(0.04, 0.03, 0.06);
uniform float face_shade = 0.62;    // faces are the wall colour, this much darker
uniform float back_line = 0.1;      // share of the depth drawn as the black back line

uniform float fog_distance = 95.0;
uniform vec3 fog_color : source_color = vec3(0.1);
uniform float fade = 0.0;
uniform vec3 fade_color : source_color = vec3(0.0);

varying vec3 world_pos;
varying vec2 face;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	face = UV;
}

void fragment() {
	float depth = face.x;
	if (gazer_debug_ids == 1) {
		ALBEDO = depth > 1.0 - back_line ? ID_BACKLINE : ID_WALL;
	} else {
		float s = -world_pos.z;
		float angle = atan(world_pos.x, -world_pos.y);
		float progress = clamp(s / level_length, 0.0, 1.0);
		vec3 wall = texture(wall_gradient, vec2(progress, 0.5)).rgb;
		vec3 color = wall * face_shade;
		float fade_far = 1.0 - smoothstep(28.0, 60.0, length(world_pos - CAMERA_POSITION_WORLD));

		// Blocks: only the seams that cross the face. A face along the tunnel
		// is crossed by the seams between tile rows, the end of a ring by the
		// seams between tile columns. (A seam running along a face would
		// cover all of it or none.)
		float v = wall_v(angle);
		vec2 seams = seam_distances(s, v);
		float seam = face.y > 0.5 ? seams.x : seams.y;
		float w = max(fwidth(seam), 0.0001);
		float in_seam = 1.0 - smoothstep(TILE_SEAM - w, TILE_SEAM + w, seam);
		color = mix(color, wall * (face_shade - 0.25), in_seam * fade_far);
		vec2 tile;
		tile_box(s, v, tile);
		color *= 1.0 - mod(tile.x + tile.y, 2.0) * 0.05 * fade_far;

		// The black line at the back of the shell. depth is interpolated
		// linearly across each quad, so its rate of change is smooth.
		float dw = min(fwidth(depth), back_line * 0.5);
		color = mix(color, outline_color, smoothstep(1.0 - back_line - dw, 1.0 - back_line + dw, depth));

		float ahead = s + CAMERA_POSITION_WORLD.z;
		color = mix(color, fog_color, smoothstep(fog_distance * 0.3, fog_distance, ahead));
		ALBEDO = mix(color, fade_color, fade);
	}
}
