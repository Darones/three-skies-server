extends Node3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var legendary := args.size() > 0 and args[0] == "legendary"
	var unlocked: Array[int] = []
	if legendary:
		unlocked = [1, 2, 3]
	MetaProgression.unlocked_weapons = unlocked
	MetaProgression.weapons_enabled = {"warrior": true, "mage": true, "fairy": true}
	_build_stage()
	var classes := [HeroUnit.Cls.WARRIOR, HeroUnit.Cls.MAGE, HeroUnit.Cls.FAIRY]
	var xs := [-2.3, 0.0, 2.3]
	for i in classes.size():
		var hero := HeroUnit.new()
		add_child(hero)
		hero.setup(null, classes[i], 0, true)
		hero.set_physics_process(false)
		hero.position = Vector3(xs[i], 0.0, 0.0)
		hero.visual.rotation.y = PI
	await get_tree().create_timer(1.2).timeout
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await get_tree().create_timer(0.4).timeout
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://ui_shots")
	image.save_png("user://ui_shots/weapon_probe_%s.png" % ("legendary" if legendary else "simple"))
	print("WEAPON_PROBE_DONE")
	get_tree().quit()


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
	camera.position = Vector3(0.0, 1.7, 9.2)
	camera.fov = 42.0
	camera.look_at_from_position(Vector3(0.0, 1.7, 9.2), Vector3(0.0, 1.05, 0.0), Vector3.UP)
	add_child(camera)
	camera.current = true
