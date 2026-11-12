extends Node3D

# Проверка посадки крыльев на Фее ровно тем же способом, что в hero.gd:
# кость spine02 -> BoneAttachment3D -> WingAttachment -> модель крыльев.
# Файл в tools/, в сборку не попадает.

const FAIRY := "res://art/generated/fairy/rig.glb"
const WINGS := "res://assets/wings/angel_wings_animated.glb"
const OUT_DIR := "user://wings_preview"

# подбираемые значения
const WING_OFFSET := Vector3(0.0, 0.0, -0.32)
const WING_ROTATION := Vector3(0.0, 18.0, 10.0)
const WING_SCALE := 1.0

var wing_attach: Node3D
var wing_model: Node3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_build_environment()

	var fairy := load(FAIRY).instantiate() as Node3D
	add_child(fairy)
	var skeleton := _find_skeleton(fairy)
	if skeleton == null:
		print("NO SKELETON")
		get_tree().quit()
		return

	var bone_name := ""
	var preferred := ["spine02", "chest", "torso", "body", "spine"]
	for want in preferred:
		for i in range(skeleton.get_bone_count()):
			if String(skeleton.get_bone_name(i)).to_lower().contains(want):
				bone_name = skeleton.get_bone_name(i)
				break
		if bone_name != "":
			break
	print("BONE ", bone_name)

	var bone_attach := BoneAttachment3D.new()
	bone_attach.name = "WingBoneAttachment"
	bone_attach.bone_name = bone_name
	skeleton.add_child(bone_attach)

	wing_attach = Node3D.new()
	wing_attach.name = "WingAttachment"
	bone_attach.add_child(wing_attach)

	var parent_scale := bone_attach.global_transform.basis.get_scale()
	var inverse := Vector3(
		1.0 / maxf(absf(parent_scale.x), 0.001),
		1.0 / maxf(absf(parent_scale.y), 0.001),
		1.0 / maxf(absf(parent_scale.z), 0.001)
	)
	wing_attach.scale = inverse
	wing_attach.position = WING_OFFSET * inverse

	wing_model = load(WINGS).instantiate() as Node3D
	wing_model.name = "Wings3D"
	wing_attach.add_child(wing_model)
	wing_model.scale = Vector3.ONE * WING_SCALE
	wing_model.rotation_degrees = WING_ROTATION

	var player := _find_anim(wing_model)
	if player != null and player.has_animation("Flap"):
		player.play("Flap")
		print("PLAYING Flap length=", player.get_animation("Flap").length)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true

	await _shot(cam, "back", Vector3(0.0, 1.25, 2.6))
	await _shot(cam, "back_tq", Vector3(1.8, 1.35, 1.9))
	await _shot(cam, "side", Vector3(2.7, 1.25, 0.2))
	print("WINGS_PREVIEW_DONE")
	get_tree().quit()


func _shot(cam: Camera3D, shot: String, pos: Vector3) -> void:
	cam.position = pos
	cam.look_at(Vector3(0.0, 1.05, 0.0), Vector3.UP)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(OUT_DIR.path_join("%s.png" % shot))
	print("SHOT ", shot)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.11, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.72)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
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
