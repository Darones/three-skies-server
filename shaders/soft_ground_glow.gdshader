shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 glow_color : source_color = vec4(0.3, 1.0, 0.6, 1.0);
uniform float intensity : hint_range(0.0, 2.0) = 0.8;
uniform float ring_bias : hint_range(0.0, 1.0) = 0.0;
uniform float inner_fade : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_speed = 0.0;
uniform float pulse_amount : hint_range(0.0, 0.5) = 0.0;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float distance_from_center = length(centered) * 2.0;
	float filled = exp(-distance_from_center * distance_from_center * 3.6);
	float ring = smoothstep(1.0, 0.55, distance_from_center) * smoothstep(0.22, 0.72, distance_from_center);
	float glow = mix(filled, ring, ring_bias);
	glow *= 1.0 - inner_fade * smoothstep(0.55, 0.0, distance_from_center);
	float pulse = 1.0 + pulse_amount * sin(TIME * pulse_speed);
	float alpha = clamp(glow * intensity * pulse, 0.0, 1.0);
	ALBEDO = glow_color.rgb;
	ALPHA = alpha * glow_color.a;
	EMISSION = glow_color.rgb * alpha;
}
