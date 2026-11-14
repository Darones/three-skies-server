extends Node3D

const CONFIG_PATH := "res://tools/legendary_tuning.json"


func _ready() -> void:
	MetaProgression.unlocked_weapons = [1, 2, 3]
	MetaProgression.weapons_enabled = {"warrior": true, "mage": true, "fairy": true}
	_build_stage()
	var config := _load_config()
	var keys := ["warrior", "mage", "fairy"]
	var classes := [HeroUnit.Cls.WARRIOR, HeroUnit.Cls.MAGE, HeroUnit.Cls.FAIRY]
	var xs := [-2.3, 0.0, 2.3]
	for i in classes.size():
		var hero := HeroUnit.new()
		add_child(hero)
		hero.setup(null, classes[i], 0, true)
		hero.set_physics_process(false)
		hero.position = Vector3(xs[i], 0.0, 0.0)
		hero.visual.rotation.y = PI
		if hero.anim_player != null:
			hero.anim_player.seek(0.0, true)
			hero.anim_player.pause()
		var entry: Dictionary = config.get(keys[i], {})
		if not entry.is_empty():
			hero.weapon_base_scale = float(entry.get("scale", hero.weapon_base_scale))
			var rot: Array = entry.get("rot", [0.0, 0.0, 0.0])
			hero.weapon_rotation_offset = Vector3(float(rot[0]), float(rot[1]), float(rot[2]))
			var pos: Array = entry.get("pos", [0.0, 0.0, 0.0])
			hero.weapon_world_offset = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
			hero.call("_update_weapon_transform")
		print("TUNE ", keys[i], " scale=", hero.weapon_base_scale, " rot=", hero.weapon_rotation_offset, " pos=", hero.weapon_world_offset)
		if hero.weapon_instance != null and is_instance_valid(hero.weapon_instance):
			var weapon_basis := hero.weapon_instance.global_transform.basis.orthonormalized()
			print("  AXES ", keys[i], " X=", weapon_basis.x, " Y=", weapon_basis.y, " Z=", weapon_basis.z)
			print("  ORIGIN ", keys[i], " ", hero.weapon_instance.global_position)
	await get_tree().create_timer(1.2).timeout
	for child in get_children():
		var unit := child as HeroUnit
		if unit != null and unit.weapon_instance != null and is_instance_valid(unit.weapon_instance):
			var weapon_basis := unit.weapon_instance.global_transform.basis.orthonormalized()
			print("FINAL_AXES ", unit.hero_class, " X=", weapon_basis.x, " Y=", weapon_basis.y, " Z=", weapon_basis.z)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await get_tree().create_timer(0.4).timeout
	DirAccess.make_dir_recursive_absolute("user://ui_shots")
	var image := get_viewport().get_texture().get_image()
	image.save_png("user://ui_shots/legendary_tune_front.png")
	# Вид сбоку: разворачиваем героев на 90 градусов
	for hero in get_children():
		if hero is HeroUnit:
			hero.visual.rotation.y = PI * 0.5
	await get_tree().create_timer(0.3).timeout
	image = get_viewport().get_texture().get_image()
	image.save_png("user://ui_shots/legendary_tune_side.png")
	print("LEGENDARY_PROBE_DONE")
	get_tree().quit()


func _load_config() -> Dictionary:
	if not FileAccess.file_exists(CONFIG_PATH):
		return {}
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _build_stage() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.05, 0.07, 0.11)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.65, 0.85)
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.light_energy = 1.6
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)

	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.45, 0.7, 1.0)
	rim.light_energy = 0.9
	rim.rotation_degrees = Vector3(-25.0, 145.0, 0.0)
	add_child(rim)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20.0, 20.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.11, 0.13, 0.18)
	ground_material.roughness = 0.92
	ground.material_override = ground_material
	add_child(ground)

	var camera := Camera3D.new()
	camera.fov = 42.0
	camera.look_at_from_position(Vector3(0.0, 1.7, 9.2), Vector3(0.0, 1.05, 0.0), Vector3.UP)
	add_child(camera)
	camera.current = true
