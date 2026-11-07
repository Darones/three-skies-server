shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec2 arena_half_extents = vec2(27.0, 19.5);
uniform vec4 mist_color : source_color = vec4(0.62, 0.79, 0.88, 1.0);
uniform float fade_start = 0.78;
uniform float fade_end = 1.02;
uniform float mist_opacity = 0.32;

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float edge_distance = length(world_xz / arena_half_extents);
	float edge_fade = smoothstep(fade_start, fade_end, edge_distance);
	ALBEDO = mist_color.rgb;
	ALPHA = edge_fade * mist_opacity;
}
