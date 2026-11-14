extends Node3D

# Показывает крылья в позах Idle и Run — как в бою, с учётом масштаба героя.

const OUT_DIR := "user://wings_pose"
const HEROES := {
	"warrior": "res://art/generated/warrior/rig.glb",
	"mage": "res://art/generated/mage/rig.glb",
	"fairy": "res://art/generated/fairy/rig.glb",
}
const WINGS := {
	1: {"path": "res://assets/wings/angel_wings_animated.glb", "tint": Color(1, 1, 1)},
	4: {"path": "res://assets/wings/low_poly_demon_wings_animated.glb", "tint": Color(1, 1, 1)},
}
const TUNING := {
	"warrior": {
		1: {"position": Vector3(0.0, 0.25, -0.15), "rotation": Vector3(-1.7, 0.0, 0.0), "scale": 1.0},
		4: {"position": Vector3(0.0, -0.68, -0.46), "rotation": Vector3(0.0, 0.0, 0.0), "scale": 0.006},
	},
	"mage": {
		1: {"position": Vector3(0.0, 0.25, -0.15), "rotation": Vector3(-1.7, 0.0, 0.0), "scale": 1.0},
		4: {"position": Vector3(0.0, -0.77, -0.49), "rotation": Vector3(0.0, 0.0, 0.0), "scale": 0.006},
	},
	"fairy": {
		1: {"position": Vector3(0.0, 0.25, -0.07), "rotation": Vector3(-1.7, 0.0, 0.0), "scale": 1.0},
		4: {"position": Vector3(0.0, -0.75, -0.15), "rotation": Vector3(16.98, 0.0, 0.0), "scale": 0.006},
	},
}
const FIT := 2.15 / 1.7

var hero_root: Node3D = null
var skeleton: Skeleton3D = null
var anim: AnimationPlayer = null
var wing: Node3D = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_build_environment()
	var cam := Camera3D.new()
	cam.fov = 32.0
	add_child(cam)
	cam.current = true
	for hero_key in HEROES.keys():
		for wing_id in WINGS.keys():
			await _render(hero_key, int(wing_id), cam, "idle", "Idle", 0.0)
			await _render(hero_key, int(wing_id), cam, "run", "Run", 0.28)
	print("WINGS_POSE_DONE")
	get_tree().quit()


func _frame_camera(cam: Camera3D) -> void:
	if skeleton == null:
		return
	var min_y := 9999.0
	var max_y := -9999.0
	for i in range(skeleton.get_bone_count()):
		var point := skeleton.global_transform * skeleton.get_bone_global_pose(i).origin
		min_y = minf(min_y, point.y)
		max_y = maxf(max_y, point.y)
	var height := maxf(max_y - min_y + 0.35, 1.0)
	var center := Vector3(0.0, min_y + height * 0.5, 0.0)
	var distance := (height + 1.2) * 1.9
	cam.position = center + Vector3(distance * 0.33, height * 0.08, distance)
	cam.look_at(center + Vector3(0.0, height * 0.1, 0.0), Vector3.UP)


func _render(hero_key: String, wing_id: int, cam: Camera3D, shot: String, action: String, frame_time: float) -> void:
	await _spawn_hero(hero_key)
	_frame_camera(cam)
	if anim != null and anim.has_animation(action):
		anim.play(action)
		anim.seek(frame_time, true)
	await get_tree().process_frame
	await _spawn_wing(hero_key, wing_id)
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := OUT_DIR.path_join("%s_wing%d_%s.png" % [hero_key, wing_id, shot])
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)


func _spawn_hero(hero_key: String) -> void:
	if wing != null and is_instance_valid(wing):
		wing.queue_free()
		wing = null
	if hero_root != null and is_instance_valid(hero_root):
		hero_root.queue_free()
		hero_root = null
	await get_tree().process_frame
	var scene := load(HEROES[hero_key]) as PackedScene
	hero_root = scene.instantiate() as Node3D
	hero_root.scale = Vector3.ONE * FIT
	add_child(hero_root)
	skeleton = _find_skeleton(hero_root)
	anim = _find_animation_player(hero_root)
	await get_tree().process_frame


func _spawn_wing(hero_key: String, wing_id: int) -> void:
	if wing != null and is_instance_valid(wing):
		wing.queue_free()
		wing = null
	var config: Dictionary = TUNING[hero_key][wing_id]
	var scene := load(String(WINGS[wing_id]["path"])) as PackedScene
	wing = scene.instantiate() as Node3D
	add_child(wing)
	var bone_index := _find_bone("Spine02")
	if skeleton == null or bone_index < 0:
		return
	var bone_world := skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)
	var skel_basis := skeleton.global_transform.basis
	var forward := -skel_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var rotation_offset: Vector3 = config["rotation"]
	var basis := Basis(right, Vector3.UP, forward)
	basis = basis * Basis.from_euler(Vector3(
		deg_to_rad(rotation_offset.x), deg_to_rad(rotation_offset.y), deg_to_rad(rotation_offset.z)))
	basis = basis.scaled(Vector3.ONE * float(config["scale"]) * FIT)
	wing.global_transform = Transform3D(basis, bone_world.origin + Vector3(config["position"]) * FIT)


func _find_bone(bone_name: String) -> int:
	if skeleton == null:
		return -1
	for i in range(skeleton.get_bone_count()):
		if String(skeleton.get_bone_name(i)).to_lower() == bone_name.to_lower():
			return i
	return -1


func _find_skeleton(node: Node) -> Skeleton3D:
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is Skeleton3D:
			return current as Skeleton3D
		for child in current.get_children():
			stack.append(child)
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is AnimationPlayer:
			return current as AnimationPlayer
		for child in current.get_children():
			stack.append(child)
	return null


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.055, 0.07, 0.105)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.72)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_hdr_threshold = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.5
	key.rotation_degrees = Vector3(-30.0, 160.0, 0.0)
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.55
	fill.rotation_degrees = Vector3(-18.0, -35.0, 0.0)
	add_child(fill)
	var rim := OmniLight3D.new()
	rim.position = Vector3(0.0, 2.2, -2.2)
	rim.light_energy = 2.2
	rim.omni_range = 5.0
	rim.light_color = Color(0.62, 0.78, 1.0)
	add_child(rim)
