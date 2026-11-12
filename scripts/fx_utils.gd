class_name FxUtils
extends RefCounted

const SOFT_GROUND_GLOW_SHADER: Shader = preload("res://shaders/soft_ground_glow.gdshader")


static func soft_ground_glow(size: float, color: Color, ring_bias := 0.0, intensity := 0.8, inner_fade := 0.0) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	var instance := MeshInstance3D.new()
	instance.mesh = plane
	instance.scale = Vector3(size, 1.0, size)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = SOFT_GROUND_GLOW_SHADER
	material.set_shader_parameter("glow_color", color)
	material.set_shader_parameter("intensity", intensity)
	material.set_shader_parameter("ring_bias", ring_bias)
	material.set_shader_parameter("inner_fade", inner_fade)
	instance.material_override = material
	return instance


static func set_glow_color(instance: MeshInstance3D, color: Color) -> void:
	var material := instance.material_override as ShaderMaterial
	if material != null:
		material.set_shader_parameter("glow_color", color)


static func set_glow_intensity(instance: MeshInstance3D, value: float) -> void:
	var material := instance.material_override as ShaderMaterial
	if material != null:
		material.set_shader_parameter("intensity", value)
