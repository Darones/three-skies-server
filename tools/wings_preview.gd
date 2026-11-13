extends Node3D

# Проверяет посадку крыльев на Войне теми же мировыми осями, что в hero.gd.

const HERO := "res://art/generated/warrior/rig.glb"
const OUT_DIR := "user://wings_preview"
const WING_TINT_SHADER: Shader = preload("res://shaders/wing_tint.gdshader")

const VARIANTS := [
	{"name": "w_white", "path": "res://assets/wings/angel_wings_animated.glb", "scale": 1.0,
	 "position": Vector3(0, 0, -0.12), "rotation": Vector3(0, 0, 0),
	 "tint": Color(1, 1, 1), "emission": 0.0, "rim": 0.0},
	{"name": "w_gold", "path": "res://assets/wings/angel_wings_animated.glb", "scale": 1.0,
	 "position": Vector3(0, 0, -0.12), "rotation": Vector3(0, 0, 0),
	 "tint": Color(1.0, 0.78, 0.34), "emission": 0.30, "rim": 0.55},
	{"name": "w_black", "path": "res://assets/wings/angel_wings_animated.glb", "scale": 1.06,
	 "position": Vector3(0, 0, -0.12), "rotation": Vector3(0, 0, 4),
	 "tint": Color(0.16, 0.14, 0.20), "emission": 0.0, "rim": 0.35},
	{"name": "w_demon", "path": "res://assets/wings/low_poly_demon_wings_animated.glb", "scale": 0.006,
	 "position": Vector3(0, -0.85, -0.12), "rotation": Vector3(0, 0, 0),
	 "tint": Color(1, 1, 1), "emission": 0.0, "rim": 0.0},
]

var skeleton: Skeleton3D
var bone_index := -1
var model: Node3D = null
var model_scale := 1.0
var rotation_offset := Vector3.ZERO
var world_offset := Vector3.ZERO


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_build_environment()

	var hero := load(HERO).instantiate() as Node3D
	add_child(hero)
	skeleton = _find_skeleton(hero)
	for i in range(skeleton.get_bone_count()):
		if String(skeleton.get_bone_name(i)).to_lower().contains("spine02"):
			bone_index = i
			break
	print("BONE index ", bone_index)

	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true

	for variant in VARIANTS:
		await _shot_variant(cam, variant)
	print("WINGS_PREVIEW_DONE")
	get_tree().quit()


func _shot_variant(cam: Camera3D, variant: Dictionary) -> void:
	if model != null and is_instance_valid(model):
		model.queue_free()
		model = null
	var scene := load(String(variant["path"])) as PackedScene
	model = scene.instantiate() as Node3D
	add_child(model)
	model_scale = float(variant["scale"])
	rotation_offset = variant["rotation"]
	world_offset = variant["position"]
	await get_tree().process_frame
	_update_transform()

	var tint: Color = variant["tint"]
	if not tint.is_equal_approx(Color.WHITE):
		_apply_tint(model, tint, float(variant["emission"]), float(variant["rim"]))

	await get_tree().process_frame
	_update_transform()
	cam.position = Vector3(0.0, 1.4, 2.9)
	cam.look_at(Vector3(0.0, 1.1, 0.0), Vector3.UP)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT_DIR.path_join("%s.png" % variant["name"]))
	print("SHOT ", variant["name"])


func _update_transform() -> void:
	if model == null or skeleton == null or bone_index < 0:
		return
	var bone_world := skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)
	var skel_basis := skeleton.global_transform.basis
	var up := Vector3.UP
	var forward := -skel_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var right := forward.cross(up).normalized()
	var basis := Basis(right, up, forward)
	basis = basis * Basis.from_euler(Vector3(
		deg_to_rad(rotation_offset.x), deg_to_rad(rotation_offset.y), deg_to_rad(rotation_offset.z)))
	basis = basis.scaled(Vector3.ONE * model_scale)
	model.global_transform = Transform3D(basis, bone_world.origin + world_offset)


func _apply_tint(node: Node, tint: Color, emission: float, rim: float) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh != null:
				for s in range(mi.mesh.get_surface_count()):
					var src := mi.get_active_material(s) as BaseMaterial3D
					var mat := ShaderMaterial.new()
					mat.shader = WING_TINT_SHADER
					mat.set_shader_parameter("tint", tint)
					mat.set_shader_parameter("emission_strength", emission)
					mat.set_shader_parameter("rim_strength", rim)
					if src != null and src.albedo_texture != null:
						mat.set_shader_parameter("albedo_texture", src.albedo_texture)
					mi.set_surface_override_material(s, mat)
		_apply_tint(child, tint, emission, rim)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.11, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.72)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_hdr_threshold = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.4
	key.rotation_degrees = Vector3(-32.0, 148.0, 0.0)
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.55
	fill.light_color = Color(0.72, 0.78, 1.0)
	fill.rotation_degrees = Vector3(-18.0, -40.0, 0.0)
	add_child(fill)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null
