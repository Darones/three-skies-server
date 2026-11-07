shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec3 player_position = vec3(0.0, 0.0, 0.0);
uniform vec3 ally_position_1 = vec3(0.0, 0.0, 0.0);
uniform vec3 ally_position_2 = vec3(0.0, 0.0, 0.0);
uniform int vision_count = 1;
uniform float view_radius = 10.0;
uniform float edge_softness = 3.0;
uniform float fog_opacity = 0.85;
uniform vec2 arena_half_extent = vec2(52.0, 37.0);
uniform vec4 fog_color : source_color = vec4(0.025, 0.035, 0.08, 1.0);

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float arena_edge_distance = length(world_position.xz / arena_half_extent);
	if (arena_edge_distance > 1.035) {
		discard;
	}

	float player_distance = view_radius + edge_softness + 1.0;
	if (vision_count > 0) {
		player_distance = length(world_position.xz - player_position.xz);
	}
	if (vision_count > 1) {
		player_distance = min(player_distance, length(world_position.xz - ally_position_1.xz));
	}
	if (vision_count > 2) {
		player_distance = min(player_distance, length(world_position.xz - ally_position_2.xz));
	}
	float fog_fade = smoothstep(view_radius, view_radius + edge_softness, player_distance);
	ALBEDO = fog_color.rgb;
	ALPHA = fog_fade * fog_opacity;
}
