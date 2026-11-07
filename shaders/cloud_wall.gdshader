shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4 cloud_tint : source_color = vec4(0.72, 0.86, 0.94, 0.38);

void fragment() {
	float wave = 0.5 + 0.5 * sin(UV.x * 19.0 + sin(UV.y * 7.0) * 1.6);
	float lower_edge = 0.05 + wave * 0.06;
	float upper_edge = 0.68 + sin(UV.x * 12.0) * 0.11 + sin(UV.x * 27.0) * 0.04;
	float vertical_fade = smoothstep(lower_edge, lower_edge + 0.12, UV.y);
	vertical_fade *= 1.0 - smoothstep(upper_edge - 0.12, upper_edge, UV.y);
	float side_fade = smoothstep(0.0, 0.16, UV.x) * (1.0 - smoothstep(0.84, 1.0, UV.x));
	float billow = 0.84 + 0.16 * sin(UV.x * 34.0 + sin(UV.y * 11.0) * 1.8);
	ALBEDO = cloud_tint.rgb;
	ALPHA = cloud_tint.a * vertical_fade * side_fade * billow;
}
