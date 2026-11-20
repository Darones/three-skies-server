extends RefCounted

## Shared builder for the single-mesh 3D health bar used by heroes, remote
## players and the Sky Shell.
##
## The bar is one QuadMesh with `shaders/health_bar.gdshader`: background,
## fill and frame live in the same fragment shader. That is deliberate — two
## billboarded quads at the same position are sorted by the renderer and can
## cover each other at some camera angles (the old black-bar bug).

const BAR_SHADER: Shader = preload("res://shaders/health_bar.gdshader")


static func create(width: float, height: float, fill: Color, y: float) -> MeshInstance3D:
	var bar := MeshInstance3D.new()
	bar.name = "HealthBar3D"
	var quad := QuadMesh.new()
	quad.size = Vector2(width, height)
	bar.mesh = quad
	var material := ShaderMaterial.new()
	material.shader = BAR_SHADER
	material.set_shader_parameter("fill_ratio", 1.0)
	material.set_shader_parameter("fill_color", fill)
	material.set_shader_parameter("bar_size", Vector2(width, height))
	bar.material_override = material
	bar.position = Vector3(0.0, y, 0.0)
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return bar


static func set_fill(bar: MeshInstance3D, ratio: float) -> void:
	if bar == null or not is_instance_valid(bar):
		return
	var material := bar.material_override as ShaderMaterial
	if material != null:
		material.set_shader_parameter("fill_ratio", clampf(ratio, 0.0, 1.0))
