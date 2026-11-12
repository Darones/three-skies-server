shader_type canvas_item;
render_mode unshaded;

uniform float progress = 0.0;
uniform float corner_radius = 0.14;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 0.85);

void fragment() {
	vec2 uv = UV;
	vec2 p = abs(uv - vec2(0.5)) - vec2(0.5 - corner_radius);
	float d = length(max(p, vec2(0.0))) + min(max(p.x, p.y), 0.0) - corner_radius;
	if (d > 0.0) {
		discard;
	}
	float dark_fraction = clamp(1.0 - progress, 0.0, 1.0);
	if (uv.y > dark_fraction) {
		discard;
	}
	COLOR = tint;
}
