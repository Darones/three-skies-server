extends Node3D

# Рендерит превью товаров для витрины магазина: герой + надетый предмет.

const OUT_DIR := "user://shop_preview"
const WING_TINT_SHADER: Shader = preload("res://shaders/wing_tint.gdshader")

const HEROES := {
	"fairy": "res://art/generated/fairy/rig.glb",
	"mage": "res://art/generated/mage/rig.glb",
	"warrior": "res://art/generated/warrior/rig.glb",
}

const WINGS := {
	1: {"path": "res://assets/wings/angel_wings_animated.glb", "scale": 1.0,
		"position": Vector3(0.0, 0.0, 0.0), "rotation": Vector3(0.0, 0.0, 0.0),
		"tint": Color(1.0, 1.0, 1.0), "emission": 0.0, "rim": 0.0},
	2: {"path": "res://assets/wings/angel_wings_animated.glb", "scale": 1.0,
		"position": Vector3(0.0, 0.0, 0.0), "rotation": Vector3(0.0, 0.0, 0.0),
		"tint": Color(1.0, 0.78, 0.34), "emission": 0.15, "rim": 0.30},
	3: {"path": "res://assets/wings/angel_wings_animated.glb", "scale": 1.06,
		"position": Vector3(0.0, 0.0, 0.0), "rotation": Vector3(0.0, 0.0, 4.0),
		"tint": Color(0.10, 0.09, 0.13), "emission": 0.0, "rim": 0.0},
	4: {"path": "res://assets/wings/low_poly_demon_wings_animated.glb", "scale": 0.006,
		"position": Vector3(0.0, -0.85, 0.0), "rotation": Vector3(0.0, 0.0, 0.0),
		"tint": Color(1.0, 1.0, 1.0), "emission": 0.0, "rim": 0.0},
}

const WEAPONS := {
	"warrior": {"path": "res://addons/low_poly_rpg_items/props/longsword.tscn",
		"scale": 0.72, "offset": Vector3(0.06, 0.0, -0.12), "rotation": Vector3(0.0, 0.0, -12.0),
		"bone": "RightHand"},
	"fairy": {"path": "res://scenes/LegendaryBow.tscn",
		"scale": 0.82, "offset": Vector3(-0.06, 0.0, -0.1), "rotation": Vector3(0.0, 0.0, 8.0),
		"bone": "LeftHand"},
}

var skeleton: Skeleton3D = null
var hero_model: Node3D = null


func _ready() -> void:
	get_window().size = Vector2i(640, 680)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_build_environment()
	var cam := Camera3D.new()
	cam.fov = 32.0
	cam.position = Vector3(0.0, 1.32, 3.1)
	cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	add_child(cam)
	cam.current = true

	for hero_key in HEROES.keys():
		await _spawn_hero(String(hero_key))
		_frame_hero(cam, false)
		for wing_id in WINGS.keys():
			await _shot_wing(cam, String(hero_key), int(wing_id))
		if WEAPONS.has(hero_key):
			_frame_hero(cam, true)
			await _shot_weapon(cam, String(hero_key))
	print("SHOP_PREVIEW_DONE")
	get_tree().quit()


func _frame_hero(cam: Camera3D, weapon_view: bool) -> void:
	var aabb := _hero_aabb()
	if aabb.size.y <= 0.01:
		return
	var center := aabb.get_center()
	var height := maxf(aabb.size.y, 0.5)
	var distance := height * 1.85
	var side := distance * 0.72 if weapon_view else distance * 0.06
	cam.position = center + Vector3(side, height * 0.10, distance)
	cam.look_at(center + Vector3(0.0, height * 0.08, 0.0), Vector3.UP)


func _hero_aabb() -> AABB:
	if skeleton == null:
		return AABB()
	var result := AABB()
	var first := true
	for i in range(skeleton.get_bone_count()):
		var origin := skeleton.global_transform * skeleton.get_bone_global_pose(i).origin
		var point := AABB(origin - Vector3(0.08, 0.08, 0.08), Vector3(0.16, 0.16, 0.16))
		if first:
			result = point
			first = false
		else:
			result = result.merge(point)
	result.position.y -= 0.06
	result.size.y += 0.42
	return result


