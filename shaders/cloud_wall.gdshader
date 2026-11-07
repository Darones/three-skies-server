shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4 cloud_tint : source_color = vec4(0.78, 0.9, 0.97, 0.22);

void fragment() {
	float low_wave = sin(UV.x * 31.4159 + sin(UV.x * 69.115 + UV.y * 8.0) * 0.45);
	float high_wave = sin(UV.x * 81.6814 + sin(UV.y * 17.0) * 0.35);
	float lower_edge = 0.04 + low_wave * 0.025;
	float upper_edge = 0.82 + low_wave * 0.09 + high_wave * 0.035;
	float vertical_fade = smoothstep(lower_edge, lower_edge + 0.16, UV.y);
	vertical_fade *= 1.0 - smoothstep(upper_edge - 0.15, upper_edge + 0.025, UV.y);
	float billow = 0.78 + 0.22 * sin(UV.x * 43.9823 + sin(UV.y * 13.0) * 1.4);
	ALBEDO = cloud_tint.rgb;
	ALPHA = cloud_tint.a * vertical_fade * billow;
}
