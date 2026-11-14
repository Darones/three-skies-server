extends Node3D

const FAIRY := "res://art/generated/fairy/character.tscn"
const WARRIOR := "res://art/generated/warrior/character.tscn"


func _ready() -> void:
	var world := Node3D.new()
	add_child(world)
	var fairy := (load(FAIRY) as PackedScene).instantiate()
	fairy.position = Vector3(-1.0, 0.0, 0.0)
	world.add_child(fairy)
	var warrior := (load(WARRIOR) as PackedScene).instantiate()
	warrior.position = Vector3(1.0, 0.0, 0.0)
	world.add_child(warrior)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.6, 5.2)
	camera.look_at_from_position(Vector3(0.0, 1.6, 5.2), Vector3(0.0, 0.9, 0.0))
	camera.current = true
	add_child(camera)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 25.0, 0.0)
	sun.light_energy = 1.3
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0.0, 1.4, 2.4)
	fill.light_energy = 3.0
	fill.omni_range = 8.0
	add_child(fill)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.18, 0.2, 0.26)
	env.environment.ambient_light_color = Color(0.5, 0.55, 0.7)
	env.environment.ambient_light_energy = 0.9
	add_child(env)

	for i in 6:
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var path := "user://ui_shots/hero_clean_probe.png"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	image.save_png(path)
	print("HERO_CLEAN_PROBE_DONE ", path)
	get_tree().quit()
