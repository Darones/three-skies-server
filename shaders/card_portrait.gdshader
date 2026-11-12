shader_type canvas_item;

uniform vec2 rect_size = vec2(314.0, 362.0);
uniform vec2 texture_size = vec2(896.0, 1200.0);
uniform float corner_px = 14.0;

void fragment() {
	vec2 uv = UV;
	vec2 pixel = uv * rect_size;
	vec2 half_size = rect_size * 0.5;
	vec2 p = abs(pixel - half_size) - (half_size - vec2(corner_px));
	float d = length(max(p, vec2(0.0))) + min(max(p.x, p.y), 0.0) - corner_px;
	if (d > 0.0) {
		discard;
	}
	float rect_aspect = rect_size.x / rect_size.y;
	float tex_aspect = texture_size.x / texture_size.y;
	vec2 scale = vec2(1.0);
	if (tex_aspect > rect_aspect) {
		scale.y = rect_aspect / tex_aspect;
	} else {
		scale.x = tex_aspect / rect_aspect;
	}
	vec2 sample_uv = (uv - 0.5) * scale + 0.5;
	if (sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0) {
		discard;
	}
	COLOR = texture(TEXTURE, sample_uv);
}
