extends Node3D

# Р РµРЅРґРµСЂРёС‚ РІСЃРµ С‡РµС‚С‹СЂРµ РІР°СЂРёР°РЅС‚Р° РєСЂС‹Р»СЊРµРІ РЅР° Р¤РµРµ, СЂРѕРІРЅРѕ С‚РµРј Р¶Рµ СЃРїРѕСЃРѕР±РѕРј,
# С‡С‚Рѕ Рё hero.gd: Spine02 -> BoneAttachment3D -> WingAttachment -> РјРѕРґРµР»СЊ.
# Р¤Р°Р№Р» РІ tools/, РІ СЃР±РѕСЂРєСѓ РЅРµ РїРѕРїР°РґР°РµС‚.

const FAIRY := "res://art/generated/fairy/rig.glb"
const WING_TINT_SHADER: Shader = preload("res://shaders/wing_tint.gdshader")
const OUT_DIR := "user://wings_preview"

const VARIANTS := [
	{
		"name": "1_white",
		"path": "res://assets/wings/angel_wings_animated.glb",
		"scale": 1.0,
		"position": Vector3.ZERO,
		"rotation": Vector3(0.0, 18.0, 10.0),
		"tint": Color(1, 1, 1),
		"emission": 0.0,
		"rim": 0.0,
	},
	{
		"name": "2_gold",
		"path": "res://assets/wings/angel_wings_animated.glb",
		"scale": 1.0,
		"position": Vector3.ZERO,
		"rotation": Vector3(0.0, 18.0, 10.0),
		"tint": Color(1.0, 0.78, 0.34),
		"emission": 0.30,
		"rim": 0.55,
	},
	{
		"name": "3_black",
		"path": "res://assets/wings/angel_wings_animated.glb",
		"scale": 1.06,
		"position": Vector3.ZERO,
		"rotation": Vector3(0.0, 18.0, 4.0),
		"tint": Color(0.16, 0.14, 0.20),
		"emission": 0.0,
		"rim": 0.35,
	},
	{
		"name": "4_demon",
		"path": "res://assets/wings/low_poly_demon_wings_animated.glb",
		"scale": 0.006,
		"position": Vector3(0.0, -1.45, 0.0),
		"rotation": Vector3(0.0, 0.0, 0.0),
		"tint": Color(1, 1, 1),
		"emission": 0.0,
		"rim": 0.0,
	},
]

var fairy: Node3D
var skeleton: Skeleton3D
var bone_attach: BoneAttachment3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_build_environment()

	fairy = load(FAIRY).instantiate() as Node3D
	add_child(fairy)
	skeleton = _find_skeleton(fairy)
	if skeleton == null:
		print("NO SKELETON")
		get_tree().quit()
		return

	var bone_name := ""
	for want in ["spine02", "chest", "torso", "body", "spine"]:
		for i in range(skeleton.get_bone_count()):
			if String(skeleton.get_bone_name(i)).to_lower().contains(want):
				bone_name = skeleton.get_bone_name(i)
				break
		if bone_name != "":
			break
	print("BONE ", bone_name)

	bone_attach = BoneAttachment3D.new()
	bone_attach.bone_name = bone_name
	skeleton.add_child(bone_attach)

	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true

	for variant in VARIANTS:
		await _shot_variant(cam, variant)
	print("WINGS_PREVIEW_DONE")
	get_tree().quit()


func _shot_variant(cam: Camera3D, variant: Dictionary) -> void:
	for old in bone_attach.get_children():
		bone_attach.remove_child(old)
		old.queue_free()

	var attach := Node3D.new()
	attach.name = "WingAttachment"
	bone_attach.add_child(attach)
	var parent_scale := bone_attach.global_transform.basis.get_scale()
	var inverse := Vector3(
		1.0 / maxf(absf(parent_scale.x), 0.001),
		1.0 / maxf(absf(parent_scale.y), 0.001),
		1.0 / maxf(absf(parent_scale.z), 0.001)
	)
	attach.scale = inverse
	attach.position = Vector3(0.0, 0.0, -0.10) * inverse

	var scene := load(String(variant["path"])) as PackedScene
	if scene == null:
		print("LOAD FAIL ", variant["name"])
		return
	var model := scene.instantiate() as Node3D
	attach.add_child(model)
	model.scale = Vector3.ONE * float(variant["scale"])
	model.position = variant["position"]
	model.rotation_degrees = variant["rotation"]

	var tint: Color = variant["tint"]
	var emission := float(variant["emission"])
	var rim := float(variant["rim"])
	if not (tint.is_equal_approx(Color.WHITE) and emission <= 0.0 and rim <= 0.0):
		_apply_tint(model, tint, emission, rim)

	var player := _find_anim(model)
	if player != null:
		for anim_name in player.get_animation_list():
			if String(anim_name).to_lower().contains("flap"):
				player.play(anim_name)
				break

	await get_tree().process_frame
	await get_tree().process_frame
	cam.position = Vector3(0.0, 1.3, 2.7)
	cam.look_at(Vector3(0.0, 1.05, 0.0), Vector3.UP)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(OUT_DIR.path_join("%s.png" % variant["name"]))
	print("SHOT ", variant["name"])


func _apply_tint(node: Node, tint: Color, emission: float, rim: float) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			if mesh_instance.mesh != null:
				for surface_index in range(mesh_instance.mesh.get_surface_count()):
					var source := mesh_instance.get_active_material(surface_index) as BaseMaterial3D
					var material := ShaderMaterial.new()
					material.shader = WING_TINT_SHADER
					material.set_shader_parameter("tint", tint)
					material.set_shader_parameter("emission_strength", emission)
					material.set_shader_parameter("rim_strength", rim)
					if source != null and source.albedo_texture != null:
						material.set_shader_parameter("albedo_texture", source.albedo_texture)
					mesh_instance.set_surface_override_material(surface_index, material)
		_apply_tint(child, tint, emission, rim)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.11, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.72)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.8
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


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_anim(child)
		if found != null:
			return found
	return null

