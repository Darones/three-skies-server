extends Node3D

# Сажает легендарный лук в левую руку Феи теми же параметрами, что hero.gd,
# и снимает два ракурса.

const FAIRY := "res://art/generated/fairy/rig.glb"
const BOW := "res://scenes/LegendaryBow.tscn"
const OUT_DIR := "user://bow_hand"

const HAND_OFFSET := Vector3(-0.06, 0.0, -0.1)
const BOW_SCALE := 0.82
const BOW_ROTATION := Vector3(0.0, 0.0, 8.0)


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
	for i in range(skeleton.get_bone_count()):
		if String(skeleton.get_bone_name(i)).to_lower() == "lefthand":
			bone_name = skeleton.get_bone_name(i)
			break
	print("BONE ", bone_name)
	if bone_name == "":
		get_tree().quit()
		return

	var attach := BoneAttachment3D.new()
	skeleton.add_child(attach)
	attach.bone_name = bone_name
	var parent_scale := maxf(absf(skeleton.global_transform.basis.get_scale().x), 0.001)
	attach.position = HAND_OFFSET / parent_scale

	var bow := load(BOW).instantiate() as Node3D
	attach.add_child(bow)
	bow.scale = Vector3.ONE * (BOW_SCALE / parent_scale)
	bow.rotation_degrees = BOW_ROTATION

	var player := _find_anim(bow)
	if player != null and player.has_animation("shoot"):
		player.play("shoot")
		player.seek(0.0, true)
		player.pause()

	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true

	await get_tree().process_frame
	var hand_index := skeleton.find_bone(bone_name)
	var bone_world := skeleton.global_transform * skeleton.get_bone_global_pose(hand_index)
	var bone_scale := maxf(absf(skeleton.global_transform.basis.get_scale().x), 0.0001)
	var skel_basis := skeleton.global_transform.basis
	var up := Vector3.UP
	var fwd := -skel_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := fwd.cross(up).normalized()
	var basis := Basis(right, up, fwd)
	basis = basis * Basis.from_euler(Vector3(0.0, 0.0, deg_to_rad(8.0)))
	basis = basis.scaled(Vector3.ONE * BOW_SCALE)
	bow.global_transform = Transform3D(basis, bone_world.origin + Vector3(-0.06, 0.0, -0.10))
	print("HAND_GLOBAL ", skeleton.get_bone_global_pose(hand_index).origin)
	print("BOW_GLOBAL ", bow.global_position)
	print("BOW_SCALE ", bow.scale, " visible=", bow.visible)
	for m in bow.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		print("  MESH ", mi.name, " global=", mi.global_position, " aabb=", mi.get_aabb(), " vis=", mi.is_visible_in_tree())

	await _shot(cam, "front", Vector3(0.0, 1.25, 2.6))
	await _shot(cam, "tq", Vector3(1.7, 1.35, 1.9))

	# только лук, без тела — проверить посадку в руке
	for m in fairy.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := m as MeshInstance3D
		if not String(mesh_node.name).begins_with("geometry_0"):
			mesh_node.visible = false
	await _shot(cam, "bow_only", Vector3(0.0, 1.25, 2.6))
	print("BOW_HAND_DONE")
	get_tree().quit()


func _shot(cam: Camera3D, name: String, pos: Vector3) -> void:
	cam.position = pos
	cam.look_at(Vector3(0.0, 1.05, 0.0), Vector3.UP)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(OUT_DIR.path_join("%s.png" % name))
	print("SHOT ", name)


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


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_anim(child)
		if found != null:
			return found
	return null
