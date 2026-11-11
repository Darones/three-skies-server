shader_type canvas_item;
render_mode unshaded;

uniform vec4 tint : source_color = vec4(0.72, 0.02, 0.02, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float dist = length(uv) * 1.5;
	float vignette = smoothstep(0.32, 1.0, dist);
	COLOR = vec4(tint.rgb, vignette * intensity);
}
