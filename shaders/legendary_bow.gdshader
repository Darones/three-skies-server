shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Легендарный лук: перламутр у рукояти переходит в аметист к кончикам.
// Свечение включается по высоте модели, а не по цвету, чтобы кончики
// горели ровно и не зависели от запечённого градиента.

uniform vec3 glow_tint : source_color = vec3(0.62, 0.26, 1.0);
uniform float glow_strength = 1.05;
uniform float half_height = 0.4758;
uniform float glow_start = 0.55;
uniform float glow_end = 0.98;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.3;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.08;

varying float glow_mask;

void vertex() {
	float t = clamp(abs(VERTEX.y) / max(half_height, 0.0001), 0.0, 1.0);
	glow_mask = smoothstep(glow_start, glow_end, t);
}

void fragment() {
	vec3 base = COLOR.rgb;
	ALBEDO = base;
	METALLIC = metallic_value;
	ROUGHNESS = roughness_value;
	float body = 0.6 + 0.4 * dot(base, vec3(0.33));
	EMISSION = glow_tint * glow_mask * glow_strength * body;
}