func _spawn_hero(hero_key: String) -> void:
	if hero_model != null and is_instance_valid(hero_model):
		hero_model.queue_free()
		hero_model = null
	await get_tree().process_frame
	var scene := load(HEROES[hero_key]) as PackedScene
	hero_model = scene.instantiate() as Node3D
	add_child(hero_model)
	skeleton = _find_skeleton(hero_model)
	var anim := _find_animation_player(hero_model)
	if anim != null:
		for action_name in anim.get_animation_list():
			if String(action_name).to_lower().contains("idle"):
				anim.play(action_name)
				break
	await get_tree().process_frame
	await get_tree().process_frame


func _shot_wing(cam: Camera3D, hero_key: String, wing_id: int) -> void:
	var config: Dictionary = WINGS[wing_id]
	var wing_scene := load(String(config["path"])) as PackedScene
	var wing := wing_scene.instantiate() as Node3D
	add_child(wing)
	_place_wing(wing, config)
	var tint: Color = config["tint"]
	if not tint.is_equal_approx(Color.WHITE) or float(config["emission"]) > 0.0 or float(config["rim"]) > 0.0:
		_apply_tint(wing, tint, float(config["emission"]), float(config["rim"]))
	await get_tree().process_frame
	_place_wing(wing, config)
	await RenderingServer.frame_post_draw
	var path := OUT_DIR.path_join("%s_wing%d.png" % [hero_key, wing_id])
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)
	wing.queue_free()
	await get_tree().process_frame


func _shot_weapon(cam: Camera3D, hero_key: String) -> void:
	var config: Dictionary = WEAPONS[hero_key]
	var packed := load(String(config["path"])) as PackedScene
	var weapon := packed.instantiate() as Node3D
	add_child(weapon)
	_place_weapon(weapon, config)
	await get_tree().process_frame
	_place_weapon(weapon, config)
	await RenderingServer.frame_post_draw
	var path := OUT_DIR.path_join("%s_weapon.png" % hero_key)
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)
	weapon.queue_free()
	await get_tree().process_frame


func _find_bone(bone_name: String) -> int:
	if skeleton == null:
		return -1
	for i in range(skeleton.get_bone_count()):
		if String(skeleton.get_bone_name(i)).to_lower() == bone_name.to_lower():
			return i
	return -1


func _place_wing(wing: Node3D, config: Dictionary) -> void:
	var bone_index := _find_bone("Spine02")
	if skeleton == null or bone_index < 0:
		return
	var bone_world := skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)
	var rotation_offset: Vector3 = config["rotation"]
	var basis := bone_world.basis.orthonormalized()
	basis = basis * Basis.from_euler(Vector3(
		deg_to_rad(rotation_offset.x), deg_to_rad(rotation_offset.y), deg_to_rad(rotation_offset.z)))
	basis = basis.scaled(Vector3.ONE * float(config["scale"]))
	var world_offset: Vector3 = config["position"] + Vector3(0.0, 0.0, -0.12)
	wing.global_transform = Transform3D(basis, bone_world.origin + world_offset)


func _place_weapon(weapon: Node3D, config: Dictionary) -> void:
	var bone_index := _find_bone(String(config["bone"]))
	if skeleton == null or bone_index < 0:
		return
	var bone_world := skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)
	var rotation_offset: Vector3 = config["rotation"]
	var basis := bone_world.basis.orthonormalized()
	basis = basis * Basis.from_euler(Vector3(
		deg_to_rad(rotation_offset.x), deg_to_rad(rotation_offset.y), deg_to_rad(rotation_offset.z)))
	basis = basis.scaled(Vector3.ONE * float(config["scale"]))
	weapon.global_transform = Transform3D(basis, bone_world.origin + Vector3(config["offset"]))


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
	rim.position = Vector3(0.0, 1.7, -1.6)
	rim.light_energy = 2.2
	rim.omni_range = 4.0
	rim.light_color = Color(0.62, 0.78, 1.0)
	add_child(rim)
