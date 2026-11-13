shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Одна геометрия крыльев, разные окрасы: белые, золотые, чёрные.
// tint умножается на исходную текстуру перьев, поэтому рисунок сохраняется.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 rim_color : source_color = vec3(1.0, 0.82, 0.38);
uniform float rim_strength = 0.0;
uniform float emission_strength = 0.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.72;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	vec3 base = tex.rgb * tint;
	ALBEDO = base;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	EMISSION = rim_color * fresnel * rim_strength + base * emission_strength;
}
