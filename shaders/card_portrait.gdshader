shader_type canvas_item;

uniform vec2 rect_size = vec2(330.0, 442.0);
uniform float corner_px = 16.0;

void fragment() {
	vec2 uv = UV;
	vec2 pixel = uv * rect_size;
	vec2 half_size = rect_size * 0.5;
	vec2 p = abs(pixel - half_size) - (half_size - vec2(corner_px));
	float d = length(max(p, vec2(0.0))) + min(max(p.x, p.y), 0.0) - corner_px;
	if (d > 0.0) {
		discard;
	}
	COLOR = texture(TEXTURE, uv);
}
