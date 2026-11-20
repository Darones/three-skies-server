shader_type spatial;
// One-mesh health bar. The background, the fill and the frame are all drawn
// by this shader, so there is no second quad that can cover the fill at some
// camera angles. Works on the Compatibility renderer.
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float fill_ratio : hint_range(0.0, 1.0) = 1.0;
uniform vec4 fill_color : source_color = vec4(0.36, 0.95, 0.52, 1.0);
uniform vec4 empty_color : source_color = vec4(0.045, 0.035, 0.065, 0.94);
uniform vec4 frame_color : source_color = vec4(0.01, 0.008, 0.015, 1.0);
uniform vec2 bar_size = vec2(1.7, 0.16);
uniform float frame_width = 0.014;

void vertex() {
	// Camera-facing billboard that keeps the quad's world scale. Doing this in
	// the shader avoids per-node scale, which billboard materials may discard.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 border = vec2(frame_width / max(bar_size.x, 0.001), frame_width / max(bar_size.y, 0.001));
	float on_frame = step(UV.x, border.x) + step(1.0 - border.x, UV.x)
		+ step(UV.y, border.y) + step(1.0 - border.y, UV.y);
	vec3 color = empty_color.rgb;
	float alpha = empty_color.a;
	if (on_frame > 0.5) {
		color = frame_color.rgb;
		alpha = frame_color.a;
	} else if (UV.x <= fill_ratio) {
		color = fill_color.rgb;
		alpha = fill_color.a;
	}
	ALBEDO = color;
	ALPHA = alpha;
}
