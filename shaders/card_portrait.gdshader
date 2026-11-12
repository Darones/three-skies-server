shader_type canvas_item;

uniform float corner_radius = 0.06;

void fragment() {
	vec2 uv = UV;
	vec2 p = abs(uv - vec2(0.5)) - vec2(0.5 - corner_radius);
	float d = length(max(p, vec2(0.0))) + min(max(p.x, p.y), 0.0) - corner_radius;
	if (d > 0.0) {
		discard;
	}
	COLOR = texture(TEXTURE, uv);
}
